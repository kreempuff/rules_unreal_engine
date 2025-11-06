package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// Reflection macros that indicate a header needs UHT processing
var reflectionMacros = []*regexp.Regexp{
	regexp.MustCompile(`^\s*UCLASS\s*\(`),
	regexp.MustCompile(`^\s*USTRUCT\s*\(`),
	regexp.MustCompile(`^\s*UENUM\s*\(`),
	regexp.MustCompile(`^\s*UINTERFACE\s*\(`),
	regexp.MustCompile(`^\s*GENERATED_BODY\s*\(`),             // Modern macro (all UCLASS/USTRUCT use this)
	regexp.MustCompile(`^\s*GENERATED_USTRUCT_BODY\s*\(`),     // Legacy struct macro
	regexp.MustCompile(`^\s*GENERATED_UCLASS_BODY\s*\(`),      // Legacy class macro
	regexp.MustCompile(`^\s*GENERATED_UINTERFACE_BODY\s*\(`),  // Interface macro
}

// ScanHeader returns true if the header file contains reflection macros
func ScanHeader(path string) (bool, error) {
	file, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	inBlockComment := false

	for scanner.Scan() {
		line := scanner.Text()

		// Handle block comments /* */
		if strings.Contains(line, "/*") {
			inBlockComment = true
		}
		if strings.Contains(line, "*/") {
			inBlockComment = false
			continue // Skip this line (has closing comment)
		}
		if inBlockComment {
			continue
		}

		// Remove line comments //
		if idx := strings.Index(line, "//"); idx != -1 {
			line = line[:idx]
		}

		// Check for reflection macros
		for _, macro := range reflectionMacros {
			if macro.MatchString(line) {
				return true, nil
			}
		}
	}

	return false, scanner.Err()
}

func main() {
	// Usage: uhtscan <header1.h> <header2.h> ...
	// Prints absolute paths of headers that need UHT processing (one per line)
	// Exit code 0: success, non-zero: error

	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "Usage: uhtscan <header-files...>")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "Scans C++ headers for Unreal reflection macros (UCLASS, USTRUCT, UENUM, etc.)")
		fmt.Fprintln(os.Stderr, "Prints paths of headers that need UHT processing.")
		os.Exit(1)
	}

	hasError := false
	for _, path := range os.Args[1:] {
		needsUHT, err := ScanHeader(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error scanning %s: %v\n", path, err)
			hasError = true
			continue
		}

		if needsUHT {
			fmt.Println(path)
		}
	}

	if hasError {
		os.Exit(1)
	}
}
