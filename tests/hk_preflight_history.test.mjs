// HK preflight regression: old progress and reviewed submissions survive a new start.
// Frontend-only tests. They do not modify production scores, history, or stages.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const start = html.indexOf("async function adminView(){");
const end = html.indexOf("\nasync function review(", start);
assert.ok(start >= 0 && end > start, "HK control room must exist");
const admin = html.slice(start, end);

const progressSelector = admin.match(/const progressedTeams=teams\.filter\(tm=>tm\.stages_completed>0\|\|tm\.current_stage!==tm\.start_stage\);/)?.[0];
const reviewSelector = admin.match(/const reviewedSubmissions=subs\.filter\(s=>s\.status!=="pending"\);/)?.[0];
assert.ok(progressSelector, "progress selector must exist");
assert.ok(reviewSelector, "reviewed submission selector must exist");

const progressed = teams => Array.from(runInNewContext(progressSelector + "progressedTeams.map(t=>t.name)", { teams }));
const reviewed = subs => Array.from(runInNewContext(reviewSelector + "reviewedSubmissions.map(s=>s.id)", { subs }));

test("HK warns for teams that completed stages even if their score is zero", () => {
  assert.deepEqual(progressed([
    { name:"Started", start_stage:1, current_stage:1, stages_completed:0, score:0 },
    { name:"Progressed", start_stage:1, current_stage:2, stages_completed:1, score:0 },
    { name:"Finished", start_stage:3, current_stage:3, stages_completed:5, score:0 }
  ]), ["Progressed","Finished"]);
});

test("HK detects changed current stage even if completion counter is stale", () => {
  assert.deepEqual(progressed([
    { name:"Moved", start_stage:2, current_stage:4, stages_completed:0 },
    { name:"Untouched", start_stage:4, current_stage:4, stages_completed:0 }
  ]), ["Moved"]);
});

test("HK counts reviewed history but not already separately warned pending work", () => {
  assert.deepEqual(reviewed([
    {id:"a",status:"approved"},
    {id:"b",status:"rejected"},
    {id:"c",status:"pending"}
  ]), ["a","b"]);
});

test("HK escapes team names and explains old data is retained", () => {
  assert.match(admin, /progressedTeams\.map\(tm=>esc\(tm\.name\)\)/);
  assert.match(admin, /Delprogresjonen beholdes og nullstilles ikke automatisk/);
  assert.match(admin, /tidligere godkjente eller avviste innsendinger/);
  assert.match(admin, /De slettes ikke automatisk/);
});

test("preflight never resets score, stage, or submissions", () => {
  assert.doesNotMatch(admin, /from\("teams"\)\.update\(\{score:0/);
  assert.doesNotMatch(admin, /from\("submissions"\)\.delete\(/);
  assert.doesNotMatch(admin, /from\("stage_unlocks"\)\.delete\(/);
});
