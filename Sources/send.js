(() => {
 const provider = __PROVIDER__;
 const hosts = {chatgpt:'chatgpt.com',gemini:'gemini.google.com',claude:'claude.ai'};
 if(location.hostname!==hosts[provider]) return JSON.stringify({error:'Chat page changed. Nothing sent.'});
 const selectors = {chatgpt:['button[data-testid="send-button"]','button[aria-label="Send prompt"]'],gemini:['button.send-button','button[aria-label="Send message"]'],claude:['button[aria-label="Send message"]','button[aria-label="Send Message"]']};
 const button = selectors[provider].flatMap(s=>Array.from(document.querySelectorAll(s))).find(e=>e.getClientRects().length && !e.disabled && e.getAttribute('aria-disabled')!=='true');
 if(!button) return JSON.stringify({error:'Send button unavailable. The prompt is filled in Chrome; send it there manually.'});
 button.click(); return JSON.stringify({sent:true});
})()
