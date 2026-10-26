import http from 'node:http';

const LIMIT = 262144;
const terminal = new Set(['done', 'error', 'cancelled']);
export class CommonbeamError extends Error {
  constructor(code, requestID = null) {
    super(`Commonbeam: ${code}`);
    this.name = 'CommonbeamError'; this.code = code; this.requestID = requestID;
  }
}
const fail = () => { throw new CommonbeamError('backendProtocolError'); };

/** Byte-oriented framing preserves UTF-8 split across chunks and bounds before decoding. */
export async function* decodeEvents(chunks) {
  const pending = Buffer.alloc(131072);
  let pendingLength = 0, id, ended = false, total = 0;
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for await (const chunk of chunks) {
    // Process slices so a malicious chunk cannot inflate our pending buffer.
    const bytes = Buffer.from(chunk);
    let offset = 0;
    while (offset < bytes.length) {
      const newline = bytes.indexOf(10, offset);
      const end = newline < 0 ? bytes.length : newline;
      if (pendingLength + end - offset > 131072) fail();
      bytes.copy(pending, pendingLength, offset, end);
      pendingLength += end - offset;
      offset = end + 1;
      if (newline < 0) break;
      let event;
      try { event = JSON.parse(decoder.decode(pending.subarray(0, pendingLength))); } catch { fail(); }
      pendingLength = 0;
      if (!event || typeof event !== 'object' || typeof event.id !== 'string' || !event.id || event.id.length > 128 || ended) fail();
      if (!id) {
        if (event.type !== 'start' || typeof event.profile !== 'string' || !Number.isSafeInteger(event.profileRevision) || event.profileRevision < 1 || event.execution !== 'local') fail();
        id = event.id;
      } else {
        if (event.id !== id || event.type === 'start') fail();
        if (event.type === 'delta') {
          if (typeof event.text !== 'string') fail();
          total += Buffer.byteLength(event.text);
          if (total > LIMIT) fail();
        } else if (terminal.has(event.type)) {
          if (event.type === 'done' && (!['stop', 'length'].includes(event.finishReason) || !validUsage(event.usage))) fail();
          if (event.type === 'error' && typeof event.error?.code !== 'string') fail();
          ended = true;
        } else fail();
      }
      yield event;
    }
  }
  if (pendingLength || !ended) fail();
}
function validUsage(usage) {
  return usage && ['inputTokens', 'outputTokens'].every(k => usage[k] === null || Number.isSafeInteger(usage[k]) && usage[k] >= 0);
}
function bodyFor({ profile, messages, maxOutputTokens = 256, deadlineMs = 30000 }, stream) {
  if (!profile || typeof profile.id !== 'string' || !Number.isSafeInteger(profile.revision) || profile.revision < 1 ||
      !Array.isArray(messages) || messages.length < 1 || messages.length > 32 ||
      messages.some(m => !m || Object.keys(m).some(k => !['role', 'content'].includes(k)) || !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string') ||
      !Number.isInteger(maxOutputTokens) || maxOutputTokens < 1 || maxOutputTokens > 512 ||
      !Number.isInteger(deadlineMs) || deadlineMs < 1000 || deadlineMs > 120000) throw new CommonbeamError('invalidRequest');
  if (messages.reduce((n, m) => n + Buffer.byteLength(m.content), 0) > 65536) throw new CommonbeamError('payloadTooLarge');
  const body = JSON.stringify({ profile: profile.id, profileRevision: profile.revision, messages, maxOutputTokens, deadlineMs, stream });
  if (Buffer.byteLength(body) > 98304) throw new CommonbeamError('payloadTooLarge');
  return body;
}

export class Commonbeam {
  #port; #token;
  constructor({ port = 52441, token }) {
    if (!Number.isInteger(port) || port < 1024 || port > 65535 || typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)) throw new CommonbeamError('invalidRequest');
    this.#port = port; this.#token = token;
    this.text = Object.freeze({ generate: this.generate.bind(this), stream: this.stream.bind(this) });
  }
  // node:http is deliberately direct: no environment proxies and no redirect following.
  async #open(path, body, signal, timeout) {
    if (signal?.aborted) throw new CommonbeamError('cancelled');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    const abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    const cleanup = () => { clearTimeout(timer); signal?.removeEventListener('abort', abort); };
    try {
      const response = await new Promise((resolve, reject) => {
        const req = http.request({ hostname: '127.0.0.1', port: this.#port, path,
          method: body === undefined ? 'GET' : 'POST', agent: false, signal: controller.signal,
          maxHeaderSize: 16384,
          headers: { authorization: `Bearer ${this.#token}`, ...(body === undefined ? {} : { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) }) }
        }, resolve);
        req.on('error', reject); req.end(body);
      });
      return { response, close: () => { cleanup(); response.destroy(); } };
    } catch {
      cleanup();
      throw new CommonbeamError(signal?.aborted ? 'cancelled' : 'serviceUnavailable');
    }
  }
  async #json(path, body, signal, timeout = 2000) {
    const { response, close } = await this.#open(path, body, signal, timeout);
    try {
      let length = 0, chunks = [];
      for await (const chunk of response) { length += chunk.length; if (length > LIMIT) fail(); chunks.push(chunk); }
      if (response.statusCode >= 300 && response.statusCode < 400) fail();
      if (response.headers['content-type']?.split(';')[0] !== 'application/json') fail();
      let value;
      try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); } catch { fail(); }
      if (response.statusCode !== 200) throw new CommonbeamError(safeCode(value?.error?.code));
      return value;
    } catch (error) {
      if (error instanceof CommonbeamError) throw error;
      throw new CommonbeamError(signal?.aborted ? 'cancelled' : 'serviceUnavailable');
    } finally { close(); }
  }
  async capabilities({ signal } = {}) {
    const result = await this.#json('/v1/capabilities', undefined, signal);
    if (result.protocol !== 1) throw new CommonbeamError('protocolMismatch');
    if (!Array.isArray(result.profiles) || result.profiles.length > 64 || result.profiles.some(p => !p || typeof p.id !== 'string' || !Number.isSafeInteger(p.revision) || p.revision < 1 || !Array.isArray(p.operations))) fail();
    return { ...result, require(id, operation = 'text.generate') {
      const profile = result.profiles.find(p => p.id === id);
      if (!profile) throw new CommonbeamError('unknownProfile');
      if (profile.state !== 'ready') throw new CommonbeamError('modelNotReady');
      if (profile.execution !== 'local') throw new CommonbeamError('localExecutionUnverified');
      if (!profile.operations.includes(operation)) throw new CommonbeamError('unsupportedCapability');
      return profile;
    } };
  }
  async #negotiate(profile, signal) {
    const current = (await this.capabilities({ signal })).require(profile.id);
    if (current.revision !== profile.revision) throw new CommonbeamError('profileChanged');
  }
  async generate(options) {
    // Consume the same streaming state machine for complete results, including explicit cancel.
    let start, text = '', done;
    for await (const event of this.stream(options)) {
      if (event.type === 'start') start = event;
      if (event.type === 'delta') text += event.text;
      if (event.type === 'done') done = event;
    }
    const { type, ...provenance } = start;
    return { ...provenance, modelDigest: provenance.modelDigest ?? null, text, finishReason: done.finishReason, usage: done.usage };
  }
  async *stream(options) {
    const body = bodyFor(options, true);
    await this.#negotiate(options.profile, options.signal);
    const { response, close } = await this.#open('/v1/text/generate', body, options.signal, (options.deadlineMs ?? 30000) + 1000);
    let id, complete = false;
    try {
      if (response.statusCode !== 200) {
        let data = ''; for await (const chunk of response) { if (Buffer.byteLength(data) + chunk.length > 8192) fail(); data += chunk.toString(); }
        let code; try { code = JSON.parse(data)?.error?.code; } catch { fail(); }
        throw new CommonbeamError(safeCode(code));
      }
      if (response.headers['content-type']?.split(';')[0] !== 'application/x-ndjson') fail();
      for await (const event of decodeEvents(response)) {
        if (event.type === 'start') id = event.id;
        if (terminal.has(event.type)) complete = true;
        if (event.type === 'error') throw new CommonbeamError(safeCode(event.error.code), id);
        if (event.type === 'cancelled') throw new CommonbeamError('cancelled', id);
        yield event;
      }
    } catch (error) {
      if (error instanceof CommonbeamError) throw error;
      throw new CommonbeamError(options.signal?.aborted ? 'cancelled' : 'serviceUnavailable', id);
    } finally {
      close();
      if (id && !complete) await this.cancel(id).catch(() => {});
    }
  }
  async cancel(id) {
    if (typeof id !== 'string' || !/^[A-Za-z0-9-]{1,128}$/.test(id)) throw new CommonbeamError('invalidRequest');
    const { response, close } = await this.#open(`/v1/requests/${id}/cancel`, '{}', undefined, 2000);
    try {
      if (![202, 204].includes(response.statusCode)) throw new CommonbeamError(response.statusCode === 404 ? 'unknownRequest' : 'serviceUnavailable');
    } finally { close(); }
  }
}
const codes = new Set(['invalidRequest','unsupportedCapability','contextExceeded','unauthenticated','permissionDenied','unknownProfile','profileChanged','payloadTooLarge','queueFull','rateLimited','serviceUnavailable','modelNotReady','backendUnavailable','localExecutionUnverified','deadlineExceeded','backendProtocolError','cancelled']);
const safeCode = code => codes.has(code) ? code : 'backendProtocolError';
