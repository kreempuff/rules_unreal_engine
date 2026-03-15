package uht

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// UHTManifest represents the JSON manifest file that UHT expects
// Based on Epic's UHTManifest type from Engine/Source/Programs/Shared/EpicGames.Core/UHTTypes.cs
type UHTManifest struct {
	IsGameTarget           bool        `json:"IsGameTarget"`
	RootLocalPath          string      `json:"RootLocalPath"`
	TargetName             string      `json:"TargetName"`
	ExternalDependenciesFile string    `json:"ExternalDependenciesFile"`
	Modules                []UHTModule `json:"Modules"`
}

// UHTModule represents a single module in the manifest
type UHTModule struct {
	Name                     string   `json:"Name"`
	ModuleType               string   `json:"ModuleType"`
	OverrideModuleType       string   `json:"OverrideModuleType"`
	BaseDirectory            string   `json:"BaseDirectory"`
	IncludePaths             []string `json:"IncludePaths"`
	OutputDirectory          string   `json:"OutputDirectory"`
	ClassesHeaders           []string `json:"ClassesHeaders"`
	PublicHeaders            []string `json:"PublicHeaders"`
	InternalHeaders          []string `json:"InternalHeaders"`
	PrivateHeaders           []string `json:"PrivateHeaders"`
	PublicDefines            []string `json:"PublicDefines"`
	GeneratedCPPFilenameBase string   `json:"GeneratedCPPFilenameBase"`
	SaveExportedHeaders      bool     `json:"SaveExportedHeaders"`
	UHTGeneratedCodeVersion  string   `json:"UHTGeneratedCodeVersion"`
	VersePath                string   `json:"VersePath"`
	VerseScope               string   `json:"VerseScope"`
	HasVerse                 bool     `json:"HasVerse"`
	VerseMountPoint          string   `json:"VerseMountPoint"`
	AlwaysExportStructs      bool     `json:"AlwaysExportStructs"`
	AlwaysExportEnums        bool     `json:"AlwaysExportEnums"`
}

// GenerateManifestOptions contains parameters for manifest generation
type GenerateManifestOptions struct {
	ModuleName   string
	ModuleType   string   // "Runtime", "Developer", "Editor", etc.
	IsGameTarget bool     // true for game modules, false for engine modules
	BaseDir      string   // Module source directory (absolute path)
	OutputDir    string   // Where UHT writes generated files (absolute path)
	Headers      []string // List of header files (absolute paths)
	UERoot       string   // Unreal Engine root directory
	TargetName   string   // Build target name (default: "BazelTarget")
}

// GenerateManifest creates a UHT manifest JSON file
func GenerateManifest(opts GenerateManifestOptions) ([]byte, error) {
	// Validate required fields
	if opts.ModuleName == "" {
		return nil, fmt.Errorf("module name is required")
	}
	if opts.BaseDir == "" {
		return nil, fmt.Errorf("base directory is required")
	}
	if opts.OutputDir == "" {
		return nil, fmt.Errorf("output directory is required")
	}

	// Set defaults
	if opts.ModuleType == "" {
		opts.ModuleType = "Runtime"
	}
	if opts.TargetName == "" {
		opts.TargetName = "BazelTarget"
	}
	if opts.UERoot == "" {
		// Default to BaseDir (will be overridden by caller)
		opts.UERoot = opts.BaseDir
	}

	// Convert all paths to absolute (handles both relative Bazel paths and absolute paths)
	// When running with no-sandbox, filepath.Abs resolves relative paths from real execroot
	absBaseDir, err := filepath.Abs(opts.BaseDir)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve base directory: %w", err)
	}

	absOutputDir, err := filepath.Abs(opts.OutputDir)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve output directory: %w", err)
	}

	absUERoot, err := filepath.Abs(opts.UERoot)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve UE root: %w", err)
	}

	// Convert header paths to absolute
	absHeaders := make([]string, len(opts.Headers))
	for i, hdr := range opts.Headers {
		absHdr, err := filepath.Abs(hdr)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve header %s: %w", hdr, err)
		}
		absHeaders[i] = absHdr
	}

	// Build include paths (Public, Private subdirectories of BaseDir)
	includePaths := []string{
		filepath.Join(absBaseDir, "Public"),
		filepath.Join(absBaseDir, "Private"),
	}

	// Determine module type prefix based on whether this is a game target
	// UHT expects "GameRuntime" for game modules, "EngineRuntime" for engine modules
	moduleTypePrefix := "Game"
	if !opts.IsGameTarget {
		moduleTypePrefix = "Engine"
	}

	// Build module entry matching Epic's UHTManifest.Module schema
	module := UHTModule{
		Name:                     opts.ModuleName,
		ModuleType:               moduleTypePrefix + opts.ModuleType, // "GameRuntime", "EngineRuntime", etc.
		OverrideModuleType:       "None",
		BaseDirectory:            absBaseDir,
		IncludePaths:             includePaths,
		OutputDirectory:          absOutputDir,
		ClassesHeaders:           []string{},
		PublicHeaders:            absHeaders,
		InternalHeaders:          []string{},
		PrivateHeaders:           []string{},
		PublicDefines:            []string{},
		GeneratedCPPFilenameBase: filepath.Join(absOutputDir, opts.ModuleName+".gen"),
		SaveExportedHeaders:      true,
		UHTGeneratedCodeVersion:  "None",
		VersePath:                "",
		VerseScope:               "PublicUser",
		HasVerse:                 false,
		VerseMountPoint:          "",
		AlwaysExportStructs:      true,
		AlwaysExportEnums:        true,
	}

	// Build manifest
	manifest := UHTManifest{
		IsGameTarget:            opts.IsGameTarget,
		RootLocalPath:           absUERoot,
		TargetName:              opts.TargetName,
		ExternalDependenciesFile: "",
		Modules:                 []UHTModule{module},
	}

	// Serialize to JSON with indentation
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to marshal manifest: %w", err)
	}

	return data, nil
}

// WriteManifestFile generates and writes a UHT manifest to a file
func WriteManifestFile(path string, opts GenerateManifestOptions) error {
	data, err := GenerateManifest(opts)
	if err != nil {
		return err
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("failed to write manifest to %s: %w", path, err)
	}

	return nil
}
