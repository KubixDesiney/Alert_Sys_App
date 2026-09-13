# SIAS to local Wazuh collector

This collector reads the SIAS `audit_log` Realtime Database path over outbound HTTPS and writes a small, redacted JSON-lines envelope into the append-only `C:\SOC-Lab\events\sias.ndjson` file. Wazuh reads that file locally.

The service-account file and cursor stay on the Windows host. They are never committed to this repository. The first run looks back five minutes; later runs resume from `C:\SOC-Lab\state\sias-collector.json` and deduplicate by the Firebase record key.

## Configure the local host

Create a Python virtual environment outside the repository, install `requirements.txt`, and set these process-level variables:

```text
FB_DB_URL=https://<firebase-project>-default-rtdb.firebaseio.com
FIREBASE_SERVICE_ACCOUNT_FILE=C:\SOC-Secrets\sias-reader.json
SOC_EVENTS_FILE=C:\SOC-Lab\events\sias.ndjson
SOC_STATE_FILE=C:\SOC-Lab\state\sias-collector.json
SIAS_ENVIRONMENT=development
```

The service account needs read access to the selected audit and health paths only. Do not put the JSON key in GitHub, the SIAS app, or the Wazuh compose directory.

Run the safe local self-test first:

```text
python soc-collector\sias_collector.py --self-test
```

Then perform one real poll:

```text
python soc-collector\sias_collector.py --once
```

For a continuous local run, use the included PowerShell wrapper. It keeps the
credential path in the process environment and starts the collector at its
15-second polling interval:

```text
powershell -ExecutionPolicy Bypass -File soc-collector\run-sias-collector.ps1 -ServiceAccountFile C:\SOC-Secrets\sias-reader.json
```

After the output is reviewed, run it continuously with the default 15-second interval. The Windows Scheduled Task or service wrapper should run under a dedicated local account with write access only to `C:\SOC-Lab\events` and `C:\SOC-Lab\state`.

## Event contract

The collector emits `schema_version`, `event_id`, `event_time`, `source`, `environment`, `event_type`, `action`, `outcome`, `severity`, `actor_id`, and a small set of target/cursor fields. It intentionally excludes audit detail, metadata blobs, message contents, tokens, passwords, and service-account material.

Use the `soc-foundation` branch for review. Deployment of a Firebase service account and enabling a recurring Windows task are separate operational steps.

## Vercel runtime collector

`vercel_collector.py` polls the read-only Vercel deployment events endpoint and writes redacted runtime events to `C:\\SOC-Lab\\events\\vercel.ndjson`. Keep the token outside the repository and give it only the project/team read access needed for logs.

```text
VERCEL_TOKEN=<read-only token>
VERCEL_PROJECT_ID=prj_<project id>
VERCEL_TEAM_ID=team_<team id>
VERCEL_ENVIRONMENT=production
SOC_EVENTS_FILE=C:\\SOC-Lab\\events\\vercel.ndjson
SOC_STATE_FILE=C:\\SOC-Lab\\state\\vercel-collector.json
```

Run the local self-test before supplying a token:

```text
python soc-collector\\vercel_collector.py --self-test
```

Then perform one real poll or run continuously:

```text
python soc-collector\\vercel_collector.py --once
python soc-collector\\vercel_collector.py
```

The collector deduplicates events by a hash of the deployment and event body, keeps a bounded local cursor, and never writes Vercel credentials to the event file.

For a scheduled Windows run, keep the token in a file outside the repository and use the wrapper:

```text
powershell -ExecutionPolicy Bypass -File soc-collector\\run-vercel-collector.ps1 -TokenFile C:\\SOC-Secrets\\vercel-readonly.token -ProjectId prj_<project id> -TeamId team_<team id>
```

The Wazuh integration snippets are in `wazuh-vercel-rules.xml` and `wazuh-vercel-localfile.conf`. Include the rules in the manager's local rules file and the localfile block inside the manager configuration, then restart the manager.
