package cmd

import "encoding/xml"

type GitDependenciesFile struct {
	XMLName xml.Name
	//WorkingManifest string `xml:""`
}

type WorkingManifest struct {
	XMLName xml.Name
	Files   []File `xml:"Files>File"`
	Packs   []Pack `xml:"Packs>Pack"`
	Blobs   []Blob `xml:"Blobs>Blob"`
}

type File struct {
	XMLName      xml.Name
	Name         string `xml:"Name,attr"`
	Hash         string `xml:"Hash,attr"`
	ExpectedHash string `xml:"ExpectedHash,attr"`
	Timestamp    int    `xml:"Timestamp,attr"`
}

type Blob struct {
	XMLName    xml.Name
	Hash       string `xml:"Hash,attr"`
	Size       int    `xml:"Size,attr"`
	PackHash   string `xml:"PackHash,attr"`
	PackOffset int    `xml:"PackOffset,attr"`
}
type Pack struct {
	XMLName        xml.Name
	Hash           string `xml:"Hash,attr"`
	Size           int    `xml:"Size,attr"`
	CompressedSize int    `xml:"CompressedSize,attr"`
	RemotePath     string `xml:"RemotePath,attr"`
}
