/*go:build integration*/

package gitDeps

import (
	"os"
	"testing"
	"time"
)
import "github.com/stretchr/testify/assert"

func TestSqliteDb(t *testing.T) {
	defer func() {
		_ = os.Remove("test.db")
	}()
	db, err := OpenDb(nil)
	assert.Nil(t, err)
	defer db.Close()

	t.Run("Ping", func(t *testing.T) {
		err = db.Ping()
		assert.Nil(t, err)
	})

	t.Run("Create table", func(t *testing.T) {
		_, err = db.Exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);")
		assert.Nil(t, err)
	})

	t.Run("Insert", func(t *testing.T) {
		r, err := db.Exec("INSERT INTO test (name) VALUES ('test')")
		assert.Nil(t, err)

		n, err := r.RowsAffected()
		assert.Nil(t, err)
		assert.Equal(t, int64(1), n)
	})

	t.Run("Select", func(t *testing.T) {
		rows, err := db.Query("SELECT name FROM test")
		assert.Nil(t, err)
		defer rows.Close()
		numRows := 0
		for rows.Next() {
			numRows++
		}
		assert.Equal(t, 1, numRows)
	})

	// ...
	time.Sleep(10 * time.Second) // Sleep for 10 seconds
}
