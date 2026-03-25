package mcpserver

import (
	"sync"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/bridge"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/tools"
)

// ToolSetManager dynamically manages which tool categories are exposed via MCP.
// Only core tools and explicitly enabled categories are visible to the AI client.
type ToolSetManager struct {
	server *mcp.Server
	bridge *bridge.GodotBridge
	mu     sync.Mutex
	active map[string]bool
}

func newToolSetManager(server *mcp.Server, b *bridge.GodotBridge) *ToolSetManager {
	return &ToolSetManager{
		server: server,
		bridge: b,
		active: make(map[string]bool),
	}
}

// EnableCategories activates one or more tool categories.
func (m *ToolSetManager) EnableCategories(cats ...string) []string {
	m.mu.Lock()
	defer m.mu.Unlock()

	var enabled []string
	for _, cat := range cats {
		if m.active[cat] {
			continue
		}
		defs := tools.ByCategory(cat)
		if len(defs) == 0 {
			continue
		}
		m.active[cat] = true
		for _, td := range defs {
			m.server.AddTool(
				&mcp.Tool{
					Name:        td.Name,
					Description: td.Description,
					InputSchema: td.InputSchema,
				},
				toolHandler(m.bridge, td),
			)
		}
		enabled = append(enabled, cat)
	}
	return enabled
}

// DisableCategories removes tool categories from the active set.
func (m *ToolSetManager) DisableCategories(cats ...string) []string {
	m.mu.Lock()
	defer m.mu.Unlock()

	var disabled []string
	var removeNames []string
	for _, cat := range cats {
		if !m.active[cat] {
			continue
		}
		for _, td := range tools.ByCategory(cat) {
			removeNames = append(removeNames, td.Name)
		}
		delete(m.active, cat)
		disabled = append(disabled, cat)
	}
	if len(removeNames) > 0 {
		m.server.RemoveTools(removeNames...)
	}
	return disabled
}

// ActiveCategories returns the currently enabled category names.
func (m *ToolSetManager) ActiveCategories() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]string, 0, len(m.active))
	for cat := range m.active {
		out = append(out, cat)
	}
	return out
}
