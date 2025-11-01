/*
Copyright © 2022 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"kreempuff.dev/rules-unreal-engine/pkg/gitDeps"
	"net/http"
)

var gitDepsCmd = &cobra.Command{
	Use:   "gitDeps",
	Short: "Downloads and extracts Unreal Engine dependencies",
	Long: `Downloads and extracts all dependency packs from a .ue4dependencies manifest file.

This command replaces Epic's Setup.sh script with a faster, more reliable implementation.`,
	Run: func(cmd *cobra.Command, args []string) {
		// Get flags
		input, _ := cmd.Flags().GetString("input")
		outputDir, _ := cmd.Flags().GetString("output-dir")
		verify, _ := cmd.Flags().GetBool("verify")
		verbose, _ := cmd.Flags().GetBool("verbose")

		// Set log level
		if verbose {
			logrus.SetLevel(logrus.DebugLevel)
		} else {
			logrus.SetLevel(logrus.InfoLevel)
		}

		// Parse manifest
		logrus.Infof("parsing manifest from: %s", input)
		manifest, err := gitDeps.GetManifestFromInput(input)
		if err != nil {
			logrus.Errorf("failed to parse manifest: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("found %d packs to download", len(manifest.Packs))
		logrus.Infof("base URL: %s", manifest.BaseUrl)

		// Download and extract all packs
		err = gitDeps.DownloadAllPacks(*http.DefaultClient, *manifest, outputDir, verify)
		if err != nil {
			logrus.Errorf("failed to download packs: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Info("all dependencies downloaded and extracted successfully")
	},
}

func init() {
	rootCmd.AddCommand(gitDepsCmd)

	// Define flags
	gitDepsCmd.Flags().StringP("input", "i", ".", "Path to .ue4dependencies file or directory containing it")
	gitDepsCmd.Flags().StringP("output-dir", "o", ".", "Directory to extract dependencies to")
	gitDepsCmd.Flags().BoolP("verify", "v", true, "Verify SHA1 checksums of downloaded packs")
	gitDepsCmd.Flags().Bool("verbose", false, "Enable verbose logging")
}
