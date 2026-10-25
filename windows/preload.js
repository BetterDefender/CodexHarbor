const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('harbor', {
  info: () => ipcRenderer.invoke('app:info'),
  setLanguage: (language) => ipcRenderer.invoke('ui:language', language),
  list: (api) => ipcRenderer.invoke('core:list', api),
  switchAccount: (key) => ipcRenderer.invoke('core:switch', key),
  remove: (key) => ipcRenderer.invoke('core:remove', key),
  alias: (key, value) => ipcRenderer.invoke('core:alias', key, value),
  importFile: (file) => ipcRenderer.invoke('core:import', file),
  saveCurrent: () => ipcRenderer.invoke('core:saveCurrent'),
  syncCurrent: () => ipcRenderer.invoke('core:syncCurrent'),
  openCodex: () => ipcRenderer.invoke('core:openCodex'),
  pickImport: () => ipcRenderer.invoke('dialog:import')
});
