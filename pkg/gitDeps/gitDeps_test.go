package gitDeps

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"github.com/stretchr/testify/assert"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
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
