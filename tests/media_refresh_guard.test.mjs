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

const mediaDetector=html.match(/const hasNewTeamMedia=[^\n]*;/)?.[0];
assert.ok(mediaDetector,"hasNewTeamMedia must exist");
function hasNewMedia(latest,known){
  return runInNewContext(mediaDetector+"\nhasNewTeamMedia(latest,known)",{latest,known});
}
test("team refresh detects new proof files but ignores known or empty media",()=>{
  assert.equal(hasNewMedia([{id:"new"}],[{id:"old"}]),true);
  assert.equal(hasNewMedia([{id:"known"}],[{id:"known"}]),false);
  assert.equal(hasNewMedia([],[{id:"known"}]),false);
  assert.equal(hasNewMedia([{id:"known"}],[]),true);
});
test("live updates poll own-team media and recheck draft safety after network calls",()=>{
  assert.ok(html.includes('sb.from("media").select("id").eq("team_id",team).order("created_at",{ascending:false}).limit(1)'));
  assert.ok(html.includes('if((messageChanged(recent.data,messages)||hasNewTeamMedia(recentMedia.data,media))&&canRefreshView())'));
  assert.ok(html.includes('if(hasNewWork&&canRefreshView())await adminView()'));
  assert.ok(html.includes('if(specialNow.data.some(x=>!tasks.some(t=>t.id===x.id))&&canRefreshView())'));
  assert.ok(html.includes('&&canRefreshView())await teamView()}}}}catch(e)'));
});

const draftGuard=html.match(/function hasUnsentDraft\(\)\{[^\n]*\}/)?.[0];
assert.ok(draftGuard,"hasUnsentDraft must exist");
const hasDraft=elements=>runInNewContext(draftGuard+"\nhasUnsentDraft()",{
  document:{querySelectorAll:()=>elements}
});
test("empty and unchanged form controls do not prevent refresh",()=>{
  assert.equal(hasDraft([]),false);
  assert.equal(hasDraft([{tagName:"TEXTAREA",type:"textarea",value:"",defaultValue:""}]),false);
  assert.equal(hasDraft([{tagName:"INPUT",type:"number",value:"600",defaultValue:"600"}]),false);
  assert.equal(hasDraft([{tagName:"INPUT",type:"file",files:[]}]),false);
});
test("typed text and changed numeric HK award are protected",()=>{
  assert.equal(hasDraft([{tagName:"TEXTAREA",type:"textarea",value:"Bevis",defaultValue:""}]),true);
  assert.equal(hasDraft([{tagName:"INPUT",type:"text",value:"Lag",defaultValue:""}]),true);
  assert.equal(hasDraft([{tagName:"INPUT",type:"number",value:"800",defaultValue:"600"}]),true);
});
test("selected proof file is protected",()=>{
  assert.equal(hasDraft([{tagName:"INPUT",type:"file",files:[{name:"bevis.mp4"}]}]),true);
});
test("selects use original option even without an explicit selected attribute",()=>{
  const options=[{selected:true,defaultSelected:false},{selected:false,defaultSelected:false}];
  assert.equal(hasDraft([{tagName:"SELECT",type:"select-one",options,selectedIndex:0}]),false);
  assert.equal(hasDraft([{tagName:"SELECT",type:"select-one",options,selectedIndex:1}]),true);
  const withDefault=[{defaultSelected:false},{defaultSelected:true}];
  assert.equal(hasDraft([{tagName:"SELECT",type:"select-one",options:withDefault,selectedIndex:1}]),false);
  assert.equal(hasDraft([{tagName:"SELECT",type:"select-one",options:withDefault,selectedIndex:0}]),true);
});
test("readonly, disabled, hidden and unchanged checkbox controls do not block refresh",()=>{
  assert.equal(hasDraft([{tagName:"INPUT",type:"text",value:"new",defaultValue:"",readOnly:true}]),false);
  assert.equal(hasDraft([{tagName:"INPUT",type:"text",value:"new",defaultValue:"",disabled:true}]),false);
  assert.equal(hasDraft([{tagName:"INPUT",type:"hidden",value:"new",defaultValue:""}]),false);
  assert.equal(hasDraft([{tagName:"INPUT",type:"checkbox",checked:false,defaultChecked:false}]),false);
  assert.equal(hasDraft([{tagName:"INPUT",type:"checkbox",checked:true,defaultChecked:false}]),true);
});


const teamSnapshot=html.match(/const teamSnapshotChanged=[^\n]*;/)?.[0];
assert.ok(teamSnapshot,"teamSnapshotChanged must exist");
const snapshotChanged=(before,after)=>runInNewContext(teamSnapshot+"\nteamSnapshotChanged(before,after)",{before,after});

test("team snapshot changes refresh approved award without a stage change",()=>{
  const before={current_stage:2,stages_completed:1,score:600};
  assert.equal(snapshotChanged(before,{...before,score:800}),true);
  assert.equal(snapshotChanged(before,{...before,score:600}),false);
});
test("team snapshot changes still detect stage progress and ignore absent teams",()=>{
  const before={current_stage:2,stages_completed:1,score:600};
  assert.equal(snapshotChanged(before,{...before,current_stage:3}),true);
  assert.equal(snapshotChanged(before,{...before,stages_completed:2}),true);
  assert.equal(snapshotChanged(null,before),false);
  assert.equal(snapshotChanged(before,null),false);
});
test("score polling defers team view refresh while user has an unsent draft",()=>{
  assert.match(html,/const previousTeam=team\?teams\.find\(t=>t\.id===team\):null/);
  assert.match(html,/const currentTeam=team\?teams\.find\(t=>t\.id===team\):null/);
  assert.match(html,/teamSnapshotChanged\(previousTeam,currentTeam\)\)\{pendingTeamStageRefresh=true/);
  assert.match(html,/team&&pendingTeamStageRefresh&&canRefreshView\(\)\)\{await teamView\(\);pendingTeamStageRefresh=false/);
});

// Metadata recovery: a lost insert response must not create a false upload failure.
const metadataHelper=html.match(/async function registerMediaMetadata\(record\)\{[^\n]*\}/)?.[0];
assert.ok(metadataHelper,"registerMediaMetadata must exist");
function verifyMetadata({insertError=null,stored=null,readError=null}={}){
  const calls=[];
  const sb={from:table=>{
    assert.equal(table,"media");
    return {
      insert:async()=>{calls.push("insert");return {error:insertError}},
      select:columns=>{assert.equal(columns,"team_id,submission_id,message_id,mime_type");calls.push("select");return {
        eq:(key,value)=>{assert.equal(key,"storage_path");assert.equal(value,"team/parent/file.mp4");return {
          maybeSingle:async()=>({data:stored,error:readError})
        }}
      }}
    };
  }};
  const record={team_id:"team",submission_id:"parent",message_id:null,mime_type:"video/mp4",storage_path:"team/parent/file.mp4"};
  return {result:runInNewContext(metadataHelper+"\nregisterMediaMetadata(record)",{sb,record}),calls};
}
test("successful media metadata insert does not require a second query",async()=>{
  const x=verifyMetadata();await x.result;assert.deepEqual(x.calls,["insert"]);
});
test("matching metadata confirms success after a lost insert response",async()=>{
  const x=verifyMetadata({insertError:new Error("network timeout"),stored:{team_id:"team",submission_id:"parent",message_id:null,mime_type:"video/mp4"}});
  await x.result;assert.deepEqual(x.calls,["insert","select"]);
});
test("missing or mismatched metadata never counts as a confirmed upload",async()=>{
  const failed=new Error("insert rejected");
  await assert.rejects(verifyMetadata({insertError:failed}).result,/insert rejected/);
  await assert.rejects(verifyMetadata({insertError:failed,stored:{team_id:"other",submission_id:"parent",message_id:null,mime_type:"video/mp4"}}).result,/insert rejected/);
  await assert.rejects(verifyMetadata({insertError:failed,readError:new Error("read failed")}).result,/insert rejected/);
});
test("failed metadata registration reports an uploaded file reference without deleting storage",()=>{
  assert.match(html,/let uploaded=false,path="";try/);
  assert.match(html,/uploaded=true;const record=/);
  assert.match(html,/Filen ble lagret, men registreringen kunne ikke bekreftes/);
  assert.match(html,/Oppgi filreferansen til HK/);
  assert.doesNotMatch(html,/\.remove\(\[path\]\)/);
});
