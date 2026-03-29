package uht

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ModuleRegistryEntry represents a module in the registry JSON
type ModuleRegistryEntry struct {
	Name    string   `json:"name"`
	Type    string   `json:"type"`
	BaseDir string   `json:"base_dir"` // relative to Engine/Source, e.g., "Runtime/Core"
	Deps    []string `json:"deps"`     // dependency module names for topological sorting
}

// GenerateMultiModuleManifestOptions contains parameters for multi-module manifest generation
type GenerateMultiModuleManifestOptions struct {
	Registry     []ModuleRegistryEntry // All modules to include
	UESourceRoot string               // Absolute path to Engine/Source directory
	OutputRoot   string               // Root output directory for all modules
	UERoot       string               // Unreal Engine root directory
	TargetName   string
	IsGameTarget bool
}

// GenerateMultiModuleManifest creates a UHT manifest with all modules
func GenerateMultiModuleManifest(opts GenerateMultiModuleManifestOptions) ([]byte, error) {
	if opts.TargetName == "" {
		opts.TargetName = "BazelTarget"
	}

	absUERoot, err := filepath.Abs(opts.UERoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve UE root: %w", err)
	}

	absOutputRoot, err := filepath.Abs(opts.OutputRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve output root: %w", err)
	}

	absUESourceRoot, err := filepath.Abs(opts.UESourceRoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve UE source root: %w", err)
	}

	moduleTypePrefix := "Engine"
	if opts.IsGameTarget {
		moduleTypePrefix = "Game"
	}

	// Topological sort — UHT processes modules sequentially and needs base types
	// registered before derived types
	sortedRegistry := topologicalSort(opts.Registry)

	var modules []UHTModule
	globalSeenBasenames := make(map[string]bool)

	for _, entry := range sortedRegistry {
		moduleDir := filepath.Join(absUESourceRoot, entry.BaseDir)

		// Skip if directory doesn't exist
		if _, err := os.Stat(moduleDir); os.IsNotExist(err) {
			continue
		}

		// Skip Stub modules — they conflict with their real counterparts
		if strings.Contains(entry.BaseDir, "/Stub") || strings.HasSuffix(entry.Name, "Stub") {
			continue
		}

		// Discover headers (including legacy Classes/ directory)
		allHeaders := make([]string, 0)
		for _, subdir := range []string{"Public", "Internal", "Private", "Classes"} {
			dir := filepath.Join(moduleDir, subdir)
			if _, err := os.Stat(dir); os.IsNotExist(err) {
				continue
			}
			filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
				if err != nil {
					return nil
				}
				if !info.IsDir() && strings.HasSuffix(path, ".h") {
					allHeaders = append(allHeaders, path)
				}
				return nil
			})
		}

		// Filter to only headers with reflection macros
		filteredHeaders := FilterHeaders(allHeaders)

		// Skip NoExportTypes.h from output (its .gen.cpp references types from Slate/Engine)
		// But keep it in the header list so UHT can find base type definitions
		publicHeaders := make([]string, 0)
		for _, h := range filteredHeaders {
			basename := filepath.Base(h)

			// Skip duplicate basenames globally (UHT requirement — unique across ALL modules)
			if globalSeenBasenames[basename] {
				continue
			}
			globalSeenBasenames[basename] = true

			// Skip VerseVM internals (UHT can't parse them)
			if strings.Contains(h, "/VerseVM/") && !strings.Contains(h, "VVMVerse") {
				continue
			}

			publicHeaders = append(publicHeaders, h)
		}

		// Build include paths (including legacy Classes/ directory)
		includePaths := []string{}
		for _, subdir := range []string{"Public", "Internal", "Private", "Classes"} {
			dir := filepath.Join(moduleDir, subdir)
			if _, err := os.Stat(dir); err == nil {
				includePaths = append(includePaths, dir)
			}
		}

		// Per-module output directory
		moduleOutputDir := filepath.Join(absOutputRoot, entry.Name)

		moduleType := moduleTypePrefix + "Runtime"
		if entry.Type == "Developer" {
			moduleType = moduleTypePrefix + "Developer"
		} else if entry.Type == "Editor" {
			moduleType = moduleTypePrefix + "Editor"
		}

		modules = append(modules, UHTModule{
			Name:                     entry.Name,
			ModuleType:               moduleType,
			OverrideModuleType:       "None",
			BaseDirectory:            moduleDir,
			IncludePaths:             includePaths,
			OutputDirectory:          moduleOutputDir,
			ClassesHeaders:           []string{},
			PublicHeaders:            publicHeaders,
			InternalHeaders:          []string{},
			PrivateHeaders:           []string{},
			PublicDefines:            []string{},
			GeneratedCPPFilenameBase: filepath.Join(moduleOutputDir, entry.Name+".gen"),
			SaveExportedHeaders:      true,
			UHTGeneratedCodeVersion:  "None",
			VersePath:                "",
			VerseScope:               "PublicUser",
			HasVerse:                 false,
			VerseMountPoint:          "",
			AlwaysExportStructs:      true,
			AlwaysExportEnums:        true,
		})
	}

	manifest := UHTManifest{
		IsGameTarget:            opts.IsGameTarget,
		RootLocalPath:           absUERoot,
		TargetName:              opts.TargetName,
		ExternalDependenciesFile: "",
		Modules:                 modules,
	}

	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to marshal manifest: %w", err)
	}

	return data, nil
}

// topologicalSort sorts modules so that dependencies come before dependents
func topologicalSort(entries []ModuleRegistryEntry) []ModuleRegistryEntry {
	// Build name→entry map and adjacency list
	byName := make(map[string]*ModuleRegistryEntry)
	for i := range entries {
		byName[entries[i].Name] = &entries[i]
	}

	// Kahn's algorithm with cycle breaking
	// UE has circular deps (Core ↔ TraceLog, Engine ↔ UMG, etc.)
	// For UHT ordering, we break cycles by ignoring back-edges to "foundational" modules
	// Foundational modules that must appear early for UHT type resolution.
	// These break circular deps in the topo sort by being forced to in-degree 0.
	// Order matters: Core → CoreUObject → UI/Rendering → Engine → Editor
	foundational := map[string]bool{
		"Core": true, "CoreUObject": true,
		"InputCore": true, "SlateCore": true, "Slate": true,
		"RHI": true, "RenderCore": true,
		"PhysicsCore": true, "DeveloperSettings": true,
		"Engine": true,
		"UnrealEd": true,
	}

	inDegree := make(map[string]int)
	for _, e := range entries {
		if _, ok := inDegree[e.Name]; !ok {
			inDegree[e.Name] = 0
		}
		for _, dep := range e.Deps {
			// Skip deps on foundational modules for in-degree calculation
			// (they'll be force-added first anyway)
			if foundational[dep] {
				continue
			}
			if _, ok := byName[dep]; ok {
				inDegree[e.Name]++
			}
		}
	}

	// Force foundational modules to have 0 in-degree (always first)
	for name := range foundational {
		inDegree[name] = 0
	}

	// Start with 0 in-degree modules, foundational ones first in fixed order
	var queue []string
	for _, name := range []string{
		"Core", "CoreUObject",
		"InputCore", "SlateCore", "Slate",
		"RHI", "RenderCore",
		"PhysicsCore", "DeveloperSettings",
		"Engine",
		"UnrealEd",
	} {
		if _, ok := byName[name]; ok {
			queue = append(queue, name)
		}
	}
	// Add other 0-degree modules alphabetically
	var zeroInDegree []string
	for _, e := range entries {
		if inDegree[e.Name] == 0 && !foundational[e.Name] {
			zeroInDegree = append(zeroInDegree, e.Name)
		}
	}
	sort.Strings(zeroInDegree)
	queue = append(queue, zeroInDegree...)

	var sorted []ModuleRegistryEntry
	visited := make(map[string]bool)

	for len(queue) > 0 {
		// Pop first
		name := queue[0]
		queue = queue[1:]

		if visited[name] {
			continue
		}
		visited[name] = true

		if entry, ok := byName[name]; ok {
			sorted = append(sorted, *entry)
		}

		// Find modules that depend on this one and decrement their in-degree
		var newReady []string
		for _, e := range entries {
			if visited[e.Name] {
				continue
			}
			for _, dep := range e.Deps {
				if dep == name {
					inDegree[e.Name]--
					if inDegree[e.Name] <= 0 {
						newReady = append(newReady, e.Name)
					}
				}
			}
		}
		sort.Strings(newReady)
		queue = append(queue, newReady...)
	}

	// Add any remaining modules (circular deps — just append alphabetically)
	for _, e := range entries {
		if !visited[e.Name] {
			sorted = append(sorted, e)
		}
	}

	return sorted
}

// LoadModuleRegistry reads a module registry JSON file
func LoadModuleRegistry(path string) ([]ModuleRegistryEntry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read registry: %w", err)
	}

	var entries []ModuleRegistryEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return nil, fmt.Errorf("failed to parse registry: %w", err)
	}

	return entries, nil
}

// WriteMultiModuleManifest generates and writes a multi-module manifest
func WriteMultiModuleManifest(path string, opts GenerateMultiModuleManifestOptions) error {
	data, err := GenerateMultiModuleManifest(opts)
	if err != nil {
		return err
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("failed to write manifest: %w", err)
	}

	return nil
}
