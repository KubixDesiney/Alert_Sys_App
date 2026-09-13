#!/usr/bin/env python3
"""Poll SIAS Firebase audit records and write Wazuh-ready JSON lines.

The collector is intentionally pull-only. It keeps Firebase credentials and
state outside the repository and writes only an allow-listed event envelope to
the local SOC event directory.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


TOKEN_URL = "https://oauth2.googleapis.com/token"
DEFAULT_EVENTS_DIR = r"C:\SOC-Lab\events"
DEFAULT_EVENTS_FILE = r"C:\SOC-Lab\events\sias.ndjson"
DEFAULT_STATE_FILE = r"C:\SOC-Lab\state\sias-collector.json"


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def first_value(record: dict[str, Any], *names: str) -> Any:
    for name in names:
        value = record.get(name)
        if value not in (None, ""):
            return value
    return None


def clean(value: Any, limit: int = 200) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    return text[:limit] or None


def parse_time(value: Any) -> str:
    if isinstance(value, (int, float)):
        stamp = float(value) / (1000 if value > 10**12 else 1)
        return iso_z(datetime.fromtimestamp(stamp, timezone.utc))
    text = clean(value, 80)
    if text:
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
            return iso_z(parsed)
        except ValueError:
            pass
    return iso_z(utc_now())


def severity_for(action: str, record: dict[str, Any]) -> str:
    explicit = clean(first_value(record, "severity", "risk"), 20)
    if explicit and explicit.lower() in {"low", "medium", "high", "critical"}:
        return explicit.lower()
    if action in {"alert.escalate", "alert.critical_toggle", "account.revoke", "account.role_change", "ai.override"}:
        return "high"
    if action in {"settings.change", "forecast.deploy", "account.provision", "account.password_reset"}:
        return "medium"
    return "low"


def normalize_record(key: str, record: dict[str, Any], environment: str) -> dict[str, Any] | None:
    """Convert one SIAS audit record into the stable SOC envelope."""
    if not isinstance(record, dict):
        return None
    action = clean(first_value(record, "action", "event_type"), 80)
    if not action:
        return None
    event_time = parse_time(first_value(record, "at", "event_time", "timestamp"))
    event: dict[str, Any] = {
        "schema_version": "1.0",
        "event_id": f"sias-audit-{key}",
        "event_time": event_time,
        "source": "sias",
        "environment": environment,
        "event_type": action,
        "action": action,
        "outcome": clean(first_value(record, "outcome", "result"), 24) or "success",
        "severity": severity_for(action, record),
        "actor_id": clean(first_value(record, "actorId", "actor_id"), 160) or "unknown",
        "collector_cursor": key,
    }
    optional = {
        "actor_role": ("actorRole", "actor_role"),
        "target_type": ("targetType", "target_type"),
        "target_id": ("targetId", "target_id"),
        "factory_id": ("factoryId", "factory_id"),
        "request_id": ("requestId", "request_id"),
    }
    for output_name, names in optional.items():
        value = clean(first_value(record, *names), 200)
        if value:
            event[output_name] = value
    return event


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


class FirebaseRest:
    def __init__(self, database_url: str, service_account_file: Path) -> None:
        self.database_url = database_url.rstrip("/")
        self.service_account = json.loads(service_account_file.read_text(encoding="utf-8"))
        self.session = requests.Session()
        self.cached_token = ""
        self.token_expires_at = 0.0

    def access_token(self) -> str:
        now = time.time()
        if self.cached_token and now < self.token_expires_at - 60:
            return self.cached_token
        issued = int(now)
        header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
        claim = b64url(json.dumps({
            "iss": self.service_account["client_email"],
            "scope": "https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email",
            "aud": TOKEN_URL,
            "iat": issued,
            "exp": issued + 3600,
        }, separators=(",", ":")).encode())
        private_key = self.service_account["private_key"].replace("\\n", "\n").encode()
        signer = serialization.load_pem_private_key(private_key, password=None)
        unsigned = f"{header}.{claim}".encode("ascii")
        signature = signer.sign(unsigned, padding.PKCS1v15(), hashes.SHA256())
        assertion = f"{header}.{claim}.{b64url(signature)}"
        response = self.session.post(TOKEN_URL, data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }, timeout=20)
        response.raise_for_status()
        body = response.json()
        self.cached_token = body["access_token"]
        self.token_expires_at = now + int(body.get("expires_in", 3600))
        return self.cached_token

    def audit_records(self, start_at: str) -> dict[str, Any]:
        response = self.session.get(
            f"{self.database_url}/audit_log.json",
            params={
                "orderBy": json.dumps("at"),
                "startAt": json.dumps(start_at),
                "limitToFirst": "500",
                "access_token": self.access_token(),
            },
            timeout=20,
        )
        response.raise_for_status()
        body = response.json()
        return body if isinstance(body, dict) else {}


def read_state(path: Path, lookback_minutes: int) -> dict[str, str]:
    if path.exists():
        body = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(body, dict):
            return {"cursor_at": str(body.get("cursor_at", "")), "cursor_key": str(body.get("cursor_key", ""))}
    return {"cursor_at": iso_z(utc_now() - timedelta(minutes=lookback_minutes)), "cursor_key": ""}


def write_state(path: Path, state: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps({**state, "updated_at": iso_z(utc_now())}, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def append_event(events_file: Path, event: dict[str, Any]) -> None:
    events_file.parent.mkdir(parents=True, exist_ok=True)
    with events_file.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(event, separators=(",", ":"), ensure_ascii=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def run_once(client: FirebaseRest, events_file: Path, state_path: Path, environment: str, lookback_minutes: int) -> int:
    state = read_state(state_path, lookback_minutes)
    records = client.audit_records(state["cursor_at"])
    ordered = sorted(records.items(), key=lambda item: (parse_time(first_value(item[1], "at", "event_time", "timestamp")), item[0]))
    count = 0
    for key, record in ordered:
        event_time = parse_time(first_value(record, "at", "event_time", "timestamp"))
        if (event_time, key) <= (state["cursor_at"], state["cursor_key"]):
            continue
        event = normalize_record(key, record, environment)
        if event:
            append_event(events_file, event)
            count += 1
        state = {"cursor_at": event_time, "cursor_key": key}
    write_state(state_path, state)
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="poll once and exit")
    parser.add_argument("--self-test", action="store_true", help="print a normalized sample without network access")
    parser.add_argument("--interval", type=int, default=int(os.getenv("SIAS_POLL_INTERVAL_SECONDS", "15")))
    parser.add_argument("--lookback-minutes", type=int, default=int(os.getenv("SIAS_INITIAL_LOOKBACK_MINUTES", "5")))
    args = parser.parse_args()
    if args.self_test:
        sample = {"at": iso_z(utc_now()), "action": "account.role_change", "actorId": "lab-user", "targetId": "lab-target"}
        print(json.dumps(normalize_record("self-test", sample, "development"), indent=2))
        return 0

    database_url = os.environ.get("FB_DB_URL")
    service_account_file = os.environ.get("FIREBASE_SERVICE_ACCOUNT_FILE")
    if not database_url or not service_account_file:
        print("Set FB_DB_URL and FIREBASE_SERVICE_ACCOUNT_FILE before starting the collector.", file=sys.stderr)
        return 2
    client = FirebaseRest(database_url, Path(service_account_file))
    events_file = Path(os.environ.get("SOC_EVENTS_FILE", DEFAULT_EVENTS_FILE))
    state_path = Path(os.environ.get("SOC_STATE_FILE", DEFAULT_STATE_FILE))
    environment = os.environ.get("SIAS_ENVIRONMENT", "development")
    while True:
        try:
            count = run_once(client, events_file, state_path, environment, args.lookback_minutes)
            print(f"SIAS collector: wrote {count} event(s)", flush=True)
        except Exception as error:  # keep the long-running collector alive
            print(f"SIAS collector error: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
            if args.once:
                return 1
        if args.once:
            return 0
        time.sleep(max(5, args.interval))


if __name__ == "__main__":
    raise SystemExit(main())

