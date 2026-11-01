# Wind Alarm Agent

Wind Alarm watches live webcams at Kochelsee and Gardasee, reads the on-screen wind in knots, and sends a Firebase push when a fresh reading is strictly above that location's threshold. A Flutter app subscribes to those pushes, shows the latest reading, and can raise a local alarm.

## What it checks

| Location | Webcams | Alarm when | FCM topic |
| --- | --- | --- | --- |
| Kochelsee | Trimini | fresh base wind **> 10 kt** | `wind_alarms_kochelsee` |
| Gardasee | Malcesine Nord, Malcesine, Campione | fresh base wind **> 12 kt** at Malcesine Nord or Malcesine | `wind_alarms_gardasee` |

Campione is fetched and shown, but it does not raise the Gardasee alarm on its own. Gusts are stored and displayed; the alarm uses base wind only. Wind is in knots (`kts`), the unit printed on the addicted-sports.com overlay.

A reading is fresh when the station timestamp (`utctstamp`) is at most 60 minutes old. The alarm uses that timestamp, not the time the job started. `python app.py --location kochelsee` uses that location's threshold (10 kt). Pass `--threshold` only to override it. A run with no fresh station reading exits non-zero. A failed OCR pass is not reported as 0 kt.

## Architecture

```text
webcam page (Playwright)
        |
        v
LangGraph: fetch -> OCR -> freshness -> threshold -> optional FCM
        |
        v
aggregator (one run per webcam, then a single push per location)
        |
        +--> in-memory store + FastAPI
        +--> DynamoDB / Cosmos and S3 / Blob JSON (when USE_AWS or USE_AZURE)
        |
        v
Flutter app (polls measurements.json, subscribes to the FCM topic)
```

The graph lives in `src/wind_alarm/`. The live value comes from the webcam's station feed (`wsavg` / `wsmax` in knots, UTC timestamp), which is the same data the "Wind & Wetter" panel shows. The burned-in overlay on `current/640.jpg` is the check: base wind is the unlabeled knots line, gust is the `Böe` line, and the °C line and the clock are not wind. OCR (EasyOCR) and, when `USE_AZURE` or `USE_AWS` is set, the vision model are the fallback when the station feed is missing. `app.py` runs the aggregator. `skip_notification` is set on each webcam run so only the aggregated push is sent.

A separate forecast path screenshots Windfinder, Windguru, and the Föhn diagram and asks the configured model for a German summary. Results are written to `forecast.json` on S3 or Azure Blob, or to a local file when neither cloud flag is set.

### Schedulers

The local windows are Europe/Berlin clock times, all year: Kochelsee **05:00–08:00**, Gardasee **05:00–10:00**. Berlin is UTC+1 in winter (CET) and UTC+2 in summer (CEST). The UTC crons are the union of those two offsets, so the local window is inside the schedule in both seasons. That also runs a bit early in winter and a bit late in summer.

| Location | Local window | GitHub backup (every 15 min) | EventBridge primary (every 5 min) |
| --- | --- | --- | --- |
| Kochelsee | 05:00–08:00 | `*/15 3-7 * * *` (03:00–07:45 UTC) | `cron(*/5 3-7 * * ? *)` |
| Gardasee | 05:00–10:00 | `*/15 3-9 * * *` (03:00–09:45 UTC) | `cron(*/5 3-9 * * ? *)` |

EventBridge (`terraform/main.tf`) is the primary clock. It does not stop after a quiet repository, which is what silenced GitHub Actions from 29 April 2026 until 31 October 2026. GitHub Actions stays as a backup. It can skip or delay runs. After you apply the Terraform schedule, set the repository variable `WIND_ALARM_SEND_FROM_ACTIONS` to `false` so the backup still measures and fails the job when the station is down, but does not send a second push. Until that variable is set, GitHub still sends.

One push per location per Berlin day. A later run in the same morning that is still above the threshold does not push again.

`verify-readings.yml` compares the station feed with the overlay. Its schedule runs only when `WIND_READING_VERIFY` is `true`. It never sends a push.

An hourly EventBridge heartbeat publishes `WindAlarm/SchedulerAlive`. The alarm `wind-alarm-scheduler-silent` treats missing data as a failure. A run with no fresh station reading returns HTTP 500 so `wind-alarm-measurement-errors` can fire. Neither alarm emails anyone until you attach a notification in the CloudWatch console.

### If no alarm arrived

1. Open the latest **Daily Wind Alarm Check** or **Daily Gardasee Wind Alarm Check** run. The step summary lists each station as `measured`, `stale`, or `fetch_failed`, with the knots, the UTC timestamp, and the source. Exit 0 means a fresh station reading. Exit 1 means only stale data. Exit 2 means nothing was read. A green run that printed `0.0 kt` and `fresh: False` was the old failure mode; current runs exit non-zero instead.
2. If there is no run in the local window, GitHub skipped it. Check CloudWatch for `SchedulerAlive` after Terraform is applied. A silent scheduler is the `wind-alarm-scheduler-silent` alarm.
3. Confirm the phone is subscribed: Kochelsee monitoring on (topic `wind_alarms_kochelsee`), Gardasee monitoring on (`wind_alarms_gardasee`). iOS needs the Push capability, an APNs key on Firebase project `wind-alarm-agent`, and Time Sensitive notifications allowed. See the notes on pull request #4 for the Firebase bundle id.
4. `FIREBASE_SERVICE_ACCOUNT_JSON` must be a key for project `wind-alarm-agent`. The log line names the project id and not the key.
5. The picture on the webcam can lag the station JSON by about a minute. The alarm uses the JSON. `python app.py --verify --location kochelsee` compares them and does not push.

### HTTP API

`src/wind_alarm/api.py` (started with `python app.py --api`):

- `GET /health`
- `GET /measurements` and `GET /measurements/{location}` (`X-API-Key`)
- `GET /measurements/{location}/history`
- `POST /trigger/{location}` with JSON `{"threshold": 10.5, "freshness": 15}`

Static files the app reads when `WindApiService` is in S3 mode:

- `measurements.json`
- `history/{location}.json`
- `forecast.json`

The bucket name is `wind-alarm-web-assets-<account-id>` (see Terraform and `app/lib/services/wind_api_service.dart`).

### Flutter app

`app/` is the iOS and Android client. It subscribes to the location FCM topics, polls the static JSON, and can schedule a local alarm from a push whose data contains `action=schedule_alarm`. The displayed alarm thresholds match the schedulers (10 kt Kochelsee, 12 kt Gardasee).

### Containers and Lambda

- `Dockerfile` serves the API (`python app.py --api`) on port 8000. `docker-compose.yml` publishes that port.
- `Dockerfile.lambda` is the Lambda image. The handler is `wind_alarm.aws.lambda_handler.handler`. Do not bake a Firebase service-account file into the image; pass `FIREBASE_SERVICE_ACCOUNT_JSON` at runtime.
- `make push-image` builds that image and pushes it to the ECR repository from Terraform outputs.

## Development setup

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

Python 3.10 or newer. The Lambda image uses 3.12; GitHub Actions use 3.10.

Flutter (from `app/`):

```bash
cd app
flutter pub get
```

## Running

```bash
# one-shot Kochelsee check at the scheduled threshold
PYTHONPATH=src python app.py --location kochelsee --threshold 10

# Gardasee
PYTHONPATH=src python app.py --location gardasee --threshold 12

# repeat every 30 minutes
PYTHONPATH=src python app.py --location kochelsee --threshold 10 --loop --interval 30

# HTTP API on port 8000
PYTHONPATH=src python app.py --api

# compare station JSON with the overlay; does not send a push
PYTHONPATH=src python app.py --verify --location kochelsee
PYTHONPATH=src python app.py --verify --location gardasee

# LangGraph (default) or Bedrock Agents
PYTHONPATH=src python app.py --orchestrator langgraph
```

`make run` starts `app.py` with its defaults (Kochelsee, threshold 12, LangGraph unless `USE_AWS` or `WIND_ALARM_ORCHESTRATOR` says otherwise). `--orchestrator` overrides that selection.

```bash
make up      # docker compose, API on :8000
make down
```

## Testing and lint

```bash
make test    # pytest
make lint    # pylint (src/, tests/, app.py)
make scan    # pip-audit, safety, and bandit; findings are reported, the target does not fail the build
```

`pytest.ini` puts `src/` and the repository root on the Python path, so `pytest` works without exporting `PYTHONPATH`.

Flutter:

```bash
cd app
flutter analyze
```

## Deployment

- **GitHub Actions.** `.github/workflows/ci.yml` runs tests, pylint, the security scan, and `make build` on pushes to `main` and `develop`. The two wind workflows above run on a schedule and can also be started with `workflow_dispatch`.
- **AWS.** `terraform/` creates ECR, the Lambda image function, DynamoDB, a public S3 bucket for the JSON the app polls, and the EventBridge rules. `make tf-init`, `make tf-plan`, and `make tf-apply` wrap Terraform. `make push-image` publishes `Dockerfile.lambda`.
- **Azure.** `terraform/azure.tf` defines a resource group, Azure OpenAI, Cosmos DB, a Blob container, and a Consumption Function App with `USE_AZURE=true`. The Function App image registry in that file is still `mcr.microsoft.com` and is not pointed at a built image. The Python code stores history in Cosmos DB and JSON in Blob Storage when `USE_AZURE` is set. `make tf-init` loads this stack together with the AWS files, because both live in `terraform/`.
- **iOS.** `.github/workflows/ios-deploy.yml` builds the Flutter iOS app on macOS and uploads it to TestFlight with an App Store Connect API key. The workflow runs on pushes to `main` and via `workflow_dispatch`.

## Environment variables and secrets

Names only. Do not commit values. `.env` is gitignored; `python-dotenv` loads it for local runs.

| Name | Used for |
| --- | --- |
| `API_KEY` | `X-API-Key` expected by the HTTP API. The code and the Flutter client ship with a development default; set a real value before exposing the API. |
| `HOST`, `PORT` | API bind address (default `0.0.0.0:8000`) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Firebase Admin service-account JSON. Preferred over a key file. |
| `FIREBASE_CREDENTIALS_PATH` | Path to a service-account JSON file (default `serviceAccountKey.json`) |
| `FCM_TOPIC` | Fallback topic when a run has no per-location topic. Scheduled alarms use the topics in the table above. |
| `USE_AWS`, `USE_AZURE` | Turn on the matching cloud OCR, history store, and static JSON upload |
| `WIND_ALARM_ORCHESTRATOR` | `langgraph` or `bedrock` |
| `WIND_ALARM_KB_TABLE` | DynamoDB table (default `wind-alarm-knowledge-base`) |
| `WIND_ALARM_BUCKET` | S3 bucket for `measurements.json`, history, and forecast |
| `BEDROCK_REGION`, `BEDROCK_OCR_MODEL_ID` | Bedrock runtime used for OCR and forecasts |
| `BEDROCK_AGENT_ID`, `BEDROCK_AGENT_ALIAS` | Required only for `--orchestrator bedrock` |
| `DEFAULT_LOCATION`, `DEFAULT_THRESHOLD`, `FRESHNESS_LIMIT` | Lambda alarm defaults |
| `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_KEY`, `AZURE_OPENAI_DEPLOYMENT_NAME` | Azure OpenAI vision |
| `AZURE_COSMOS_ENDPOINT`, `AZURE_COSMOS_KEY`, `AZURE_COSMOS_DB`, `AZURE_COSMOS_CONTAINER` | Cosmos DB history |
| `AZURE_STORAGE_CONNECTION_STRING` or `AZURE_STORAGE_ACCOUNT_URL` | Blob Storage |
| `AZURE_STORAGE_CONTAINER_NAME` | Blob container (default `wind-alarm-assets`) |

AWS credentials are the standard SDK variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` or an instance/task role).

GitHub Actions secrets:

| Secret | Used by |
| --- | --- |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `wind-alarm.yml`, `gardasee-alarm.yml` |
| `APP_STORE_CONNECT_KEY_CONTENT`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APPLE_TEAM_ID` | `ios-deploy.yml` |

## Layout

```text
app.py                         CLI and API entry point
src/wind_alarm/                graph, aggregator, API, forecast
src/wind_alarm/aws/            Lambda handler and Bedrock orchestrator
src/aws/  src/azure/           DynamoDB/S3 and Cosmos/Blob stores
src/handlers/lambda_handler.py legacy Lambda entry, same aggregation path
app/                           Flutter client
terraform/                     AWS resources
.github/workflows/             CI, both wind schedules, iOS TestFlight
```
