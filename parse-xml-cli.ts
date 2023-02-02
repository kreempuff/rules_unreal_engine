import {parseString} from "npm:xml2js";

const decoder = new TextDecoder("utf-8");
const data = decoder.decode(await Deno.readFile(Deno.args[0]));

parseString(data, (err, result) => {
    if (err) {
        console.error(err);
        return;
    }

    try {
        Deno.writeTextFileSync(Deno.args[1], JSON.stringify(result, null, 4));
    } catch (writeErr) {
        console.error(writeErr);
    }
});
