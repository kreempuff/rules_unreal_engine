// @deno-types="npm:@types/xml2js"
import {parseStringPromise} from "npm:xml2js";

const input = Deno.args[0];
const output = Deno.args[1];

const decoder = new TextDecoder("utf-8");
const data = decoder.decode(await Deno.readFile(input));
const result = await parseStringPromise(data);
const baseUrl = result["DependencyManifest"]["$"]["BaseUrl"];
const urls = []
for (const pack of result["DependencyManifest"]["Packs"][0]["Pack"]) {
    urls.push((baseUrl + "/" + pack["$"]["RemotePath"] + "/" + pack["$"]["Hash"]));
}
Deno.writeTextFileSync(output, JSON.stringify(result, null, 4));
console.log(urls.join(","));
