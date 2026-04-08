package main

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const defaultHTTPPort = 6506

func resolveHTTPPort() int {
	if v := os.Getenv("GODOT_MCP_HTTP_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			return p
		}
	}
	return defaultHTTPPort
}

// runClient connects to an existing HTTP daemon (or starts one) and proxies
// MCP JSON-RPC between stdio and the daemon's Streamable HTTP endpoint.
func runClient(ctx context.Context) error {
	port := resolveHTTPPort()
	endpoint := fmt.Sprintf("http://localhost:%d/mcp", port)

	if err := ensureDaemon(port); err != nil {
		return err
	}

	return proxyStdio(ctx, endpoint, port)
}

// ensureDaemon checks whether the HTTP daemon is reachable. If not, it takes
// the daemon lockfile (blocking) to serialize with other clients, then spawns
// the daemon and waits for it to become ready.
func ensureDaemon(port int) error {
	addr := "localhost:" + strconv.Itoa(port)

	if conn, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
		conn.Close()
		log.Printf("[client] Daemon already running on port %d", port)
		return nil
	}

	// Take a blocking lock — if another client is already spawning, we wait
	// for it to finish rather than spawning a second daemon.
	lf, err := os.OpenFile(lockPath(), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return fmt.Errorf("open lockfile: %w", err)
	}
	syscall.Flock(int(lf.Fd()), syscall.LOCK_EX) // blocking
	defer func() {
		syscall.Flock(int(lf.Fd()), syscall.LOCK_UN)
		lf.Close()
	}()

	// Re-check after acquiring lock — another client may have started it.
	if conn, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
		conn.Close()
		log.Printf("[client] Daemon already running on port %d", port)
		return nil
	}

	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve executable: %w", err)
	}

	log.Printf("[client] Starting daemon: %s", exe)
	cmd := exec.Command(exe)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Env = os.Environ()
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start daemon: %w", err)
	}
	cmd.Process.Release() // detach — daemon outlives client

	// Release the lock so the daemon can acquire it during startup.
	// The lock's purpose (serializing client spawns) is already fulfilled.
	syscall.Flock(int(lf.Fd()), syscall.LOCK_UN)

	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if conn, err := net.DialTimeout("tcp", addr, 500*time.Millisecond); err == nil {
			conn.Close()
			log.Printf("[client] Daemon ready on port %d", port)
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("daemon did not start within 10s")
}

// proxyStdio reads JSON-RPC messages from stdin, POSTs each to the HTTP
// endpoint, and writes responses to stdout. It also opens an SSE stream
// for server-initiated notifications (e.g. tools/list_changed).
func proxyStdio(ctx context.Context, endpoint string, port int) error {
	client := &http.Client{Timeout: 5 * time.Minute}

	var (
		sessionID string
		sessionMu sync.Mutex
		writeMu   sync.Mutex
		sseReady  = make(chan struct{})
	)

	writeStdout := func(data []byte) {
		writeMu.Lock()
		os.Stdout.Write(data)
		os.Stdout.Write([]byte("\n"))
		writeMu.Unlock()
	}

	// resetSession clears the session ID so the next request re-initializes.
	resetSession := func() {
		sessionMu.Lock()
		sessionID = ""
		sessionMu.Unlock()
	}

	// Open SSE notification stream once the session is established.
	go func() {
		<-sseReady

		sessionMu.Lock()
		sid := sessionID
		sessionMu.Unlock()
		if sid == "" {
			return
		}

		req, _ := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
		req.Header.Set("Accept", "text/event-stream")
		req.Header.Set("Mcp-Session-Id", sid)

		resp, err := client.Do(req)
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("[client] SSE stream error: %v", err)
			}
			return
		}
		defer resp.Body.Close()

		readSSE(resp.Body, writeStdout)
	}()

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1<<20), 1<<20)

	sseStarted := false
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}

		req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(line))
		if err != nil {
			log.Printf("[client] Bad request: %v", err)
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/json, text/event-stream")

		sessionMu.Lock()
		if sessionID != "" {
			req.Header.Set("Mcp-Session-Id", sessionID)
		}
		sessionMu.Unlock()

		resp, err := client.Do(req)
		if err != nil {
			// Daemon likely died — restart it and retry once.
			log.Printf("[client] HTTP error: %v — restarting daemon", err)
			resetSession()
			if derr := ensureDaemon(port); derr != nil {
				log.Printf("[client] Failed to restart daemon: %v", derr)
				continue
			}
			req, _ = http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(line))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Accept", "application/json, text/event-stream")
			resp, err = client.Do(req)
			if err != nil {
				log.Printf("[client] HTTP retry failed: %v", err)
				continue
			}
		}

		if sid := resp.Header.Get("Mcp-Session-Id"); sid != "" {
			sessionMu.Lock()
			sessionID = sid
			sessionMu.Unlock()
			if !sseStarted {
				sseStarted = true
				close(sseReady)
			}
		}

		switch {
		case resp.StatusCode == http.StatusAccepted:
			// Notification acknowledged — no response to forward.
			resp.Body.Close()

		case strings.HasPrefix(resp.Header.Get("Content-Type"), "text/event-stream"):
			readSSE(resp.Body, writeStdout)
			resp.Body.Close()

		default:
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if len(body) > 0 {
				writeStdout(body)
			}
		}
	}

	return scanner.Err()
}

// readSSE reads an SSE stream and calls emit for each data payload.
func readSSE(r io.Reader, emit func([]byte)) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 1<<20), 1<<20)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "data: ") {
			emit([]byte(line[6:]))
		}
	}
}
