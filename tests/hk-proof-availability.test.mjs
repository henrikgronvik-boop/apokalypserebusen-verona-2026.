// HK must distinguish a missing proof from a registered file whose signed URL failed.
import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("function submissionProofState(");
const end=html.indexOf("\nfunction mediaHtml(",start);
assert.ok(start>=0&&end>start,"submissionProofState helper must exist");
const context={media:[]};
vm.createContext(context);
vm.runInContext(html.slice(start,end)+"\nglobalThis.getProofState=submissionProofState;",context);
const state=id=>({...context.getProofState(id)});

test("missing proof is distinguished from a signed-URL outage",()=>{
 assert.deepEqual(state("s1"),{registered:false,viewable:false});
 context.media=[{submission_id:"s1",url:null}];
 assert.deepEqual(state("s1"),{registered:true,viewable:false});
});

test("available proof enables review regardless of other unavailable attachments",()=>{
 context.media=[
  {submission_id:"s1",url:null},
  {submission_id:"s1",url:"https://example.invalid/signed"},
  {submission_id:"s2",url:null}
 ];
 assert.deepEqual(state("s1"),{registered:true,viewable:true});
 assert.deepEqual(state("s2"),{registered:true,viewable:false});
 assert.deepEqual(state("s3"),{registered:false,viewable:false});
});

test("HK review continues to require viewable proof",()=>{
 assert.match(html,/viewable:hasProof}=submissionProofState\(s\.id\)/);
 assert.match(html,/hasProof\?'':'<p class="alert">/);
 assert.match(html,/hasProof\?'':'disabled title="Mangler tilgjengelig bevis"/);
});

test("HK receives different recovery guidance for missing versus unavailable proof",()=>{
 assert.match(html,/hasRegisteredProof\?'Vedlegget er registrert, men kan ikke åpnes nå/);
 assert.match(html,/Ingen bilde- eller videobevis er registrert/);
 assert.match(html,/Ikke be laget laste opp samme fil på nytt/);
});
