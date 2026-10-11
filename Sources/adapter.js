// Function body for WKWebView.callAsyncJavaScript. Arguments arrive as values.
const hosts = {chatgpt:'chatgpt.com', gemini:'gemini.google.com', claude:'claude.ai'};
if (location.hostname !== hosts[provider]) return {error:'Finish signing in and open a chat in this panel first.'};
const visible = e => !!e && e.getClientRects().length > 0;
const first = selectors => selectors.flatMap(s => Array.from(document.querySelectorAll(s))).find(visible);
const editors = {
 chatgpt:['#prompt-textarea','textarea[data-id="root"]'],
 gemini:['rich-textarea [contenteditable="true"]','[contenteditable="true"][role="textbox"]','textarea[role="textbox"]'],
 claude:['[contenteditable="true"].ProseMirror','[contenteditable="true"][role="textbox"]','textarea[role="textbox"]']
};
const sends = {
 chatgpt:['button[data-testid="send-button"]','button[aria-label="Send prompt"]'],
 gemini:['button.send-button','button[aria-label="Send message"]'],
 claude:['button[aria-label="Send message"]','button[aria-label="Send Message"]']
};
const editor = first(editors[provider] || []);
if (!editor) return {error:'Prompt box not found. Sign in and open a chat in this panel. You can also type directly in the website.'};
const value = () => editor.tagName === 'TEXTAREA' ? editor.value : editor.innerText;
const busy = first(['button[data-testid="stop-button"]','button[aria-label="Stop response"]','button[aria-label="Stop generating"]','button.stop-button']);
if (busy) return {error:'This AI is still generating. Wait or stop its response in the panel.'};
if (action === 'prepare') {
 if (value().trim()) return {error:'This panel already contains an unsent draft. Clear it before using the shared prompt.'};
 editor.focus();
 if (editor.tagName === 'TEXTAREA') {
  Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(editor, prompt);
  editor.dispatchEvent(new Event('input', {bubbles:true}));
  editor.dispatchEvent(new Event('change', {bubbles:true}));
 } else {
  const selection=window.getSelection(); const range=document.createRange();
  range.selectNodeContents(editor); selection.removeAllRanges(); selection.addRange(range);
  if (!document.execCommand('insertText',false,prompt)) return {error:'Could not fill the prompt box. Paste directly into this panel.'};
 }
 window.__AIComparePending = {token, prompt};
 return {prepared:true};
}
if (action === 'send') {
 const pending=window.__AIComparePending;
 if (!pending || pending.token !== token || pending.prompt !== prompt) return {error:'The page changed before sending. Check this panel before retrying.'};
 if (value().trim() !== prompt.trim()) return {error:'The draft changed before sending. Check this panel before retrying.'};
 const button = sends[provider].flatMap(s=>Array.from(document.querySelectorAll(s))).find(e=>visible(e) && !e.disabled && e.getAttribute('aria-disabled')!=='true');
 if (!button) return {waiting:true};
 // Invalidate before clicking: retries can never click twice for this dispatch.
 delete window.__AIComparePending;
 button.click(); return {sent:true};
}
return {error:'Unsupported action'};
