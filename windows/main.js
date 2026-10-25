const { app, BrowserWindow, Menu, Tray, dialog, ipcMain } = require('electron');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const { execFile, execFileSync } = require('node:child_process');

const isDemo = process.argv.includes('--demo');
let mainWindow;
let tray = null;
let isQuitting = false;
let closeDialogOpen = false;
let uiLanguage = 'en';
let proxyCache = { at: 0, env: {} };

const nativeCopy = {
  en: {
    open: 'Open Codex Harbor',
    quit: 'Quit',
    closeTitle: 'Close Codex Harbor',
    closeMessage: 'Minimize to the system tray or quit?',
    closeDetail: 'Minimize keeps Codex Harbor running in the system tray.',
    minimize: 'Minimize to tray',
    cancel: 'Cancel',
    balloon: 'Still running in the system tray',
    importTitle: 'Import Codex credentials'
  },
  zh: {
    open: '打开 Codex Harbor',
    quit: '退出',
    closeTitle: '关闭 Codex Harbor',
    closeMessage: '最小化到托盘，还是退出？',
    closeDetail: '最小化后，Codex Harbor 会继续在系统托盘运行。',
    minimize: '最小化到托盘',
    cancel: '取消',
    balloon: '仍在系统托盘中运行',
    importTitle: '导入 Codex 凭据'
  }
};

function nativeText(key) {
  return (nativeCopy[uiLanguage] || nativeCopy.en)[key];
}

app.setName('Codex Harbor');
app.setAppUserModelId('com.gh0stx.codexharbor');

function corePath() {
  const windowsCore = process.arch === 'arm64' ? 'harbor-core-arm64.exe' : 'harbor-core-x64.exe';
  if (process.platform === 'win32') return path.join(__dirname, 'core', windowsCore);
  const local = path.join(__dirname, '..', 'Vendor', 'core', 'bin', 'harbor-core');
  if (fs.existsSync(local)) return local;
  return path.join(__dirname, 'core', windowsCore);
}

function codexHome() {
  if (process.env.CODEX_HOME) return process.env.CODEX_HOME;
  if (process.platform === 'win32') return path.join(process.env.USERPROFILE || os.homedir(), '.codex');
  return path.join(process.env.HOME || os.homedir(), '.codex');
}

function codexConfigInfo() {
  const home = codexHome();
  let wsl = false;
  let authMode = 'unknown';
  try {
    const config = fs.readFileSync(path.join(home, 'config.toml'), 'utf8');
    wsl = /runCodexInWindowsSubsystemForLinux\s*=\s*true/i.test(config);
    const match = config.match(/cli_auth_credentials_store\s*=\s*"([^"]+)"/i);
    if (match) authMode = match[1].toLowerCase();
  } catch {
    // No readable config; leave the defaults.
  }
  if (fs.existsSync(path.join(home, 'secrets', 'codex_auth.age'))) authMode = 'encrypted';
  return { home, wsl, authMode };
}

function windowsProxyEnv() {
  if (process.platform !== 'win32') return {};
  if (Date.now() - proxyCache.at < 30000) return proxyCache.env;
  const env = {};
  try {
    const out = execFileSync('reg', ['query', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'], {
      encoding: 'latin1',
      windowsHide: true
    });
    const enabled = /ProxyEnable\s+REG_DWORD\s+0x1\b/i.test(out);
    const server = out.match(/ProxyServer\s+REG_SZ\s+(.+)/i)?.[1]?.trim();
    if (enabled && server) {
      let http = server;
      let https = server;
      if (server.includes('=')) {
        const parts = Object.fromEntries(server.split(';').map((part) => part.split('=')));
        http = parts.http || parts.https || server;
        https = parts.https || parts.http || server;
      }
      const url = (value) => /^(https?|socks5h?):\/\//i.test(value) ? value : `http://${value}`;
      env.HTTP_PROXY = env.http_proxy = url(http);
      env.HTTPS_PROXY = env.https_proxy = url(https);
      env.ALL_PROXY = env.all_proxy = url(https);
    }
  } catch {
    // No system proxy or registry access unavailable.
  }
  proxyCache = { at: Date.now(), env };
  return env;
}

function coreEnv() {
  const env = { ...process.env, ...windowsProxyEnv(), CODEX_HOME: codexHome() };
  if (process.platform === 'win32') {
    const system32 = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32');
    env.PATH = `${system32};${env.PATH || ''}`;
  }
  return env;
}

function codexProcesses() {
  if (process.platform !== 'win32') return Promise.resolve([]);
  const script = "$names = @('ChatGPT','Codex','codex'); @(Get-Process -Name $names -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique)";
  return new Promise((resolve) => {
    execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], {
      windowsHide: true,
      timeout: 15000,
      maxBuffer: 1024 * 1024
    }, (error, stdout) => {
      if (error) {
        resolve(['process_check_failed']);
        return;
      }
      resolve(String(stdout || '').split(/\r?\n/).map((line) => line.trim()).filter(Boolean));
    });
  });
}

function authAccountId(auth) {
  const tokens = auth?.tokens || {};
  let accountId = tokens.account_id;
  if (!accountId && typeof tokens.id_token === 'string') {
    try {
      const payload = JSON.parse(Buffer.from(tokens.id_token.split('.')[1], 'base64url').toString('utf8'));
      accountId = payload['https://api.openai.com/auth']?.chatgpt_account_id;
    } catch {
      // Fall through to a core import if the JWT is unreadable.
    }
  }
  return accountId;
}

function snapshotFileName(accountKey) {
  const safe = /^[A-Za-z0-9._-]+$/.test(accountKey) && accountKey !== '.' && accountKey !== '..';
  return `${safe ? accountKey : Buffer.from(accountKey, 'utf8').toString('base64url')}.auth.json`;
}

function syncCurrentSnapshot() {
  const home = codexHome();
  const authPath = path.join(home, 'auth.json');
  if (!fs.existsSync(authPath)) return { ok: false, error: 'auth.json was not found. Sign in with Codex first.' };
  try {
    const registry = JSON.parse(fs.readFileSync(path.join(home, 'accounts', 'registry.json'), 'utf8'));
    const activeKey = registry.active_account_key;
    const accounts = Array.isArray(registry.accounts) ? registry.accounts : [];
    const active = accounts.find((account) => account.account_key === activeKey);
    if (!active || !active.chatgpt_account_id) {
      return { ok: false, error: 'No matching active account snapshot.' };
    }
    const auth = JSON.parse(fs.readFileSync(authPath, 'utf8'));
    if (authAccountId(auth) !== active.chatgpt_account_id) {
      return { ok: false, error: 'account_mismatch' };
    }
    const snapshotPath = path.join(home, 'accounts', snapshotFileName(activeKey));
    if (!fs.existsSync(snapshotPath)) return { ok: false, error: 'snapshot_missing' };
    fs.copyFileSync(authPath, snapshotPath);
    return { ok: true, path: snapshotPath };
  } catch (error) {
    return { ok: false, error: error.message || 'snapshot_sync_failed' };
  }
}

async function syncCurrentAuth() {
  const authPath = path.join(codexHome(), 'auth.json');
  if (!fs.existsSync(authPath)) {
    return { ok: false, error: 'auth.json was not found. Sign in with Codex first.' };
  }
  const snapshot = syncCurrentSnapshot();
  if (snapshot.ok || !['account_mismatch', 'No matching active account snapshot.', 'snapshot_missing'].includes(snapshot.error)) {
    return snapshot;
  }
  return runCore(['import', authPath], { json: false, timeout: 180000 });
}

function runCore(args, { json = true, timeout = 120000 } = {}) {
  return new Promise((resolve) => {
    const file = corePath();
    if (!fs.existsSync(file)) {
      resolve({ ok: false, error: 'The account core is missing. Reinstall Codex Harbor.' });
      return;
    }
    execFile(file, args, {
      env: coreEnv(),
      timeout,
      maxBuffer: 32 * 1024 * 1024,
      windowsHide: true
    }, (error, stdout, stderr) => {
      const output = String(stdout || '').trim();
      const diagnostics = String(stderr || '').trim();
      const exitCode = typeof error?.code === 'number' ? error.code : (error ? 1 : 0);
      if (!json) {
        resolve({
          ok: !error,
          exitCode,
          output,
          diagnostics,
          error: error ? (diagnostics || error.message) : undefined
        });
        return;
      }
      if (!output) {
        resolve({
          ok: false,
          exitCode,
          output,
          diagnostics,
          error: error ? (diagnostics || error.message) : 'The account core returned no result.'
        });
        return;
      }
      try {
        const data = JSON.parse(output);
        if (data && data.error) {
          resolve({ ok: false, exitCode, data, output, diagnostics, error: data.error.code || 'core_error' });
          return;
        }
        resolve({ ok: !error, exitCode, data, output, diagnostics });
      } catch {
        resolve({
          ok: false,
          exitCode,
          output,
          diagnostics,
          error: error ? (diagnostics || error.message) : 'The account core returned invalid JSON.'
        });
      }
    });
  });
}

function showWindow() {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
}

function trayMenuTemplate() {
  return [
    { label: nativeText('open'), click: showWindow },
    { type: 'separator' },
    { label: nativeText('quit'), click: () => { isQuitting = true; app.quit(); } }
  ];
}

function refreshTrayMenu() {
  if (tray) tray.setContextMenu(Menu.buildFromTemplate(trayMenuTemplate()));
}

function createTray() {
  if (tray) return;
  const icon = path.join(__dirname, 'assets', process.platform === 'win32' ? 'icon.ico' : 'icon.png');
  if (!fs.existsSync(icon)) return;
  try {
    tray = new Tray(icon);
  } catch {
    tray = null;
    return;
  }
  tray.setToolTip('Codex Harbor');
  refreshTrayMenu();
  tray.on('click', showWindow);
  tray.on('double-click', showWindow);
}

function createWindow() {
  const icon = path.join(__dirname, 'assets', process.platform === 'win32' ? 'icon.ico' : 'icon.png');
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 1040,
    minHeight: 720,
    title: 'Codex Harbor',
    backgroundColor: '#0e1012',
    autoHideMenuBar: true,
    icon: fs.existsSync(icon) ? icon : undefined,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });
  Menu.setApplicationMenu(null);
  mainWindow.on('close', (event) => {
    if (isQuitting || process.platform !== 'win32') return;
    event.preventDefault();
    if (closeDialogOpen) return;
    closeDialogOpen = true;
    dialog.showMessageBox(mainWindow, {
      type: 'question',
      buttons: [nativeText('minimize'), nativeText('quit'), nativeText('cancel')],
      defaultId: 0,
      cancelId: 2,
      noLink: true,
      title: nativeText('closeTitle'),
      message: nativeText('closeMessage'),
      detail: nativeText('closeDetail')
    }).then(({ response }) => {
      closeDialogOpen = false;
      if (response === 0) {
        mainWindow.hide();
        if (process.platform === 'win32' && typeof tray?.displayBalloon === 'function') {
          tray.displayBalloon({
            title: 'Codex Harbor',
            content: nativeText('balloon'),
            iconType: 'info'
          });
        }
      } else if (response === 1) {
        isQuitting = true;
        app.quit();
      }
    }).catch(() => {
      closeDialogOpen = false;
    });
  });
  createTray();
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'), {
    query: { demo: isDemo ? '1' : '0' }
  });
}

ipcMain.handle('core:list', (_event, api) => runCore(['list', api ? '--api' : '--skip-api', '--json']));
ipcMain.handle('core:switch', async (_event, key) => {
  const running = await codexProcesses();
  if (running.length) {
    return { ok: false, error: 'client_running', detail: running.join(', ') };
  }
  const sync = await syncCurrentAuth();
  const args = ['switch', key, '--json'];
  if (process.platform !== 'win32') args.push('--restart-daemon');
  const result = await runCore(args, { timeout: 120000 });
  const syncWarning = !sync.ok && fs.existsSync(path.join(codexHome(), 'auth.json'))
    ? (sync.error || 'sync_failed')
    : null;
  return { ...result, syncWarning };
});
ipcMain.handle('core:remove', (_event, key) => runCore(['remove', key, '--json'], { timeout: 120000 }));
ipcMain.handle('core:alias', (_event, key, value) => value
  ? runCore(['alias', 'set', key, value], { json: false })
  : runCore(['alias', 'clear', key], { json: false }));

ipcMain.handle('core:import', (_event, file) => runCore(['import', file], { json: false, timeout: 180000 }));

ipcMain.handle('core:saveCurrent', syncCurrentAuth);
ipcMain.handle('core:syncCurrent', syncCurrentAuth);

ipcMain.handle('core:openCodex', () => runCore(['app', '--id', 'OpenAI.Codex', '--codex-home', codexHome()], { json: false, timeout: 180000 }));

ipcMain.handle('dialog:import', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: nativeText('importTitle'),
    properties: ['openFile', 'openDirectory']
  });
  return result.canceled ? null : result.filePaths[0];
});

ipcMain.handle('ui:language', (_event, language) => {
  uiLanguage = language === 'zh' ? 'zh' : 'en';
  refreshTrayMenu();
  return true;
});

ipcMain.handle('app:info', () => {
  const config = codexConfigInfo();
  return {
    name: app.getName(),
    version: app.getVersion(),
    demo: isDemo,
    platform: process.platform,
    codexHome: config.home,
    wsl: config.wsl,
    authMode: config.authMode
  };
});

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', showWindow);
  app.whenReady().then(() => {
    uiLanguage = (app.getLocale() || '').toLowerCase().startsWith('zh') ? 'zh' : 'en';
    createWindow();
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });
}

app.on('before-quit', () => {
  isQuitting = true;
  if (tray) {
    tray.destroy();
    tray = null;
  }
});

app.on('window-all-closed', () => app.quit());
