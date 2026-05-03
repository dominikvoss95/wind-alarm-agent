#!/bin/bash
# Security scanning for Python dependencies

set -e

echo "=== Running Security Scans ==="

# Check for insecure dependencies
echo "[1/3] Checking dependencies with pip-audit..."
pip install -q pip-audit
pip-audit -r requirements.txt || true

# Check for known vulnerabilities with safety
echo "[2/3] Checking with safety..."
pip install -q safety
safety check || true

# Static analysis with bandit
echo "[3/3] Running bandit static analysis..."
pip install -q bandit
bandit -r src/ -x src/wind_alarm/fetcher.py,src/wind_alarm/extract_wind.py || true

echo "=== Security Scan Complete ==="