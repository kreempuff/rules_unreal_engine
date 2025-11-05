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
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
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

		// Extract packs in parallel using worker pool (one worker per CPU)
		numWorkers := runtime.NumCPU()
		logrus.Infof("extracting %d packs using %d workers", len(manifest.Packs), numWorkers)

		// Create work queue and error channel
		type packJob struct {
			index int
			pack  gitDeps.Pack
		}
		packQueue := make(chan packJob, numWorkers*2)
		errorChan := make(chan error, len(manifest.Packs))
		var wg sync.WaitGroup
		var processed atomic.Int64

		// Start worker pool
		for w := 0; w < numWorkers; w++ {
			wg.Add(1)
			go func(workerID int) {
				defer wg.Done()

				for job := range packQueue {
					pack := job.pack
					packFile := filepath.Join(packsDir, fmt.Sprintf("%s.pack.gz", pack.Hash))

					// Check if pack exists
					if _, err := os.Stat(packFile); os.IsNotExist(err) {
						logrus.Warnf("pack file not found: %s", packFile)
						processed.Add(1)
						continue
					}

					// Open and decompress the pack
					f, err := os.Open(packFile)
					if err != nil {
						errorChan <- fmt.Errorf("failed to open pack %s: %w", packFile, err)
						processed.Add(1)
						continue
					}

					gzr, err := gzip.NewReader(f)
					if err != nil {
						f.Close()
						errorChan <- fmt.Errorf("failed to decompress pack %s: %w", packFile, err)
						processed.Add(1)
						continue
					}

					// Read decompressed data
					packData, err := io.ReadAll(gzr)
					gzr.Close()
					f.Close()

					if err != nil {
						errorChan <- fmt.Errorf("failed to read pack %s: %w", packFile, err)
						processed.Add(1)
						continue
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
						errorChan <- fmt.Errorf("failed to extract pack %s: %w", pack.Hash, err)
						processed.Add(1)
						continue
					}

					// Log progress every 100 packs
					count := processed.Add(1)
					if count%100 == 0 {
						logrus.Infof("extracted %d/%d packs", count, len(manifest.Packs))
					}
				}
			}(w)
		}

		// Send all packs to work queue
		for i, pack := range manifest.Packs {
			packQueue <- packJob{index: i, pack: pack}
		}
		close(packQueue)

		// Wait for all workers to finish
		wg.Wait()
		close(errorChan)

		// Check for errors
		var errors []error
		for err := range errorChan {
			errors = append(errors, err)
		}

		if len(errors) > 0 {
			logrus.Errorf("encountered %d errors during extraction:", len(errors))
			for _, err := range errors {
				logrus.Error(err)
			}
			logrus.Exit(UnknownExitCode)
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
