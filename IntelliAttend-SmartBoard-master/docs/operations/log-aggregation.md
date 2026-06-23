# Log Aggregation (O5)

SmartBoard emits structured JSON logs in production (`kReleaseMode`).

## Format
```json
{"timestamp":"2026-05-09T23:30:00.000Z","level":"info","message":"...","logger":"intelliattend"}
```

## Shipping to a Central Aggregator

### Option A: Fluentd / Fluent Bit
Forward logs from the local app log file to a remote aggregator:
```ini
[INPUT]
  Name        tail
  Path        %APPDATA%/IntelliAttend/logs/app.log
  Parser      json
  Tag         intelliattend

[OUTPUT]
  Name        http
  Host        your-loki-server
  Port        3100
  URI         /loki/api/v1/push
  Format      json
```

### Option B: CloudWatch Agent
Install the CloudWatch agent on the Windows board and monitor the log file at `%APPDATA%\IntelliAttend\logs\app.log`.

### Option C: Custom Forwarder
The backend `/api/v1/device/heartbeat` endpoint can be extended to accept a batch of recent log lines and store them in Firestore for IT dashboard consumption.

## Retention
- Local log files: 7 days (managed by the app)
- Cloud aggregator: 30 days (configured per aggregator policy)
