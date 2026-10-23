SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

TF := terraform -chdir=terraform
CHECKOV_VERSION := 3.3.30
MODULES := $(wildcard terraform/modules/*)

.PHONY: help fmt validate lint scan test function-check integration build check

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

build: ## Package the function into build/function (locked, hash-verified, linux arm64)
	rm -rf build
	mkdir -p build/function
	cd function && uv export --frozen --no-dev --no-emit-project -o $(CURDIR)/build/requirements.txt
	uv pip install --quiet --target build/function --python-platform aarch64-manylinux2014 --python-version 3.13 --require-hashes --no-deps -r build/requirements.txt
	cp function/handler.py build/function/
	cp -R function/certs build/function/
	find build/function -name __pycache__ -type d -prune -exec rm -rf {} +

check: ## Everything that needs no AWS account
	terraform fmt -check -recursive terraform
	$(MAKE) validate lint scan test function-check
