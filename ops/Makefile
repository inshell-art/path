SHELL := /bin/bash

ROOT := $(shell git rev-parse --show-toplevel)
NETWORK ?=
LANE ?=
RUN_ID ?=
BUNDLE_PATH ?=
AUDIT_ID ?=
AUDIT_PATH ?=
INPUT_FILE ?=
INPUT_KIND ?=
PARAMS_SCHEMA ?=
LOCKED_INPUTS_FILE ?=
INPUTS_TEMPLATE ?=

.PHONY: lock-inputs bundle verify approve apply postconditions audit-plan audit-collect audit-verify audit-report audit-signoff audit-all policy-init-check scan-secrets lint-secret-snippets

lock-inputs:
	NETWORK=$(NETWORK) LANE=$(LANE) RUN_ID=$(RUN_ID) INPUT_FILE=$(INPUT_FILE) INPUT_KIND=$(INPUT_KIND) PARAMS_SCHEMA=$(PARAMS_SCHEMA) $(ROOT)/ops/tools/lock_inputs.sh

bundle:
	NETWORK=$(NETWORK) LANE=$(LANE) RUN_ID=$(RUN_ID) LOCKED_INPUTS_FILE=$(or $(LOCKED_INPUTS_FILE),$(INPUTS_TEMPLATE)) INPUTS_TEMPLATE=$(INPUTS_TEMPLATE) $(ROOT)/ops/tools/bundle.sh

verify:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/verify_bundle.sh

approve:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/approve_bundle.sh

apply:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/apply_bundle.sh

postconditions:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/postconditions.sh

audit-plan:
	NETWORK=$(NETWORK) AUDIT_ID=$(AUDIT_ID) AUDIT_PATH=$(AUDIT_PATH) $(ROOT)/ops/tools/audit_plan.sh

audit-collect:
	NETWORK=$(NETWORK) AUDIT_ID=$(AUDIT_ID) AUDIT_PATH=$(AUDIT_PATH) $(ROOT)/ops/tools/audit_collect.sh

audit-verify:
	NETWORK=$(NETWORK) AUDIT_ID=$(AUDIT_ID) AUDIT_PATH=$(AUDIT_PATH) $(ROOT)/ops/tools/audit_verify.sh

audit-report:
	NETWORK=$(NETWORK) AUDIT_ID=$(AUDIT_ID) AUDIT_PATH=$(AUDIT_PATH) $(ROOT)/ops/tools/audit_report.sh

audit-signoff:
	NETWORK=$(NETWORK) AUDIT_ID=$(AUDIT_ID) AUDIT_PATH=$(AUDIT_PATH) $(ROOT)/ops/tools/audit_signoff.sh

audit-all: audit-plan audit-collect audit-verify audit-report

policy-init-check:
	NETWORK=$(NETWORK) $(ROOT)/ops/tools/check_policy_initialization.sh

scan-secrets:
	@if command -v gitleaks >/dev/null 2>&1; then \
	  if [[ -f ../gitleaks.toml ]]; then \
	    gitleaks detect --config ../gitleaks.toml; \
	  else \
	    gitleaks detect; \
	  fi; \
	else \
	  echo "gitleaks not found. Install it to run secret scans."; \
	  exit 2; \
	fi

lint-secret-snippets:
	NETWORK=$(NETWORK) $(ROOT)/ops/tools/lint_secret_snippets.sh
