import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("const MEDIA_EXTENSIONS=");
const end=html.indexOf("async function teamView()",start);
assert.ok(start>=0&&end>start,"Media upload implementation must be present");
const source=html.slice(start,end);

function harness(insertResults,lookupResults=[]){
 const uploads=[],inserts=[],lookups=[],notices=[],delays=[];
 let insertIndex=0,lookupIndex=0;
 const context={
  flash:{innerHTML:""},flashTimer:null,mediaUploadsInFlight:0,
  clearTimeout:()=>{},
  setTimeout:(fn,ms)=>{delays.push(ms);fn();},
  crypto:{randomUUID:()=>"01234567-89ab-4cde-8fab-0123456789ab"},
  note:message=>notices.push(message),
  sb:{
   storage:{from:()=>({upload:async path=>{uploads.push(path);return {error:null}}})},
   from:()=>({
    insert:async record=>{
     inserts.push({...record});
     const outcome=insertResults[insertIndex++]??{error:null};
     if(outcome instanceof Error)throw outcome;
     return outcome;
    },
    select:()=>({eq:()=>({maybeSingle:async()=>{
     lookups.push(true);
     const outcome=lookupResults[lookupIndex++]??{data:null,error:null};
     if(outcome instanceof Error)throw outcome;
     return outcome;
    }})})
   })
  }
 };
 vm.createContext(context);
 vm.runInContext(source+"\\nglobalThis.uploadMedia=uploadFiles;",context);
 const file={name:"evidence.mp4",type:"video/mp4",size:2048};
 return {upload:()=>context.uploadMedia([file],"team-a","submission-a","submission_id"),uploads,inserts,lookups,notices,delays};
}

test("thrown network failure retries only metadata, not the uploaded video",async()=>{
 const h=harness([new TypeError("Failed to fetch"),{error:null}]);
 assert.equal(await h.upload(),0);
 assert.equal(h.uploads.length,1);
 assert.equal(h.inserts.length,2);
 assert.equal(h.lookups.length,1);
 assert.equal(h.delays.length,1);
 assert.equal(h.inserts[0].storage_path,h.inserts[1].storage_path);
});

test("ambiguous thrown error is successful if metadata already exists and matches",async()=>{
 const h=harness([new TypeError("Failed to fetch")],[{data:{team_id:"team-a",submission_id:"submission-a",message_id:null,mime_type:"video/mp4"},error:null}]);
 assert.equal(await h.upload(),0);
 assert.equal(h.inserts.length,1);
 assert.equal(h.delays.length,0);
});

test("transient lookup exception does not prevent a safe metadata retry",async()=>{
 const h=harness([{error:{status:503,message:"Service unavailable"}},{error:null}],[new TypeError("Failed to fetch")]);
 assert.equal(await h.upload(),0);
 assert.equal(h.uploads.length,1);
 assert.equal(h.inserts.length,2);
 assert.equal(h.delays.length,1);
});

test("thrown authorization failure never retries or bypasses RLS",async()=>{
 const h=harness([Object.assign(new Error("RLS denied"),{status:403,code:"42501"})]);
 assert.equal(await h.upload(),1);
 assert.equal(h.uploads.length,1);
 assert.equal(h.inserts.length,1);
 assert.equal(h.delays.length,0);
 assert.match(h.notices.join(" "),/filreferansen til HK/);
});

test("repeated thrown network failures stop after three metadata attempts",async()=>{
 const h=harness([new TypeError("Failed to fetch"),new TypeError("Failed to fetch"),new TypeError("Failed to fetch")]);
 assert.equal(await h.upload(),1);
 assert.equal(h.uploads.length,1);
 assert.equal(h.inserts.length,3);
 assert.equal(h.delays.length,2);
});

test("a conflicting existing record is never treated as a successful registration",async()=>{
 const h=harness([new TypeError("Failed to fetch")],[{data:{team_id:"other-team",submission_id:"submission-a",message_id:null,mime_type:"video/mp4"},error:null}]);
 assert.equal(await h.upload(),1);
 assert.equal(h.inserts.length,1);
 assert.equal(h.delays.length,0);
});
