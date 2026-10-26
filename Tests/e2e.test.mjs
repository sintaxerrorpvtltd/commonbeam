import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import { Commonbeam } from '../packages/sdk-js/index.js';

const port = Number(process.env.COMMONBEAM_TEST_PORT);
const state = process.env.COMMONBEAM_TEST_STATE;
const token = (await readFile(`${state}/node.secret`, 'utf8')).trim();
const otherToken = (await readFile(`${state}/swift.secret`, 'utf8')).trim();
const beam = new Commonbeam({port,token});
async function call(path, {method='GET', headers={}, body}={}) {
  return new Promise((resolve,reject) => {
    const req=http.request({hostname:'127.0.0.1',port,path,method,agent:false,headers:{...headers}},res=>{
      const parts=[];res.on('data',c=>parts.push(c));res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,text:Buffer.concat(parts).toString()}));
    });req.setTimeout(3000,()=>req.destroy(new Error('timeout')));req.on('error',reject);req.end(body);
  });
}
test('live Swift service exposes only minimal unauthenticated health',async()=>{
  const r=await call('/healthz');assert.equal(r.status,200);
  assert.deepEqual(JSON.parse(r.text),{service:'commonbeam',protocol:1,ready:true});
  assert.equal((await call('/v1/capabilities')).status,401);
});
test('live transport rejects browser, rebinding, query and preflight requests',async()=>{
  for(const headers of [{origin:'null'},{host:'evil.test'},{cookie:'a=b'}]) assert.ok((await call('/healthz',{headers})).status>=400);
  assert.equal((await call('/healthz?token=x')).status,400);
  assert.equal((await call('/healthz',{method:'OPTIONS'})).status,400);
});
test('live transport rejects form and oversized bodies before inference',async()=>{
  const headers={authorization:`Bearer ${token}`,'content-type':'application/x-www-form-urlencoded'};
  assert.equal((await call('/v1/text/generate',{method:'POST',headers,body:'a=b'})).status,400);
  headers['content-type']='application/json';headers['content-length']='98305';
  assert.equal((await call('/v1/text/generate',{method:'POST',headers})).status,413);
});
test('live SDK generates synthetic text, preserves provenance and enforces owner cancellation',async()=>{
  const profile=(await beam.capabilities()).require('fixture-text');
  const result=await beam.generate({profile,messages:[{role:'user',content:'synthetic fixture'}]});
  assert.ok(result.text.startsWith('[Synthetic test response'));
  assert.equal(result.backend,'synthetic-fixture');assert.equal(result.modelDigest,null);
  const other=new Commonbeam({port,token:otherToken});
  await assert.rejects(other.cancel(result.id),{code:'unknownRequest'});
  await beam.cancel(result.id);
});
test('live stream break cancels the request without exposing another grant',async()=>{
  const profile=(await beam.capabilities()).require('fixture-text');let id;
  for await(const event of beam.stream({profile,messages:[{role:'user',content:'cancel fixture'}]})){id=event.id;break;}
  assert.ok(id);await beam.cancel(id);
});
test('raw duplicate Host and authorization headers cannot reach inference',async()=>{
  const response=await new Promise((resolve,reject)=>{
    const socket=net.connect(port,'127.0.0.1',()=>socket.end(`GET /v1/capabilities HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nHost: evil.test\r\nAuthorization: Bearer ${token}\r\nAuthorization: Bearer ${otherToken}\r\nConnection: close\r\n\r\n`));
    let text='';socket.setTimeout(3000,()=>socket.destroy(new Error('timeout')));socket.on('data',chunk=>text+=chunk);socket.on('end',()=>resolve(text));socket.on('error',reject);
  });
  assert.ok(!response.includes('200 OK'));
});
