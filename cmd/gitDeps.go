/*
Copyright © 2022 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"bytes"
	"kreempuff.dev/rules-unreal-engine/pkg/gitDeps"
	"os"
	"path/filepath"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var gitDepsCmd = &cobra.Command{
	Use:   "gitDeps",
	Short: "Parses Unreal dependencies and performs actions on them",
	Long:  `Parses Unreal dependencies and performs actions on them.`,
	Run: func(cmd *cobra.Command, args []string) {
		logrus.SetLevel(logrus.DebugLevel)

		input, err := cmd.Flags().GetString("input")

		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		// Expand full path from relative path
		abs, err := filepath.Abs(input)

		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		// Check if directory exists
		stat, err := os.Stat(abs)

		if err != nil && os.IsNotExist(err) {
			logrus.Error("Directory does not exist")
			logrus.Exit(UnknownExitCode)
		}

		// Find dependency file
		var depFile string

		if stat.IsDir() {
			depFile = filepath.Join(abs, ".ue4dependencies")
		} else {
			depFile = input
		}
		_, err = os.Stat(depFile)

		if os.IsNotExist(err) {
			logrus.Errorf("dependency file does not exist: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		// TODO
		// check if file is a file

		f, err := os.ReadFile(depFile)

		if err != nil {
			logrus.Errorf("error opening dependency file: %s", err)
			logrus.Exit(UnknownExitCode)
		}
		buf := bytes.NewBuffer(f)

		manifest, err := gitDeps.ParseFile(buf)
		if err != nil {
			logrus.Errorf("error decoding dependency file: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("url: %s/%s/%s, compressed size: %d", manifest.BaseUrl, manifest.Packs[0].RemotePath, manifest.Packs[0].Hash, manifest.Packs[0].CompressedSize)
	},
}

func init() {
	rootCmd.AddCommand(gitDepsCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// gitDepsCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	gitDepsCmd.Flags().StringP("input", "i", ".", "The dependency file or directory to parse dependencies from")
}
