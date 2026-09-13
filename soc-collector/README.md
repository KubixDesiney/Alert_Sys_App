# SIAS to local Wazuh collector

This collector reads the SIAS `audit_log` Realtime Database path over outbound HTTPS and writes a small, redacted JSON-lines envelope into the local SOC folder. Wazuh reads the resulting `*.json` files from `C:\SOC-Lab\events`.

The service-account file and cursor stay on the Windows host. They are never committed to this repository. The first run looks back five minutes; later runs resume from `C:\SOC-Lab\state\sias-collector.json` and deduplicate by the Firebase record key.

## Configure the local host

Create a Python virtual environment outside the repository, install `requirements.txt`, and set these process-level variables:

```text
FB_DB_URL=https://<firebase-project>-default-rtdb.firebaseio.com
FIREBASE_SERVICE_ACCOUNT_FILE=C:\SOC-Secrets\sias-reader.json
SOC_EVENTS_DIR=C:\SOC-Lab\events
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

After the output is reviewed, run it continuously with the default 15-second interval. The Windows Scheduled Task or service wrapper should run under a dedicated local account with write access only to `C:\SOC-Lab\events` and `C:\SOC-Lab\state`.

## Event contract

The collector emits `schema_version`, `event_id`, `event_time`, `source`, `environment`, `event_type`, `action`, `outcome`, `severity`, `actor_id`, and a small set of target/cursor fields. It intentionally excludes audit detail, metadata blobs, message contents, tokens, passwords, and service-account material.

Use the `soc-foundation` branch for review. Deployment of a Firebase service account and enabling a recurring Windows task are separate operational steps.

