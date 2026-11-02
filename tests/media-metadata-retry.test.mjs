import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("const MEDIA_EXTENSIONS=");
const end=html.indexOf("async function teamView()",start);
assert.ok(start>=0&&end>start);
const source=html.slice(start,end);

function harness(responses,lookups){
  const uploads=[],inserts=[],notices=[],delays=[];
  let nextInsert=0,nextLookup=0;
  const context={
    flash:{innerHTML:""},flashTimer:null,mediaUploadsInFlight:0,
    clearTimeout:()=>{},
    setTimeout:(resolve,ms)=>{delays.push(ms);resolve();},
    crypto:{randomUUID:()=>"01234567-89ab-4cde-8fab-0123456789ab"},
    note:message=>notices.push(message),
    sb:{
      storage:{from:()=>({upload:async(path)=>{uploads.push(path);return {error:null};}})},
      from:()=>({
        insert:async record=>{inserts.push({...record});return responses[nextInsert++]??{error:null};},
        select:()=>({eq:()=>({maybeSingle:async()=>lookups[nextLookup++]??{data:null,error:null}})})
      })
    }
  };
  vm.createContext(context);
  vm.runInContext(source+"\nglobalThis.mediaApi={uploadFiles};",context);
  return {api:context.mediaApi,uploads,inserts,notices,delays};
}
const file={name:"bevis.mp4",type:"video/mp4",size:1024};
const upload=async h=>h.api.uploadFiles([file],"team-1","submission-1","submission_id");

test("transient metadata error retries the insert, never the upload",async()=>{
  const h=harness([{error:{status:503,message:"Temporary outage"}},{error:null}],[{data:null,error:null}]);
  assert.equal(await upload(h),0);
  assert.equal(h.uploads.length,1);
  assert.equal(h.inserts.length,2);
  assert.equal(h.delays.length,1);
  assert.equal(h.inserts[0].storage_path,h.inserts[1].storage_path);
});

test("ambiguous response succeeds if the existing metadata matches",async()=>{
  const h=harness([{error:{message:"Failed to fetch"}}],[{error:null,data:{team_id:"team-1",submission_id:"submission-1",message_id:null,mime_type:"video/mp4"}}]);
  assert.equal(await upload(h),0);
  assert.equal(h.uploads.length,1);
  assert.equal(h.inserts.length,1);
  assert.equal(h.delays.length,0);
});

test("permission failure is not retried and keeps the recovery reference",async()=>{
  const h=harness([{error:{status:403,code:"42501",message:"RLS denied"}}],[{data:null,error:null}]);
  assert.equal(await upload(h),1);
  assert.equal(h.uploads.length,1);
  assert.equal(h.inserts.length,1);
  assert.equal(h.delays.length,0);
  assert.match(h.notices.join(" "),/Filen ble lagret/);
  assert.match(h.notices.join(" "),/team-1\/submission-1\//);
});

test("persistent transient errors stop after three inserts",async()=>{
  const h=harness(Array.from({length:3},()=>({error:{status:503,message:"Unavailable"}})),Array.from({length:3},()=>({data:null,error:null})));
  assert.equal(await upload(h),1);
  assert.equal(h.uploads.length,1);
  assert.equal(h.inserts.length,3);
  assert.equal(h.delays.length,2);
  assert.match(h.notices.join(" "),/filreferansen til HK/);
});

test("conflicting metadata is never overwritten or retried",async()=>{
  const h=harness([{error:{status:503,message:"Unavailable"}}],[{error:null,data:{team_id:"other-team",submission_id:"submission-1",message_id:null,mime_type:"video/mp4"}}]);
  assert.equal(await upload(h),1);
  assert.equal(h.inserts.length,1);
  assert.equal(h.delays.length,0);
});
