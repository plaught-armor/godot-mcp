GODOT ?= /mnt/based_backup/Repos/godot/bin/godot.linuxbsd.editor.x86_64
PROJECT := $(shell pwd)
GO_DIR := mcp-server-go

.PHONY: test test-gdscript test-go test-integration build clean

## Run all tests (except integration — that needs a free port)
test: test-gdscript test-go

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
