// HK start preflight: teams without a registered user must be visible before the competition.
// These tests check frontend behavior only, not a two-device end-to-end flow.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const adminStart = html.indexOf("async function adminView(){");
const adminEnd = html.indexOf("\nasync function review(", adminStart);
assert.ok(adminStart >= 0 && adminEnd > adminStart, "admin view must exist");
const admin = html.slice(adminStart, adminEnd);

const selection = admin.match(/const unregisteredTeams=teams\.filter\(tm=>!members\.some\(m=>m\.team_id===tm\.id\)\);/)?.[0];
assert.ok(selection, "missing-team selection must exist");
function missing(teams, members) {
  return runInNewContext(selection + "unregisteredTeams.map(t=>t.name)", {teams,members});
}

test("HK checks registered members using the existing admin-only SELECT policy", () => {
  assert.match(admin, /query\("team_members"\)/);
  assert.doesNotMatch(html.slice(0, adminStart), /query\("team_members"\)/);
});

test("three teams with only one registered user warn for the other two", () => {
  assert.deepEqual(Array.from(missing(
    [{id:"a",name:"Lag A"},{id:"b",name:"Lag B"},{id:"c",name:"Lag C"}],
    [{team_id:"b",user_id:"one"}]
  )), ["Lag A","Lag C"]);
});

test("multiple members on one team do not hide other unregistered teams", () => {
  assert.deepEqual(Array.from(missing(
    [{id:"a",name:"Lag A"},{id:"b",name:"Lag B"}],
    [{team_id:"a",user_id:"one"},{team_id:"a",user_id:"two"}]
  )), ["Lag B"]);
});

test("HK receives a ready message only when every team has a member", () => {
  assert.deepEqual(Array.from(missing(
    [{id:"a",name:"Lag A"},{id:"b",name:"Lag B"}],
    [{team_id:"a"},{team_id:"b"}]
  )), []);
  assert.match(admin, /Alle lag har minst én registrert bruker/);
  assert.match(admin, /lag mangler registrert bruker/);
});

test("preflight warning escapes displayed team names and does not expose member identities", () => {
  assert.match(admin, /unregisteredTeams\.map\(tm=>esc\(tm\.name\)\)/);
  assert.doesNotMatch(admin, /unregisteredTeams\.map\(tm=>esc\(tm\.user_id\)\)/);
  assert.match(admin, /Del lagkode privat/);
});
