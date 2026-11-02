import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("const MEDIA_EXTENSIONS=");
const end=html.indexOf("async function teamView()",start);
assert.ok(start>=0&&end>start,"Media validation and upload functions must exist in index.html");
const mediaSource=html.slice(start,end);

function harness(){
  const uploads=[],records=[],notices=[];
  const context={
    flash:{innerHTML:""},
    flashTimer:null,
    mediaUploadsInFlight:0,
    clearTimeout:()=>{},
    crypto:{randomUUID:()=>"01234567-89ab-4cde-8fab-0123456789ab"},
    note:message=>notices.push(message),
    sb:{
      storage:{from:bucket=>{
        assert.equal(bucket,"rebus-bevis");
        return {upload:async(path,file,options)=>{uploads.push({path,file,options});return {error:null}}};
      }},
      from:table=>{
        assert.equal(table,"media");
        return {insert:async record=>{records.push(record);return {error:null}}};
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(mediaSource+"\nglobalThis.mediaApi={validateFiles,uploadFiles};",context);
  return {api:context.mediaApi,uploads,records,notices,context};
}

const file=(name,type,size=1024)=>({name,type,size});

test("supports only the six expected image and video MIME types",()=>{
  const {api}=harness();
  for(const type of ["image/jpeg","image/png","image/webp","video/mp4","video/quicktime","video/webm"]){
    assert.doesNotThrow(()=>api.validateFiles([file("proof",type)]));
  }
  for(const type of ["image/heic","text/html","image/svg+xml","video/x-msvideo",""]){
    assert.throws(()=>api.validateFiles([file("proof",type)]),/format som ikke støttes/);
  }
});

test("rejects zero-byte media before any upload",async()=>{
  const {api,uploads,records}=harness();
  assert.throws(()=>api.validateFiles([file("empty.jpg","image/jpeg",0)]),/tom/);
  assert.equal(await api.uploadFiles([file("empty.jpg","image/jpeg",0)],"team-1","submission-1","submission_id"),1);
  assert.equal(uploads.length,0);
  assert.equal(records.length,0);
});

test("enforces the free-tier 50 MB per-file cap",()=>{
  const {api}=harness();
  assert.doesNotThrow(()=>api.validateFiles([file("max.mp4","video/mp4",50*1024*1024)]));
  assert.throws(()=>api.validateFiles([file("too-large.mp4","video/mp4",50*1024*1024+1)]),/50 MB/);
});

test("generates a trusted extension from MIME rather than a user-supplied filename",async()=>{
  const {api,uploads,records}=harness();
  const result=await api.uploadFiles([file("not-an-image.html","image/jpeg")],"team-1","submission-1","submission_id");
  assert.equal(result,0);
  assert.equal(uploads.length,1);
  assert.match(uploads[0].path,/^team-1\/submission-1\/[a-f0-9-]+\.jpg$/);
  assert.equal(uploads[0].options.contentType,"image/jpeg");
  assert.equal(records[0].storage_path,uploads[0].path);
  assert.equal(records[0].submission_id,"submission-1");
});

test("normalizes MOV and WebM paths without trusting extensions",async()=>{
  const {api,uploads}=harness();
  const result=await api.uploadFiles([
    file("movie.jpg","video/quicktime"),
    file("movie.exe","video/webm")
  ],"team-1","message-1","message_id");
  assert.equal(result,0);
  assert.match(uploads[0].path,/\.mov$/);
  assert.match(uploads[1].path,/\.webm$/);
  assert.equal(uploads[0].options.upsert,false);
  assert.equal(uploads[1].options.upsert,false);
});

test("does not upload unsupported HEIC content even if filename ends in jpg",async()=>{
  const {api,uploads,records,notices}=harness();
  assert.equal(await api.uploadFiles([file("photo.jpg","image/heic")],"team-1","submission-1","submission_id"),1);
  assert.equal(uploads.length,0);
  assert.equal(records.length,0);
  assert.match(notices.join(" "),/HEIC/);
});
