# Wind Alarm Development Toolset

export PYTHONPATH := src:.

.PHONY: help setup run test lint scan build push-image tf-init tf-plan tf-apply tf-bootstrap-init tf-bootstrap-plan tf-azure-init up down clean

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Install dependencies and setup environment
	pip install -r requirements.txt
	playwright install chromium

run: ## Run the application locally
	python3 app.py

test: ## Run unit tests
	pytest tests/

lint: ## Run code quality checks
	pylint src/ tests/ app.py

scan: ## Run security audits
	bash scripts/security_scan.sh

build: ## Build standard Docker image
	docker build -t wind-alarm-agent .

tf-init: ## Initialize the AWS stack. Requires TF_STATE_BUCKET.
	@test -n "$(TF_STATE_BUCKET)" || { echo "Set TF_STATE_BUCKET. See docs/terraform-oidc.md"; exit 1; }
	cd terraform && terraform init -input=false -backend-config="bucket=$(TF_STATE_BUCKET)"

tf-plan: ## Plan AWS infrastructure changes
	cd terraform && terraform plan -input=false -lock-timeout=5m

tf-apply: ## Apply AWS infrastructure changes
	cd terraform && terraform apply -input=false -lock-timeout=5m -auto-approve

tf-bootstrap-init: ## Initialize the one-time GitHub OIDC bootstrap stack
	cd terraform/bootstrap && terraform init -input=false

tf-bootstrap-plan: ## Plan the one-time GitHub OIDC bootstrap stack
	cd terraform/bootstrap && terraform plan -input=false

tf-azure-init: ## Initialize the optional Azure stack
	cd terraform/azure && terraform init -input=false

push-image: ## Build and push container to AWS ECR
	$(eval ECR_URL=$(shell cd terraform && terraform output -raw ecr_repository_url))
	aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin $(ECR_URL)
	docker build -f Dockerfile.lambda -t $(ECR_URL):latest .
	docker push $(ECR_URL):latest

up: ## Start stack with Docker Compose
	docker-compose up -d

down: ## Stop stack
	docker-compose down

clean: ## Remove temporary files and cache
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	rm -rf .coverage htmlcov
