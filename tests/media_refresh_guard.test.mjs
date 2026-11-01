// Regression checks for the media-upload refresh/navigation guard.
// This tests frontend control flow, not actual mobile/browser uploads.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {runInNewContext} from "node:vm";
import {test} from "node:test";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const guard=html.match(/function canRefreshView\(\)\{[^\n]*\}/)?.[0];
assert.ok(guard,"canRefreshView must exist");

function canRefresh(uploads,{draft=false,formActive=false,codeOpen=false,playingVideo=false}={}){
  const document={
    getElementById:()=>codeOpen?{}:null,
    activeElement:formActive?{closest:()=>({})}:null,
    querySelectorAll:()=>playingVideo?[{paused:false,ended:false}]:[{paused:true,ended:false}]
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
test("video playback blocks automatic view refresh, paused video does not",()=>{
  assert.equal(canRefresh(0,{playingVideo:true}),false);
  assert.equal(canRefresh(0,{playingVideo:false}),true);
});

test("upload counter and navigation protection remain wired",()=>{
  assert.match(html,/async function uploadFiles\([^)]*\)\{mediaUploadsInFlight\+\+;/);
  assert.match(html,/finally\{mediaUploadsInFlight=Math\.max\(0,mediaUploadsInFlight-1\)\}/);
  assert.match(html,/document\.hidden\|\|mediaUploadsInFlight>0/);
  assert.match(html,/beforeunload",event=>\{if\(mediaUploadsInFlight===0&&!hasUnsentDraft\(\)\)return;/);
  assert.doesNotMatch(html,/mediaUploadBusy/);
});

const manualGuard=html.match(/function confirmManualRefresh\(\)\{[^\n]*\}/)?.[0];
assert.ok(manualGuard,"confirmManualRefresh must exist");

function manualRefresh(uploads,{draft=false,codeOpen=false,playingVideo=false,confirmation=true}={}){
  const calls=[];
  const document={
    getElementById:()=>codeOpen?{}:null,
    querySelectorAll:()=>playingVideo?[{paused:false,ended:false}]:[{paused:true,ended:false}]
  };
  const allowed=runInNewContext(manualGuard+"\nconfirmManualRefresh()",{
    mediaUploadsInFlight:uploads,
    document,
    hasUnsentDraft:()=>draft,
    confirm:()=>{calls.push("confirm");return confirmation;},
    note:()=>calls.push("note")
  });
  return {allowed,calls};
}

test("manual refresh works when idle without prompting",()=>{
  assert.deepEqual(manualRefresh(0),{allowed:true,calls:[]});
});
test("manual refresh cannot interrupt an active upload",()=>{
  assert.deepEqual(manualRefresh(1),{allowed:false,calls:["note"]});
  assert.deepEqual(manualRefresh(2,{confirmation:true}),{allowed:false,calls:["note"]});
});
test("unsent drafts require confirmation before manual refresh",()=>{
  assert.deepEqual(manualRefresh(0,{draft:true,confirmation:false}),{allowed:false,calls:["confirm"]});
  assert.deepEqual(manualRefresh(0,{draft:true,confirmation:true}),{allowed:true,calls:["confirm"]});
});
test("visible team code or playing video require confirmation",()=>{
  assert.deepEqual(manualRefresh(0,{codeOpen:true,confirmation:false}),{allowed:false,calls:["confirm"]});
  assert.deepEqual(manualRefresh(0,{playingVideo:true,confirmation:false}),{allowed:false,calls:["confirm"]});
});
test("both manual refresh buttons use the guard",()=>{
  assert.match(html,/getElementById\("team-refresh"\)\.onclick=async e=>\{if\(!confirmManualRefresh\(\)\)return;/);
  assert.match(html,/getElementById\("admin-refresh"\)\.onclick=async\(\)=>\{if\(!confirmManualRefresh\(\)\)return;/);
});
