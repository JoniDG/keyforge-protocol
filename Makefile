.PHONY: help generate generate-go generate-ts validate validate-frames validate-methods validate-events clean check-tools

SCHEMAS_DIR := schemas
EXAMPLES_DIR := examples
DIST_DIR    := dist
GO_OUT      := go/protocol
TS_OUT      := $(DIST_DIR)/ts

# Go-installed binaries (go-jsonschema) live in $GOPATH/bin which is not always
# on the user's PATH. Prepend it so make recipes always find them.
GOBIN := $(shell go env GOPATH)/bin
export PATH := $(GOBIN):$(PATH)

# All schema files, used as deps for generation.
COMMON_SCHEMA   := $(SCHEMAS_DIR)/common.schema.json
ENVELOPE_SCHEMA := $(SCHEMAS_DIR)/envelope.schema.json
METHOD_SCHEMAS  := $(wildcard $(SCHEMAS_DIR)/methods/*.schema.json)
EVENT_SCHEMAS   := $(wildcard $(SCHEMAS_DIR)/events/*.schema.json)
ALL_SCHEMAS     := $(COMMON_SCHEMA) $(ENVELOPE_SCHEMA) $(METHOD_SCHEMAS) $(EVENT_SCHEMAS)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

check-tools: ## Verify required generators are installed
	@command -v go-jsonschema >/dev/null 2>&1 || { echo "ERROR: go-jsonschema not found. Run: go install github.com/atombender/go-jsonschema@latest"; exit 1; }
	@command -v json2ts >/dev/null 2>&1 || { echo "ERROR: json-schema-to-typescript not found. Run: npm install -g json-schema-to-typescript"; exit 1; }
	@command -v ajv >/dev/null 2>&1 || { echo "ERROR: ajv-cli not found. Run: npm install -g ajv-cli"; exit 1; }

generate: check-tools generate-go generate-ts ## Generate Go and TS types from schemas

generate-go: ## Generate Go types into the go/ submodule
	@mkdir -p $(GO_OUT)
	$(GOBIN)/go-jsonschema -p protocol -o $(GO_OUT)/types.go $(ALL_SCHEMAS)
	@echo "✓ Generated Go types in $(GO_OUT)/"

generate-ts: ## Generate TypeScript types
	@mkdir -p $(TS_OUT)
	@for schema in $(ALL_SCHEMAS); do \
		base=$$(basename $$schema .schema.json); \
		dir=$$(dirname $$schema); \
		json2ts -i $$schema -o $(TS_OUT)/$$base.ts --cwd=$$dir >/dev/null; \
	done
	@echo "✓ Generated TS types in $(TS_OUT)/"

validate: check-tools validate-frames validate-methods validate-events ## Validate every example against its schema
	@echo "✓ All examples valid"

validate-frames: ## Validate envelope frames in examples/frames/
	@for ex in $(EXAMPLES_DIR)/frames/*.json; do \
		ajv validate -s $(ENVELOPE_SCHEMA) -d $$ex --spec=draft2020 -r $(COMMON_SCHEMA) || exit 1; \
	done

validate-methods: ## Validate method content examples in examples/methods/
	@for ex in $(EXAMPLES_DIR)/methods/*.json; do \
		base=$$(basename $$ex .json); \
		ajv validate -s $(SCHEMAS_DIR)/methods/$$base.schema.json -d $$ex --spec=draft2020 -r $(COMMON_SCHEMA) || exit 1; \
	done

validate-events: ## Validate event content examples in examples/events/
	@for ex in $(EXAMPLES_DIR)/events/*.json; do \
		base=$$(basename $$ex .json); \
		ajv validate -s $(SCHEMAS_DIR)/events/$$base.schema.json -d $$ex --spec=draft2020 -r $(COMMON_SCHEMA) || exit 1; \
	done

clean: ## Remove dist/
	rm -rf $(DIST_DIR)
	@echo "✓ Cleaned $(DIST_DIR)/"
