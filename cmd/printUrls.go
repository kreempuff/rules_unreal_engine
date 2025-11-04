package cmd

import (
	"fmt"
	"github.com/sirupsen/logrus"
	"kreempuff.dev/rules-unreal-engine/pkg/gitDeps"

	"github.com/spf13/cobra"
)

// printUrlsCmd represents the printUrls command
var printUrlsCmd = &cobra.Command{
	Use:   "printUrls",
	Short: "Prints the urls of the packs in the dependency file",
	Long:  `Prints the urls of the packs in the dependency file`,
	Run: func(cmd *cobra.Command, args []string) {
		input, err := cmd.Flags().GetString("input")
		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		output, err := cmd.Flags().GetString("output")
		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		prefixes, err := cmd.Flags().GetStringSlice("prefix")
		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		manifest, err := gitDeps.GetManifestFromInput(input)
		if err != nil {
			logrus.Errorf("error decoding dependency file: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		// Get pack URLs, optionally filtered by file prefixes
		urls := gitDeps.GetPackUrlsWithPrefixes(*manifest, prefixes)

		out := ""
		switch output {
		case "json":
			out = formatUrlsAsJSON(urls)
		case "bazel":
			out = formatUrlsAsBazel(urls)
		}

		fmt.Println(out)
	},
}

// formatUrlsAsBazel formats the urls as a list of bazel urls
func formatUrlsAsBazel(urls []string) string {
	var output string
	for _, url := range urls {
		output += fmt.Sprintf("urls = [\"%s\"],", url)
	}
	return output
}

// formatUrlsAsJSON formats the urls as a JSON array of strings
func formatUrlsAsJSON(urls []string) string {
	var output string
	output += "["
	for i, url := range urls {
		if i > 0 {
			output += ","
		}
		output += fmt.Sprintf("\"%s\"", url)
	}
	output += "]"
	return output
}

func init() {
	gitDepsCmd.AddCommand(printUrlsCmd)

	// Define flags
	printUrlsCmd.Flags().StringP("input", "i", ".", "Path to .ue4dependencies file or directory containing it")
	printUrlsCmd.Flags().StringP("output", "o", "json", "How the urls should be printed. Valid values are 'json' and 'bazel'.")
	printUrlsCmd.Flags().StringSlice("prefix", []string{}, "Only include packs containing files with these path prefixes (repeatable, e.g., --prefix=Engine/Binaries --prefix=Engine/Source/Programs)")
}
