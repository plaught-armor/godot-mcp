// Package docs fetches Godot class reference XML from GitHub raw content
// on demand and caches parsed results in memory per session.
package docs

import (
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

const rawURL = "https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/%s.xml"

var (
	cache   = make(map[string]*GodotClass, 64)
	cacheMu sync.RWMutex
	client  = &http.Client{Timeout: 10 * time.Second}
)

type GodotClass struct {
	Name        string        `xml:"name,attr"`
	Inherits    string        `xml:"inherits,attr"`
	Brief       string        `xml:"brief_description"`
	Description string        `xml:"description"`
	Methods     []GodotMethod `xml:"methods>method"`
	Members     []GodotMember `xml:"members>member"`
	Signals     []GodotSignal `xml:"signals>signal"`
	Constants   []GodotConst  `xml:"constants>constant"`
}

type GodotMethod struct {
	Name        string     `xml:"name,attr"`
	Qualifiers  string     `xml:"qualifiers,attr"`
	Return      GodotRet   `xml:"return"`
	Args        []GodotArg `xml:"param"`
	Description string     `xml:"description"`
}

type GodotRet struct {
	Type string `xml:"type,attr"`
}

type GodotArg struct {
	Index   int    `xml:"index,attr"`
	Name    string `xml:"name,attr"`
	Type    string `xml:"type,attr"`
	Default string `xml:"default,attr"`
}

type GodotMember struct {
	Name        string `xml:"name,attr"`
	Type        string `xml:"type,attr"`
	Default     string `xml:"default,attr"`
	Description string `xml:",chardata"`
}

type GodotSignal struct {
	Name        string     `xml:"name,attr"`
	Args        []GodotArg `xml:"param"`
	Description string     `xml:"description"`
}

type GodotConst struct {
	Name  string `xml:"name,attr"`
	Value string `xml:"value,attr"`
	Enum  string `xml:"enum,attr"`
}

// FetchClass fetches and caches a class from GitHub raw XML.
func FetchClass(className string) (*GodotClass, error) {
	cacheMu.RLock()
	if c, ok := cache[className]; ok {
		cacheMu.RUnlock()
		return c, nil
	}
	cacheMu.RUnlock()

	url := fmt.Sprintf(rawURL, className)
	resp, err := client.Get(url)
	if err != nil {
		return nil, fmt.Errorf("fetch docs: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return nil, fmt.Errorf("class not found: %s", className)
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("GitHub returned %d for %s", resp.StatusCode, className)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read docs: %w", err)
	}

	var c GodotClass
	if err := xml.Unmarshal(body, &c); err != nil {
		return nil, fmt.Errorf("parse docs XML: %w", err)
	}

	// Clean whitespace in descriptions
	c.Brief = strings.TrimSpace(c.Brief)
	c.Description = strings.TrimSpace(c.Description)
	for i := range c.Methods {
		c.Methods[i].Description = strings.TrimSpace(c.Methods[i].Description)
	}
	for i := range c.Members {
		c.Members[i].Description = strings.TrimSpace(c.Members[i].Description)
	}
	for i := range c.Signals {
		c.Signals[i].Description = strings.TrimSpace(c.Signals[i].Description)
	}

	cacheMu.Lock()
	cache[className] = &c
	cacheMu.Unlock()

	return &c, nil
}

// CacheCount returns the number of cached classes.
func CacheCount() int {
	cacheMu.RLock()
	defer cacheMu.RUnlock()
	return len(cache)
}
