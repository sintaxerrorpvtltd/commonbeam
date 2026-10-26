export interface Profile { id:string; revision:number; state:string; execution:'local'; backend:string; modelDigest:string|null; operations:string[]; features:{stream:boolean; jsonSchema:boolean; tools:boolean}; limits:{maxInputBytes:number; maxOutputTokens:number; contextTokens:number|null} }
export interface Message { role:'system'|'user'|'assistant'; content:string }
export interface Options { profile:Profile; messages:Message[]; maxOutputTokens?:number; deadlineMs?:number; signal?:AbortSignal }
export interface Usage { inputTokens:number|null; outputTokens:number|null }
export type TextEvent = {type:'start'; id:string; profile:string; profileRevision:number; execution:'local'; backend:string; modelDigest:string|null} | {type:'delta'; id:string; text:string} | {type:'done'; id:string; finishReason:'stop'|'length'; usage:Usage} | {type:'error'|'cancelled'; id:string; error?:{code:string}};
export interface Result {id:string; profile:string; profileRevision:number; execution:'local'; backend:string; modelDigest:string|null; text:string; finishReason:'stop'|'length'; usage:Usage}
export class CommonbeamError extends Error { code:string; requestID:string|null; constructor(code:string, requestID?:string|null) }
export class Commonbeam {
  constructor(options:{port?:number;token:string});
  capabilities(options?:{signal?:AbortSignal}):Promise<{protocol:1;profiles:Profile[];require(id:string,operation?:string):Profile}>;
  generate(options:Options):Promise<Result>;
  stream(options:Options):AsyncGenerator<TextEvent>;
  text:{generate(options:Options):Promise<Result>;stream(options:Options):AsyncGenerator<TextEvent>};
  cancel(id:string):Promise<void>;
}
export function decodeEvents(chunks:AsyncIterable<Uint8Array>|Iterable<Uint8Array>):AsyncGenerator<TextEvent>;
