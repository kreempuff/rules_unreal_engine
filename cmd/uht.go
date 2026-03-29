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
		isGameTarget, _ := cmd.Flags().GetBool("game-target")
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
			ModuleName:   moduleName,
			ModuleType:   moduleType,
			IsGameTarget: isGameTarget,
			BaseDir:      baseDir,
			OutputDir:    outputDir,
			Headers:      headers,
			UERoot:       ueRoot,
			TargetName:   targetName,
		}

		if err := uht.WriteManifestFile(output, opts); err != nil {
			logrus.Errorf("failed to generate manifest: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("generated manifest: %s", output)
	},
}

var uhtManifestAllCmd = &cobra.Command{
	Use:   "manifest-all",
	Short: "Generate UHT manifest for all modules",
	Long:  `Generate a single .uhtmanifest JSON file containing all UE modules for a full UHT pass.`,
	Run: func(cmd *cobra.Command, args []string) {
		registryPath, _ := cmd.Flags().GetString("registry")
		ueSourceRoot, _ := cmd.Flags().GetString("ue-source-root")
		outputRoot, _ := cmd.Flags().GetString("output-root")
		ueRoot, _ := cmd.Flags().GetString("ue-root")
		output, _ := cmd.Flags().GetString("output")

		registry, err := uht.LoadModuleRegistry(registryPath)
		if err != nil {
			logrus.Errorf("failed to load registry: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("loaded %d modules from registry", len(registry))

		opts := uht.GenerateMultiModuleManifestOptions{
			Registry:     registry,
			UESourceRoot: ueSourceRoot,
			OutputRoot:   outputRoot,
			UERoot:       ueRoot,
			IsGameTarget: false, // Engine modules
		}

		if err := uht.WriteMultiModuleManifest(output, opts); err != nil {
			logrus.Errorf("failed to generate manifest: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("generated multi-module manifest: %s", output)
	},
}

func init() {
	rootCmd.AddCommand(uhtCmd)
	uhtCmd.AddCommand(uhtManifestCmd)
	uhtCmd.AddCommand(uhtManifestAllCmd)

	// manifest-all flags
	uhtManifestAllCmd.Flags().String("registry", "", "Path to module registry JSON")
	uhtManifestAllCmd.Flags().String("ue-source-root", "", "Path to Engine/Source directory")
	uhtManifestAllCmd.Flags().String("output-root", "", "Root output directory for all modules")
	uhtManifestAllCmd.Flags().String("ue-root", "", "Unreal Engine root directory")
	uhtManifestAllCmd.Flags().StringP("output", "o", "", "Output manifest file path")
	uhtManifestAllCmd.MarkFlagRequired("registry")
	uhtManifestAllCmd.MarkFlagRequired("ue-source-root")
	uhtManifestAllCmd.MarkFlagRequired("output-root")
	uhtManifestAllCmd.MarkFlagRequired("output")

	// Define flags for manifest command
	uhtManifestCmd.Flags().String("module-name", "", "Module name (e.g., 'Core', 'TestModule')")
	uhtManifestCmd.Flags().String("module-type", "Runtime", "Module type (Runtime, Developer, Editor, Program)")
	uhtManifestCmd.Flags().Bool("game-target", true, "Whether this is a game target (true) or engine target (false)")
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
