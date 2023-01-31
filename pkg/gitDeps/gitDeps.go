package gitDeps

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"github.com/sirupsen/logrus"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
)

func ParseDir(dir fs.FS) []WorkingManifest {
	return nil
}

var (
	XmlDecodeError = errors.New("error decoding deps file")
	UnknownError   = errors.New("error unknown")
)

// ParseFile takes an XML file that represents Unreal Engine dependencies and returns a
// data structure representing the file for further processing
func ParseFile(data io.Reader) (*WorkingManifest, error) {
	w := WorkingManifest{}
	err := xml.NewDecoder(data).Decode(&w)
	if err != nil {
		if _, ok := err.(xml.UnmarshalError); ok {
			return nil, XmlDecodeError
		}
		return nil, UnknownError
	}
	return &w, nil
}

func GetBlobFromFile(file File, w WorkingManifest) *Blob {
	var blob *Blob
	for _, b := range w.Blobs {
		if file.Hash == b.Hash {
			blob = &b
		}
	}
	return blob
}

func GetFileFromManifest(filename string, w WorkingManifest) (file *File) {
	for _, v := range w.Files {
		if filename == v.Name {
			file = &v
		}
	}
	return
}

// DownloadPack downloads a Pack from the UnrealEngined CDN using a manifest file.
// The format of the url was taken from the original GitDependencies Unreal Engine program:
//
//	Pack.Url = String.Format("{0}/{1}/{2}", RequiredPack.Manifest.BaseUrl, RequiredPack.Pack.RemotePath, RequiredPack.Pack.Hash);
//	# https://github.com/kreempuff/UnrealEngine/blob/bd73ff2e35f9e0900035c8ad0080bb8fecefac24/Engine/Source/Programs/GitDependencies/Program.cs#L1033
func DownloadPack(w io.Writer, httpClient http.Client, pack *Pack, manifest WorkingManifest) error {
	url := fmt.Sprintf("%s/%s/%s", manifest.BaseUrl, pack.RemotePath, pack.Hash)
	l := logrus.WithFields(logrus.Fields{
		"packUrl": url,
	})

	res, err := httpClient.Get(url)
	if err != nil {
		return err
	}

	l.Debugf("downloading pack")
	_, err = io.Copy(w, res.Body)
	if err != nil {
		return err
	}
	l.Debug("downloaded pack")
	return nil
}

func GetPackfromFileName(filename string, w WorkingManifest) *Pack {

	file := GetFileFromManifest(filename, w)
	if file == nil {
		return nil
	}

	blob := GetBlobFromFile(*file, w)
	if blob == nil {
		return nil
	}

	var pack *Pack
	for _, p := range w.Packs {
		if blob.PackHash == p.Hash {
			pack = &p
		}
	}

	if pack == nil {
		return nil
	}

	return pack
}

// GetPackUrls returns a list of urls for all the packs in a manifest file
func GetPackUrls(w WorkingManifest) []string {
	var urls []string
	for _, p := range w.Packs {
		urls = append(urls, fmt.Sprintf("%s/%s/%s", w.BaseUrl, p.RemotePath, p.Hash))
	}
	return urls
}

// GetManifestFromInput takes a string that represents a path or directory to a manifest file and returns
// a data structure representing the file for further processing
func GetManifestFromInput(input string) (*WorkingManifest, error) {
	// Expand full path from relative path
	abs, err := filepath.Abs(input)

	if err != nil {
		return nil, err
	}

	// Check if directory exists
	stat, err := os.Stat(abs)

	if err != nil && os.IsNotExist(err) {
		return nil, fmt.Errorf("file does not exist: %w", err)
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
		return nil, fmt.Errorf("file does not exist: %w", err)
	}

	// TODO
	// check if file is a file

	f, err := os.ReadFile(depFile)

	if err != nil {
		return nil, err
	}
	buf := bytes.NewBuffer(f)
	return ParseFile(buf)
}
