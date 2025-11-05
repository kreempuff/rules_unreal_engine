package cmd

import (
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"kreempuff.dev/rules-unreal-engine/pkg/uht"
	"strings"
)

var uhtCmd = &cobra.Command{
	Use:   "uht",
	Short: "UnrealHeaderTool utilities",
	Long: `Commands for working with Unreal Engine's header tool and code generation.

This includes manifest generation and other UHT-related utilities.`,
}

var uhtManifestCmd = &cobra.Command{
	Use:   "manifest",
	Short: "Generate UHT manifest file",
	Long: `Generate a .uhtmanifest JSON file for UnrealHeaderTool.

This command creates the manifest that tells UHT which headers to process
and where to write generated reflection code.`,
	Run: func(cmd *cobra.Command, args []string) {
		// Get flags
		moduleName, _ := cmd.Flags().GetString("module-name")
		moduleType, _ := cmd.Flags().GetString("module-type")
		baseDir, _ := cmd.Flags().GetString("base-dir")
		outputDir, _ := cmd.Flags().GetString("output-dir")
		headersStr, _ := cmd.Flags().GetString("headers")
		ueRoot, _ := cmd.Flags().GetString("ue-root")
		targetName, _ := cmd.Flags().GetString("target-name")
		output, _ := cmd.Flags().GetString("output")

		// Parse comma-separated headers
		var headers []string
		if headersStr != "" {
			headers = strings.Split(headersStr, ",")
		}

		// Generate manifest
		opts := uht.GenerateManifestOptions{
			ModuleName: moduleName,
			ModuleType: moduleType,
			BaseDir:    baseDir,
			OutputDir:  outputDir,
			Headers:    headers,
			UERoot:     ueRoot,
			TargetName: targetName,
		}

		if err := uht.WriteManifestFile(output, opts); err != nil {
			logrus.Errorf("failed to generate manifest: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("generated manifest: %s", output)
	},
}

func init() {
	rootCmd.AddCommand(uhtCmd)
	uhtCmd.AddCommand(uhtManifestCmd)

	// Define flags for manifest command
	uhtManifestCmd.Flags().String("module-name", "", "Module name (e.g., 'Core', 'TestModule')")
	uhtManifestCmd.Flags().String("module-type", "Runtime", "Module type (Runtime, Developer, Editor, Program)")
	uhtManifestCmd.Flags().String("base-dir", "", "Module base directory (absolute path)")
	uhtManifestCmd.Flags().String("output-dir", "", "Output directory for generated files (absolute path)")
	uhtManifestCmd.Flags().String("headers", "", "Comma-separated list of header files (absolute paths)")
	uhtManifestCmd.Flags().String("ue-root", "", "Unreal Engine root directory (defaults to base-dir)")
	uhtManifestCmd.Flags().String("target-name", "BazelTarget", "Build target name")
	uhtManifestCmd.Flags().StringP("output", "o", "", "Output manifest file path")

	uhtManifestCmd.MarkFlagRequired("module-name")
	uhtManifestCmd.MarkFlagRequired("base-dir")
	uhtManifestCmd.MarkFlagRequired("output-dir")
	uhtManifestCmd.MarkFlagRequired("output")
}
