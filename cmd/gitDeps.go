/*
Copyright © 2022 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"kreempuff.dev/rules-unreal-engine/pkg/gitDeps"
	"net/http"
	"os"
)

var gitDepsCmd = &cobra.Command{
	Use:   "gitDeps",
	Short: "Parses Unreal dependencies and performs actions on them",
	Long:  `Parses Unreal dependencies and performs actions on them.`,
	Run: func(cmd *cobra.Command, args []string) {
		logrus.SetLevel(logrus.DebugLevel)

		input, err := cmd.Flags().GetString(gitDeps.InputFlag)
		if err != nil {
			logrus.Error(err)
			logrus.Exit(UnknownExitCode)
		}

		manifest, err := gitDeps.GetManifestFromInput(input)
		if err != nil {
			logrus.Errorf("error decoding dependency file: %s", err)
			logrus.Exit(UnknownExitCode)
		}

		logrus.Infof("url: %s/%s/%s, compressed size: %d", manifest.BaseUrl, manifest.Packs[0].RemotePath, manifest.Packs[0].Hash, manifest.Packs[0].CompressedSize)

		filename := ".tgitconfig"
		p := gitDeps.GetPackfromFileName(filename, *manifest)
		if p == nil {
			logrus.Errorf("pack not found for %s", filename)
		} else {
			logrus.Infof("pack for %s is %s", filename, p.RemotePath)
		}

		err = gitDeps.DownloadPack(os.Stdout, *http.DefaultClient, p, *manifest)
		if err != nil {
			logrus.Error("failed to download pack", err)
			logrus.Debugf("pack: %s failed to download", p.Hash)
		}
	},
}

func init() {
	rootCmd.AddCommand(gitDepsCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// gitDepsCmd.PersistentFlags().String("foo", "", "A help for foo")
	gitDepsCmd.PersistentFlags().StringP("input", "i", ".", "The dependency file or directory to parse dependencies from")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	//gitDepsCmd.Flags().StringP("input", "i", ".", "The dependency file or directory to parse dependencies from")
}
