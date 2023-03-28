package cmd

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"kreempuff.dev/rules-unreal-engine/pkg/gitDeps"
	"net/http"
	"strconv"
)

// Max number of shas to download
const shasToDownload = 1_000_000

// shasCmd represents the shas command
var shasCmd = &cobra.Command{
	Use:   "cache-shas",
	Short: "Download and store shas for unreal dependencies",
	Long:  `Download and store shas for unreal dependencies. It's stored in a sqlite db.`,
	Run: func(cmd *cobra.Command, args []string) {
		// Get input from flag
		input, err := cmd.Flags().GetString("input")
		if err != nil {
			logrus.Error(err)
			return
		}

		dbFileName, err := cmd.Flags().GetString("db")
		if err != nil {
			logrus.Error(err)
			return
		}

		// Get manifest from input
		manifest, err := gitDeps.GetManifestFromPath(input)
		if err != nil {
			logrus.Errorf("error decoding dependency file: %s", err)
			return
		}

		if err != nil {
			logrus.Error(err)
			logrus.Exit(InvalidInputExitCode)
		}

		db, err := PrepareDb(&dbFileName)
		if err != nil {
			logrus.Errorf("error preparing db: %s", err)
			return
		}
		defer db.Close()

		packsInserted := make([]gitDeps.Pack, 0)
		for i, pack := range manifest.Packs {
			if i == shasToDownload {
				break
			}
			logrus.Infof("Remaining packs: %d", len(manifest.Packs)-i)
			logrus.Infof("Looking for pack (%s) in database", pack.Hash)
			_, err = gitDeps.FindGitDepByPackHash(db, pack.Hash)

			if err != nil && err != sql.ErrNoRows {
				logrus.Errorf("error finding pack (%s): %s", pack.Hash, err)
				return
			}
			if err != sql.ErrNoRows {
				logrus.Infof("Pack (%s) already in database", pack.Hash)
				continue
			}

			logrus.Infof("Downloading pack (%s, %s) ...", pack.Hash, bytesToHumanReadableString(pack.Size))

			buffer := bytes.Buffer{}
			err = gitDeps.DownloadPack(&buffer, *http.DefaultClient, &pack, *manifest)
			if err != nil {
				logrus.Errorf("error downloading pack (%s): %s", pack.Hash, err)
				return
			}
			sum := sha256.Sum256(buffer.Bytes())
			hex.EncodeToString(sum[:])

			logrus.Infof("Inserting pack (%s) into database", pack.Hash)
			err = gitDeps.InsertFileSha(db, pack.Hash, hex.EncodeToString(sum[:]))
			if err != nil {
				logrus.Errorf("error inserting pack (%s) into database: %s", pack.Hash, err)
				return
			}
			packsInserted = append(packsInserted, pack)
		}

		if len(packsInserted) == 0 {
			logrus.Info("No packs inserted into database")
			return
		} else {
			logrus.Infof("Inserted %d packs into database", len(packsInserted))

			logrus.Debug("Inserted packs: ")
			for _, pack := range packsInserted {
				logrus.Debugf("Hash: %s, Size: %d, Path: %s", pack.Hash, pack.Size, pack.RemotePath)
			}
		}

	},
}

func bytesToHumanReadableString(bytes int) string {
	if bytes < 1024 {
		return strconv.Itoa(bytes) + " B"
	} else if bytes < 1024*1024 {
		return strconv.Itoa(bytes/1024) + " KB"
	} else if bytes < 1024*1024*1024 {
		return strconv.Itoa(bytes/1024/1024) + " MB"
	} else {
		return strconv.Itoa(bytes/1024/1024/1024) + " GB"
	}
}

func PrepareDb(sqliteDb *string) (*sql.DB, error) {
	db, err := gitDeps.OpenDb(sqliteDb)

	if err != nil {
		return nil, err
	}

	err = gitDeps.CreateTable(db)

	if err != nil {
		defer func(db *sql.DB) {
			err := db.Close()
			if err != nil {
				logrus.Error("error closing db: ", err)
			}
		}(db)
		return nil, err
	}

	return db, nil
}

func transformBytesToHex(in []byte) string {
	hash := sha256.Sum256(in)
	return hex.EncodeToString(hash[:])
}

func init() {
	gitDepsCmd.AddCommand(shasCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// shasCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	shasCmd.Flags().String("db", "./test.db", "File path to sqlite db")
}
