package gitDeps

import (
	_ "embed"
	"encoding/xml"
	"github.com/stretchr/testify/assert"
	"testing"
)

//go:embed working-manifest-test.xml
var workingManifestTestXml []byte

func TestBasic(t *testing.T) {
	t.Run("xml unmarshal basic", func(t *testing.T) {
		w := WorkingManifest{}
		err := xml.Unmarshal(workingManifestTestXml, &w)
		assert.Nil(t, err)
		assert.Equal(t, "http://cdn.unrealengine.com/dependencies", w.BaseUrl)
		assert.Len(t, w.Files, 1)
		assert.Len(t, w.Packs, 1)
		assert.Len(t, w.Blobs, 1)

		f := w.Files[0]
		assert.Equal(t, f.Name, "some-file")
		assert.Equal(t, f.Hash, "d3d7bbcf9b2fc8b6e4f2965354a5633c4f175589")
		assert.Equal(t, f.ExpectedHash, "d3d7bbcf9b2fc8b6e4f2965354a5633c4f175589")
		assert.Equal(t, f.Timestamp, 637988041677261645)

		b := w.Blobs[0]
		assert.Equal(t, "d3d7bbcf9b2fc8b6e4f2965354a5633c4f175589", b.Hash)
		assert.Equal(t, "11d5023ca81e6600e5546173c8ccee28fd7cf617", b.PackHash)
		assert.Equal(t, 8, b.PackOffset)
		assert.Equal(t, 8152030, b.Size)

		p := w.Packs[0]
		assert.Equal(t, "UnrealEngine-30001", p.RemotePath)
		assert.Equal(t, 629630, p.CompressedSize)
		assert.Equal(t, 2095931, p.Size)
		assert.Equal(t, "11d5023ca81e6600e5546173c8ccee28fd7cf617", p.Hash)

	})
}
