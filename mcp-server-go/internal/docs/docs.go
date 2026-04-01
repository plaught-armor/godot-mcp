// Package docs provides embedded Godot class reference documentation
// from the official XML files in godot/doc/classes/.
package docs

import (
	"embed"
	"encoding/xml"
	"log"
	"strings"
	"sync"
)

//go:embed classes/*.xml
var classFiles embed.FS

// GodotClass represents a parsed class from the XML reference.
type GodotClass struct {
	Name             string         `xml:"name,attr"`
	Inherits         string         `xml:"inherits,attr"`
	BriefDescription string         `xml:"brief_description"`
	Description      string         `xml:"description"`
	Methods          []GodotMethod  `xml:"methods>method"`
	Members          []GodotMember  `xml:"members>member"`
	Signals          []GodotSignal  `xml:"signals>signal"`
	Constants        []GodotConst   `xml:"constants>constant"`
}

// GodotMethod represents a method in the class reference.
type GodotMethod struct {
	Name        string        `xml:"name,attr"`
	Qualifiers  string        `xml:"qualifiers,attr"`
	Return      GodotReturn   `xml:"return"`
	Arguments   []GodotArg    `xml:"param"`
	Description string        `xml:"description"`
}

// GodotReturn is a method return type.
type GodotReturn struct {
	Type string `xml:"type,attr"`
}

// GodotArg is a method argument.
type GodotArg struct {
	Index   int    `xml:"index,attr"`
	Name    string `xml:"name,attr"`
	Type    string `xml:"type,attr"`
	Default string `xml:"default,attr"`
}

// GodotMember is a class property.
type GodotMember struct {
	Name        string `xml:"name,attr"`
	Type        string `xml:"type,attr"`
	Default     string `xml:"default,attr"`
	Description string `xml:",chardata"`
}

// GodotSignal is a signal definition.
type GodotSignal struct {
	Name        string     `xml:"name,attr"`
	Arguments   []GodotArg `xml:"param"`
	Description string     `xml:"description"`
}

// GodotConst is a constant or enum value.
type GodotConst struct {
	Name        string `xml:"name,attr"`
	Value       string `xml:"value,attr"`
	Enum        string `xml:"enum,attr"`
	Description string `xml:",chardata"`
}

var (
	classes     map[string]*GodotClass
	classNames  []string
	loadOnce    sync.Once
)

func ensureLoaded() {
	loadOnce.Do(func() {
		classes = make(map[string]*GodotClass, 1000)
		entries, err := classFiles.ReadDir("classes")
		if err != nil {
			log.Printf("[docs] Failed to read embedded classes: %v", err)
			return
		}
		for _, e := range entries {
			if !strings.HasSuffix(e.Name(), ".xml") {
				continue
			}
			data, err := classFiles.ReadFile("classes/" + e.Name())
			if err != nil {
				continue
			}
			var c GodotClass
			if xml.Unmarshal(data, &c) == nil && c.Name != "" {
				classes[c.Name] = &c
				classNames = append(classNames, c.Name)
			}
		}
		log.Printf("[docs] Loaded %d class references", len(classes))
	})
}

// LookupClass returns a class by exact name.
func LookupClass(name string) *GodotClass {
	ensureLoaded()
	return classes[name]
}

// SearchClasses returns class names matching a substring (case-insensitive).
func SearchClasses(query string, limit int) []string {
	ensureLoaded()
	q := strings.ToLower(query)
	results := make([]string, 0, limit)
	for _, name := range classNames {
		if strings.Contains(strings.ToLower(name), q) {
			results = append(results, name)
			if len(results) >= limit {
				break
			}
		}
	}
	return results
}

// SearchMethods finds methods matching a name substring across all classes.
func SearchMethods(query string, limit int) []map[string]string {
	ensureLoaded()
	q := strings.ToLower(query)
	results := make([]map[string]string, 0, limit)
	for _, name := range classNames {
		c := classes[name]
		for _, m := range c.Methods {
			if strings.Contains(strings.ToLower(m.Name), q) {
				results = append(results, map[string]string{
					"class":  c.Name,
					"method": m.Name,
					"return": m.Return.Type,
				})
				if len(results) >= limit {
					return results
				}
			}
		}
	}
	return results
}

// ClassCount returns the number of loaded classes.
func ClassCount() int {
	ensureLoaded()
	return len(classes)
}
