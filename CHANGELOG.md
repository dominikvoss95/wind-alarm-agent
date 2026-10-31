# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
### Fixed
- LangGraph dropped `skip_notification`, so each webcam could send its own push in addition to the aggregated alert.
- `POST /trigger/{location}` ignored the JSON `threshold` and `freshness` and always used the defaults.
- Local OCR treated a screenshot with no wind label as a successful 0 kt reading. Azure OpenAI and Bedrock responses missing `wind` now fail the same way.
- History queries with `USE_AZURE` returned mock data. Forecast runs with `USE_AZURE` were not uploaded to Blob Storage.
- DynamoDB writes failed when `observed_at` was present but null. S3 and Blob measurement JSON now include `updated_at`, `fetch_status`, `base_wind`, and `gust`, which the Flutter client needs to treat a reading as fresh.
- The Flutter client also accepts `parse_status` / `observed_at` on older JSON, skips broken history rows, and shows the real alarm thresholds (10 kt Kochelsee, 12 kt Gardasee) instead of a hard-coded 12 kt and 14 kt.
- `app.py --orchestrator` was ignored. `app.py --api` starts the HTTP API, which the Docker image already expected.
- `src/wind_alarm/fetcher.py` imported the missing `wind_vision` package.
- Firebase Admin can initialize from `FIREBASE_SERVICE_ACCOUNT_JSON` without a key file in the image.
- CI workflow had a duplicate `branches` key. The wind workflows referenced `secrets` in an `if:` condition (GitHub rejects that) and installed Playwright without OS dependencies.
- The Kochelsee workflow's fallback FCM topic did not match `wind_alarms_kochelsee`. The EventBridge description quoted a UTC window the cron expression does not run.

### Changed
- README now covers the agent, both schedules, Lambda/Docker, the Flutter app, and the environment variable names.
- `requirements.txt` includes `python-dotenv`, `fastapi`, and `uvicorn`, which the API and config loader import.
- Pylint is configured in `.pylintrc` so `make lint` checks the current tree without a style-only rewrite.

### Added
- Initial project structure created.
- Dependencies defined in `requirements.txt`.
- `README.md` and `CHANGELOG.md` created.
