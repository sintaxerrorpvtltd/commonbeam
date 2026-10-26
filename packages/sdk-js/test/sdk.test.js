import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import http from 'node:http';
import { once } from 'node:events';
import { Commonbeam, decodeEvents } from '../index.js';

const fixture = name => readFile(new URL(`../../../protocol/fixtures/${name}`, import.meta.url));
const stream = await fixture('stream.ndjson');
const caps = JSON.parse(await fixture('capabilities.json'));
const token = 'a'.repeat(43);
// Socket coverage is opt-in: the managed executor forbids listen(2).
// Run COMMONBEAM_SOCKET_TESTS=1 npm test on an unrestricted local terminal.
const socketTest = process.env.COMMONBEAM_SOCKET_TESTS === '1' ? test : test.skip;
async function collect(chunks) { const out = []; for await (const event of decodeEvents(chunks)) out.push(event); return out; }
async function server(t, handler) {
  const instance = http.createServer(handler);
  instance.listen(0, '127.0.0.1'); await once(instance, 'listening');
  t.after(() => { instance.closeAllConnections(); instance.close(); });
  return new Commonbeam({ port: instance.address().port, token });
}
test('shared fixture survives one-byte UTF-8 fragmentation and empty delta', async () => {
  const events = await collect([...stream].map(b => Buffer.from([b])));
  assert.deepEqual(events.map(e => e.type), ['start','delta','delta','done']);
  assert.equal(events[1].text, 'Hello 🌍');
});
test('every possible two-chunk split gives identical events', async () => {
  const reference = await collect([stream]);
  for (let i = 0; i <= stream.length; i++) assert.deepEqual(await collect([stream.subarray(0, i), stream.subarray(i)]), reference);
});
test('reject duplicate terminal, delta before start, mismatched ID, missing terminal', async () => {
  const lines = stream.toString().trimEnd().split('\n');
  for (const text of [stream + lines.at(-1) + '\n', lines.slice(1).join('\n') + '\n', lines.slice(0, -1).join('\n') + '\n', stream.toString().replace('"type":"delta","id":"fixture-request"', '"type":"delta","id":"other"')]) {
    await assert.rejects(collect([Buffer.from(text)]), { code: 'backendProtocolError' });
  }
});
test('reject invalid UTF-8, oversize line and invalid usage', async () => {
  for (const bytes of [Buffer.from([255,10]), Buffer.alloc(131073, 32), Buffer.from(stream.toString().replace('"outputTokens":null', '"outputTokens":-1'))]) {
    await assert.rejects(collect([bytes]), { code: 'backendProtocolError' });
  }
});
test('validate token and port before networking', () => {
  assert.throws(() => new Commonbeam({ port: 80, token }), { code: 'invalidRequest' });
  assert.throws(() => new Commonbeam({ token: 'bad\r\nInjected: yes' }), { code: 'invalidRequest' });
});
socketTest('SOCKET: SDK negotiates before sending a prompt and preserves result provenance', async t => {
  const seen = [];
  const beam = await server(t, async (req, res) => {
    seen.push(req.url); assert.equal(req.headers.authorization, `Bearer ${token}`);
    if (req.url === '/v1/capabilities') { res.setHeader('content-type', 'application/json'); return res.end(JSON.stringify(caps)); }
    let body = ''; for await (const chunk of req) body += chunk;
    assert.equal(JSON.parse(body).messages[0].content, 'synthetic');
    res.setHeader('content-type', 'application/x-ndjson'); res.end(stream);
  });
  const result = await beam.generate({ profile: caps.profiles[0], messages: [{role:'user',content:'synthetic'}] });
  assert.deepEqual(seen, ['/v1/capabilities', '/v1/text/generate']);
  assert.equal(result.text, 'Hello 🌍'); assert.equal(result.backend, 'fixture');
});
socketTest('SOCKET: protocol mismatch prevents prompt transmission', async t => {
  let count = 0;
  const beam = await server(t, (req, res) => { count++; res.setHeader('content-type', 'application/json'); res.end(JSON.stringify({...caps, protocol:2})); });
  await assert.rejects(beam.generate({ profile:caps.profiles[0], messages:[{role:'user',content:'secret'}] }), {code:'protocolMismatch'});
  assert.equal(count, 1);
});
socketTest('SOCKET: revision change prevents prompt transmission', async t => {
  let count = 0;
  const beam = await server(t, (req, res) => { count++; res.setHeader('content-type', 'application/json'); res.end(JSON.stringify({...caps, profiles:[{...caps.profiles[0],revision:2}]})); });
  await assert.rejects(beam.generate({ profile:caps.profiles[0], messages:[{role:'user',content:'secret'}] }), {code:'profileChanged'});
  assert.equal(count, 1);
});
socketTest('SOCKET: redirects are rejected and never followed', async t => {
  let requests = 0;
  const beam = await server(t, (req, res) => { requests++; res.writeHead(302, {location:'http://127.0.0.1:9/leak'}); res.end(); });
  await assert.rejects(beam.capabilities(), {code:'backendProtocolError'});
  assert.equal(requests, 1);
});
socketTest('SOCKET: typed HTTP errors omit untrusted provider text', async t => {
  const beam = await server(t, (req, res) => { res.writeHead(401, {'content-type':'application/json'}); res.end(JSON.stringify({error:{code:'unauthenticated',message:'private-provider-body'}})); });
  await assert.rejects(beam.capabilities(), error => error.code === 'unauthenticated' && !error.message.includes('private-provider-body'));
});
socketTest('SOCKET: breaking a stream sends explicit owner cancellation', async t => {
  let cancelled = false;
  const beam = await server(t, (req, res) => {
    if (req.url === '/v1/capabilities') { res.setHeader('content-type', 'application/json'); return res.end(JSON.stringify(caps)); }
    if (req.url.endsWith('/cancel')) { cancelled = true; res.writeHead(202); return res.end(); }
    res.setHeader('content-type', 'application/x-ndjson'); res.write(stream.toString().split('\n')[0] + '\n');
  });
  for await (const event of beam.stream({profile:caps.profiles[0], messages:[{role:'user',content:'x'}]})) { assert.equal(event.type,'start'); break; }
  assert.equal(cancelled, true);
});
socketTest('SOCKET: stream error is mapped to same typed error', async t => {
  const beam = await server(t, (req, res) => {
    if (req.url === '/v1/capabilities') { res.setHeader('content-type', 'application/json'); return res.end(JSON.stringify(caps)); }
    res.setHeader('content-type', 'application/x-ndjson');
    res.end(stream.toString().split('\n')[0] + '\n' + JSON.stringify({type:'error',id:'fixture-request',error:{code:'deadlineExceeded'}}) + '\n');
  });
  await assert.rejects(beam.generate({profile:caps.profiles[0],messages:[{role:'user',content:'x'}]}), {code:'deadlineExceeded'});
});
test('invalid input is rejected before connecting', async () => {
  const beam = new Commonbeam({port:52441, token});
  await assert.rejects(beam.generate({profile:caps.profiles[0], messages:[{role:'tool',content:'x'}]}), {code:'invalidRequest'});
});
