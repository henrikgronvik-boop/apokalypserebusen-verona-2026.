// Regression checks for the media-upload refresh/navigation guard.
// This tests frontend control flow, not actual mobile/browser uploads.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {runInNewContext} from "node:vm";
import {test} from "node:test";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const guard=html.match(/function canRefreshView\(\)\{[^\n]*\}/)?.[0];
assert.ok(guard,"canRefreshView must exist");

function canRefresh(uploads,{draft=false,formActive=false,codeOpen=false}={}){
  const document={
    getElementById:()=>codeOpen?{}:null,
    activeElement:formActive?{closest:()=>({})}:null
  };
  return runInNewContext(guard+"\ncanRefreshView()",{
    mediaUploadsInFlight:uploads,document,hasUnsentDraft:()=>draft
  });
}

test("idle view may refresh",()=>assert.equal(canRefresh(0),true));
test("one or more media uploads block refresh",()=>{
  assert.equal(canRefresh(1),false);
  assert.equal(canRefresh(2),false);
});
test("existing unsent drafts, active forms and team code block refresh",()=>{
  assert.equal(canRefresh(0,{draft:true}),false);
  assert.equal(canRefresh(0,{formActive:true}),false);
  assert.equal(canRefresh(0,{codeOpen:true}),false);
});
test("upload counter and navigation protection remain wired",()=>{
  assert.match(html,/async function uploadFiles\([^)]*\)\{mediaUploadsInFlight\+\+;/);
  assert.match(html,/finally\{mediaUploadsInFlight=Math\.max\(0,mediaUploadsInFlight-1\)\}/);
  assert.match(html,/document\.hidden\|\|mediaUploadsInFlight>0/);
  assert.match(html,/beforeunload",event=>\{if\(mediaUploadsInFlight===0\)return;/);
  assert.doesNotMatch(html,/mediaUploadBusy/);
});
