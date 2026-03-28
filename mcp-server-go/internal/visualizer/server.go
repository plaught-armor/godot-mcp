package visualizer

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/coder/websocket"
	"github.com/plaught-armor/godot-mcp/mcp-server-go/internal/bridge"
)

const defaultVizPort = 6510

// Server serves the project visualization and handles internal WebSocket commands.
type Server struct {
	mu         sync.Mutex
	bridge     bridge.Bridge
	httpServer *http.Server
}

// New creates a new visualization server.
func New(b bridge.Bridge) *Server {
	return &Server{bridge: b}
}

// Serve starts the visualization server and opens the browser.
// Returns the URL where the visualization is hosted.
func (s *Server) Serve(projectData any) (string, error) {
	s.Stop() // Close any previous instance

	// Inject git status into the project data
	projectData = s.injectGitStatus(projectData)

	dataJSON, err := json.Marshal(projectData)
	if err != nil {
		return "", fmt.Errorf("marshal project data: %w", err)
	}

	// Build the HTML page: inline CSS, reference JS modules externally
	htmlPage, err := buildHTML(dataJSON)
	if err != nil {
		return "", err
	}

	ln, err := findListener(defaultVizPort)
	if err != nil {
		return "", err
	}

	mux := http.NewServeMux()

	// Serve the assembled HTML at root
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			if r.Header.Get("Upgrade") == "websocket" {
				s.handleWS(w, r)
				return
			}
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-cache")
			w.Write([]byte(htmlPage))
			return
		}

		// Serve JS and CSS files from embedded assets
		name := strings.TrimPrefix(r.URL.Path, "/")
		if strings.Contains(name, "..") {
			http.NotFound(w, r)
			return
		}
		data, err := assets.ReadFile("assets/" + name)
		if err != nil {
			http.NotFound(w, r)
			return
		}

		ct := "application/octet-stream"
		switch {
		case strings.HasSuffix(name, ".js"):
			ct = "text/javascript; charset=utf-8"
		case strings.HasSuffix(name, ".css"):
			ct = "text/css; charset=utf-8"
		}
		w.Header().Set("Content-Type", ct)
		w.Header().Set("Cache-Control", "no-cache")
		w.Write(data)
	})

	srv := &http.Server{Handler: mux}

	s.mu.Lock()
	s.httpServer = srv
	s.mu.Unlock()

	go func() {
		if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
			log.Printf("[visualizer] Server error: %v", err)
		}
	}()

	port := ln.Addr().(*net.TCPAddr).Port
	url := fmt.Sprintf("http://localhost:%d", port)
	log.Printf("[visualizer] Serving at %s", url)

	if err := openBrowser(url); err != nil {
		log.Printf("[visualizer] Could not open browser: %v", err)
	}

	return url, nil
}

// Stop shuts down the visualization server.
func (s *Server) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.httpServer != nil {
		s.httpServer.Close()
		s.httpServer = nil
		log.Printf("[visualizer] Server stopped")
	}
}

// buildHTML assembles the final HTML page:
// - Reads template.html
// - Inlines visualizer.css into <style>
// - Replaces %%SCRIPT%% with a <script type="module"> that imports main.js
// - Injects project data as a global variable
func buildHTML(projectDataJSON []byte) (string, error) {
	templateBytes, err := assets.ReadFile("assets/template.html")
	if err != nil {
		return "", fmt.Errorf("read template.html: %w", err)
	}

	cssBytes, err := assets.ReadFile("assets/visualizer.css")
	if err != nil {
		return "", fmt.Errorf("read visualizer.css: %w", err)
	}

	html := string(templateBytes)

	// Inline CSS (same as TS version)
	html = strings.Replace(html, "%%CSS%%", string(cssBytes), 1)

	// Inject project data as a regular (non-module) script so it runs before
	// the ES module import.  Module imports are hoisted, so if both were in
	// the same <script type="module">, the import would execute first and
	// state.js would read window.__PROJECT_DATA__ before it was set.
	//
	// Escape "</script>" inside JSON strings to prevent XSS breakout.
	safeJSON := strings.ReplaceAll(string(projectDataJSON), "</script>", `<\/script>`)
	dataScript := fmt.Sprintf("window.__PROJECT_DATA__ = %s;", safeJSON)
	html = strings.Replace(html, "%%DATA%%", dataScript, 1)

	return html, nil
}

type wsMessage struct {
	ID      int            `json:"id"`
	Command string         `json:"command"`
	Args    map[string]any `json:"args"`
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		OriginPatterns: []string{"localhost:*", "127.0.0.1:*"},
	})
	if err != nil {
		log.Printf("[visualizer] WebSocket accept error: %v", err)
		return
	}
	defer conn.CloseNow()

	conn.SetReadLimit(10 * 1024 * 1024) // 10 MB — match bridge limit

	log.Printf("[visualizer] Browser connected via WebSocket")

	ctx := r.Context()
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			break
		}

		var msg wsMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("[visualizer] Invalid JSON from browser: %v", err)
			conn.Write(ctx, websocket.MessageText, mustJSON(map[string]any{"error": "invalid JSON"}))
			continue
		}

		result := s.handleInternalCommand(ctx, msg.Command, msg.Args)
		result["id"] = msg.ID

		conn.Write(ctx, websocket.MessageText, mustJSON(result))
	}

	log.Printf("[visualizer] Browser disconnected")
}

// allowedCommands is the set of Godot tools the visualizer is permitted to invoke.
var allowedCommands = map[string]bool{
	"scene_edit":                true,
	"create_script_file":        true,
	"delete_script":             true,
	"edit_script":               true,
	"get_scene_hierarchy":       true,
	"get_scene_node_properties": true,
	"map_project":               true,
	"map_scenes":                true,
	"modify_function":           true,
	"modify_function_delete":    true,
	"modify_signal":             true,
	"modify_variable":           true,
	"rename_script":             true,
	"set_scene_node_property":   true,
}

func (s *Server) handleInternalCommand(ctx context.Context, command string, args map[string]any) map[string]any {
	if s.bridge == nil {
		return map[string]any{"error": "Bridge not initialized"}
	}
	if !s.bridge.IsConnected() {
		return map[string]any{"error": "Godot is not connected"}
	}
	if !allowedCommands[command] {
		return map[string]any{"error": "Command not allowed: " + command}
	}

	log.Printf("[visualizer] Internal command: %s", command)

	raw, err := s.bridge.InvokeTool(ctx, command, args, "")
	if err != nil {
		return map[string]any{"error": err.Error()}
	}

	var result map[string]any
	if err := json.Unmarshal(raw, &result); err != nil {
		return map[string]any{"error": "Invalid response from Godot"}
	}
	return result
}

func findListener(start int) (net.Listener, error) {
	for port := start; port < start+100; port++ {
		ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err == nil {
			return ln, nil
		}
	}
	return nil, fmt.Errorf("no available port found starting from %d", start)
}

func mustJSON(v any) []byte {
	data, _ := json.Marshal(v)
	return data
}

// injectGitStatus adds git_status to the project data map.
func (s *Server) injectGitStatus(projectData any) any {
	projectPath := ""
	if s.bridge != nil {
		status := s.bridge.GetStatus()
		// Use primary instance's project path
		for _, inst := range status.Instances {
			if inst.Primary {
				projectPath = inst.ProjectPath
				break
			}
		}
	}
	if projectPath == "" {
		return projectData
	}

	gitStatus := getGitStatus(projectPath)
	if gitStatus == nil {
		return projectData
	}

	// The project data is a map[string]any with "project_map" key
	dataMap, ok := projectData.(map[string]any)
	if !ok {
		return projectData
	}
	dataMap["git_status"] = gitStatus
	return dataMap
}

// getGitStatus runs git commands to determine file statuses.
// Returns a map of relative res:// paths to their git status.
func getGitStatus(projectPath string) map[string]string {
	// Find the git repo root from the project path
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	cmd.Dir = projectPath
	out, err := cmd.Output()
	if err != nil {
		log.Printf("[visualizer] Not a git repo or git not found: %v", err)
		return nil
	}
	gitRoot := strings.TrimSpace(string(out))

	// Run git status --porcelain to get all changed files
	cmd = exec.Command("git", "status", "--porcelain")
	cmd.Dir = gitRoot
	out, err = cmd.Output()
	if err != nil {
		log.Printf("[visualizer] git status failed: %v", err)
		return nil
	}

	result := make(map[string]string)
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	for _, line := range lines {
		if len(line) < 4 {
			continue
		}
		status := strings.TrimSpace(line[:2])
		filePath := strings.TrimSpace(line[3:])

		// Handle renamed files (old -> new)
		if idx := strings.Index(filePath, " -> "); idx >= 0 {
			filePath = filePath[idx+4:]
		}

		// Convert absolute git path to res:// path
		absPath := filepath.Join(gitRoot, filePath)
		relPath, err := filepath.Rel(projectPath, absPath)
		if err != nil {
			continue
		}

		// Skip files outside the project
		if strings.HasPrefix(relPath, "..") {
			continue
		}

		// Only track .gd files
		if !strings.HasSuffix(relPath, ".gd") {
			continue
		}

		resPath := "res://" + filepath.ToSlash(relPath)

		// Map git status codes to simple labels
		switch {
		case status == "??" || status == "A" || status == "AM":
			result[resPath] = "added"
		case strings.Contains(status, "M"):
			result[resPath] = "modified"
		case strings.Contains(status, "D"):
			result[resPath] = "deleted"
		case strings.Contains(status, "R"):
			result[resPath] = "renamed"
		default:
			result[resPath] = "changed"
		}
	}

	if len(result) > 0 {
		log.Printf("[visualizer] Git status: %d modified .gd files", len(result))
	}

	return result
}
