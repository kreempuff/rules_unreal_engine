/*
Copyright © 2022 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"encoding/xml"
	"fmt"
	"os"
	"path/filepath"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

// gitDepsCmd represents the gitDeps command
var gitDepsCmd = &cobra.Command{
	Use:   "gitDeps",
	Short: "Parses Unreal dependencies and performs actions on them",
	Long:  `Parses Unreal dependencies and performs actions on them.`,
	Run: func(cmd *cobra.Command, args []string) {
		logrus.SetLevel(logrus.DebugLevel)

		dir, err := cmd.Flags().GetString("input")

		if err != nil {
			fmt.Println(err)
		}

		// Expand full path from relative path
		abs, err := filepath.Abs(dir)

		if err != nil {
			fmt.Println(err)
		}

		// Check if directory exists
		stat, err := os.Stat(abs)

		if err != nil && os.IsNotExist(err) {
			fmt.Println("Directory does not exist")
		}

		if !stat.IsDir() {
			fmt.Println("Path is not a directory")
		}

		// Find dependency file
		depFile := filepath.Join(abs, ".ue4dependencies")
		_, err = os.Stat(depFile)

		if os.IsNotExist(err) {
			logrus.Errorf("dependency file does not exist: %s", err)
			return
		}

		// TODO 
		// check if file is a file

		f, err := os.ReadFile(depFile)

		if err != nil {
			logrus.Errorf("error opening dependency file: %s", err)
			return
		}

		manifest := GitDependenciesFile{}
		err = xml.Unmarshal(f, &manifest)

		if err != nil {
			logrus.Errorf("error decoding dependency file: %s", err)
			return
		}

		logrus.Infof("manifest file count: %v", manifest)
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
