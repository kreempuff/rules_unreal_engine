package gitDeps

import (
	"encoding/xml"
	"errors"
	"io"
	"io/fs"
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
