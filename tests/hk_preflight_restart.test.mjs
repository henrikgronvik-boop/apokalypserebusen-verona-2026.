// HK preflight: don't mistake a reused competition for a clean start.
// Frontend regression tests only; no database writes or user impersonation.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const start = html.indexOf("async function adminView(){");
const end = html.indexOf("\nasync function review(", start);
assert.ok(start >= 0 && end > start, "HK control room must exist");
const admin = html.slice(start, end);

const releaseSelection = admin.match(/const releasedSpecials=tasks\.filter\(t=>t\.requires_release&&t\.released_at\);/)?.[0];
assert.ok(releaseSelection, "released-special selection must exist");
const released = tasks => Array.from(runInNewContext(
  releaseSelection + "releasedSpecials.map(t=>t.title)",
  { tasks }
));

test("HK warns only for specials already released by HK", () => {
  assert.deepEqual(released([
    {title:"Hemmelig oppdrag",requires_release:true,released_at:"2026-11-02T10:00:00Z"},
    {title:"Den store finalen",requires_release:true,released_at:null},
    {title:"Musikkvideo",requires_release:false,released_at:"2026-11-02T10:00:00Z"}
  ]), ["Hemmelig oppdrag"]);
});

test("HK warns if any pending submission or skip request remains", () => {
  assert.match(admin, /pending\.length\|\|skipPending\.length\?/);
  assert.match(admin, /innsendinger og/);
  assert.match(admin, /forespørsler om å hoppe over venter på HK/);
  assert.match(admin, /Behandle disse før dere bruker konkurransen på nytt/);
});

test("HK warns that released missions and deadlines survive a restart", () => {
  assert.match(admin, /releasedSpecials\.length\?/);
  assert.match(admin, /Frigivelsen og tidsfristen gjelder fortsatt/);
  assert.match(admin, /releasedSpecials\.map\(t=>esc\(t\.title\)\)/);
});

test("new preflight does not auto-reset scores, stages, or releases", () => {
  assert.match(admin, /Dette nullstilles ikke automatisk/);
  assert.doesNotMatch(admin, /from\("teams"\)\.update\(\{score:0/);
  assert.doesNotMatch(admin, /from\("tasks"\)\.update\(\{released_at:null/);
});
