#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import {pathToFileURL} from "node:url";

if (process.argv.length !== 3) {
    process.stderr.write("usage: commonmark_js_driver.mjs COMMONMARK_JS_ROOT\n");
    process.exit(2);
}

const root = path.resolve(process.argv[2]);
const commonmark = await import(pathToFileURL(path.join(root, "lib", "index.js")));
const source = fs.readFileSync(0, "utf8");
const document = new commonmark.Parser().parse(source);
process.stdout.write(new commonmark.HtmlRenderer().render(document));
