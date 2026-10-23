SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

TF := terraform -chdir=terraform
CHECKOV_VERSION := 3.3.30
MODULES := $(wildcard terraform/modules/*)

.PHONY: help fmt validate lint scan test check

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

check: ## Everything that needs no AWS account
	terraform fmt -check -recursive terraform
	$(MAKE) validate lint scan test
