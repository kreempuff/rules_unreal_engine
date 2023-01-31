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
		input, err := cmd.Flags().GetString(gitDeps.InputFlag)
		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		output, err := cmd.Flags().GetString("output")
		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		manifest, err := gitDeps.GetManifestFromInput(input)
		if err != nil {
			logrus.Errorf("error decoding dependency file: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		fmt.Println(len(manifest.Files))
		fmt.Println(len(manifest.Packs))
		fmt.Println(len(manifest.Blobs))
		urls := gitDeps.GetPackUrls(*manifest)

		out := ""
		switch output {
		case "json":
			out = formatUrlsAsJson(urls)
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

// formatUrlsAsJson formats the urls as an array of json objects
// with the key 'url' and the value being the url
func formatUrlsAsJson(urls []string) string {
	var output string
	output += "["
	for _, url := range urls {
		output += fmt.Sprintf("{\"url\": \"%s\"},", url)
	}
	output += "]"
	return output
}

func init() {
	gitDepsCmd.AddCommand(printUrlsCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// printUrlsCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	printUrlsCmd.Flags().StringP("output", "o", "json", "How the urls should be printed. Valid values are 'json' and 'bazel'.")
}
