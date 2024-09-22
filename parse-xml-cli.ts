import {parseString} from "npm:xml2js";

const decoder = new TextDecoder("utf-8");
const data = decoder.decode(await Deno.readFile(Deno.args[0]));

/**
 *  {
 *      "downloadUrl": "",
 *      "id": "",
 *  }
 */
parseString(data, (err, result) => {
    if (err) {
        console.error(err);
        return;
    }
    const baseUrl = result["DependencyManifest"]["$"]["BaseUrl"];

    const packs = result["DependencyManifest"]["Packs"][0]["Pack"].reduce((shaMap, pack) => {
        shaMap[pack["$"]["Hash"]] = {
            downloadUrl: `${baseUrl}/${pack["$"]["RemotePath"]}/${pack["$"]["Hash"]}`,
            id: pack["$"]["Hash"]
        };
        return shaMap;
    }, {})

    try {
        // Deno.writeTextFileSync(Deno.args[1], JSON.stringify(result, null, 4));
        Deno.writeTextFileSync(Deno.args[1], JSON.stringify(packs, null));
    } catch (writeErr) {
        console.error(writeErr);
    }
});
