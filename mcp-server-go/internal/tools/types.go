package tools

// Schema is a minimal JSON Schema representation that marshals
// to valid JSON Schema for the MCP protocol.
type Schema struct {
	Type        string             `json:"type,omitempty"`
	Description string             `json:"description,omitempty"`
	Properties  map[string]*Schema `json:"properties,omitempty"`
	Required    []string           `json:"required,omitempty"`
	Items       *Schema            `json:"items,omitempty"`
	Enum        []string           `json:"enum,omitempty"`
}

// ToolDef pairs a tool's MCP metadata with its mock response generator.
type ToolDef struct {
	Name        string
	Description string
	InputSchema *Schema
	MockFn      func(args map[string]any) any
	Runtime     bool // true = route to runtime (game process), not editor
}
