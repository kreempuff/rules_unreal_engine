package gitDeps

import (
	"bytes"
	"compress/gzip"
	"crypto/sha1"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/sirupsen/logrus"
)

// ParseDir walks through a filesystem and finds all .ue4dependencies files,
// parsing them into WorkingManifest structs
func ParseDir(dir fs.FS) ([]WorkingManifest, error) {
	var manifests []WorkingManifest

	err := fs.WalkDir(dir, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !d.IsDir() && filepath.Base(path) == ".ue4dependencies" {
			file, err := dir.Open(path)
			if err != nil {
				logrus.WithError(err).Warnf("failed to open %s", path)
				return nil // Continue walking, don't fail entire operation
			}
			defer file.Close()

			manifest, err := ParseFile(file)
			if err != nil {
				logrus.WithError(err).Warnf("failed to parse %s", path)
				return nil // Continue walking
			}

			manifests = append(manifests, *manifest)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	return manifests, nil
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
	return GetPackUrlsWithPrefix(w, "")
}

func GetPackUrlsWithPrefix(w WorkingManifest, prefix string) []string {
	// If no prefix, return all packs
	if prefix == "" {
		var urls []string
		for _, p := range w.Packs {
			urls = append(urls, fmt.Sprintf("%s/%s/%s", w.BaseUrl, p.RemotePath, p.Hash))
		}
		return urls
	}

	// Build map of PackHash -> bool (packs that contain files with prefix)
	neededPacks := make(map[string]bool)
	for _, file := range w.Files {
		if strings.HasPrefix(file.Name, prefix) {
			// Find which pack contains this file's blob
			for _, blob := range w.Blobs {
				if blob.Hash == file.Hash {
					neededPacks[blob.PackHash] = true
					break
				}
			}
		}
	}

	// Return URLs only for needed packs
	var urls []string
	for _, p := range w.Packs {
		if neededPacks[p.Hash] {
			urls = append(urls, fmt.Sprintf("%s/%s/%s", w.BaseUrl, p.RemotePath, p.Hash))
		}
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

// ExtractUEPack extracts files from an Unreal Engine pack (gzip-compressed binary container)
// Epic's format: Each pack is gzip-compressed and contains multiple files concatenated together.
// The manifest specifies PackOffset and Size to extract individual files.
func ExtractUEPack(packData []byte, blobs []Blob, files []File, targetDir string, manifest WorkingManifest) error {
	l := logrus.WithField("targetDir", targetDir)
	l.Debugf("extracting %d files from pack", len(files))

	for _, file := range files {
		// Find the blob for this file
		var blob *Blob
		for i := range blobs {
			if blobs[i].Hash == file.Hash {
				blob = &blobs[i]
				break
			}
		}

		if blob == nil {
			l.Warnf("no blob found for file: %s", file.Name)
			continue
		}

		// Extract file data from pack using offset and size
		if blob.PackOffset+blob.Size > len(packData) {
			return fmt.Errorf("blob %s extends beyond pack data (offset=%d, size=%d, packlen=%d)",
				blob.Hash, blob.PackOffset, blob.Size, len(packData))
		}

		fileData := packData[blob.PackOffset : blob.PackOffset+blob.Size]

		// Construct target path
		targetPath := filepath.Join(targetDir, file.Name)

		// Prevent path traversal attacks using filepath.Rel
		cleanTargetDir := filepath.Clean(targetDir)
		cleanTargetPath := filepath.Clean(targetPath)
		relPath, err := filepath.Rel(cleanTargetDir, cleanTargetPath)
		if err != nil || strings.HasPrefix(relPath, ".."+string(os.PathSeparator)) || strings.HasPrefix(relPath, "..") && len(relPath) == 2 {
			return fmt.Errorf("illegal file path (path traversal detected): %s", file.Name)
		}

		l.Debugf("extracting: %s (%d bytes)", file.Name, blob.Size)

		// Create parent directories
		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			return fmt.Errorf("failed to create directory for %s: %w", file.Name, err)
		}

		// Write file with appropriate permissions
		fileMode := os.FileMode(0644)
		if file.IsExecutable {
			fileMode = 0755
		}
		if err := os.WriteFile(targetPath, fileData, fileMode); err != nil {
			return fmt.Errorf("failed to write file %s: %w", file.Name, err)
		}

		// Verify file hash if specified
		if file.ExpectedHash != "" {
			valid, actualHash := VerifyHash(fileData, file.ExpectedHash)
			if !valid {
				l.Warnf("file %s hash mismatch: expected %s, got %s", file.Name, file.ExpectedHash, actualHash)
			}
		}
	}

	l.Debugf("extracted %d files successfully", len(files))
	return nil
}

// VerifyHash computes the SHA1 hash of data and compares it with the expected hash
func VerifyHash(data []byte, expectedHash string) (bool, string) {
	h := sha1.New()
	h.Write(data)
	actualHash := hex.EncodeToString(h.Sum(nil))
	return actualHash == expectedHash, actualHash
}

// DownloadAndExtractPack downloads a pack, decompresses it, and extracts files to the target directory
func DownloadAndExtractPack(httpClient http.Client, pack *Pack, manifest WorkingManifest, targetDir string, verifyChecksum bool) error {
	url := fmt.Sprintf("%s/%s/%s", manifest.BaseUrl, pack.RemotePath, pack.Hash)
	l := logrus.WithFields(logrus.Fields{
		"packUrl":   url,
		"targetDir": targetDir,
		"packHash":  pack.Hash,
	})

	l.Debug("downloading pack")
	res, err := httpClient.Get(url)
	if err != nil {
		return fmt.Errorf("failed to download pack: %w", err)
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status code: %d", res.StatusCode)
	}

	// Decompress gzip stream
	l.Debug("decompressing pack")
	gzr, err := gzip.NewReader(res.Body)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzr.Close()

	// Read decompressed pack data
	packData, err := io.ReadAll(gzr)
	if err != nil {
		return fmt.Errorf("failed to read decompressed pack: %w", err)
	}

	// Find all blobs that belong to this pack
	var packBlobs []Blob
	for _, blob := range manifest.Blobs {
		if blob.PackHash == pack.Hash {
			packBlobs = append(packBlobs, blob)
		}
	}

	// Find all files that reference these blobs
	var packFiles []File
	for _, file := range manifest.Files {
		for _, blob := range packBlobs {
			if file.Hash == blob.Hash {
				packFiles = append(packFiles, file)
				break
			}
		}
	}

	l.Debugf("extracting %d files from pack", len(packFiles))

	// Extract files from pack
	if err := ExtractUEPack(packData, packBlobs, packFiles, targetDir, manifest); err != nil {
		return fmt.Errorf("failed to extract pack: %w", err)
	}

	l.Debug("pack downloaded and extracted successfully")
	return nil
}

// DownloadAllPacks downloads and extracts all packs from a manifest
func DownloadAllPacks(httpClient http.Client, manifest WorkingManifest, targetDir string, verifyChecksum bool) error {
	l := logrus.WithFields(logrus.Fields{
		"packCount": len(manifest.Packs),
		"targetDir": targetDir,
	})

	l.Info("downloading all packs")

	for i, pack := range manifest.Packs {
		l.Infof("downloading pack %d/%d", i+1, len(manifest.Packs))
		if err := DownloadAndExtractPack(httpClient, &pack, manifest, targetDir, verifyChecksum); err != nil {
			return fmt.Errorf("failed to download pack %s: %w", pack.Hash, err)
		}
	}

	l.Info("all packs downloaded successfully")
	return nil
}
