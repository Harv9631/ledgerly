'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  plaid: {
    getConfig: () => ipcRenderer.invoke('plaid:get-config'),
    setConfig: (serverUrl) => ipcRenderer.invoke('plaid:set-config', { serverUrl }),
    createLinkToken: () => ipcRenderer.invoke('plaid:create-link-token'),
    openLink: (token) => ipcRenderer.invoke('plaid:open-link', token),
    exchangeToken: (publicToken, metadata) => ipcRenderer.invoke('plaid:exchange-token', publicToken, metadata),
    syncAccounts: (itemId) => ipcRenderer.invoke('plaid:sync-accounts', itemId),
    syncTransactions: (itemId, reset) => ipcRenderer.invoke('plaid:sync-transactions', itemId, reset),
    getLinkedItems: () => ipcRenderer.invoke('plaid:get-linked-items'),
    removeItem: (itemId) => ipcRenderer.invoke('plaid:remove-item', itemId)
  },
  ai: {
    getConfig: () => ipcRenderer.invoke('ai:get-config'),
    setConfig: (apiKey) => ipcRenderer.invoke('ai:set-config', { apiKey }),
    getHistory: (conversationId) => ipcRenderer.invoke('ai:get-history', conversationId),
    clearHistory: (conversationId) => ipcRenderer.invoke('ai:clear-history', conversationId),
    getRateLimit: () => ipcRenderer.invoke('ai:get-rate-limit'),
    queueTransaction: (t, ctx) => ipcRenderer.invoke('ai:queue-transaction', { transaction: t, context: ctx }),
    reprocess: (opts) => ipcRenderer.invoke('ai:reprocess', opts),
    detectTrends: (payload) => ipcRenderer.invoke('ai:detect-trends', payload),
    analyzeTransaction: (payload) => ipcRenderer.invoke('ai:analyze-transaction', payload),
    getAlerts: () => ipcRenderer.invoke('ai:get-alerts'),
    debtOptimizer: (payload) => ipcRenderer.invoke('ai:debt-optimizer', payload),
    getFeatures: (txId) => ipcRenderer.invoke('ai:get-features', txId),
    deleteAllData: (opts) => ipcRenderer.invoke('ai:delete-all-data', opts),
    categorizeTransactions: (transactions) => ipcRenderer.invoke('ai:categorize-transactions', { transactions }),
    forecastCashFlow: (payload) => ipcRenderer.invoke('ai:forecast-cashflow', payload),
    detectSubscriptionsAI: (payload) => ipcRenderer.invoke('ai:detect-subscriptions', payload),
    taxSummary: (payload) => ipcRenderer.invoke('ai:categorize-taxes', payload),
    projectNetWorth: (payload) => ipcRenderer.invoke('ai:project-net-worth', payload),
    goalAdvice: (payload) => ipcRenderer.invoke('ai:advise-goals', payload),
    parseSearchQuery: (payload) => ipcRenderer.invoke('ai:parse-search-query', payload),
    budgetAdvice: (payload) => ipcRenderer.invoke('ai:advise-budget', payload),
    suggestMileage: (payload) => ipcRenderer.invoke('ai:suggest-mileage', payload),
    chat: (payload) => ipcRenderer.send('ai:chat', payload),
    onChunk: (cb) => ipcRenderer.on('ai:chat-chunk', (_e, text) => cb(text)),
    onDone: (cb) => ipcRenderer.on('ai:chat-done', (_e, data) => cb(data)),
    onError: (cb) => ipcRenderer.on('ai:chat-error', (_e, msg) => cb(msg)),
    removeListeners: () => {
      ipcRenderer.removeAllListeners('ai:chat-chunk');
      ipcRenderer.removeAllListeners('ai:chat-done');
      ipcRenderer.removeAllListeners('ai:chat-error');
    }
  }
});
