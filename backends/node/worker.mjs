import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import katex from 'katex';
import {parseFragment} from 'parse5';
import {createHighlighter, bundledLanguages} from 'shiki';
import puppeteer from 'puppeteer';
import {renderMermaid} from '@mermaid-js/mermaid-cli';
import {decodeRequest, encodeProduct, readRequest, Writer, Limited, Unsupported} from './protocol.mjs';
import {guardedBrowser} from './boundary.mjs';

const runtime = fileURLToPath(new URL('.', import.meta.url));
const args = process.argv.slice(2);
const theme = args[0], diagramTheme = args[1], allowNoSandbox = args[2] === 'true';
// Libraries cannot pollute the framed protocol or expose source/path diagnostics.
console.log = console.warn = console.error = () => {};

async function checkVersions() {
  for (const [name, version] of [['katex', '0.19.0'], ['shiki', '4.5.0'], ['parse5', '8.0.0'], ['@mermaid-js/mermaid-cli', '12.0.0']]) {
    const value = JSON.parse(await readFile(path.join(runtime, 'node_modules', name, 'package.json'), 'utf8'));
    if (value.version !== version) throw new Unsupported();
  }
  if (process.version !== 'v24.22.0' || !['github-light', 'github-dark'].includes(theme) ||
      !['default', 'dark', 'neutral', 'forest'].includes(diagramTheme)) throw new Unsupported();
}

function math(request, limits) {
  const fragment = parseFragment(katex.renderToString(request.source, {
    displayMode: request.display, output: 'mathml', trust: false, strict: 'error', throwOnError: true,
    maxExpand: 100, maxSize: 10, globalGroup: false,
  }));
  const search = [...fragment.childNodes];
  let root;
  while (search.length) {
    const node = search.pop();
    if (node.tagName === 'math') { if (root) throw new Unsupported(); root = node; }
    else if (node.childNodes) search.push(...node.childNodes);
  }
  if (!root) throw new Unsupported();
  const nodes = [], stack = [{node: root, depth: 1}];
  while (stack.length) {
    const {node, depth} = stack.pop();
    if (nodes.length >= limits.nodes || depth > limits.depth) throw new Limited();
    if (node.nodeName === '#text') { nodes.push({tag: '', text: node.value, attributes: [], children: 0}); continue; }
    if (!node.tagName || node.namespaceURI !== 'http://www.w3.org/1998/Math/MathML') throw new Unsupported();
    // TeX annotations duplicate source and are not presentation data.
    const children = (node.childNodes ?? []).filter(child => !['annotation', 'annotation-xml'].includes(child.tagName));
    if (children.length > limits.nodes - nodes.length - stack.length) throw new Limited();
    const attributes = (node.attrs ?? []).map(attribute => {
      if (attribute.prefix) throw new Unsupported();
      return {name: attribute.name, value: attribute.value};
    });
    nodes.push({tag: node.tagName, text: '', attributes, children: children.length});
    for (let index = children.length - 1; index >= 0; index--) stack.push({node: children[index], depth: depth + 1});
  }
  return nodes;
}

function utf8Offsets(source) {
  const offsets = new Uint32Array(source.length + 1);
  let bytes = 0;
  for (let i = 0; i < source.length;) {
    const point = source.codePointAt(i), units = point > 0xffff ? 2 : 1;
    offsets[i] = bytes;
    if (units === 2) offsets[i + 1] = 0xffffffff;
    bytes += point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4;
    i += units; offsets[i] = bytes;
  }
  return offsets;
}

async function highlight(request, limits, highlighter) {
  // bundledLanguages is an allowlist of owned lazy loaders, never a path import.
  if (!Object.hasOwn(bundledLanguages, request.language)) throw new Unsupported();
  await highlighter.loadLanguage(request.language);
  const result = highlighter.codeToTokens(request.source, {lang: request.language, theme});
  const offsets = utf8Offsets(request.source), tokens = [];
  let previous = 0;
  for (const line of result.tokens) for (const token of line) {
    if (!token.content) continue;
    if (tokens.length >= limits.tokens) throw new Limited();
    const start = token.offset, end = start + token.content.length;
    if (!Number.isInteger(start) || start < previous || end > request.source.length ||
        request.source.slice(start, end) !== token.content || offsets[start] === 0xffffffff || offsets[end] === 0xffffffff ||
        !/^#[0-9a-fA-F]{6}$/.test(token.color ?? '')) throw new Unsupported();
    const fontStyle = token.fontStyle === -1 ? 0 : token.fontStyle ?? 0;
    if (!Number.isInteger(fontStyle) || fontStyle < 0 || fontStyle > 7) throw new Unsupported();
    tokens.push({start: offsets[start], end: offsets[end], color: Number.parseInt(token.color.slice(1), 16), fontStyle});
    previous = end;
  }
  return tokens;
}

function criticalPng(value, limits) {
  const bytes = Buffer.from(value);
  if (bytes.length > limits.output) throw new Limited();
  if (bytes.length < 57 || !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('png');
  const parts = [bytes.subarray(0, 8)];
  for (let offset = 8; offset < bytes.length;) {
    if (bytes.length - offset < 12) throw new Error('png');
    const length = bytes.readUInt32BE(offset);
    if (length > bytes.length - offset - 12) throw new Error('png');
    const kind = bytes.subarray(offset + 4, offset + 8).toString('ascii');
    if (['IHDR', 'IDAT', 'IEND'].includes(kind)) parts.push(bytes.subarray(offset, offset + length + 12));
    else if ((bytes[offset + 4] & 32) === 0) throw new Unsupported();
    offset += length + 12;
  }
  return Buffer.concat(parts);
}

async function main() {
  await checkVersions();
  const {requests, limits: declared} = decodeRequest(await readRequest(process.stdin));
  const limits = {...declared, output: Math.min(declared.output, 8388608), totalOutput: Math.min(declared.totalOutput, 33554432),
    nodes: Math.min(declared.nodes, 65536), depth: Math.min(declared.depth, 128), tokens: Math.min(declared.tokens, 131072), pixels: Math.min(declared.pixels, 4194304)};
  const output = new Writer(limits.totalOutput + requests.length * 2 + 64);
  output.raw(Buffer.from('MDRICH-RESPONSE/1\n')); output.uint(requests.length);
  let browser, guard, highlighter, productBytes = 0;
  try {
    for (const request of requests) {
      try {
        let product;
        if (request.kind === 0) product = math(request, limits);
        else if (request.kind === 2) {
          highlighter ??= await createHighlighter({themes: [theme], langs: []});
          product = await highlight(request, limits, highlighter);
        } else {
          // First delivery intentionally supports strict flowcharts only.
          if (!/^(?:flowchart|graph)\s+(?:TB|TD|BT|RL|LR)\b/.test(request.source.trimStart()) ||
              /%%\s*\{|^\s*click\b/m.test(request.source) || request.source.trimStart().startsWith('---')) throw new Unsupported();
          if (Buffer.byteLength(request.source) > 65536) throw new Limited();
          if (!browser) {
            browser = await puppeteer.launch({executablePath: path.join(runtime, 'chrome/chrome'), headless: true, pipe: true,
              args: [...(allowNoSandbox ? ['--no-sandbox', '--disable-setuid-sandbox'] : []), '--disable-dev-shm-usage'],
              handleSIGINT: false, handleSIGTERM: false, handleSIGHUP: false});
            if (await browser.version() !== 'Chrome/155.0.8059.84') throw new Unsupported();
            guard = await guardedBrowser(browser, runtime, limits.pixels);
          }
          guard.blocked.clear();
          const size = Math.min(1024, guard.dimension);
          const result = await renderMermaid(guard, request.source, 'png', {
            viewport: {width: Math.min(800, size), height: Math.min(600, size), deviceScaleFactor: 1}, size, fontEmbed: false,
            customFontCSS: [{cssUrl: pathToFileURL(path.join(runtime, 'fonts/font.css'))}],
            mermaidConfig: {theme: diagramTheme, securityLevel: 'strict', startOnLoad: false, fontFamily: 'MarkdownRich',
              maxTextSize: 65536, maxEdges: 512, flowchart: {htmlLabels: false},
              secure: ['securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'fontFamily']},
          });
          if (guard.blocked.size) throw new Unsupported();
          product = criticalPng(result.data, limits);
        }
        const encoded = encodeProduct(request.kind, product, limits);
        if (encoded.length > limits.totalOutput - productBytes) throw new Limited();
        productBytes += encoded.length;
        output.byte(0); output.raw(encoded);
      } catch (error) {
        output.byte(error instanceof Limited ? 6 : error instanceof Unsupported || error?.name === 'ParseError' ? 3 : 5);
      }
    }
  } finally {
    highlighter?.dispose();
    if (browser) await browser.close();
  }
  process.stdout.write(output.finish());
}

try { await main(); }
catch (error) { process.stderr.write('rich backend failed\n'); process.exitCode = error instanceof Limited ? 75 : error instanceof Unsupported ? 69 : 70; }
