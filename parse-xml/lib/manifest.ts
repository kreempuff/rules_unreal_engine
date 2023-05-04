import {XMLParser} from "npm:fast-xml-parser";
import {GzipStream} from "https://deno.land/x/compress@v0.4.4/mod.ts";
import {exists as fileExists} from "https://deno.land/std@0.185.0/fs/mod.ts";



interface GitDependeciesManifestFile {
    DependencyManifest: {
        Files: {
            File: [
                {
                    "@_Name": string;
                    "@_Hash": string;
                    "@_IsExecutable"?: boolean;
                }
            ]
        },
        Packs: {
            Pack: [
                {
                    "@_Hash": string;
                    "@_Size": string;
                    "@_CompressedSize": string;
                    "@_RemotePath": string;
                }
            ]
        },
        Blobs: {
            Blob: [
                {
                    "@_Hash": string;
                    "@_Size": string;
                    "@_PackHash": string;
                    "@_PackOffset": string;
                }
            ]
        }
    }
}

export function parseManifestFromFile(filename: string): GitDependeciesManifestFile {
    const data = Deno.readTextFileSync(filename);

    const parser = new XMLParser({
        ignoreAttributes: false,
    });
    return parser.parse<string>(data) as Manifest;
}

/**
 * GitDependencies
 */
class GitDependencies {

    private _manifest: GitDependeciesManifestFile;
    private _packDirectory: string;

    /**
     * @constructor
     * @description Parses the manifest file and stores the pack location
     * @param filename {string} The path to the manifest file
     * @param packDirectory {string} The location of the pack files. This is the base url in the manifest
     */
    constructor(filename: string, packDirectory: string) {
        if (filename === undefined) {
            throw new Error("Manifest filename is undefined");
        }
        this._manifest = parseManifestFromFile(filename);

        if (packDirectory === undefined) {
            throw new Error("Pack directory is undefined");
        }
        this._packDirectory = packDirectory;
    }

    /**
     * Returns the list of all files in the manifest
     */
    printAllFiles(): string[] {
        return this._manifest.DependencyManifest.Files.File.map(file => file["@_Name"]);
    }

    /**
     * Returns the list of all packs in the manifest
     */
    printAllPacks(): string[] {
        return this._manifest.DependencyManifest.Packs.Pack.map(pack => pack["@_Hash"]);
    }

    async getFileBytes(filename: string): Uint8Array {
        const file = this._manifest.DependencyManifest.Files.File.find(file => file["@_Name"] === filename);
        if (!file) {

            throw new Error(`File ${filename} not found in manifest`);
        }

        // Get the blob associated with the file
        const blob = this._manifest.DependencyManifest.Blobs.Blob.find(blob => blob["@_Hash"] === file["@_Hash"]);

        // Get pack associated with the blob
        const pack = this._manifest.DependencyManifest.Packs.Pack.find(pack => pack["@_Hash"] === blob["@_PackHash"]);

        // Check if uncompressed pack exists locally
        const compressedPackFilePath: string = `${this._packDirectory}/${pack["@_Hash"]}`;
        const uncompressedPackFilePath: string = `${compressedPackFilePath}.uncompressed`;
        const uncompressedPackExists = await fileExists(uncompressedPackFilePath);
        if (!uncompressedPackExists) {
            const gzipStream = new GzipStream();
            gzipStream.on("progress", (progress: string) => {
                console.log(`Progress: ${progress}`);
            });
            console.log(`Uncompressing ${uncompressedPackFilePath} to ${uncompressedPackFilePath}`);
            await gzipStream.uncompress(`${compressedPackFilePath}`, uncompressedPackFilePath);
        } else {
            console.log(`Uncompressed pack "${pack["@_Hash"]}.uncompressed" already exists`);
        }

        const uncompressedPackFile = await Deno.open(`${uncompressedPackFilePath}`, {read: true});

        // Seek to the offset of the blob in the pack
        await uncompressedPackFile.seek(Number(blob["@_PackOffset"]), Deno.SeekMode.Start);

        // Read the blob size from the pack
        const blobSize = Number(blob["@_Size"]);
        const blobBytes = new Uint8Array(blobSize);
        await uncompressedPackFile.read(blobBytes);


        // print the file name, blob hash, and pack hash
        console.log(file["@_Name"]);
        console.log(blob["@_Hash"]);
        console.log(pack["@_Hash"]);

        // print the first blob as string
        console.log(new TextDecoder().decode(blobBytes));
    }
}


if (import.meta.main) {
    const gitDependencies = new GitDependencies(
        "/Users/kareemmarch/Projects/rules_unreal_engine/bazel-rules_unreal_engine/external/unreal_engine/UnrealEngine/Engine/Build/Commit.gitdeps.xml",
        "/Users/kareemmarch/Projects/rules_unreal_engine/bazel-rules_unreal_engine/external/unreal_engine/gitdeps");
    await gitDependencies.getFileBytes(".tgitconfig")
}