# Wind Alarm Agent

A Python-based wind alarm agent that checks a primary wind data source for Kochelsee and triggers a notification when the configured base wind threshold is exceeded.

## Tech Stack
- Python
- LangGraph
- httpx
- Pydantic
- Pytest
- MkDocs

## Development Setup

1. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Run Tests
   ```bash
   pytest
   ```

4. Run Linting
   ```bash
   pylint src/ tests/
   ```
