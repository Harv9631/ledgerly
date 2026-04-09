'use strict';

const { ipcRenderer, contextBridge } = require('electron');

// Intercept Plaid Link completion messages regardless of which page is loaded.
// When link.html is loaded as the top-level page (not in an iframe), its internal frames
// call window.parent.postMessage(...) which, since window.parent === window, fires a
// message event on window. The preload captures this and forwards via IPC.
window.addEventListener('message', function(event) {
  var data = event.data;
  if (!data || typeof data !== 'object') return;
  var action = data.action || '';
  var publicToken = data.public_token ||
    (data.payload && data.payload.public_token) ||
    (data.metadata && data.metadata.public_token);
  if ((action === 'plaidlink:handoff' || action === 'plaidlink:success' ||
       (publicToken && action.indexOf('exit') === -1 && action.indexOf('close') === -1)) && publicToken) {
    ipcRenderer.send('plaid:result', { success: true, public_token: publicToken, metadata: data.metadata || data.payload || {} });
  } else if (action === 'plaidlink:exit' || action === 'plaidlink:close') {
    ipcRenderer.send('plaid:result', { success: false });
  }
}, false);

// Expose bridge for plaid-link.html to call explicitly
contextBridge.exposeInMainWorld('plaidBridge', {
  sendResult: (result) => ipcRenderer.send('plaid:result', result)
});
