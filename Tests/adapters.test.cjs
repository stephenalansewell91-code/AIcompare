const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const adapter = fs.readFileSync(__dirname+'/../Sources/adapter.js','utf8');
const send = fs.readFileSync(__dirname+'/../Sources/send.js','utf8');
function run(source, provider, action, prompt, elements={}, host) {
 const context = {
  location:{hostname:host || {chatgpt:'chatgpt.com',gemini:'gemini.google.com',claude:'claude.ai'}[provider]},
  document:{querySelectorAll:s=>elements[s]||[],createRange:()=>({selectNodeContents(){}}),execCommand:()=>true},
  window:{getSelection:()=>({removeAllRanges(){},addRange(){}})},
  HTMLTextAreaElement:class {}, Event:class {}
 };
 Object.defineProperty(context.HTMLTextAreaElement.prototype,'value',{set(v){this.value=v;}});
 const js = source.replaceAll('__PROVIDER__',JSON.stringify(provider)).replaceAll('__ACTION__',JSON.stringify(action)).replaceAll('__PROMPT__',JSON.stringify(prompt));
 return JSON.parse(vm.runInNewContext(js,context));
}
const el = (extras={})=>({getClientRects:()=>[{}],innerText:'',focus(){},dispatchEvent(){},...extras});
for(const p of ['chatgpt','gemini','claude']) {
 assert.match(run(adapter,p,'read','',{},'accounts.google.com').error,/Sign in|sign in/);
 assert.match(run(adapter,p,'prepare','test').error,/Prompt box/);
 assert.match(run(send,p,'send','').error,/Send button/);
}
const draft = el({tagName:'TEXTAREA',value:'my unsent draft'});
assert.match(run(adapter,'chatgpt','prepare','new',{'#prompt-textarea':[draft]}).error,/draft/);
assert.equal(draft.value,'my unsent draft');
const editor = el({tagName:'TEXTAREA',value:''});
const multiline = '"quoted"\nline two\n__ACTION__ \\ $()`';
assert.equal(run(adapter,'chatgpt','prepare',multiline,{'#prompt-textarea':[editor]}).prepared,true);
assert.equal(editor.value,multiline);
assert.match(run(adapter,'chatgpt','prepare','new',{'#prompt-textarea':[el({tagName:'TEXTAREA',value:''})],'button[data-testid="stop-button"]':[el()]}).error,/generating/);
assert.deepEqual(run(adapter,'chatgpt','read','',{'[data-message-author-role="assistant"]':[el({innerText:'first'}),el({innerText:'second'})]}),{text:'second',count:2});
let clicked=0;
const button=el({disabled:false,getAttribute:()=>null,click(){clicked++;}});
assert.equal(run(send,'chatgpt','send','',{'button[data-testid="send-button"]':[button]}).sent,true);
assert.equal(clicked,1);
button.disabled=true;
assert.ok(run(send,'chatgpt','send','',{'button[data-testid="send-button"]':[button]}).error);
assert.equal(clicked,1);
console.log('Adapter checks passed: host restrictions, missing controls, protected drafts, busy state, multiline prompt, latest reply, enabled/disabled send.');
