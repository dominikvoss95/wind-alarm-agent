# ==========================================
# Platform Engineering Toolset for Wind Alarm
# ==========================================

.PHONY: help setup run test lint scan build up down clean

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Install dependencies and setup local environment
	pip install -r requirements.txt
	@echo "Setup complete. Please ensure your .env file is configured."

run: ## Run the application locally
	python3 app.py --api

test: ## Run pytest suite
	pytest tests/

lint: ## Run pylint checks
	pylint src/ tests/ app.py --fail-under=8.0

scan: ## Run security scans (Linux Script)
	bash scripts/security_scan.sh

build: ## Build the Linux-based Docker image
	docker build -t wind-alarm-agent .

up: ## Start the platform using Docker Compose
	docker-compose up -d

down: ## Stop the platform
	docker-compose down

clean: ## Cleanup temporary Linux files and pycache
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	rm -rf .venv
	@echo "Cleanup complete."
