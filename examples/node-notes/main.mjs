import { readFile, stat } from 'node:fs/promises';
import { Commonbeam } from '../../packages/sdk-js/index.js';

// Token is never a command-line argument, bundled value or renderer variable.
const path = process.env.COMMONBEAM_TOKEN_FILE;
if (!path) throw new Error('Set COMMONBEAM_TOKEN_FILE to a private grant file (mode 0600).');
const metadata = await stat(path);
if (!metadata.isFile() || (metadata.mode & 0o777) !== 0o600 || metadata.uid !== process.getuid()) throw new Error('Grant file must belong to you and have mode 0600.');
const token = (await readFile(path, 'utf8')).trim();
const beam = new Commonbeam({ token, port: Number(process.env.COMMONBEAM_PORT ?? 52441) });
try {
  const profile = (await beam.capabilities()).require(process.env.COMMONBEAM_PROFILE ?? 'fixture-text');
  const result = await beam.text.generate({ profile, messages: [{ role: 'user', content: 'Summarize: We tested the rewrite feature. The notes feature needs another review. Tomorrow we will fix the remaining issues.' }] });
  console.log(result.text);
} catch (error) { console.error(error.code ?? 'serviceUnavailable'); process.exitCode = 1; }
