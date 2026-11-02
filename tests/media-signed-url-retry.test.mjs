import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("async function signMediaUrl(");
const end=html.indexOf("function mediaHtml(",start);
const classifyStart=html.indexOf("function isTransientMediaError(");
const classifyEnd=html.indexOf("async function registerMediaMetadata(",classifyStart);
assert.ok(start>=0&&end>start&&classifyStart>=0&&classifyEnd>classifyStart,
  "Signed URL retry and transient error classifier must exist");
const source=html.slice(start,end)+"\n"+html.slice(classifyStart,classifyEnd);

function harness(responses){
 const calls=[],delays=[];
 let next=0;
 const context={
  media:[],lastMediaRefreshAt:0,
  query:async table=>{
   assert.equal(table,"media");
   return [{id:"m1",team_id:"team-a",submission_id:"submission-a",message_id:null,
     storage_path:"team-a/submission-a/evidence.jpg",mime_type:"image/jpeg"}];
  },
  sb:{storage:{from:bucket=>{
   assert.equal(bucket,"rebus-bevis");
   return {createSignedUrl:async(path,seconds)=>{
    calls.push({path,seconds});
    const response=responses[next++]??{error:{status:503,message:"Unavailable"}};
    if(response instanceof Error)throw response;
    return response;
   }};
  }}},
  setTimeout:(resolve,ms)=>{delays.push(ms);resolve();}
 };
 vm.createContext(context);
 vm.runInContext(source+"\nglobalThis.api={signMediaUrl,loadMedia,getMedia:()=>media};",context);
 return {api:context.api,calls,delays};
}

test("retries a temporary 503 once, preserving the same private storage path",async()=>{
 const h=harness([{error:{status:503,message:"Temporary outage"}},
  {error:null,data:{signedUrl:"https://private.example/signed"}}]);
 await h.api.loadMedia([{id:"submission-a"}]);
 assert.equal(h.calls.length,2);
 assert.equal(h.calls[0].path,h.calls[1].path);
 assert.equal(h.calls[0].seconds,3600);
 assert.equal(h.api.getMedia()[0].url,"https://private.example/signed");
 assert.equal(h.delays.length,1);
});

test("does not retry RLS or permission failures and never creates a public URL",async()=>{
 const h=harness([{error:{status:403,code:"42501",message:"Permission denied"}}]);
 await h.api.loadMedia([{id:"submission-a"}]);
 assert.equal(h.calls.length,1);
 assert.equal(h.delays.length,0);
 assert.equal(h.api.getMedia()[0].url,null);
});

test("retries a thrown mobile network error",async()=>{
 const h=harness([new TypeError("Failed to fetch"),
  {error:null,data:{signedUrl:"https://private.example/second"}}]);
 await h.api.loadMedia([{id:"submission-a"}]);
 assert.equal(h.calls.length,2);
 assert.equal(h.api.getMedia()[0].url,"https://private.example/second");
});

test("stops after three transient failures without exposing a file",async()=>{
 const h=harness(Array.from({length:3},()=>({error:{status:408,message:"Request timed out"}})));
 await h.api.loadMedia([{id:"submission-a"}]);
 assert.equal(h.calls.length,3);
 assert.deepEqual(h.delays,[250,500]);
 assert.equal(h.api.getMedia()[0].url,null);
});

test("does not retry a malformed successful response without a signed URL",async()=>{
 const h=harness([{data:{},error:null}]);
 await h.api.loadMedia([{id:"submission-a"}]);
 assert.equal(h.calls.length,1);
 assert.equal(h.api.getMedia()[0].url,null);
});

test("only requests signed links for media linked to visible submissions or messages",async()=>{
 const h=harness([{data:{signedUrl:"https://private.example/ok"},error:null}]);
 await h.api.loadMedia([{id:"unrelated-submission"}]);
 assert.equal(h.calls.length,0);
 assert.equal(h.api.getMedia().length,0);
});
