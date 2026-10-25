(() => {
  'use strict';

  const DEMO = new URLSearchParams(location.search).get('demo') === '1';
  const STORE = {
    theme: 'harbor.theme',
    language: 'harbor.language',
    groups: 'harbor.groups.v1'
  };

  const DEMO_ACCOUNTS = [
    {
      account_key: 'preview-studio',
      email: 'studio@example.com',
      alias: 'Studio',
      account_name: null,
      plan: 'plus',
      active: true,
      usage: {
        source: 'api',
        updated_at: 1792886400,
        primary: { used_percent: 24, window_minutes: 300, resets_at: 1792904400 },
        secondary: { used_percent: 42, window_minutes: 10080, resets_at: 1793491200 },
        refresh: { status: 'ok' }
      }
    },
    {
      account_key: 'preview-personal',
      email: 'personal@example.com',
      alias: 'Personal',
      account_name: null,
      plan: 'pro',
      active: false,
      usage: {
        source: 'cache',
        updated_at: 1792882800,
        primary: { used_percent: 8, window_minutes: 300, resets_at: 1792900800 },
        secondary: { used_percent: 14, window_minutes: 10080, resets_at: 1793487600 },
        refresh: { status: 'not_requested' }
      }
    }
  ];

  const DEMO_GROUPS = [
    { id: 'preview-work', name: 'Work' },
    { id: 'preview-personal', name: 'Personal' }
  ];

  const DEMO_ASSIGNMENTS = {
    'preview-studio': 'preview-work',
    'preview-personal': 'preview-personal'
  };

  const state = {
    demo: DEMO,
    accounts: [],
    groups: [],
    assignments: {},
    selectedGroup: null,
    search: '',
    language: 'en',
    theme: 'system',
    version: '1.0.0',
    codexHome: '',
    wsl: false,
    authMode: 'unknown',
    busy: false,
    loaded: false,
    notice: '',
    error: ''
  };

  let toastTimer = null;

  const media = window.matchMedia('(prefers-color-scheme: dark)');
  media.addEventListener('change', () => {
    if (state.theme === 'system') applyTheme();
  });

  function t(en, zh) {
    return state.language === 'zh' ? zh : en;
  }

  function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
  }

  function title(account) {
    return account.alias || account.account_name || account.email || t('API account', 'API 账号');
  }

  function groupName(account) {
    return state.groups.find((group) => group.id === state.assignments[account.account_key])?.name || '';
  }

  function groupCount(id) {
    if (id === null || id === undefined) return state.accounts.length;
    return state.accounts.reduce((count, account) => count + (state.assignments[account.account_key] === id ? 1 : 0), 0);
  }

  function remaining(quota) {
    if (!quota) return null;
    return Math.max(0, Math.min(100, 100 - Number(quota.used_percent || 0)));
  }

  function quotaLabel(quota, plan) {
    const minutes = quota?.window_minutes;
    if (minutes === 300) return t('5-hour window', '5 小时额度');
    if (minutes === 10080) return t('Weekly', '每周额度');
    if (typeof plan === 'string' && plan.toLowerCase() === 'free') return t('Free quota', '免费额度');
    return minutes ? t(`${minutes}-minute window`, `${minutes} 分钟额度`) : '';
  }

  function formatDate(timestamp) {
    if (!timestamp) return t('Reset time unavailable', '重置时间未知');
    try {
      return new Intl.DateTimeFormat(state.language === 'zh' ? 'zh-CN' : 'en-US', {
        dateStyle: 'medium',
        timeStyle: 'short'
      }).format(new Date(timestamp * 1000));
    } catch {
      return new Date(timestamp * 1000).toLocaleString();
    }
  }

  function sourceLabel(usage) {
    const labels = {
      api: t('Live data', '在线数据'),
      local: t('Local session', '本地会话'),
      cache: t('Cached snapshot', '缓存快照'),
      none: t('No usage data', '暂无额度')
    };
    const label = labels[usage?.source] || t('Unknown source', '未知来源');
    return label + (usage?.updated_at ? ` · ${formatDate(usage.updated_at)}` : '');
  }

  function sourceWarning(usage) {
    const refresh = usage?.refresh || {};
    const authError = refresh.http_status === 401
      || refresh.status === 'missing_auth'
      || /token_revoked|invalidated|reauth|refresh_token/i.test(String(refresh.error_code || ''));
    if (authError) {
      return `<div class="warn">${esc(t('Saved login revoked or expired. Sign in again in Codex, then click Save current before switching.', '保存的登录已失效。请在 Codex 中重新登录，然后点击“保存当前登录”再切换。'))}</div>`;
    }
    const status = refresh.status;
    if (!status || ['ok', 'not_requested'].includes(status)) return '';
    const text = usage?.source === 'none'
      ? t('No usage data yet. Try refreshing.', '暂无额度数据，请尝试刷新。')
      : t('Refresh unavailable. Showing an earlier snapshot.', '本次刷新未获取新数据，显示已有快照。');
    return `<div class="warn">${esc(text)}</div>`;
  }

  function filteredAccounts() {
    const query = state.search.trim().toLowerCase();
    return state.accounts.filter((account) => {
      const haystack = `${title(account)} ${account.email || ''}`.toLowerCase();
      const matchesSearch = !query || haystack.includes(query);
      const matchesGroup = state.selectedGroup === null || state.assignments[account.account_key] === state.selectedGroup;
      return matchesSearch && matchesGroup;
    });
  }

  function sailboatSVG() {
    return `<svg viewBox="0 0 32 32" aria-hidden="true">
      <path d="M16 4v17M16 8.5 8 21h8M17.5 6.5 25 21h-7.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>
      <path d="M5 24h22l-3.2 4H8.2L5 24Z" fill="currentColor"/>
      <path d="M8 30c1.4.8 2.6.8 4 0 1.4-.8 2.6-.8 4 0 1.4.8 2.6.8 4 0 1.4-.8 2.6-.8 4 0" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
    </svg>`;
  }

  function stackSVG() {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 8h14M5 12h14M5 16h14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>`;
  }

  function folderSVG() {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h6l2 2h8v9H4V7Z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>`;
  }

  function searchSVG() {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="m16 16 4 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>`;
  }

  function loadPreferences() {
    if (state.demo) {
      state.theme = 'system';
      state.language = 'en';
      state.groups = DEMO_GROUPS.map((group) => ({ ...group }));
      state.assignments = { ...DEMO_ASSIGNMENTS };
      state.accounts = DEMO_ACCOUNTS.map((account) => ({ ...account }));
      state.notice = t('Preview mode · Fictional accounts. Actions are disabled.', '演示模式 · 虚构账号，账号操作已停用。');
      state.loaded = true;
      return;
    }
    state.theme = localStorage.getItem(STORE.theme) || 'system';
    const systemLanguage = (navigator.language || '').toLowerCase().startsWith('zh') ? 'zh' : 'en';
    state.language = localStorage.getItem(STORE.language) || systemLanguage;
    try {
      const saved = JSON.parse(localStorage.getItem(STORE.groups) || '{}');
      state.groups = Array.isArray(saved.groups) ? saved.groups.filter((g) => g && g.id && g.name) : [];
      state.assignments = saved.assignments && typeof saved.assignments === 'object' ? saved.assignments : {};
    } catch {
      state.groups = [];
      state.assignments = {};
    }
  }

  function savePreferences() {
    if (state.demo) return;
    localStorage.setItem(STORE.theme, state.theme);
    localStorage.setItem(STORE.language, state.language);
  }

  function saveGroups() {
    if (state.demo) return;
    localStorage.setItem(STORE.groups, JSON.stringify({
      groups: state.groups,
      assignments: state.assignments
    }));
  }

  function pruneAssignments() {
    const keys = new Set(state.accounts.map((account) => account.account_key));
    const next = {};
    for (const [key, group] of Object.entries(state.assignments)) {
      if (keys.has(key) && state.groups.some((g) => g.id === group)) next[key] = group;
    }
    if (Object.keys(next).length !== Object.keys(state.assignments).length) {
      state.assignments = next;
      saveGroups();
    }
  }

  function resolvedTheme() {
    if (state.theme === 'system') return media.matches ? 'dark' : 'light';
    return state.theme;
  }

  function applyTheme() {
    document.documentElement.dataset.theme = resolvedTheme();
  }

  function setTheme(theme) {
    state.theme = theme;
    savePreferences();
    renderAll();
  }

  function setLanguage(language) {
    state.language = language;
    savePreferences();
    window.harbor?.setLanguage?.(language);
    renderAll();
  }

  function setNotice(message) {
    state.notice = message;
  }

  function showToast(message) {
    if (!message) return;
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.innerHTML = `<button class="toast-close" aria-label="Close">×</button><div>${esc(message)}</div>`;
    toast.classList.remove('hidden');
    toast.querySelector('.toast-close').addEventListener('click', () => toast.classList.add('hidden'));
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.add('hidden'), 9000);
  }

  function hideToast() {
    document.getElementById('toast')?.classList.add('hidden');
  }

  function showError(message) {
    state.error = message || t('The operation failed.', '操作失败。');
    showToast(state.error);
  }

  function failText(result) {
    if (!result) return t('The account core did not respond.', '账号核心没有响应。');
    if (typeof result.error === 'string' && result.error) {
      const messages = {
        core_error: t('The account core reported an error.', '账号核心返回了错误。'),
        account_not_found: t('Account not found. Refresh and try again.', '未找到账号，请刷新后重试。'),
        ambiguous_query: t('More than one account matches this selection.', '账号匹配不唯一。'),
        selector_resolution_failed: t('The account list has changed. Refresh and try again.', '账号已变更，请刷新后重试。'),
        curl_unavailable: t('curl was not found. Windows 10 or later is required.', '找不到 curl，请确认系统为 Windows 10 或更高版本。'),
        registry_error: t('Account data could not be read. Check the folder permissions.', '无法读取账号数据，请检查目录权限。'),
        state_uncertain: t('The write result is uncertain. Refresh and verify the account before trying again.', '写入状态不确定，请先刷新列表确认结果。'),
        client_running: t('Codex/ChatGPT is still running. Quit it and try again.', 'Codex/ChatGPT 仍在运行。请手动退出后重试。')
      };
      return messages[result.error] || result.error;
    }
    return t('The account core returned an unexpected result.', '账号核心返回了异常结果。');
  }

  function liveNotice(accounts) {
    const stale = accounts.some((account) => {
      const status = account.usage?.refresh?.status;
      return status && !['ok', 'not_requested'].includes(status);
    });
    return stale
      ? t('Refresh incomplete. Some accounts are showing cached data.', '刷新未完全成功，部分账号显示的是缓存数据。')
      : t('Refresh complete. Check each account\'s data source and status.', '刷新完成，请查看各账号的数据来源和状态。');
  }

  async function refreshUsage(api) {
    if (state.demo || state.busy) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const result = await window.harbor.list(api);
    state.busy = false;
    if (result?.ok) {
      state.accounts = result.data?.accounts || [];
      state.loaded = true;
      pruneAssignments();
      setNotice(api ? liveNotice(state.accounts) : t('Local accounts loaded. Refresh to fetch live usage.', '已读取本地账号，可刷新获取在线额度。'));
    } else {
      showError(failText(result));
      if (!state.loaded) setNotice(t('Could not load accounts.', '无法读取账号列表。'));
    }
    renderAll();
  }

  async function startupRefresh() {
    if (state.demo) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const local = await window.harbor.list(false);
    if (local?.ok) {
      state.accounts = local.data?.accounts || [];
      state.loaded = true;
      pruneAssignments();
      setNotice(t('Local accounts loaded. Syncing current login…', '已读取本地账号，正在同步当前登录…'));
      renderAll();
    }
    const sync = await window.harbor.syncCurrent();
    if (sync?.ok) {
      setNotice(t('Current login synced. Refreshing live usage…', '已同步当前登录，正在刷新在线额度…'));
    }
    const live = await window.harbor.list(true);
    state.busy = false;
    if (live?.ok) {
      state.accounts = live.data?.accounts || [];
      state.loaded = true;
      pruneAssignments();
      setNotice(liveNotice(state.accounts));
    } else {
      showError(failText(live));
      setNotice(local?.ok
        ? t('Live refresh failed. Showing local data.', '在线刷新失败，正在显示本地数据。')
        : t('Could not load accounts.', '无法读取账号列表。'));
    }
    renderAll();
  }

  async function reloadLocal() {
    const result = await window.harbor.list(false);
    if (result?.ok) {
      state.accounts = result.data?.accounts || [];
      state.loaded = true;
      pruneAssignments();
      return true;
    }
    showError(failText(result));
    return false;
  }

  async function switchAccount(key) {
    if (state.demo || state.busy) return;
    const account = state.accounts.find((item) => item.account_key === key);
    if (!account) return;
    const refresh = account.usage?.refresh || {};
    const authProblem = refresh.http_status === 401
      || refresh.status === 'missing_auth'
      || /token_revoked|invalidated|reauth|refresh_token/i.test(String(refresh.error_code || ''));
    const message = authProblem
      ? t(
        'This account\'s saved login appears revoked or expired. Codex will likely ask you to sign in again. Sign in to this account in Codex, click Save current, then quit Codex and switch. Continue anyway?',
        '该账号保存的登录已失效。Codex 很可能会要求重新登录。请先在 Codex 中登录该账号并点击“保存当前登录”，然后退出 Codex 再切换。仍要继续吗？'
      )
      : t(
        `Switch to ${title(account)}? First quit Codex/ChatGPT and any Codex CLI sessions. Harbor will not close them for you. After switching, reopen Codex. The ChatGPT desktop app keeps its own login and may ask you to sign in again.`,
        `切换到 ${title(account)}？请先手动退出 Codex/ChatGPT 以及 Codex CLI 会话，Harbor 不会替你关闭它们。切换后请重新打开 Codex。ChatGPT 桌面客户端有自己的登录状态，可能需要重新登录。`
      );
    if (!confirm(message)) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const result = await window.harbor.switchAccount(key);
    state.busy = false;
    if (result?.error === 'client_running') {
      showError(t('Codex/ChatGPT is still running: ', 'Codex/ChatGPT 仍在运行：') + (result.detail || '') + t('. Quit it and any Codex CLI sessions, then try again.', '。请手动退出它和 Codex CLI 会话后重试。'));
      renderAll();
      return;
    }
    await reloadLocal();
    if (result?.data?.switched_to) {
      const failedSync = !result.ok;
      setNotice(failedSync
        ? t('Credentials were written, but the background sync did not complete. Reopen Codex, then try Sync again.', '凭据已写入，但后台同步未完成。请重新打开 Codex，稍后再试“重新同步”。')
        : t('Account switched. Reopen Codex. If it asks you to sign in, sign in and click Save current to update this account before switching again.', '账号已切换，请重新打开 Codex；如果要求登录，请登录后点击“保存当前登录”更新该账号，再切换。'));
      if (failedSync) showToast(failText(result));
      else if (result.syncWarning) showToast(t('The previous login could not be synced to its saved snapshot. Click Save current for that account before switching back to it.', '上一个账号的登录未能同步到快照。切换回该账号前，请先对它点击“保存当前登录”。'));
    } else {
      showError(failText(result));
    }
    renderAll();
  }

  async function saveCurrent() {
    if (state.demo || state.busy) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const result = await window.harbor.saveCurrent();
    state.busy = false;
    if (result?.ok) {
      setNotice(t('Current sign-in saved.', '当前登录已保存。'));
      await reloadLocal();
    } else {
      showError(failText(result));
    }
    renderAll();
  }

  async function importCredentials() {
    if (state.demo || state.busy) return;
    const file = await window.harbor.pickImport();
    if (!file) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const result = await window.harbor.importFile(file);
    state.busy = false;
    if (result?.ok) {
      setNotice(t('Import completed. The account list has been updated.', '导入操作完成，账号列表已更新。'));
      await reloadLocal();
    } else {
      showError(failText(result));
    }
    renderAll();
  }

  async function openCodex() {
    if (state.demo || state.busy) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const result = await window.harbor.openCodex();
    state.busy = false;
    if (result?.ok) {
      const output = (result.output || result.diagnostics || '').trim().split('\n').filter(Boolean).slice(-1)[0];
      setNotice(output || t('Codex launch requested.', '已请求启动 Codex。'));
    } else {
      showError(result?.error || result?.diagnostics || t('Could not launch Codex.', '无法启动 Codex。'));
    }
    renderAll();
  }

  async function removeAccount(account) {
    if (state.demo || state.busy) return;
    if (!confirm(t(`Remove ${title(account)} from this PC?`, `从本机移除 ${title(account)}？`))) return;
    state.busy = true;
    state.error = '';
    renderAll();
    const result = await window.harbor.remove(account.account_key);
    state.busy = false;
    if (result?.ok) {
      setNotice(t('Account removed. Check your current sign-in.', '账号已移除，请确认当前登录状态。'));
      await reloadLocal();
    } else {
      showError(failText(result));
    }
    renderAll();
  }

  async function saveAlias(account, alias) {
    if (state.demo || state.busy) return;
    state.busy = true;
    const result = await window.harbor.alias(account.account_key, alias || null);
    state.busy = false;
    if (result?.ok) {
      setNotice(t('Account alias updated.', '账号别名已更新。'));
      await reloadLocal();
    } else {
      showError(failText(result));
    }
    renderAll();
  }

  function newGroupId() {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    return `group-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }

  function addGroup(name) {
    const value = name.trim();
    if (!value) return false;
    if (state.groups.some((group) => group.name.toLowerCase() === value.toLowerCase())) {
      showToast(t('That group already exists.', '该账号组已存在。'));
      return false;
    }
    state.groups.push({ id: newGroupId(), name: value });
    saveGroups();
    renderAll();
    return true;
  }

  function renameGroup(id, name) {
    const value = name.trim();
    if (!value) return;
    if (state.groups.some((group) => group.id !== id && group.name.toLowerCase() === value.toLowerCase())) {
      showToast(t('That group already exists.', '该账号组已存在。'));
      return;
    }
    const group = state.groups.find((item) => item.id === id);
    if (!group) return;
    group.name = value;
    saveGroups();
    renderAll();
  }

  function deleteGroup(id) {
    const group = state.groups.find((item) => item.id === id);
    if (!group) return false;
    if (!confirm(t(`Delete the group "${group.name}"? Its accounts will become ungrouped.`, `删除账号组“${group.name}”？组内账号会变为未分组。`))) return false;
    state.groups = state.groups.filter((item) => item.id !== id);
    for (const [key, value] of Object.entries(state.assignments)) {
      if (value === id) delete state.assignments[key];
    }
    if (state.selectedGroup === id) state.selectedGroup = null;
    saveGroups();
    renderAll();
    return true;
  }

  function moveAccount(key, groupId) {
    if (groupId && state.groups.some((group) => group.id === groupId)) {
      state.assignments[key] = groupId;
    } else {
      delete state.assignments[key];
    }
    saveGroups();
    renderAll();
  }

  function quotaHTML(quota, plan, fallback) {
    if (!quota) {
      return `<div class="quota">
        <div class="quota-top"><span class="label">${esc(fallback)}</span><span class="pct">—</span></div>
        <div class="track"></div>
        <div class="reset">${esc(t('Reset time unavailable', '重置时间未知'))}</div>
      </div>`;
    }
    const percent = Math.round(remaining(quota));
    return `<div class="quota">
      <div class="quota-top"><span class="label">${esc(quotaLabel(quota, plan) || fallback)}</span><span class="pct">${percent}% <small>${esc(t('left', '剩余'))}</small></span></div>
      <div class="track"><div class="fill ${percent < 20 ? 'low' : ''}" style="width:${percent}%"></div></div>
      <div class="reset">${esc(formatDate(quota.resets_at))}</div>
    </div>`;
  }

  function cardHTML(account) {
    const usage = account.usage || {};
    const group = groupName(account);
    const showSecondary = Boolean(usage.secondary) || !usage.primary;
    const disabled = state.busy || state.demo;
    return `<article class="card ${account.active ? 'active' : ''}" draggable="true" data-key="${esc(account.account_key)}">
      <div class="card-head">
        <div class="avatar">${esc(title(account).slice(0, 1).toUpperCase())}</div>
        <div class="identity">
          <div class="name-line"><span class="name">${esc(title(account))}</span>${account.active ? `<span class="badge">${esc(t('ACTIVE', '使用中'))}</span>` : ''}</div>
          ${title(account) !== account.email ? `<div class="email">${esc(account.email || t('API key account', 'API 密钥账号'))}</div>` : ''}
          ${group ? `<div class="group-tag">${folderSVG()}${esc(group)}</div>` : ''}
        </div>
        <div class="plan">
          <span>${esc((account.plan || t('UNKNOWN', '未知套餐')).toUpperCase())}</span>
          <button class="icon-btn" data-action="menu" data-key="${esc(account.account_key)}" title="${esc(t('Account actions', '账号操作'))}">⋯</button>
        </div>
      </div>
      <div class="quotas">
        ${quotaHTML(usage.primary, account.plan, t('Short window', '短周期额度'))}
        ${showSecondary ? quotaHTML(usage.secondary, account.plan, t('Long window', '长周期额度')) : ''}
      </div>
      <div class="spacer"></div>
      <div class="card-foot">
        <div class="source">${esc(sourceLabel(usage))}${sourceWarning(usage)}</div>
        <button class="btn compact ${account.active ? '' : 'primary'}" data-action="switch" data-key="${esc(account.account_key)}" ${disabled ? 'disabled' : ''}>
          ${esc(account.active ? t('Sync again', '重新同步') : t('Switch account', '切换账号'))} ↗
        </button>
      </div>
    </article>`;
  }

  function cardsHTML() {
    if (!state.loaded && !state.demo) {
      return `<div class="empty"><div class="empty-icon">◌</div><h2>${esc(t('Loading accounts…', '正在读取账号…'))}</h2></div>`;
    }
    const accounts = filteredAccounts();
    if (!accounts.length) {
      const emptyTitle = state.accounts.length === 0
        ? t('Your next workspace starts here.', '从第一个账号开始。')
        : (state.search ? t('No matching accounts.', '没有匹配的账号。') : t('This group is empty.', '这个账号组还没有账号。'));
      const emptyDetail = state.accounts.length === 0
        ? t('Sign in with Codex, then select Save current. Or import an auth.json file or a folder of JSON files.', '先使用 Codex 完成登录，再点击“保存当前登录”；也可导入 auth.json 文件或包含 JSON 的目录。')
        : (state.search ? t('Try a different email or alias.', '试试其他邮箱或别名。') : t('Drag a card onto this group in the sidebar, or use Move to group from a card menu.', '把卡片拖到侧栏的该账号组，或在卡片菜单中选择“移动到账号组”。'));
      return `<div class="empty"><div class="empty-icon">◌</div><h2>${esc(emptyTitle)}</h2><p>${esc(emptyDetail)}</p></div>`;
    }
    return accounts.map(cardHTML).join('');
  }

  function groupOptions(account) {
    const selected = state.assignments[account.account_key] || '';
    return `<option value="">${esc(t('No group', '未分组'))}</option>` +
      state.groups.map((group) => `<option value="${esc(group.id)}" ${selected === group.id ? 'selected' : ''}>${esc(group.name)}</option>`).join('');
  }

  function groupRowsHTML() {
    if (!state.groups.length) {
      return `<div class="empty-groups">${esc(t('No groups yet. Use + to create one.', '还没有账号组，点击 + 创建。'))}</div>`;
    }
    return state.groups.map((group) => `
      <button class="group-row ${state.selectedGroup === group.id ? 'selected' : ''}" data-group="${esc(group.id)}">
        ${folderSVG()}
        <span class="group-name">${esc(group.name)}</span>
        <span class="count">${groupCount(group.id)}</span>
        ${state.selectedGroup === group.id ? '<i class="dot"></i>' : ''}
      </button>`).join('');
  }

  function sidebarHTML() {
    const allSelected = state.selectedGroup === null;
    return `<aside class="sidebar" id="sidebar">
      <div class="brand">
        <div class="brand-mark">${sailboatSVG()}</div>
        <div class="brand-text"><strong>CODEX</strong><span>HARBOR / WIN</span></div>
      </div>
      <div class="section-label">${esc(t('WORKSPACE', '工作空间'))}</div>
      <button class="group-row ${allSelected ? 'selected' : ''}" id="all-accounts" data-group="">
        ${stackSVG()}
        <span class="group-name">${esc(t('All accounts', '全部账号'))}</span>
        <span class="count">${state.accounts.length}</span>
        ${allSelected ? '<i class="dot"></i>' : ''}
      </button>
      <div class="section-head">
        <span class="section-label">${esc(t('GROUPS', '账号组'))}</span>
        <button class="icon-btn" id="add-group" title="${esc(t('Manage groups', '管理账号组'))}">+</button>
      </div>
      <div class="group-list" id="group-list">${groupRowsHTML()}</div>
      <div class="sidebar-fill"></div>
      <div class="tagline">
        <div class="arrow">↗</div>
        <strong>${esc(t('A little less friction.', '让切换，更轻松。'))}</strong>
        <span>${esc(t('Switch accounts.\nKeep your flow.', '账号随心切换，\n专注你的工作。'))}</span>
      </div>
      <div class="sidebar-rule"></div>
      <div class="section-label">${esc(t('THEME', '外观'))}</div>
      <div class="segmented">
        <button class="segment ${state.theme === 'system' ? 'selected' : ''}" data-theme-choice="system">${esc(t('System', '跟随系统'))}</button>
        <button class="segment ${state.theme === 'light' ? 'selected' : ''}" data-theme-choice="light">${esc(t('Light', '浅色'))}</button>
        <button class="segment ${state.theme === 'dark' ? 'selected' : ''}" data-theme-choice="dark">${esc(t('Dark', '深色'))}</button>
      </div>
      <div class="section-label">${esc(t('LANGUAGE', '界面语言'))}</div>
      <div class="segmented">
        <button class="segment ${state.language === 'en' ? 'selected' : ''}" data-lang="en">EN</button>
        <button class="segment ${state.language === 'zh' ? 'selected' : ''}" data-lang="zh">中文</button>
      </div>
      <button class="link-btn" id="help">ⓘ ${esc(t('Quick guide', '使用指南'))}</button>
      <div class="version">v${esc(state.version)}<br><span>by Gh0stX</span></div>
    </aside>`;
  }

  function configWarningsHTML() {
    const warnings = [];
    if (state.wsl) {
      warnings.push(t(
        'Codex is configured to run in WSL; account switching uses the Windows Codex home and may not affect the WSL client.',
        'Codex 配置为在 WSL 中运行；账号切换使用 Windows 的 Codex 目录，可能不会影响 WSL 客户端。'
      ));
    }
    if (['encrypted', 'keyring'].includes(state.authMode)) {
      warnings.push(t(
        'Codex is using non-file credential storage; switching auth.json may not update the client. Set cli_auth_credentials_store = "file" or sign in again after switching.',
        'Codex 使用非文件凭据存储；仅切换 auth.json 可能不会更新客户端。请将 cli_auth_credentials_store 设为 "file"，或在切换后重新登录。'
      ));
    }
    return warnings.map((warning) => `<div class="config-warning">⚠ ${esc(warning)}</div>`).join('');
  }

  function mainHTML() {
    const active = state.accounts.find((account) => account.active);
    const disabled = state.busy || state.demo;
    return `<main class="main">
      <header class="top">
        <div class="eyebrow">
          <span>01 / ${esc(t('ACCOUNT CONTROL', '账号管理'))}</span>
          <span class="status">● ${esc(state.demo ? t('DEMO', '演示') : t('LOCAL STORAGE', '本地存储'))}</span>
        </div>
        <div class="title-row">
          <div>
            <h1>${esc(t('Accounts', '账号总览'))}.</h1>
            <p class="subtitle">${esc(t('Every identity. One quiet workspace.', '每一个身份，都在这里。'))}</p>
          </div>
          <div class="top-actions">
            <button class="btn" id="open-codex" ${disabled ? 'disabled' : ''}>${esc(t('Open Codex', '打开 Codex'))}</button>
            <button class="btn" id="refresh" ${state.busy || state.demo ? 'disabled' : ''}>${state.busy ? '<span class="spinner"></span>' : ''}${esc(t('Refresh usage', '刷新额度'))}</button>
          </div>
        </div>
        <div class="summary">
          <span class="summary-count">${String(state.accounts.length).padStart(2, '0')}</span>
          <span class="summary-label">${esc(t('saved accounts', '个已存账号'))}</span>
          <div class="summary-divider"></div>
          <div class="active-block">
            <span class="active-label">${esc(t('ACTIVE IDENTITY', '当前身份'))}</span>
            <span class="active-name">${esc(active ? title(active) : t('None selected', '尚未选择'))}</span>
          </div>
          <span class="auto">↻ ${esc(t('Manual restart', '手动重启'))}</span>
        </div>
        <div class="controls">
          <div class="search">${searchSVG()}<input id="search" value="${esc(state.search)}" placeholder="${esc(t('Search accounts', '搜索账号'))}" aria-label="${esc(t('Search by email or alias', '按邮箱或别名搜索'))}"></div>
          <button class="btn" id="groups-btn">${esc(t('Groups', '账号组'))}</button>
          <button class="btn" id="save-btn" ${disabled ? 'disabled' : ''}>${esc(t('Save current', '保存当前登录'))}</button>
          <button class="btn primary" id="import-btn" ${disabled ? 'disabled' : ''}>＋ ${esc(t('Import', '导入账号'))}</button>
        </div>
        ${configWarningsHTML()}
      </header>
      <div class="scroll"><div class="grid" id="cards">${cardsHTML()}</div></div>
      <footer class="footer">
        <span class="footer-icon">${state.demo ? '◉' : '○'}</span>
        <span id="notice">${esc(state.notice)}</span>
      </footer>
    </main>`;
  }

  function renderCardsOnly() {
    const cards = document.getElementById('cards');
    if (cards) cards.innerHTML = cardsHTML();
  }

  function renderAll() {
    applyTheme();
    const app = document.getElementById('app');
    if (!app) return;
    const active = document.activeElement;
    const wasSearch = active?.id === 'search';
    const selection = wasSearch ? active.selectionStart : null;
    app.className = '';
    app.innerHTML = `<div class="app">${sidebarHTML()}${mainHTML()}</div>`;
    wireEvents();
    if (wasSearch) {
      const input = document.getElementById('search');
      if (input) {
        input.focus();
        if (selection !== null) input.setSelectionRange(selection, selection);
      }
    }
  }

  function wireEvents() {
    document.getElementById('refresh')?.addEventListener('click', () => refreshUsage(true));
    document.getElementById('save-btn')?.addEventListener('click', saveCurrent);
    document.getElementById('import-btn')?.addEventListener('click', importCredentials);
    document.getElementById('groups-btn')?.addEventListener('click', openGroupManager);
    document.getElementById('add-group')?.addEventListener('click', openGroupManager);
    document.getElementById('open-codex')?.addEventListener('click', openCodex);
    document.getElementById('help')?.addEventListener('click', openHelp);
    document.getElementById('all-accounts')?.addEventListener('click', () => {
      state.selectedGroup = null;
      renderAll();
    });
    document.getElementById('group-list')?.addEventListener('click', (event) => {
      const row = event.target.closest('.group-row');
      if (!row) return;
      state.selectedGroup = row.dataset.group || null;
      renderAll();
    });
    document.querySelectorAll('[data-theme-choice]').forEach((button) => {
      button.addEventListener('click', () => setTheme(button.dataset.themeChoice));
    });
    document.querySelectorAll('[data-lang]').forEach((button) => {
      button.addEventListener('click', () => setLanguage(button.dataset.lang));
    });
    const search = document.getElementById('search');
    search?.addEventListener('input', (event) => {
      state.search = event.target.value;
      renderCardsOnly();
    });
    const cards = document.getElementById('cards');
    cards?.addEventListener('click', (event) => {
      const action = event.target.closest('[data-action]');
      if (!action) return;
      const key = action.dataset.key;
      if (action.dataset.action === 'switch') switchAccount(key);
      if (action.dataset.action === 'menu') openAccountMenu(key);
    });
    cards?.addEventListener('dragstart', (event) => {
      const card = event.target.closest('.card');
      if (!card) return;
      card.classList.add('dragging');
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', card.dataset.key);
    });
    cards?.addEventListener('dragend', (event) => {
      event.target.closest('.card')?.classList.remove('dragging');
    });
    const sidebar = document.getElementById('sidebar');
    sidebar?.addEventListener('dragover', (event) => {
      const row = event.target.closest('.group-row');
      if (!row) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      row.classList.add('drop-target');
    });
    sidebar?.addEventListener('dragleave', (event) => {
      const row = event.target.closest('.group-row');
      if (row) row.classList.remove('drop-target');
    });
    sidebar?.addEventListener('drop', (event) => {
      const row = event.target.closest('.group-row');
      if (!row) return;
      event.preventDefault();
      row.classList.remove('drop-target');
      const key = event.dataTransfer.getData('text/plain');
      if (!key) return;
      moveAccount(key, row.id === 'all-accounts' ? null : (row.dataset.group || null));
    });
  }

  function openAccountMenu(key) {
    const account = state.accounts.find((item) => item.account_key === key);
    if (!account) return;
    const dialog = document.createElement('dialog');
    dialog.className = 'modal';
    dialog.innerHTML = `<div class="modal-inner">
      <h2>${esc(title(account))}</h2>
      <p>${esc(account.email || '')}</p>
      <div class="modal-section">
        <div class="section-label">${esc(t('Account alias', '账号别名'))}</div>
        <div class="modal-row"><input id="alias-input" class="field" value="${esc(account.alias || '')}" placeholder="${esc(t('Personal, Studio, Work…', '例如：个人、工作室、工作…'))}"></div>
      </div>
      <div class="modal-section">
        <div class="section-label">${esc(t('Move to group', '移动到账号组'))}</div>
        <div class="modal-row"><select id="group-select" class="field">${groupOptions(account)}</select></div>
      </div>
      <div class="modal-actions">
        <button class="btn danger" id="remove-account" ${state.demo ? 'disabled' : ''}>${esc(t('Remove account', '移除账号'))}</button>
        <span class="right">
          <button class="btn" id="cancel-account">${esc(t('Cancel', '取消'))}</button>
          <button class="btn primary" id="save-account" ${state.demo ? 'disabled' : ''}>${esc(t('Save', '保存'))}</button>
        </span>
      </div>
    </div>`;
    document.body.appendChild(dialog);
    const close = () => { dialog.close(); dialog.remove(); };
    dialog.addEventListener('close', () => dialog.remove());
    dialog.querySelector('#cancel-account').addEventListener('click', close);
    dialog.querySelector('#save-account').addEventListener('click', async () => {
      const alias = dialog.querySelector('#alias-input').value.trim();
      const group = dialog.querySelector('#group-select').value || null;
      close();
      if (!state.demo) {
        await window.harbor.alias(account.account_key, alias || null).then(async (result) => {
          if (!result?.ok) showError(failText(result));
          await reloadLocal();
        });
      }
      moveAccount(account.account_key, group);
      renderAll();
    });
    dialog.querySelector('#group-select').addEventListener('change', (event) => {
      moveAccount(account.account_key, event.target.value || null);
    });
    dialog.querySelector('#remove-account').addEventListener('click', async () => {
      close();
      await removeAccount(account);
    });
    dialog.showModal();
  }

  function groupListEditorHTML() {
    if (!state.groups.length) {
      return `<div class="empty-groups">${esc(t('No groups yet.', '还没有账号组。'))}</div>`;
    }
    return state.groups.map((group) => `<div class="group-edit">
      <input class="field" data-group-name="${esc(group.id)}" value="${esc(group.name)}">
      <span class="count">${groupCount(group.id)}</span>
      <button class="btn danger" data-delete-group="${esc(group.id)}" title="${esc(t('Delete group', '删除账号组'))}">🗑</button>
    </div>`).join('');
  }

  function assignmentsEditorHTML() {
    if (!state.accounts.length) {
      return `<div class="empty-groups">${esc(t('No accounts yet.', '还没有账号。'))}</div>`;
    }
    return state.accounts.map((account) => `<div class="assignment">
      <span>${esc(title(account))}</span>
      <select data-assign="${esc(account.account_key)}">${groupOptions(account)}</select>
    </div>`).join('');
  }

  function openGroupManager() {
    const dialog = document.createElement('dialog');
    dialog.className = 'modal';
    const close = () => { dialog.close(); dialog.remove(); renderAll(); };
    const render = () => {
      dialog.innerHTML = `<div class="modal-inner">
        <h2>${esc(t('Account groups', '账号组'))}</h2>
        <p>${esc(t('Create groups, then drag cards onto them in the sidebar or assign accounts below.', '创建账号组后，可将卡片拖到侧栏对应组，或在下方直接分配账号。'))}</p>
        <div class="modal-row">
          <input id="new-group" class="field" placeholder="${esc(t('New group name', '新账号组名称'))}">
          <button class="btn primary" id="add-group-btn">${esc(t('Add', '添加'))}</button>
        </div>
        <div class="modal-section">
          <div class="section-label">${esc(t('Groups', '账号组'))}</div>
          <div class="modal-list">${groupListEditorHTML()}</div>
        </div>
        <div class="modal-section">
          <div class="section-label">${esc(t('Assign accounts', '分配账号'))}</div>
          <div class="modal-list">${assignmentsEditorHTML()}</div>
        </div>
        <div class="modal-actions">
          <span class="version">Codex Harbor · by Gh0stX</span>
          <span class="right"><button class="btn primary" id="done-groups">${esc(t('Done', '完成'))}</button></span>
        </div>
      </div>`;
      wire();
    };
    const wire = () => {
      dialog.querySelector('#done-groups').addEventListener('click', close);
      dialog.querySelector('#add-group-btn').addEventListener('click', () => {
        const input = dialog.querySelector('#new-group');
        if (addGroup(input.value)) {
          render();
          renderAll();
        }
      });
      dialog.querySelector('#new-group').addEventListener('keydown', (event) => {
        if (event.key === 'Enter') dialog.querySelector('#add-group-btn').click();
      });
      dialog.querySelectorAll('[data-group-name]').forEach((input) => {
        input.addEventListener('change', () => {
          renameGroup(input.dataset.groupName, input.value);
          renderAll();
        });
      });
      dialog.querySelectorAll('[data-delete-group]').forEach((button) => {
        button.addEventListener('click', () => {
          if (deleteGroup(button.dataset.deleteGroup)) {
            dialog.remove();
            openGroupManager();
          }
        });
      });
      dialog.querySelectorAll('[data-assign]').forEach((select) => {
        select.addEventListener('change', () => {
          moveAccount(select.dataset.assign, select.value || null);
          render();
        });
      });
    };
    render();
    document.body.appendChild(dialog);
    dialog.addEventListener('close', () => dialog.remove());
    dialog.showModal();
  }

  function openHelp() {
    const dialog = document.createElement('dialog');
    dialog.className = 'modal';
    dialog.innerHTML = `<div class="modal-inner">
      <h2>${esc(t('Quick guide', '使用指南'))}</h2>
      <div class="help-row"><span class="num">01</span><div><h3>${esc(t('Bring your accounts', '添加账号'))}</h3><p>${esc(t('Sign in with Codex, then select Save current. Or import an auth.json file or a folder of JSON files.', '先使用 Codex 完成登录，再点击“保存当前登录”；也可导入 auth.json 文件或包含 JSON 的目录。'))}</p></div></div>
      <div class="help-row"><span class="num">02</span><div><h3>${esc(t('Know what is current', '识别数据时效'))}</h3><p>${esc(t('Refresh usage for live data; the app also refreshes once at every launch. Cached and local snapshots may be older; failed refreshes keep the last available data.', '刷新额度可获取在线数据；应用每次启动时也会自动刷新一次。缓存与本地快照可能较旧；刷新失败时会保留已有数据。'))}</p></div></div>
      <div class="help-row"><span class="num">03</span><div><h3>${esc(t('Switch, then reopen', '切换后重新打开'))}</h3><p>${esc(t('The app syncs your current Codex login automatically at launch and before switching, preserving cached usage. Before switching, quit Codex/ChatGPT and any Codex CLI sessions; Harbor will not close them for you. After switching, reopen Codex. If Codex asks you to sign in, sign in; the snapshot syncs automatically or use Save current.', '应用会在启动时和切换前自动同步当前 Codex 登录，并保留已缓存额度。切换前请手动退出 Codex/ChatGPT 和 Codex CLI 会话，Harbor 不会替你关闭它们。切换后重新打开 Codex；如果要求登录，请登录；快照会自动同步，也可以点击“保存当前登录”。'))}</p></div></div>
      <div class="help-row"><span class="num">04</span><div><h3>${esc(t('Group your accounts', '整理账号'))}</h3><p>${esc(t('Create groups from the Groups sheet. Drag a card onto a group in the sidebar, or use Move to group in a card menu.', '在“账号组”面板中创建分组。把卡片拖到侧栏的账号组，或在卡片菜单中选择“移动到账号组”。'))}</p></div></div>
      <div class="help-row"><span class="num">05</span><div><h3>${esc(t('Stored on this PC', '数据保存在本机'))}</h3><p>${esc(t('Credentials remain in local files managed by the account core. Codex home: ', '凭据保存在核心管理的本地文件中。Codex 目录：') + (state.codexHome || t('unknown', '未知')) + '. ' + t('This app does not add Keychain encryption and never displays your access tokens.', '本应用不使用钥匙串加密，也不展示访问令牌。'))}</p></div></div>
      <div class="modal-actions">
        <span class="version">Codex Harbor · by Gh0stX</span>
        <span class="right"><button class="btn primary" id="close-help">${esc(t('Done', '完成'))}</button></span>
      </div>
    </div>`;
    document.body.appendChild(dialog);
    dialog.querySelector('#close-help').addEventListener('click', () => { dialog.close(); dialog.remove(); });
    dialog.addEventListener('close', () => dialog.remove());
    dialog.showModal();
  }

  async function init() {
    try {
      const info = await window.harbor.info();
      state.demo = Boolean(info?.demo);
      state.version = info?.version || '1.0.0';
      state.codexHome = info?.codexHome || '';
      state.wsl = Boolean(info?.wsl);
      state.authMode = info?.authMode || 'unknown';
      loadPreferences();
      window.harbor?.setLanguage?.(state.language);
      document.title = 'Codex Harbor';
      renderAll();
      if (!state.demo) await startupRefresh();
    } catch (error) {
      document.getElementById('app').innerHTML = `<div class="empty"><h2>${esc(t('Unable to start Codex Harbor', '无法启动 Codex Harbor'))}</h2><p>${esc(String(error))}</p></div>`;
    }
  }

  init();
})();
