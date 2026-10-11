(() => {
  const provider = __PROVIDER__;
  const action = __ACTION__;
  const prompt = __PROMPT__;
  const hosts = {chatgpt:'chatgpt.com',gemini:'gemini.google.com',claude:'claude.ai'};
  if (location.hostname !== hosts[provider]) return JSON.stringify({error:'Open the provider chat page and sign in first.'});
  const visible = e => !!e && e.getClientRects().length > 0;
  const first = selectors => selectors.flatMap(s => Array.from(document.querySelectorAll(s))).find(visible);
  const editors = {
    chatgpt:['#prompt-textarea','textarea[data-id="root"]'],
    gemini:['rich-textarea [contenteditable="true"]','[contenteditable="true"][role="textbox"]'],
    claude:['[contenteditable="true"].ProseMirror','[contenteditable="true"][role="textbox"]']
  };
  const buttons = {
    chatgpt:['button[data-testid="send-button"]','button[aria-label="Send prompt"]'],
    gemini:['button.send-button','button[aria-label="Send message"]'],
    claude:['button[aria-label="Send message"]','button[aria-label="Send Message"]']
  };
  const responses = {
    chatgpt:['[data-message-author-role="assistant"]'],
    gemini:['model-response .markdown','model-response'],
    claude:['[data-is-streaming] .font-claude-response','.font-claude-response']
  };
  const read = () => {
    for (const selector of responses[provider]) {
      const nodes = Array.from(document.querySelectorAll(selector)).filter(visible);
      if (nodes.length) return {text:nodes[nodes.length-1].innerText,count:nodes.length};
    }
    return {text:'',count:0};
  };
  if (action === 'read') return JSON.stringify(read());
  const editor = first(editors[provider]);
  if (!editor) return JSON.stringify({error:'Prompt box not found. Sign in, open a chat, and check the site layout.'});
  const busy = first(['button[data-testid="stop-button"]','button[aria-label="Stop response"]','button[aria-label="Stop generating"]']);
  if (busy) return JSON.stringify({error:'This AI is still generating. Wait before sending again.'});
  const existing = editor.tagName === 'TEXTAREA' ? editor.value : editor.innerText;
  if (existing.trim()) return JSON.stringify({error:'The browser prompt box already contains a draft. Clear it first.'});
  if (action === 'prepare') {
    const before = read();
    editor.focus();
    if (editor.tagName === 'TEXTAREA') {
      Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(editor,prompt);
      editor.dispatchEvent(new Event('input',{bubbles:true}));
    } else {
      const selection = window.getSelection();
      const range = document.createRange(); range.selectNodeContents(editor);
      selection.removeAllRanges(); selection.addRange(range);
      if (!document.execCommand('insertText',false,prompt)) return JSON.stringify({error:'Unable to fill editor. Paste your prompt in Chrome.'});
    }
    return JSON.stringify({prepared:true,before});
  }
  return JSON.stringify({error:'Unsupported action'});
})()
