package cmd

import (
	"compress/gzip"
	"fmt"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"io"
	"kreempuff.dev/rules-unreal-engine/pkg/gitDeps"
	"os"
	"path/filepath"
	"strings"
)

var extractCmd = &cobra.Command{
	Use:   "extract",
	Short: "Extract pre-downloaded pack files using a manifest",
	Long: `Extract Unreal Engine dependencies from pre-downloaded pack files.

This command is used by the Bazel repository rule to extract packs
that were downloaded using Bazel's HTTP cache (repo_ctx.download).`,
	Run: func(cmd *cobra.Command, args []string) {
		// Get flags
		packsDir, _ := cmd.Flags().GetString("packs-dir")
		manifestPath, _ := cmd.Flags().GetString("manifest")
		outputDir, _ := cmd.Flags().GetString("output-dir")
		verbose, _ := cmd.Flags().GetBool("verbose")
		prefixes, _ := cmd.Flags().GetStringSlice("prefix")

		// Set log level
		if verbose {
			logrus.SetLevel(logrus.DebugLevel)
		} else {
			logrus.SetLevel(logrus.InfoLevel)
		}

		// Parse manifest
		logrus.Infof("parsing manifest from: %s", manifestPath)
		manifest, err := gitDeps.GetManifestFromInput(manifestPath)
		if err != nil {
			logrus.Errorf("failed to parse manifest: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("found %d packs in manifest", len(manifest.Packs))

		// Filter files by prefixes if specified
		filesToExtract := manifest.Files
		if len(prefixes) > 0 {
			var filtered []gitDeps.File
			for _, f := range manifest.Files {
				for _, prefix := range prefixes {
					if strings.HasPrefix(f.Name, prefix) {
						filtered = append(filtered, f)
						break // Don't add same file twice if it matches multiple prefixes
					}
				}
			}
			filesToExtract = filtered
			logrus.Infof("prefix filters %v: extracting %d/%d files", prefixes, len(filtered), len(manifest.Files))
		}

		// Extract each pack
		for i, pack := range manifest.Packs {
			if i%100 == 0 {
				logrus.Infof("extracting pack %d/%d", i+1, len(manifest.Packs))
			}

			// Find the downloaded pack file
			packFile := filepath.Join(packsDir, fmt.Sprintf("%s.pack.gz", pack.Hash))

			// Check if pack exists
			if _, err := os.Stat(packFile); os.IsNotExist(err) {
				logrus.Warnf("pack file not found: %s", packFile)
				continue
			}

			// Open and decompress the pack
			f, err := os.Open(packFile)
			if err != nil {
				logrus.Errorf("failed to open pack %s: %s", packFile, err)
				logrus.Exit(UnknownExitCode)
			}

			gzr, err := gzip.NewReader(f)
			if err != nil {
				f.Close()
				logrus.Errorf("failed to decompress pack %s: %s", packFile, err)
				logrus.Exit(UnknownExitCode)
			}

			// Read decompressed data
			packData, err := io.ReadAll(gzr)
			gzr.Close()
			f.Close()

			if err != nil {
				logrus.Errorf("failed to read pack %s: %s", packFile, err)
				logrus.Exit(UnknownExitCode)
			}

			// Find blobs and files for this pack
			var packBlobs []gitDeps.Blob
			for _, blob := range manifest.Blobs {
				if blob.PackHash == pack.Hash {
					packBlobs = append(packBlobs, blob)
				}
			}

			var packFiles []gitDeps.File
			for _, file := range filesToExtract {
				for _, blob := range packBlobs {
					if file.Hash == blob.Hash {
						packFiles = append(packFiles, file)
						break
					}
				}
			}

			// Extract files from pack
			if err := gitDeps.ExtractUEPack(packData, packBlobs, packFiles, outputDir, *manifest); err != nil {
				logrus.Errorf("failed to extract pack %s: %s", pack.Hash, err)
				logrus.Exit(UnknownExitCode)
			}
		}

		logrus.Info("all packs extracted successfully")
	},
}

func init() {
	rootCmd.AddCommand(extractCmd)

	// Define flags
	extractCmd.Flags().String("packs-dir", "", "Directory containing downloaded .pack.gz files")
	extractCmd.Flags().String("manifest", "", "Path to .gitdeps.xml manifest file")
	extractCmd.Flags().StringP("output-dir", "o", ".", "Directory to extract files to")
	extractCmd.Flags().Bool("verbose", false, "Enable verbose logging")
	extractCmd.Flags().StringSlice("prefix", []string{}, "Only extract files with these path prefixes (repeatable, e.g., --prefix=Engine/Binaries --prefix=Engine/Source/Programs)")

	extractCmd.MarkFlagRequired("packs-dir")
	extractCmd.MarkFlagRequired("manifest")
}
