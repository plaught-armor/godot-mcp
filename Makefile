GODOT ?= /mnt/based_backup/Repos/godot/bin/godot.linuxbsd.editor.x86_64
PROJECT := $(shell pwd)
GO_DIR := mcp-server-go

.PHONY: test test-gdscript test-parse test-dispatchers test-go test-integration build clean

## Run all tests (except integration — that needs a free port)
test: test-parse test-dispatchers test-gdscript test-go

## Validate all @tool GDScript files parse in editor context
test-parse:
	@command -v $(GODOT) >/dev/null 2>&1 || { echo "GODOT binary not found: $(GODOT). Set GODOT= to override."; exit 1; }
	@echo "=== GDScript editor parse check ==="
	@timeout 30 $(GODOT) --headless --editor --path $(PROJECT) --script tests/test_editor_parse.gd 2>&1

## Test consolidated tool dispatcher routing (requires --editor)
test-dispatchers:
	@command -v $(GODOT) >/dev/null 2>&1 || { echo "GODOT binary not found: $(GODOT). Set GODOT= to override."; exit 1; }
	@echo "=== Dispatcher routing tests ==="
	@timeout 30 $(GODOT) --headless --editor --path $(PROJECT) --script tests/test_dispatchers.gd 2>&1

## Run GDScript unit tests via test runner
test-gdscript:
	@command -v $(GODOT) >/dev/null 2>&1 || { echo "GODOT binary not found: $(GODOT). Set GODOT= to override."; exit 1; }
	@echo "=== GDScript unit tests ==="
	@$(GODOT) --headless --path $(PROJECT) --script tests/test_runner.gd 2>&1

## Build and vet Go server
test-go:
	@echo "=== Go build + vet ==="
	@cd $(GO_DIR) && go build ./... && go vet ./...
	@echo "  OK"

## Integration test: Go server + headless Godot editor
test-integration:
	@bash tests/test_integration.sh "$(GODOT)"

## Build Go binary
build:
	@cd $(GO_DIR) && go build -o bin/godot-mcp-server ./cmd/godot-mcp-server

clean:
	@cd $(GO_DIR) && rm -rf bin/
