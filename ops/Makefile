SHELL := /bin/bash

ROOT := $(shell git rev-parse --show-toplevel)
NETWORK ?=
LANE ?=
RUN_ID ?=
BUNDLE_PATH ?=

.PHONY: bundle verify approve apply postconditions scan-secrets

bundle:
	NETWORK=$(NETWORK) LANE=$(LANE) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/bundle.sh

verify:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/verify_bundle.sh

approve:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/approve_bundle.sh

apply:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/apply_bundle.sh

postconditions:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) BUNDLE_PATH=$(BUNDLE_PATH) $(ROOT)/ops/tools/postconditions.sh

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
