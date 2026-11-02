// Skip is for mandatory main tasks only. Legacy bonuses have no special_key.
import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("function taskCard(");
const end=html.indexOf("\nfunction bindTasks(",start);
assert.ok(start>=0&&end>start,"taskCard must be present");
const context={subs:[],skips:[],esc:value=>String(value??""),mediaHtml:()=>""};
vm.createContext(context);
vm.runInContext(html.slice(start,end)+"\nglobalThis.renderTask=taskCard;",context);

function card(fields={}){
 return context.renderTask({
  id:"task-1",title:"Oppgave",points:100,description:"Beskrivelse",
  stage:1,bonus:false,special_key:null,post_finish:false,
  ...fields
 });
}

test("main tasks offer HK skip request",()=>{
 assert.match(card(),/class="secondary skip-btn"/);
 assert.match(card(),/Be om å hoppe over/);
});

test("all three legacy bonuses are optional even without special_key",()=>{
 assert.doesNotMatch(card({bonus:true,special_key:null}),/skip-btn|Be om å hoppe over/);
});

test("new special missions and finale never offer skip",()=>{
 for(const special_key of ["perfect_reconstruction","secret_mission","grand_finale"]){
  assert.doesNotMatch(card({bonus:true,special_key}),/skip-btn|Be om å hoppe over/);
 }
});

test("main-task pending skip remains disabled while HK reviews it",()=>{
 context.skips=[{task_id:"task-1",status:"pending"}];
 assert.match(card(),/Hopp over: venter/);
 assert.match(card(),/disabled/);
 context.skips=[];
});
