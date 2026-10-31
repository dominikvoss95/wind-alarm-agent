# Wind Alarm Agent

Wind Alarm watches live webcams at Kochelsee and Gardasee, reads the on-screen wind in knots, and sends a Firebase push when a fresh reading is strictly above that location's threshold. A Flutter app subscribes to those pushes, shows the latest reading, and can raise a local alarm.

## What it checks

| Location | Webcams | Alarm when | FCM topic |
| --- | --- | --- | --- |
| Kochelsee | Trimini | fresh base wind **> 10 kt** | `wind_alarms_kochelsee` |
| Gardasee | Malcesine Nord, Malcesine, Campione | fresh base wind **> 12 kt** at Malcesine Nord or Malcesine | `wind_alarms_gardasee` |

Campione is fetched and shown, but it does not raise the Gardasee alarm on its own. Gusts are stored and displayed; the alarm uses base wind only. Wind is in knots (`kts`), the unit printed on the addicted-sports.com overlay.

A reading is fresh when its timestamp is at most `freshness` minutes old (default 60). The scheduled jobs below are what actually pass 10 kt and 12 kt. `python app.py` without `--threshold` uses 12 kt for whichever location you select.

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

The graph lives in `src/wind_alarm/`. Locally, OCR is EasyOCR. With `USE_AZURE` or `USE_AWS`, the screenshot is read by Azure OpenAI or Amazon Bedrock instead. `app.py` runs the aggregator. `skip_notification` is set on each webcam run so only the aggregated push is sent.

A separate forecast path screenshots Windfinder, Windguru, and the Föhn diagram and asks the configured model for a German summary. Results are written to `forecast.json` on S3 or Azure Blob, or to a local file when neither cloud flag is set.

### Schedulers

Two schedulers exist. They do not share one window.

- GitHub Actions `wind-alarm.yml`: every 15 minutes from 03:00 through 06:45 UTC, Kochelsee, threshold 10.
- GitHub Actions `gardasee-alarm.yml`: every 15 minutes from 03:00 through 08:45 UTC, Gardasee, threshold 12.
- Terraform EventBridge (`terraform/main.tf`): every 5 minutes from 03:00 through 04:55 UTC (about 05:00–06:55 CEST). One rule invokes Lambda for **both** locations (thresholds 10 and 12). Gardasee's longer morning window is only covered by the GitHub workflow.

The Flutter home screen shows the EventBridge window (05:00–07:00, every 5 minutes). The GitHub workflows are the longer 15-minute checks.

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
