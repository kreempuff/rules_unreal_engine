package gitDeps

import (
	"database/sql"
	"fmt"
	_ "github.com/mattn/go-sqlite3"
)

func CreateTable(db *sql.DB) error {
	_, err := db.Exec("CREATE TABLE IF NOT EXISTS gitDeps (id INTEGER PRIMARY KEY, packHash TEXT, sha256 TEXT);")
	return err
}

func InsertFileSha(db *sql.DB, packHash string, sha256 string) error {
	_, err := db.Exec("INSERT INTO gitDeps (packHash, sha256) VALUES (?, ?)", packHash, sha256)
	return err
}

func FindGitDepByPackHash(db *sql.DB, packHash string) (string, error) {
	var sha256 string
	err := db.QueryRow("SELECT sha256 FROM gitDeps WHERE packHash = ?", packHash).Scan(&sha256)
	return sha256, err
}

func OpenDb(dbFileName *string) (*sql.DB, error) {
	if dbFileName == nil {
		dbFileName = new(string)
		*dbFileName = "test.db"
	}

	db, err := sql.Open("sqlite3", fmt.Sprintf("file:%s?mode=rwc", *dbFileName))

	if err != nil {
		return nil, err
	}

	return db, nil
}
