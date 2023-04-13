// @deno-types="npm:@types/xml2js"
import {parseStringPromise} from "npm:xml2js";
import { DB } from "https://deno.land/x/sqlite@v3.7.0/mod.ts";

const input = Deno.args[0];
const output = Deno.args[1];
const sqlitedbPath = Deno.args[2];

interface dependency {
    sha256: string;
    url: string;
}

interface dependencyJson {
    [pack: string]: dependency;
}

const decoder = new TextDecoder("utf-8");
const data = decoder.decode(await Deno.readFile(input));
const result = await parseStringPromise(data);
const baseUrl = result["DependencyManifest"]["$"]["BaseUrl"];
const dependencies: dependencyJson = {};

const db = new DB(sqlitedbPath, {
    mode: "read"
});


for (const pack of result["DependencyManifest"]["Packs"][0]["Pack"]) {
        const row = db.queryEntries<{sha256: string}>("SELECT sha256 FROM gitDeps WHERE packHash = ?", [pack["$"]["Hash"]])
        
        if (row.length === 0) {
            console.error("No sha256 for pack: " + pack["$"]["Hash"]);
            // Set exit code to 1
            db.close();
            Deno.exit(1);
        }

        dependencies[pack["$"]["Hash"]] = {
            sha256: row[0].sha256,
            url: `${baseUrl}/${pack["$"]["RemotePath"]}/${pack["$"]["Hash"]}`
        };
}

db.close();
    
Deno.writeTextFileSync(output, JSON.stringify(dependencies, null, 4));
