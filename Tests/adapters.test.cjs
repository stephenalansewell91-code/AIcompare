const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/../Sources/adapter.js','utf8');
const el=(extra={})=>({getClientRects:()=>[{}],innerText:'',focus(){},dispatchEvent(){},...extra});
function fixture(provider='chatgpt',host) {
 const editor=el({tagName:'TEXTAREA',value:''}); let clicked=0;
 const button=el({disabled:false,getAttribute:()=>null,click(){clicked++;}});
 const elements={'#prompt-textarea':[editor],'textarea[role="textbox"]':[editor],'button[data-testid="send-button"]':[button],'button.send-button':[button],'button[aria-label="Send message"]':[button]};
 const context={provider,action:'prepare',prompt:'Hello\n"world" ✓',token:'one',location:{hostname:host||{chatgpt:'chatgpt.com',gemini:'gemini.google.com',claude:'claude.ai'}[provider]},window:{},document:{querySelectorAll:s=>elements[s]||[]},HTMLTextAreaElement:class{},Event:class{}};
 Object.defineProperty(context.HTMLTextAreaElement.prototype,'value',{set(v){this.value=v;}});
 const ctx=vm.createContext(context);
 return {editor,button,elements,context,clicks:()=>clicked,run(action){context.action=action;return vm.runInContext('(function(){'+source+'})()',ctx);}};
}
for(const provider of ['chatgpt','gemini','claude']){
 const f=fixture(provider);assert.equal(f.run('prepare').prepared,true);assert.equal(f.editor.value,f.context.prompt);
 assert.equal(f.run('send').sent,true);assert.equal(f.clicks(),1);assert.ok(f.run('send').error);assert.equal(f.clicks(),1);
 assert.ok(fixture(provider,'accounts.google.com').run('prepare').error);
}
let f=fixture();f.editor.value='Existing draft';assert.match(f.run('prepare').error,/draft/);assert.equal(f.editor.value,'Existing draft');
f=fixture();f.run('prepare');f.editor.value='Edited after filling';assert.match(f.run('send').error,/draft changed/);assert.equal(f.clicks(),0);
f=fixture();f.run('prepare');f.button.disabled=true;assert.equal(f.run('send').waiting,true);assert.equal(f.clicks(),0);f.button.disabled=false;assert.equal(f.run('send').sent,true);
f=fixture();f.elements['button[data-testid="stop-button"]']=[el()];assert.match(f.run('prepare').error,/generating/);
console.log('Passed: three providers, literal multiline input, host guard, draft preservation, changed-draft protection, delayed send button, busy detection, exactly-once submission.');
