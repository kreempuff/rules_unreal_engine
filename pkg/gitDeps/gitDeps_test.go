package gitDeps

import (
	"bytes"
	"compress/gzip"
	"encoding/xml"
	"fmt"
	"github.com/stretchr/testify/assert"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
)

func TestDownloadPack(t *testing.T) {
	w := WorkingManifest{}
	err := xml.Unmarshal(workingManifestTestXml, &w)
	assert.Nil(t, err)

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("abcdef"))
	}))
	defer ts.Close()

	// Set the proxy to the test server otherwise the test will make
	// a real request to the CDN.
	ts.Client().Transport = &http.Transport{
		Proxy: func(req *http.Request) (*url.URL, error) {
			return url.Parse(ts.URL)
		},
	}

	type args struct {
		httpClient http.Client
		pack       *Pack
		manifest   WorkingManifest
	}
	tests := []struct {
		name        string
		args        args
		wantWLength int
		wantErr     assert.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			args: args{
				httpClient: *ts.Client(),
				pack:       GetPackfromFileName("some-file", w),
				manifest:   w,
			},
			wantWLength: 6,
			wantErr:     assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := &bytes.Buffer{}
			err := DownloadPack(w, tt.args.httpClient, tt.args.pack, tt.args.manifest)
			if !tt.wantErr(t, err, fmt.Sprintf("DownloadPack(%v, %v, %v, %v)", w, tt.args.httpClient, tt.args.pack, tt.args.manifest)) {
				return
			}
			assert.Equalf(t, tt.wantWLength, w.Len(), "DownloadPack(%v, %v, %v, %v)", w, tt.args.httpClient, tt.args.pack, tt.args.manifest)
		})
	}
}

func TestGetPackUrls(t *testing.T) {
	type args struct {
		w WorkingManifest
	}
	tests := []struct {
		name string
		args args
		want []string
	}{
		{
			name: "happy path",
			args: args{
				w: WorkingManifest{
					BaseUrl: "https://some-base-url",
					Packs: []Pack{
						{
							Hash:           "some-hash",
							Size:           0,
							CompressedSize: 0,
							RemotePath:     "some-remote-path",
						},
					},
				},
			},
			want: []string{"https://some-base-url/some-remote-path/some-hash"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, GetPackUrls(tt.args.w), "GetPackUrls(%v)", tt.args.w)
		})
	}
}

func TestParseDir(t *testing.T) {
	tests := []struct {
		name          string
		fsys          fstest.MapFS
		wantCount     int
		wantErr       bool
		wantBaseUrl   string
	}{
		{
			name: "finds single .ue4dependencies file",
			fsys: fstest.MapFS{
				".ue4dependencies": &fstest.MapFile{
					Data: workingManifestTestXml,
				},
			},
			wantCount:   1,
			wantErr:     false,
			wantBaseUrl: "http://cdn.unrealengine.com/dependencies",
		},
		{
			name: "finds nested .ue4dependencies file",
			fsys: fstest.MapFS{
				"Engine/.ue4dependencies": &fstest.MapFile{
					Data: workingManifestTestXml,
				},
			},
			wantCount:   1,
			wantErr:     false,
			wantBaseUrl: "http://cdn.unrealengine.com/dependencies",
		},
		{
			name: "finds multiple .ue4dependencies files",
			fsys: fstest.MapFS{
				".ue4dependencies": &fstest.MapFile{
					Data: workingManifestTestXml,
				},
				"Subdir/.ue4dependencies": &fstest.MapFile{
					Data: workingManifestTestXml,
				},
			},
			wantCount:   2,
			wantErr:     false,
			wantBaseUrl: "http://cdn.unrealengine.com/dependencies",
		},
		{
			name:      "no .ue4dependencies files",
			fsys:      fstest.MapFS{
				"README.md": &fstest.MapFile{
					Data: []byte("# Test"),
				},
			},
			wantCount: 0,
			wantErr:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manifests, err := ParseDir(tt.fsys)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			assert.NoError(t, err)
			assert.Equal(t, tt.wantCount, len(manifests))

			if tt.wantCount > 0 {
				assert.Equal(t, tt.wantBaseUrl, manifests[0].BaseUrl)
			}
		})
	}
}

func TestExtractUEPack(t *testing.T) {
	// Create test data
	fileContent := []byte("Hello, Unreal Engine!")

	// Create a mock pack with file at offset 8 (after "UEPACK00" header)
	packData := make([]byte, 8+len(fileContent))
	copy(packData[0:8], []byte("UEPACK00"))
	copy(packData[8:], fileContent)

	tests := []struct {
		name      string
		packData  []byte
		blobs     []Blob
		files     []File
		wantErr   bool
		validate  func(t *testing.T, targetDir string)
	}{
		{
			name:     "extracts UE pack successfully",
			packData: packData,
			blobs: []Blob{
				{
					Hash:       "test-hash",
					PackHash:   "pack-hash",
					PackOffset: 8,
					Size:       len(fileContent),
				},
			},
			files: []File{
				{
					Name: "Engine/Test/test.txt",
					Hash: "test-hash",
				},
			},
			wantErr: false,
			validate: func(t *testing.T, targetDir string) {
				// Check file exists and has correct content
				filePath := filepath.Join(targetDir, "Engine", "Test", "test.txt")
				content, err := os.ReadFile(filePath)
				assert.NoError(t, err)
				assert.Equal(t, "Hello, Unreal Engine!", string(content))
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create temporary directory
			targetDir, err := os.MkdirTemp("", "gitdeps-test-*")
			assert.NoError(t, err)
			defer os.RemoveAll(targetDir)

			// Extract pack
			manifest := WorkingManifest{}
			err = ExtractUEPack(tt.packData, tt.blobs, tt.files, targetDir, manifest)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			assert.NoError(t, err)

			if tt.validate != nil {
				tt.validate(t, targetDir)
			}
		})
	}
}

func TestDownloadAndExtractPack(t *testing.T) {
	// Create a test UE pack (gzip-compressed binary with file data)
	createTestPack := func() []byte {
		fileContent := []byte("test dependency file")

		// Create pack data with header and file
		packData := make([]byte, 8+len(fileContent))
		copy(packData[0:8], []byte("UEPACK00"))
		copy(packData[8:], fileContent)

		// Gzip compress the pack
		var buf bytes.Buffer
		gw := gzip.NewWriter(&buf)
		gw.Write(packData)
		gw.Close()

		return buf.Bytes()
	}

	packData := createTestPack()
	fileContent := []byte("test dependency file")

	// Create test HTTP server
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write(packData)
	}))
	defer ts.Close()

	// Setup test manifest and pack
	manifest := WorkingManifest{
		BaseUrl: ts.URL,
		Packs: []Pack{
			{
				Hash:       "test-pack-hash",
				RemotePath: "test-path",
			},
		},
		Blobs: []Blob{
			{
				Hash:       "test-blob-hash",
				PackHash:   "test-pack-hash",
				PackOffset: 8, // After UEPACK00 header
				Size:       len(fileContent),
			},
		},
		Files: []File{
			{
				Name: "Engine/Binaries/test.bin",
				Hash: "test-blob-hash",
			},
		},
	}

	tests := []struct {
		name      string
		wantErr   bool
	}{
		{
			name:    "downloads and extracts pack successfully",
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			targetDir, err := os.MkdirTemp("", "gitdeps-pack-test-*")
			assert.NoError(t, err)
			defer os.RemoveAll(targetDir)

			err = DownloadAndExtractPack(*ts.Client(), &manifest.Packs[0], manifest, targetDir, false)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			assert.NoError(t, err)

			// Verify extracted file exists
			extractedFile := filepath.Join(targetDir, "Engine", "Binaries", "test.bin")
			content, err := os.ReadFile(extractedFile)
			assert.NoError(t, err)
			assert.Equal(t, "test dependency file", string(content))
		})
	}
}

func TestVerifyHash(t *testing.T) {
	tests := []struct {
		name         string
		data         []byte
		expectedHash string
		wantValid    bool
	}{
		{
			name:         "valid hash",
			data:         []byte("test data"),
			expectedHash: "f48dd853820860816c75d54d0f584dc863327a7c", // SHA1 of "test data"
			wantValid:    true,
		},
		{
			name:         "invalid hash",
			data:         []byte("test data"),
			expectedHash: "0000000000000000000000000000000000000000",
			wantValid:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			valid, _ := VerifyHash(tt.data, tt.expectedHash)
			assert.Equal(t, tt.wantValid, valid)
		})
	}
}
