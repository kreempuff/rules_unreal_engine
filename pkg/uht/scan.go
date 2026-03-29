package uht

import (
	"bufio"
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
	regexp.MustCompile(`^\s*GENERATED_BODY\s*\(`),
	regexp.MustCompile(`^\s*GENERATED_USTRUCT_BODY\s*\(`),
	regexp.MustCompile(`^\s*GENERATED_UCLASS_BODY\s*\(`),
	regexp.MustCompile(`^\s*GENERATED_UINTERFACE_BODY\s*\(`),
	// Delegate macros — UHT needs these for type resolution
	regexp.MustCompile(`^\s*DECLARE_DYNAMIC_DELEGATE`),
	regexp.MustCompile(`^\s*DECLARE_DYNAMIC_MULTICAST_DELEGATE`),
	// UPROPERTY/UFUNCTION on their own can indicate UHT-relevant headers
	regexp.MustCompile(`^\s*UPROPERTY\s*\(`),
	regexp.MustCompile(`^\s*UFUNCTION\s*\(`),
	regexp.MustCompile(`^\s*UDELEGATE\s*\(`),
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

		if strings.Contains(line, "/*") {
			inBlockComment = true
		}
		if strings.Contains(line, "*/") {
			inBlockComment = false
			continue
		}
		if inBlockComment {
			continue
		}

		if idx := strings.Index(line, "//"); idx != -1 {
			line = line[:idx]
		}

		for _, macro := range reflectionMacros {
			if macro.MatchString(line) {
				return true, nil
			}
		}
	}

	return false, scanner.Err()
}

// FilterHeaders returns only headers that contain reflection macros
func FilterHeaders(paths []string) []string {
	var result []string
	for _, path := range paths {
		has, err := ScanHeader(path)
		if err != nil {
			continue
		}
		if has {
			result = append(result, path)
		}
	}
	return result
}
