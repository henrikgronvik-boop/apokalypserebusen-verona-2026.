import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";

const html=readFileSync(new URL("../index.html",import.meta.url),"utf8");
const start=html.indexOf("function mediaHtml(");
const end=html.indexOf("const MEDIA_EXTENSIONS=",start);
assert.ok(start>=0&&end>start,"mediaHtml must exist in the static app");
const source=html.slice(start,end);

function render(rows,id="submission-1",kind="submission_id"){
 const context={
  media:rows,
  esc:value=>String(value??"").replace(/[&<>"]/g,c=>({
   "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"
  }[c]))
 };
 vm.createContext(context);
 vm.runInContext(source+"\nglobalThis.render=mediaHtml;",context);
 return context.render(id,kind);
}

const evidence=(url,mime_type="image/jpeg")=>({
 id:"media-1",team_id:"team-1",submission_id:"submission-1",message_id:null,
 storage_path:"team-1/submission-1/private-secret.jpg",mime_type,url
});

test("registered evidence remains visible when signing a private URL fails",()=>{
 const output=render([evidence(null)]);
 assert.match(output,/Beviset er registrert/);
 assert.match(output,/Prøv «Oppdater»/);
 assert.match(output,/role="status"/);
 assert.doesNotMatch(output,/private-secret|storage_path|src=|<img|<video/);
});

test("a signed image still renders without a warning",()=>{
 const output=render([evidence("https://signed.example/image?token=a&x=b")]);
 assert.match(output,/<img/);
 assert.match(output,/alt="Innsendt bilde"/);
 assert.match(output,/token=a&amp;x=b/);
 assert.doesNotMatch(output,/Beviset er registrert/);
});

test("a signed video remains playable",()=>{
 const output=render([evidence("https://signed.example/movie", "video/mp4")]);
 assert.match(output,/<video/);
 assert.match(output,/controls preload="metadata"/);
 assert.doesNotMatch(output,/Beviset er registrert/);
});

test("one broken attachment does not hide another successful attachment",()=>{
 const output=render([evidence(null),{...evidence("https://signed.example/ok"),id:"media-2"}]);
 assert.match(output,/Beviset er registrert/);
 assert.match(output,/<img/);
});

test("unrelated media never appears in a submission or chat message",()=>{
 const output=render([{...evidence(null),submission_id:"other-submission"}]);
 assert.equal(output,"");
 const chat=render([{...evidence(null),submission_id:null,message_id:"message-1"}],"message-1","message_id");
 assert.match(chat,/Beviset er registrert/);
});

test("signed URL attributes are escaped rather than inserted as HTML",()=>{
 const output=render([evidence('https://signed.example/" onerror="alert(1)')]);
 assert.match(output,/&quot; onerror=&quot;/);
 assert.doesNotMatch(output,/src="https:\/\/signed.example\/" onerror="/);
});
