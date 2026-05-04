.PHONY: help generate generate-go generate-ts validate clean check-tools

SCHEMAS_DIR := schemas
DIST_DIR    := dist
GO_OUT      := $(DIST_DIR)/go
TS_OUT      := $(DIST_DIR)/ts

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

check-tools: ## Verify required generators are installed
	@command -v go-jsonschema >/dev/null 2>&1 || { echo "ERROR: go-jsonschema not found. Run: go install github.com/atombender/go-jsonschema@latest"; exit 1; }
	@command -v json2ts >/dev/null 2>&1 || { echo "ERROR: json-schema-to-typescript not found. Run: npm install -g json-schema-to-typescript"; exit 1; }
	@command -v ajv >/dev/null 2>&1 || { echo "ERROR: ajv-cli not found. Run: npm install -g ajv-cli"; exit 1; }

generate: check-tools generate-go generate-ts ## Generate Go and TS types from schemas

generate-go: ## Generate Go types
	@mkdir -p $(GO_OUT)
	go-jsonschema -p protocol -o $(GO_OUT)/types.go $(SCHEMAS_DIR)/**/*.schema.json $(SCHEMAS_DIR)/*.schema.json
	@echo "✓ Generated Go types in $(GO_OUT)/"

generate-ts: ## Generate TypeScript types
	@mkdir -p $(TS_OUT)
	@for schema in $(SCHEMAS_DIR)/common.schema.json $(SCHEMAS_DIR)/messages/*.schema.json; do \
		base=$$(basename $$schema .schema.json); \
		json2ts -i $$schema -o $(TS_OUT)/$$base.ts; \
	done
	@echo "✓ Generated TS types in $(TS_OUT)/"

validate: check-tools ## Validate examples/ against their schemas
	@echo "Validating examples..."
	@ajv validate -s $(SCHEMAS_DIR)/messages/c2s_set_binding.schema.json -d examples/c2s_set_binding.json --spec=draft2020 -r $(SCHEMAS_DIR)/common.schema.json
	@ajv validate -s $(SCHEMAS_DIR)/messages/s2c_input_event.schema.json -d examples/s2c_input_event.json --spec=draft2020 -r $(SCHEMAS_DIR)/common.schema.json
	@echo "✓ All examples valid"

clean: ## Remove dist/
	rm -rf $(DIST_DIR)
	@echo "✓ Cleaned $(DIST_DIR)/"
