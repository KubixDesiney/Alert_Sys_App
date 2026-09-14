#!/usr/bin/env python3
"""Poll Vercel runtime events and write Wazuh-ready JSON lines.

The collector uses a read-only Vercel token supplied through the process
environment. It keeps only a bounded event-id cache in the local state file
and emits a redacted envelope into the same SOC event directory used by the
SIAS bridge.
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
from typing import Any, Iterable

import requests


API_BASE = "https://api.vercel.com"
DEFAULT_EVENTS_FILE = r"C:\SOC-Lab\events\vercel.ndjson"
DEFAULT_STATE_FILE = r"C:\SOC-Lab\state\vercel-collector.json"
MAX_SEEN_IDS = 1000


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def clean(value: Any, limit: int = 500) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    # Keep telemetry useful while removing common credential-shaped values.
    for marker in ("Authorization: Bearer ", "VERCEL_TOKEN=", "service_role="):
        if marker in text:
            text = text.split(marker, 1)[0] + marker + "[redacted]"
    return text[:limit] or None


def parse_time(value: Any) -> str:
    if isinstance(value, (int, float)):
        stamp = float(value) / (1000 if value > 10**12 else 1)
        return iso_z(datetime.fromtimestamp(stamp, timezone.utc))
    text = clean(value, 80)
    if text:
        try:
            return iso_z(datetime.fromisoformat(text.replace("Z", "+00:00")))
        except ValueError:
            pass
    return iso_z(utc_now())


def event_id(deployment_id: str, record: dict[str, Any]) -> str:
    material = json.dumps({"deployment": deployment_id, "record": record}, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()[:32]
    return f"vercel-runtime-{digest}"


def severity_for(level: str, text: str) -> tuple[str, str, str]:
    normalized = level.lower()
    if normalized in {"fatal", "critical"}:
        return "critical", "failure", "runtime.error"
    if normalized == "error" or "error" in text.lower() or "exception" in text.lower():
        return "high", "failure", "runtime.error"
    if normalized in {"warn", "warning"}:
        return "medium", "warning", "runtime.warning"
    return "low", "success", "runtime.log"


def normalize_event(deployment_id: str, deployment_url: str | None, record: dict[str, Any], environment: str) -> dict[str, Any] | None:
    if not isinstance(record, dict):
        return None
    text = clean(record.get("text") or record.get("message") or record.get("error") or record.get("msg"))
    level = clean(record.get("level") or record.get("type") or "info", 20) or "info"
    if not text:
        return None
    # The deployment-events endpoint also returns build stdout. Keep build
    # warnings/errors for triage, but avoid flooding Wazuh with routine npm
    # installation and cache messages.
    info = record.get("info") if isinstance(record.get("info"), dict) else {}
    lower_text = text.lower()
    build_signal = any(token in lower_text for token in ("error", "failed", "exception", "fatal", "warn"))
    if info.get("type") == "build" and level.lower() not in {"error", "fatal", "warning", "warn"} and not build_signal:
        return None
    severity, outcome, event_type = severity_for(level, text)
    event: dict[str, Any] = {
        "schema_version": "1.0",
        "event_id": event_id(deployment_id, record),
        "event_time": parse_time(record.get("timestamp") or record.get("createdAt") or record.get("time")),
        "source": "vercel",
        "environment": environment,
        "event_type": event_type,
        "action": "runtime.log",
        "outcome": outcome,
        "severity": severity,
        "actor_id": "vercel-runtime",
        "deployment_id": clean(deployment_id, 120),
        "message": text,
        "level": level,
    }
    if deployment_url:
        event["deployment_url"] = clean(deployment_url, 240)
    for output_name, names in {
        "route": ("route", "requestPath", "path"),
        "request_id": ("requestId", "request_id"),
        "source_type": ("source", "sourceType"),
    }.items():
        for name in names:
            value = clean(record.get(name), 240)
            if value:
                event[output_name] = value
                break
    return event


class VercelApi:
    def __init__(self, token: str, project_id: str, team_id: str | None, deployment_id: str | None) -> None:
        self.project_id = project_id
        self.team_id = team_id
        self.deployment_id = deployment_id
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {token}", "Accept": "application/json"})

    def latest_deployment(self) -> tuple[str, str | None]:
        params: dict[str, str] = {"projectId": self.project_id, "limit": "10"}
        if self.team_id:
            params["teamId"] = self.team_id
        # Vercel currently serves the deployments collection at v6. Older
        # versions return a 400 "Invalid API version" response.
        response = self.session.get(f"{API_BASE}/v6/deployments", params=params, timeout=20)
        response.raise_for_status()
        deployments = response.json().get("deployments", [])
        if not deployments:
            raise RuntimeError("Vercel returned no deployments for the configured project")
        candidates = [item for item in deployments if item.get("target") == "production" and item.get("state") == "READY"]
        selected = (candidates or deployments)[0]
        deployment_id = selected.get("uid") or selected.get("id") or selected.get("deploymentId")
        if not deployment_id:
            raise RuntimeError("Vercel deployment response did not include an identifier")
        return str(deployment_id), clean(selected.get("url"), 240)

    def runtime_events(self, deployment_id: str) -> Iterable[dict[str, Any]]:
        response = self.session.get(
            f"{API_BASE}/v3/deployments/{deployment_id}/events",
            params={"limit": "100", "direction": "backward"},
            stream=True,
            timeout=(15, 25),
        )
        response.raise_for_status()
        content_type = response.headers.get("content-type", "")
        if "json" in content_type and not response.headers.get("transfer-encoding"):
            body = response.json()
            records = body.get("events", body) if isinstance(body, dict) else body
            if isinstance(records, list):
                yield from (item for item in records if isinstance(item, dict))
            elif isinstance(records, dict):
                yield records
            return
        for raw_line in response.iter_lines(decode_unicode=True):
            if not raw_line:
                continue
            try:
                record = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                yield record


def read_state(path: Path) -> dict[str, Any]:
    if path.exists():
        try:
            body = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(body, dict):
                seen = body.get("seen_ids", [])
                return {"seen_ids": [str(item) for item in seen][-MAX_SEEN_IDS:]}
        except (OSError, json.JSONDecodeError):
            pass
    return {"seen_ids": []}


def write_state(path: Path, state: dict[str, Any]) -> None:
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


def run_once(client: VercelApi, events_file: Path, state_path: Path, environment: str) -> int:
    deployment_id = client.deployment_id
    deployment_url: str | None = None
    if not deployment_id:
        deployment_id, deployment_url = client.latest_deployment()
    state = read_state(state_path)
    seen = set(state["seen_ids"])
    count = 0
    for record in client.runtime_events(deployment_id):
        normalized = normalize_event(deployment_id, deployment_url, record, environment)
        if not normalized or normalized["event_id"] in seen:
            continue
        append_event(events_file, normalized)
        seen.add(normalized["event_id"])
        count += 1
    write_state(state_path, {"seen_ids": list(seen)[-MAX_SEEN_IDS:]})
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="poll once and exit")
    parser.add_argument("--self-test", action="store_true", help="print a normalized sample without network access")
    parser.add_argument("--interval", type=int, default=int(os.getenv("VERCEL_POLL_INTERVAL_SECONDS", "60")))
    args = parser.parse_args()
    if args.self_test:
        sample = {"timestamp": iso_z(utc_now()), "level": "error", "text": "synthetic SOC training event", "route": "/"}
        print(json.dumps(normalize_event("deployment-self-test", "example.vercel.app", sample, "production"), indent=2))
        return 0

    token = os.environ.get("VERCEL_TOKEN")
    project_id = os.environ.get("VERCEL_PROJECT_ID")
    if not token or not project_id:
        print("Set VERCEL_TOKEN and VERCEL_PROJECT_ID before starting the collector.", file=sys.stderr)
        return 2
    client = VercelApi(token, project_id, os.environ.get("VERCEL_TEAM_ID"), os.environ.get("VERCEL_DEPLOYMENT_ID"))
    events_file = Path(os.environ.get("SOC_EVENTS_FILE", DEFAULT_EVENTS_FILE))
    state_path = Path(os.environ.get("SOC_STATE_FILE", DEFAULT_STATE_FILE))
    environment = os.environ.get("VERCEL_ENVIRONMENT", "production")
    while True:
        try:
            count = run_once(client, events_file, state_path, environment)
            print(f"Vercel collector: wrote {count} event(s)", flush=True)
        except Exception as error:  # keep the long-running collector alive
            print(f"Vercel collector error: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
            if args.once:
                return 1
        if args.once:
            return 0
        time.sleep(max(15, args.interval))


if __name__ == "__main__":
    raise SystemExit(main())

