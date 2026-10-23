SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

TF := terraform -chdir=terraform
CHECKOV_VERSION := 3.3.30
MODULES := $(wildcard terraform/modules/*)

.PHONY: help fmt validate lint scan test function-check integration local-up local-down local-invoke build plan apply destroy verify logs check

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

plan: build ## Plan and save the plan to review (needs AWS credentials)
	$(TF) init -input=false
	$(TF) plan -input=false -out=main.tfplan

apply: ## Apply the plan saved by make plan, and nothing else
	@test -f terraform/main.tfplan || { echo "no saved plan: run make plan and review it first"; exit 1; }
	$(TF) apply -input=false main.tfplan

destroy: ## Destroy everything. Needs CONFIRM=yes, and Terraform still asks
	@test "$(CONFIRM)" = yes || { echo "refusing to destroy: run make destroy CONFIRM=yes"; exit 1; }
	@$(MAKE) --no-print-directory build
	$(TF) destroy

verify: ## Call the deployed endpoint and print the response
	curl -sS --fail-with-body "$$($(TF) output -raw info_url)" | jq .

logs: ## Tail the Lambda's CloudWatch logs (needs the AWS CLI)
	aws logs tail "$$($(TF) output -raw lambda_log_group_name)" --since 15m --follow

check: ## Everything that needs no AWS account
	terraform fmt -check -recursive terraform
	$(MAKE) validate lint scan test function-check
