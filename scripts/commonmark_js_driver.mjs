#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import {pathToFileURL} from "node:url";

if (process.argv.length !== 3) {
    process.stderr.write("usage: commonmark_js_driver.mjs COMMONMARK_JS_ROOT\n");
    process.exit(2);
}

const root = path.resolve(process.argv[2]);
const source = fs.readFileSync(0, "utf8");
const moduleUrl = pathToFileURL(path.join(root, "lib", "index.js")).href;

import(moduleUrl).then((commonmark) => {
    const document = new commonmark.Parser().parse(source);
    process.stdout.write(new commonmark.HtmlRenderer().render(document));
}).catch((error) => {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = 1;
});
