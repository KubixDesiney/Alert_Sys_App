#!/usr/bin/env python3
"""Poll protected Supabase operational tables and write Wazuh-ready events.

The collector is intended for a local SOC host. It uses a service-key file
outside the repository, reads only selected operational columns, and emits a
redacted envelope into the local SOC event directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests


DEFAULT_EVENTS_FILE = r"C:\SOC-Lab\events\supabase.ndjson"
DEFAULT_STATE_FILE = r"C:\SOC-Lab\state\supabase-collector.json"
MAX_SEEN_IDS = 2000
TABLE_QUERIES = {
    "agent_runs": "id,agent_id,mode,trigger,status,started_at,finished_at,error",
    "agent_actions": "id,agent_id,kind,risk,status,title,created_at,decided_at,executed_at",
    "notifications": "id,audience,type,title,link,read,created_at",
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def clean(value: Any, limit: int = 500) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    for marker in ("Bearer ", "service_role=", "SUPABASE_KEY=", "apikey="):
        if marker in text:
            text = text.split(marker, 1)[0] + marker + "[redacted]"
    return text[:limit] or None


def parse_time(value: Any) -> str:
    text = clean(value, 80)
    if text:
        try:
            return iso_z(datetime.fromisoformat(text.replace("Z", "+00:00")))
        except ValueError:
            pass
    return iso_z(utc_now())


def stable_id(table: str, record: dict[str, Any]) -> str:
    raw = json.dumps({"table": table, "record": record}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def normalize_record(table: str, record: dict[str, Any], environment: str) -> dict[str, Any] | None:
    if not isinstance(record, dict) or not record.get("id"):
        return None
    status = clean(record.get("status"), 30) or "unknown"
    record_type = clean(record.get("type"), 60)
    is_failure = status in {"error", "failed", "rejected"} or record_type == "agent_error"
    is_warning = status in {"running", "pending"} or (table == "notifications" and not is_failure)
    severity = "high" if is_failure else ("medium" if is_warning else "low")
    outcome = "failure" if is_failure else ("warning" if is_warning else "success")
    event_type = {"agent_runs": "agent.run", "agent_actions": "agent.action", "notifications": "notification"}[table]
    event: dict[str, Any] = {
        "schema_version": "1.0",
        "event_id": f"supabase-{table}-{stable_id(table, record)}",
        "event_time": parse_time(record.get("started_at") or record.get("created_at") or record.get("decided_at")),
        "source": "supabase",
        "environment": environment,
        "event_type": event_type,
        "action": status if table != "notifications" else (record_type or "notification"),
        "outcome": outcome,
        "severity": severity,
        "actor_id": clean(record.get("agent_id"), 160) or "supabase-system",
        "record_id": clean(record.get("id"), 120),
        "table": table,
    }
    for output_name, source_name in {
        "risk": "risk",
        "agent_mode": "mode",
        "trigger": "trigger",
        "route": "link",
        "title": "title",
    }.items():
        value = clean(record.get(source_name), 240)
        if value:
            event[output_name] = value
    error = clean(record.get("error"), 500)
    if error:
        event["error"] = error
    return event


class SupabaseRest:
    def __init__(self, project_url: str, key_file: Path) -> None:
        self.project_url = project_url.rstrip("/")
        key = key_file.read_text(encoding="utf-8").strip()
        if not key:
            raise ValueError("Supabase key file is empty")
        self.session = requests.Session()
        self.session.headers.update({"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"})

    def table_rows(self, table: str, select: str, limit: int = 100) -> list[dict[str, Any]]:
        order_column = "started_at" if table == "agent_runs" else "created_at"
        response = self.session.get(
            f"{self.project_url}/rest/v1/{table}",
            params={"select": select, "order": f"{order_column}.desc", "limit": str(limit)},
            timeout=20,
        )
        response.raise_for_status()
        body = response.json()
        return body if isinstance(body, list) else []


def read_state(path: Path) -> dict[str, list[str]]:
    if path.exists():
        try:
            body = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(body, dict):
                return {"seen_ids": [str(item) for item in body.get("seen_ids", [])][-MAX_SEEN_IDS:]}
        except (OSError, json.JSONDecodeError):
            pass
    return {"seen_ids": []}


def write_state(path: Path, state: dict[str, list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps({**state, "updated_at": iso_z(utc_now())}, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def append_event(path: Path, event: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(event, separators=(",", ":"), ensure_ascii=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def run_once(client: SupabaseRest, events_file: Path, state_path: Path, environment: str) -> int:
    state = read_state(state_path)
    seen = set(state["seen_ids"])
    count = 0
    for table, select in TABLE_QUERIES.items():
        for record in client.table_rows(table, select):
            event = normalize_record(table, record, environment)
            if not event or event["event_id"] in seen:
                continue
            append_event(events_file, event)
            seen.add(event["event_id"])
            count += 1
    write_state(state_path, {"seen_ids": list(seen)[-MAX_SEEN_IDS:]})
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="poll once and exit")
    parser.add_argument("--self-test", action="store_true", help="print a normalized sample without network access")
    parser.add_argument("--interval", type=int, default=int(os.getenv("SUPABASE_POLL_INTERVAL_SECONDS", "60")))
    args = parser.parse_args()
    if args.self_test:
        sample = {"id": "self-test", "agent_id": "lab-agent", "status": "error", "started_at": iso_z(utc_now()), "error": "synthetic SOC training event"}
        print(json.dumps(normalize_record("agent_runs", sample, "production"), indent=2))
        return 0

    project_url = os.environ.get("SUPABASE_URL")
    key_file = os.environ.get("SUPABASE_KEY_FILE")
    if not project_url or not key_file:
        print("Set SUPABASE_URL and SUPABASE_KEY_FILE before starting the collector.", file=sys.stderr)
        return 2
    client = SupabaseRest(project_url, Path(key_file))
    events_file = Path(os.environ.get("SOC_EVENTS_FILE", DEFAULT_EVENTS_FILE))
    state_path = Path(os.environ.get("SOC_STATE_FILE", DEFAULT_STATE_FILE))
    environment = os.environ.get("SUPABASE_ENVIRONMENT", "production")
    while True:
        try:
            count = run_once(client, events_file, state_path, environment)
            print(f"Supabase collector: wrote {count} event(s)", flush=True)
        except Exception as error:  # keep the long-running collector alive
            print(f"Supabase collector error: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
            if args.once:
                return 1
        if args.once:
            return 0
        time.sleep(max(15, args.interval))


if __name__ == "__main__":
    raise SystemExit(main())

