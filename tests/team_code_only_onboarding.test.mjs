import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/migrations/202611020855_disable_name_only_team_join.sql", import.meta.url), "utf8");

test("no browser flow joins or creates a team by its public name", () => {
  assert.doesNotMatch(html, /sb\.rpc\(\s*["']join_rebus_team_by_name["']/);
  assert.doesNotMatch(html, /id=["'](?:quick-team-name|join-team-name)["']/);
});

test("first-time and returning devices are offered code-based joining", () => {
  for (const view of ["authView", "joinView"]) {
    const start = html.indexOf("function " + view + "(){");
    const end = html.indexOf("function ", start + 10);
    assert.ok(start >= 0 && end > start, view + " must exist");
    assert.match(html.slice(start, end), /codeJoinForm\(\)/);
  }
  assert.match(html, /sb\.rpc\("join_rebus_team_by_code"/);
});

test("legacy name join is an invoker-only, non-mutating rejection", () => {
  assert.match(migration, /SECURITY INVOKER/);
  assert.match(migration, /RAISE EXCEPTION 'Bruk lagkode fra HK for å bli med på laget'/);
  assert.doesNotMatch(migration, /\b(?:INSERT|UPDATE|DELETE|TRUNCATE)\s+(?:INTO\s+|FROM\s+)?public\./i);
});
