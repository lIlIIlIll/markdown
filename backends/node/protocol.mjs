// Fixed binary framing: the Cangjie pipe API does not provide stdin half-close.
export class Limited extends Error {}
export class Unsupported extends Error {}

export class Reader {
  constructor(bytes) { this.bytes = bytes; this.offset = 0; }
  take(count) {
    if (!Number.isSafeInteger(count) || count < 0 || count > this.bytes.length - this.offset) throw new Error('framing');
    const result = this.bytes.subarray(this.offset, this.offset + count);
    this.offset += count;
    return result;
  }
  byte() { return this.take(1)[0]; }
  uint() { return this.take(4).readUInt32BE(); }
  string(maximum) {
    const size = this.uint();
    if (size > maximum) throw new Limited();
    return new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(this.take(size));
  }
}

export class Writer {
  constructor(maximum) { this.maximum = maximum; this.size = 0; this.parts = []; }
  raw(value) {
    const bytes = Buffer.from(value);
    if (bytes.length > this.maximum - this.size) throw new Limited();
    this.size += bytes.length;
    this.parts.push(bytes);
  }
  byte(value) { this.raw([value]); }
  uint(value) {
    if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) throw new Error('integer');
    const bytes = Buffer.alloc(4); bytes.writeUInt32BE(value); this.raw(bytes);
  }
  string(value) { const bytes = Buffer.from(value, 'utf8'); this.uint(bytes.length); this.raw(bytes); }
  finish() { return Buffer.concat(this.parts, this.size); }
}

export async function readRequest(stream) {
  // Absolute transport ceiling before accepting any caller-declared limits.
  const ceiling = 33554432;
  const parts = [];
  let size = 0;
  let expected = null;
  for await (const part of stream) {
    if (part.length > ceiling + 4 - size) throw new Limited();
    parts.push(part); size += part.length;
    if (parts.length > 65536) throw new Limited();
    if (expected === null && size >= 4) {
      const prefix = Buffer.concat(parts, size);
      expected = prefix.readUInt32BE();
      if (expected > ceiling || expected < 48) throw new Limited();
    }
    if (expected !== null && size >= expected + 4) {
      if (size !== expected + 4) throw new Error('trailing input');
      return Buffer.concat(parts, size).subarray(4);
    }
  }
  throw new Error('truncated input');
}

export function decodeRequest(bytes) {
  const input = new Reader(bytes);
  if (input.take(17).toString('ascii') !== 'MDRICH-REQUEST/1\n') throw new Error('protocol');
  const keys = ['requests', 'input', 'totalInput', 'output', 'totalOutput', 'nodes', 'depth', 'tokens', 'pixels'];
  const limits = Object.fromEntries(keys.map(key => [key, input.uint()]));
  if (Object.values(limits).some(value => value < 1 || value > 2147483647) || limits.requests > 4096 || limits.depth > 1024) throw new Limited();
  const count = input.uint();
  if (count > limits.requests) throw new Limited();
  const requests = [];
  let total = 0;
  for (let i = 0; i < count; i++) {
    const kind = input.byte(), display = input.byte();
    if (kind > 2 || display > 1) throw new Error('kind');
    const language = input.string(128);
    const source = input.string(limits.input);
    total += Buffer.byteLength(source);
    if (total > limits.totalInput) throw new Limited();
    requests.push({kind, display: Boolean(display), language, source});
  }
  if (input.offset !== bytes.length) throw new Error('trailing input');
  return {limits, requests};
}

export function encodeProduct(kind, product, limits) {
  const output = new Writer(limits.output);
  output.byte(kind);
  if (kind === 0) {
    output.uint(product.length);
    for (const node of product) {
      output.string(node.tag); output.string(node.text);
      output.uint(node.attributes.length);
      for (const attribute of node.attributes) { output.string(attribute.name); output.string(attribute.value); }
      output.uint(node.children);
    }
  } else if (kind === 1) {
    output.uint(product.length); output.raw(product);
  } else {
    output.uint(product.length);
    for (const token of product) {
      output.uint(token.start); output.uint(token.end); output.uint(token.color); output.byte(token.fontStyle);
    }
  }
  return output.finish();
}
