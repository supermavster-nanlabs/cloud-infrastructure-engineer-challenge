SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

TF := terraform -chdir=terraform
CHECKOV_VERSION := 3.3.30
MODULES := $(wildcard terraform/modules/*)

# Deployment settings. The GitHub workflow sets the same names.
ENV ?= dev
REGION ?= us-east-1
STATE_BUCKET ?=
STATE_REGION ?= us-east-1
PLAN_FLAGS ?=
LOCK_ID ?=
CONFIRM ?=
TFVARS := -var-file=environments/$(ENV).tfvars -var region=$(REGION)
PLAN_FILE := $(ENV)-$(REGION).tfplan

.PHONY: help fmt validate lint scan test function-check integration local-up local-down local-invoke build state-bucket check-env check-state check-plan init plan apply destroy unlock verify logs check

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

fmt: ## Rewrite Terraform files to canonical format
	terraform fmt -recursive terraform

validate: ## Validate the Terraform configuration (no AWS access needed)
	$(TF) init -backend=false -input=false >/dev/null
	$(TF) validate

lint: ## Run tflint on the root and every module
	tflint --init --config=$(CURDIR)/.tflint.hcl
	tflint --recursive --config=$(CURDIR)/.tflint.hcl

scan: ## Run checkov security checks (pinned version, run through uvx)
	uvx --from checkov==$(CHECKOV_VERSION) checkov --config-file .checkov.yaml

test: ## Run the Terraform tests (mocked AWS provider, no credentials needed)
	@for dir in $(MODULES); do \
		test -d $$dir/tests || continue; \
		echo "test $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$dir test; \
	done
	@echo "test terraform (whole stack)"
	@$(TF) init -backend=false -input=false >/dev/null
	@$(TF) test

function-check: ## Lint the Lambda function and run its unit tests
	cd function && uv run ruff check . && uv run ruff format --check . && uv run pytest -m "not integration"

integration: ## Run the integration tests against the PostgreSQL in the DB_* variables
	cd function && uv run pytest -m integration

local-up: ## Start a local PostgreSQL in Docker (creates local/.env from the example)
	@test -f local/.env || cp local/.env.example local/.env
	docker compose --env-file local/.env -f local/docker-compose.yml up -d --wait

local-down: ## Stop the local PostgreSQL and discard its data
	docker compose --env-file local/.env -f local/docker-compose.yml down -v

local-invoke: ## Run the real handler once against the database in local/.env
	@test -f local/.env || { echo "missing local/.env: run make local-up first"; exit 1; }
	set -a && . local/.env && set +a && cd function && uv run python invoke_local.py

build: ## Package the function into build/function (locked, hash-verified, linux arm64)
	rm -rf build
	mkdir -p build/function
	cd function && uv export --frozen --no-dev --no-emit-project -o $(CURDIR)/build/requirements.txt
	uv pip install --quiet --target build/function --python-platform aarch64-manylinux2014 --python-version 3.13 --require-hashes --no-deps -r build/requirements.txt
	cp function/handler.py build/function/
	cp -R function/certs build/function/
	find build/function -name __pycache__ -type d -prune -exec rm -rf {} +

check-env:
	@test -f terraform/environments/$(ENV).tfvars || { echo "unknown ENV '$(ENV)': use dev or prod"; exit 1; }

check-plan:
	@test -f terraform/$(PLAN_FILE) || { echo "no saved plan for $(ENV) in $(REGION): run make plan first"; exit 1; }

check-state:
	@test -n "$(STATE_BUCKET)" || { echo "set STATE_BUCKET to your state bucket (make state-bucket creates one)"; exit 1; }

state-bucket: check-state ## Create the S3 bucket that holds the state (once per account)
	aws s3api create-bucket --bucket $(STATE_BUCKET) --region $(STATE_REGION) $(if $(filter us-east-1,$(STATE_REGION)),,--create-bucket-configuration LocationConstraint=$(STATE_REGION))
	aws s3api put-bucket-versioning --bucket $(STATE_BUCKET) --region $(STATE_REGION) --versioning-configuration Status=Enabled
	aws s3api put-bucket-encryption --bucket $(STATE_BUCKET) --region $(STATE_REGION) --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
	aws s3api put-public-access-block --bucket $(STATE_BUCKET) --region $(STATE_REGION) --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

init: check-env check-state ## Connect to the shared state for ENV and REGION
	$(TF) init -input=false -reconfigure \
		-backend-config="bucket=$(STATE_BUCKET)" \
		-backend-config="key=info-api-lean/$(ENV)/$(REGION)/terraform.tfstate" \
		-backend-config="region=$(STATE_REGION)" \
		-backend-config="use_lockfile=true" \
		-backend-config="encrypt=true"

plan: build init ## Plan ENV in REGION and save the plan (PLAN_FLAGS=-destroy plans a destroy)
	$(TF) plan -input=false -lock-timeout=60s $(TFVARS) $(PLAN_FLAGS) -out=$(PLAN_FILE)

apply: check-plan init ## Apply the plan saved by make plan, and nothing else
	$(TF) apply -input=false -lock-timeout=60s $(PLAN_FILE)

destroy: check-env ## Destroy ENV in REGION. Needs CONFIRM=<ENV>, and Terraform still asks
	@test "$(CONFIRM)" = "$(ENV)" || { echo "refusing to destroy: run make destroy ENV=$(ENV) CONFIRM=$(ENV)"; exit 1; }
	@$(MAKE) --no-print-directory build init
	$(TF) destroy -lock-timeout=60s $(TFVARS)

unlock: check-env ## Release a stuck state lock. Needs LOCK_ID and CONFIRM=<ENV>
	@test -n "$(LOCK_ID)" || { echo "set LOCK_ID to the ID in the 'state is locked' error"; exit 1; }
	@test "$(CONFIRM)" = "$(ENV)" || { echo "refusing to unlock: run make unlock ENV=$(ENV) CONFIRM=$(ENV) LOCK_ID=<id>"; exit 1; }
	@$(MAKE) --no-print-directory init
	$(TF) force-unlock -force $(LOCK_ID)

verify: init ## Call the deployed endpoint and print the response
	curl -sS --fail-with-body "$$($(TF) output -raw info_url)" | jq .

logs: init ## Tail the Lambda's CloudWatch logs (needs the AWS CLI)
	aws logs tail "$$($(TF) output -raw lambda_log_group_name)" --region $(REGION) --since 15m --follow

check: ## Everything that needs no AWS account
	terraform fmt -check -recursive terraform
	$(MAKE) validate lint scan test function-check
