/* Zenith - UI */
'use strict';
(() => {
  // ------------------------------------------------------------------ helpers
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const arr = (x) => (Array.isArray(x) ? x : x == null ? [] : [x]);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const clamp = (v, a = 0, b = 100) => Math.max(a, Math.min(b, Number(v) || 0));
  const fmtBytes = (b) => {
    b = Number(b) || 0;
    if (b <= 0) return '0 MB';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
    return (b >= 100 || i < 2 ? b.toFixed(0) : b.toFixed(b >= 10 ? 1 : 2)) + ' ' + u[i];
  };
  const fmtDate = (iso) => {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d)) return String(iso);
    return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) + ', ' + d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  };
  const plural = (n, w, pl) => n + ' ' + (n === 1 ? w : (pl || w + 's'));

  const ICONS = {
    home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    monitor: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    rocket: '<path d="M5 15c-1.5 1.5-2 4-2 6 2 0 4.5-.5 6-2"/><path d="M9 15 6 12l3-1c2-4 6-7 12-8-1 6-4 10-8 12l-1 3z"/><circle cx="15.5" cy="8.5" r="1.6"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13M9 7V4h6v3"/>',
    power: '<path d="M12 3v9"/><path d="M6.3 6.3a8 8 0 1 0 11.4 0"/>',
    sparkle: '<path d="M11 3l1.8 4.7 4.7 1.8-4.7 1.8L11 16l-1.8-4.7L4.5 9.5l4.7-1.8z"/><path d="M18.5 14l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9z"/>',
    gamepad: '<path d="M6.5 8h11a4.5 4.5 0 0 1 4.5 4.5V15a3 3 0 0 1-5.4 1.8L15 15H9l-1.6 1.8A3 3 0 0 1 2 15v-2.5A4.5 4.5 0 0 1 6.5 8z"/><path d="M7.5 10.5v3M6 12h3M15.5 11.5h.01M18 13h.01"/>',
    shield: '<path d="M12 3 4.5 6v5.5c0 4.7 3.2 8.2 7.5 9.5 4.3-1.3 7.5-4.8 7.5-9.5V6z"/><path d="m9 12 2 2 4-4"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9 2.5v3M15 2.5v3M9 18.5v3M15 18.5v3M2.5 9h3M2.5 15h3M18.5 9h3M18.5 15h3"/>',
    ram: '<rect x="2.5" y="7" width="19" height="9" rx="1.5"/><path d="M6.5 10v3M10 10v3M14 10v3M17.5 10v3M5 16v3M9 16v3M15 16v3M19 16v3"/>',
    gpu: '<rect x="2" y="6" width="20" height="11" rx="2"/><circle cx="9" cy="11.5" r="3"/><path d="M15 9.5h4M15 13.5h4M4 17v3"/>',
    disk: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 14h18"/><path d="M16.5 17h.01"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 7.5h.01"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    warn: '<path d="M10.3 4.3 2.6 18a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0z"/><path d="M12 9.5v4M12 17h.01"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>',
    restore: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/>',
    bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    wifi: '<path d="M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M2 9a15 15 0 0 1 20 0"/><path d="M12 19.5h.01"/>',
    sliders: '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
    play: '<path d="M7 4.5v15l12-7.5z"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    archive: '<rect x="3" y="4" width="18" height="5" rx="1"/><path d="M5 9v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9M10 13h4"/>',
    help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6M12 17h.01"/>',
    external: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    refresh: '<path d="M20 12a8 8 0 1 1-2.3-5.7L20 8.5"/><path d="M20 3.5v5h-5"/>',
    eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    wrench: '<path d="M14.7 6.3a4 4 0 0 0-5 5L3.5 17.5a2.1 2.1 0 0 0 3 3l6.2-6.2a4 4 0 0 0 5-5l-2.5 2.5-2.5-.5-.5-2.5z"/>'
  };
  const icon = (name) => `<span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg></span>`;
  const hydrateIcons = (root = document) => $$('[data-icon]', root).forEach((el) => { if (!el.dataset.done) { el.outerHTML = icon(el.dataset.icon); } });

  // ------------------------------------------------------------------ session & API
  const params = new URLSearchParams(location.search);
  let token = params.get('t');
  try { if (token) sessionStorage.setItem('zenith-token', token); else token = sessionStorage.getItem('zenith-token'); } catch (e) { /* storage blocked */ }
  if (params.has('t')) history.replaceState(null, '', location.pathname + location.hash);

  let lost = false;
  async function api(path, body) {
    const opt = { method: body === undefined ? 'GET' : 'POST', headers: { 'X-Zenith-Token': token || '' } };
    if (body !== undefined) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
    let r;
    try { r = await fetch(path, opt); } catch (e) { connectionLost(); throw new Error('The Zenith engine is not responding.'); }
    let data = null;
    try { data = await r.json(); } catch (e) { /* no body */ }
    if (r.status === 403) { connectionLost(data && data.error); throw new Error((data && data.error) || 'Session expired'); }
    if (!r.ok) throw new Error((data && data.error) || 'Request failed (' + r.status + ')');
    return data;
  }

  function connectionLost(msg) {
    if (lost) return;
    lost = true;
    openModal(`<h2>${icon('warn')} Lost connection to Zenith</h2>
      <div class="mbody"><p>${esc(msg || 'The Zenith engine stopped or this window was opened without a valid session.')}</p>
      <p>Close this window and start Zenith again with <b>Launch Zenith.bat</b>. Nothing is lost - every change and its backup are saved on disk.</p></div>`, { locked: true });
  }

  // ------------------------------------------------------------------ state
  const Z = {
    state: null, scan: null, startup: null, apps: null, games: null, boost: null, cleaner: null, cleanerResult: null, rps: null,
    live: null, hist: { cpu: [], gpu: [], ram: [] }, busy: false,
    ui: { cat: 'all', dcat: 'all', q: '', hideApplied: false, appSel: null, boostSel: null, cleanSel: null }
  };
  const tweaks = () => arr(Z.state && Z.state.tweaks);
  const byId = (id) => tweaks().find((t) => t.id === id);
  const isOn = (t) => t.state === 'applied' || t.state === 'drifted' || t.state === 'optimal';
  const catPage = (cat) => { const c = arr(Z.state && Z.state.categories).find((x) => x.id === cat); return c ? c.page : 'optimize'; };
  const catLabel = (cat) => { const c = arr(Z.state && Z.state.categories).find((x) => x.id === cat); return c ? c.label : ({ startup: 'Startup app', apps: 'App' }[cat] || cat); };
  const showAdvanced = () => !(Z.state && Z.state.settings && Z.state.settings.showAdvanced === false);
  const visibleTweak = (t) => showAdvanced() || (t.risk !== 'advanced' && !arr(t.tags).includes('Experimental'));
  const pendingIn = (ids) => arr(ids).map(byId).filter((t) => t && (t.state === 'off' || t.state === 'drifted'));

  async function loadState() { Z.state = await api('/api/state'); updateChrome(); }
  async function loadScan(refresh) { Z.scan = await api('/api/scan' + (refresh ? '?refresh=1' : '')); }

  // ------------------------------------------------------------------ routes
  const ROUTES = {
    home: { title: 'Welcome to Zenith', sub: 'Peak performance for your rig', icon: 'home', nav: 'Dashboard', render: renderHome },
    pc: { title: 'My PC', sub: 'Hardware scan and health check', icon: 'monitor', nav: 'My PC', render: renderPC },
    optimize: { title: 'Optimizations', sub: 'FPS, latency and system performance tweaks', icon: 'rocket', nav: 'Optimizations', render: renderOptimize },
    debloat: { title: 'Debloat', sub: 'Privacy, telemetry, Windows bloat and background services', icon: 'trash', nav: 'Debloat', render: renderDebloat },
    startup: { title: 'Startup Apps', sub: 'Choose what starts with Windows', icon: 'power', nav: 'Startup', render: renderStartup },
    cleaner: { title: 'Cleaner', sub: 'Free up disk space without touching your files', icon: 'sparkle', nav: 'Cleaner', render: renderCleaner },
    games: { title: 'Games', sub: 'Your library and one-click Game Boost', icon: 'gamepad', nav: 'Games', render: renderGames },
    backup: { title: 'Backup & Restore', sub: 'Every change can be undone - here is how', icon: 'shield', nav: 'Backup & Restore', render: renderBackup },
    settings: { title: 'Settings', sub: 'Preferences, tools and about', icon: 'gear', nav: 'Settings', render: renderSettings }
  };
  const NAV = ['home', 'pc', 'optimize', 'debloat', 'startup', 'cleaner', 'games', 'backup'];
  const route = () => { const r = (location.hash || '#home').slice(1); return ROUTES[r] ? r : 'home'; };
  const go = (r) => { if (location.hash === '#' + r) render(); else location.hash = r; };

  function renderNav() {
    const pend = Z.state ? pendingIn(arr(Z.state.presets && Z.state.presets.balanced).filter((id) => byId(id) && catPage(byId(id).cat) === 'optimize')).length : 0;
    const pendD = Z.state ? pendingIn(Z.state.presets && Z.state.presets.debloat).length : 0;
    $('#nav').innerHTML = NAV.map((r) => {
      let count = '';
      if (r === 'optimize' && pend) count = `<span class="count">${pend}</span>`;
      if (r === 'debloat' && pendD) count = `<span class="count">${pendD}</span>`;
      return `<a href="#${r}" class="nav-item${route() === r ? ' active' : ''}" data-route="${r}">${icon(ROUTES[r].icon)}<span>${ROUTES[r].nav}</span>${count}</a>`;
    }).join('');
    $$('.sidebar-foot .nav-item').forEach((a) => a.classList.toggle('active', route() === a.dataset.route));
  }

  function updateChrome() {
    const s = Z.state;
    if (!s) return;
    $('#version').innerHTML = `Zenith v${esc(s.version)}` + (s.mock ? ' &middot; <span class="mock">Demo mode</span>' : '');
    const chip = $('#rp-chip');
    if (s.session && s.session.restorePointDone) { chip.hidden = false; chip.className = 'chip ok'; chip.innerHTML = '<span class="dot"></span>Restore point created'; }
    else if (s.settings && s.settings.autoRestorePoint) { chip.hidden = false; chip.className = 'chip'; chip.innerHTML = '<span class="dot"></span>Restore point before first change'; }
    else chip.hidden = true;
    $('#reboot-chip').hidden = !(s.session && s.session.rebootPending);
    renderNav();
  }

  function render() {
    const r = route();
    const def = ROUTES[r];
    $('#page-title').textContent = def.title;
    $('#page-sub').textContent = def.sub;
    renderNav();
    if (!Z.state) return;
    const view = $('#view');
    view.innerHTML = `<div>${def.render()}</div>`;
    hydrateIcons(view);
    afterRender(r);
  }

  function afterRender(r) {
    $$('img[data-fallback]').forEach((img) => img.addEventListener('error', () => { img.remove(); }, { once: true }));
    if ((r === 'home' || r === 'pc') && !Z.scan) loadScan().then(() => { if (route() === r) render(); }).catch((e) => toast(e.message, 'err'));
    if (r === 'startup' && !Z.startup) api('/api/startup').then((d) => { Z.startup = arr(d.items); if (route() === r) render(); }).catch((e) => toast(e.message, 'err'));
    if (r === 'debloat' && !Z.apps) api('/api/apps').then((d) => { Z.apps = arr(d.items); if (route() === r) render(); }).catch((e) => toast(e.message, 'err'));
    if (r === 'games') {
      if (!Z.games) api('/api/games').then((d) => { Z.games = arr(d.items); if (route() === r) render(); }).catch((e) => toast(e.message, 'err'));
      if (!Z.boost) api('/api/boost').then((d) => { Z.boost = arr(d.items); if (route() === r) render(); }).catch((e) => toast(e.message, 'err'));
    }
    if (r === 'backup' && !Z.rps) api('/api/restore-points').then((d) => { Z.rps = arr(d.items); if (route() === r) render(); }).catch(() => { Z.rps = []; });
  }

  // ------------------------------------------------------------------ components
  function ring(pct, size, color, id, label, sub) {
    const sw = size >= 140 ? 13 : 10;
    const r = (size - sw) / 2;
    const c = 2 * Math.PI * r;
    const off = c * (1 - clamp(pct) / 100);
    return `<div class="ring" style="width:${size}px;height:${size}px">
      <svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="#222d49" stroke-width="${sw}" fill="none"/>
      <circle ${id ? `id="ring-${id}"` : ''} cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${color}" stroke-width="${sw}" fill="none" stroke-linecap="round" stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" data-c="${c.toFixed(2)}"/></svg>
      <div class="ring-label"><div class="ring-value" ${id ? `id="ringv-${id}"` : ''}>${label != null ? label : Math.round(clamp(pct)) + '%'}</div>${sub ? `<div class="ring-sub">${sub}</div>` : ''}</div></div>`;
  }
  function setRing(id, pct, text) {
    const c = document.getElementById('ring-' + id);
    if (c) c.setAttribute('stroke-dashoffset', (Number(c.dataset.c) * (1 - clamp(pct) / 100)).toFixed(2));
    const v = document.getElementById('ringv-' + id);
    if (v) v.textContent = text != null ? text : Math.round(clamp(pct)) + '%';
  }
  function sparkline(values) {
    const w = 600, h = 92;
    let pts = values.slice(-48);
    if (pts.length < 2) pts = [pts[0] || 0, pts[0] || 0];
    const step = w / (pts.length - 1);
    const xy = pts.map((v, i) => [i * step, h - 6 - (clamp(v) / 100) * (h - 14)]);
    const line = xy.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
    const area = line + ` L ${w} ${h} L 0 ${h} Z`;
    return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="sg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22c55e" stop-opacity=".32"/><stop offset="1" stop-color="#22c55e" stop-opacity="0"/></linearGradient></defs>
      <path d="${area}" fill="url(#sg)"/><path d="${line}" fill="none" stroke="#22c55e" stroke-width="2.4" vector-effect="non-scaling-stroke" stroke-linejoin="round"/></svg>`;
  }
  const scoreColor = (p) => (p >= 85 ? '#22c55e' : p >= 55 ? '#ff8a1f' : '#f05252');
  const usageColor = (p, base) => (p >= 90 ? '#f05252' : base);
  const toggle = (action, id, on, disabled, label) => `<label class="toggle" title="${esc(label || '')}"><input type="checkbox" data-action="${action}" data-id="${esc(id)}" ${on ? 'checked' : ''} ${disabled ? 'disabled' : ''} aria-label="${esc(label || id)}"><span class="track"></span></label>`;
  const riskBadge = (r) => `<span class="badge ${r}">${{ safe: 'Safe', moderate: 'Moderate', advanced: 'Advanced' }[r] || r}</span>`;
  const avatarColor = (s) => { let h = 0; for (const ch of String(s)) h = (h * 31 + ch.charCodeAt(0)) % 360; return `hsl(${h} 55% 42%)`; };

  function tweakBadges(t) {
    const b = [riskBadge(t.risk)];
    if (t.state === 'optimal') b.push(`<span class="badge state-optimal">${icon('check')}Already optimal</span>`);
    else if (t.state === 'drifted') b.push(`<span class="badge state-drift" title="Windows or another app changed this back">${icon('warn')}Changed by Windows</span>`);
    else if (t.state === 'na') b.push(`<span class="badge">${esc(t.naReason)}</span>`);
    else if (t.gain > 0 && t.state === 'off') b.push(`<span class="badge gain">+${t.gain}%</span>`);
    for (const tag of arr(t.tags)) {
      if (tag === 'Power hungry') b.push(`<span class="badge tag-power">${icon('bolt')}Power hungry</span>`);
      else if (tag === 'Experimental') b.push(`<span class="badge tag-experimental">Experimental</span>`);
      else b.push(`<span class="badge">${esc(tag)}</span>`);
    }
    if (t.reboot) b.push(`<span class="badge">${icon('refresh')}Restart</span>`);
    if (t.partial) b.push(`<span class="badge advanced">Undo incomplete</span>`);
    return b.join('');
  }

  function tweakCard(t) {
    const on = isOn(t);
    const disabled = Z.busy || t.state === 'na' || t.state === 'optimal';
    const drift = t.state === 'drifted' ? `<button class="btn btn-sm" data-action="apply-one" data-id="${esc(t.id)}">Re-apply</button>` : '';
    return `<div class="card tweak${on ? ' on' : ''}${t.state === 'na' ? ' na' : ''}" data-id="${esc(t.id)}">
      <div class="thead"><h3>${esc(t.name)}</h3>
        <button class="info" data-action="tweak-info" data-id="${esc(t.id)}" title="Details and exactly what changes">${icon('info')}</button>
        ${toggle('toggle-tweak', t.id, on, disabled, t.name)}</div>
      <p class="desc">${esc(t.desc)}</p>
      <div class="tfoot">${tweakBadges(t)}<span class="spacer"></span>${drift}</div></div>`;
  }

  function tweakGrid(page, cat) {
    const q = Z.ui.q.trim().toLowerCase();
    const list = tweaks().filter((t) => catPage(t.cat) === page && visibleTweak(t)
      && (cat === 'all' || t.cat === cat)
      && (!Z.ui.hideApplied || !isOn(t))
      && (!q || (t.name + ' ' + t.desc + ' ' + catLabel(t.cat)).toLowerCase().includes(q)));
    if (!list.length) return `<div class="card empty">No tweaks match this filter.</div>`;
    return list.map(tweakCard).join('');
  }

  function catChips(page, active, action) {
    const all = tweaks().filter((t) => catPage(t.cat) === page && visibleTweak(t));
    const cats = arr(Z.state.categories).filter((c) => c.page === page);
    const chip = (id, label, list) => {
      const onN = list.filter(isOn).length;
      return `<button class="cat${active === id ? ' active' : ''}" data-action="${action}" data-cat="${id}">${esc(label)} <span class="n">${onN}/${list.length}</span></button>`;
    };
    return chip('all', 'All', all) + cats.map((c) => chip(c.id, c.label, all.filter((t) => t.cat === c.id))).join('');
  }

  // ------------------------------------------------------------------ modal / toast / jobs
  function openModal(html, opt = {}) {
    const back = document.createElement('div');
    back.className = 'modal-back';
    back.innerHTML = `<div class="modal${opt.wide ? ' wide' : ''}" role="dialog" aria-modal="true">${html}</div>`;
    $('#modal-root').appendChild(back);
    hydrateIcons(back);
    const close = () => { back.remove(); if (opt.onClose) opt.onClose(); };
    if (!opt.locked) {
      back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
      back.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
    }
    const first = back.querySelector('button.btn-primary, button.btn-danger, button');
    if (first) setTimeout(() => first.focus(), 30);
    return { el: back, close };
  }

  function confirmBox({ title, body, ok = 'Continue', cancel = 'Cancel', danger = false, iconName = 'info' }) {
    return new Promise((resolve) => {
      let done = false;
      const m = openModal(`<h2>${icon(iconName)} ${esc(title)}</h2><div class="mbody">${body}</div>
        <div class="mfoot"><button class="btn" data-m="no">${esc(cancel)}</button><button class="btn ${danger ? 'btn-danger' : 'btn-primary'}" data-m="yes">${esc(ok)}</button></div>`,
      { onClose: () => { if (!done) resolve(false); } });
      m.el.addEventListener('click', (e) => {
        const b = e.target.closest('[data-m]');
        if (!b) return;
        done = true;
        m.close();
        resolve(b.dataset.m === 'yes');
      });
    });
  }

  function infoBox(title, body, iconName = 'info', wide = false) {
    const m = openModal(`<h2>${icon(iconName)} ${esc(title)}</h2><div class="mbody">${body}</div><div class="mfoot"><button class="btn btn-primary" data-m="ok">Got it</button></div>`, { wide });
    m.el.addEventListener('click', (e) => { if (e.target.closest('[data-m]')) m.close(); });
    return m;
  }

  function toast(msg, kind = '') {
    const t = document.createElement('div');
    t.className = 'toast ' + kind;
    t.textContent = msg;
    $('#toast-root').appendChild(t);
    setTimeout(() => t.remove(), kind === 'err' ? 7000 : 4200);
  }

  async function runJob(startPromise, opt) {
    Z.busy = true;
    const m = openModal(`<h2>${icon(opt.iconName || 'bolt')} ${esc(opt.title)}</h2>
      <div class="jobstep"><div class="spinner sm" id="job-spin"></div><span id="job-step">Starting...</span></div>
      <div class="progress"><span id="job-bar" style="width:3%"></span></div>
      <div class="joblog" id="job-log"></div><div id="job-sum"></div><div class="mfoot" id="job-foot"></div>`, { locked: true, wide: true });
    let job = null;
    try {
      const { jobId } = await startPromise;
      for (;;) {
        await sleep(650);
        try { job = await api('/api/job?id=' + encodeURIComponent(jobId)); } catch (e) { if (lost) throw e; continue; }
        $('#job-step', m.el).textContent = job.step || '';
        $('#job-bar', m.el).style.width = Math.max(3, clamp(job.progress)) + '%';
        const log = $('#job-log', m.el);
        log.innerHTML = arr(job.log).map((l) => `<div class="${esc(l.level)}"><span class="dim">${esc(l.t)}</span>&nbsp; ${esc(l.msg)}</div>`).join('');
        log.scrollTop = log.scrollHeight;
        if (job.status !== 'running') break;
      }
    } catch (e) {
      Z.busy = false;
      m.close();
      toast(e.message, 'err');
      throw e;
    }
    Z.busy = false;
    const spin = $('#job-spin', m.el);
    if (spin) spin.outerHTML = job.status === 'done' ? `<span style="color:var(--green)">${icon('check')}</span>` : `<span style="color:var(--red)">${icon('warn')}</span>`;
    $('#job-bar', m.el).style.width = '100%';
    const r = job.result || {};
    let sum = '';
    let autoClose = false;
    if (job.status === 'error') {
      sum = `<div class="warnbox">${icon('warn')}<div>${esc(job.error || 'The task failed.')}</div></div>`;
    } else if (r.restorePointFailed) {
      sum = '';
    } else if (opt.summary) {
      const s = opt.summary(r);
      sum = s.html;
      autoClose = !!s.autoClose;
    }
    $('#job-sum', m.el).innerHTML = sum;
    const foot = $('#job-foot', m.el);
    const needsReboot = r.reboot && job.status === 'done';
    foot.innerHTML = (needsReboot ? `<button class="btn" data-j="reboot">${icon('refresh')} Restart PC now</button>` : '') + `<button class="btn btn-primary" data-j="close">Close</button>`;
    hydrateIcons(m.el);
    const closed = new Promise((resolve) => {
      foot.addEventListener('click', async (e) => {
        const b = e.target.closest('[data-j]');
        if (!b) return;
        if (b.dataset.j === 'reboot') { m.close(); resolve(); await rebootPrompt(); return; }
        m.close();
        resolve();
      });
      if (autoClose && !needsReboot && job.status === 'done') setTimeout(() => { if (m.el.isConnected) { m.close(); resolve(); } }, 900);
      if (r.restorePointFailed) { m.close(); resolve(); }
    });
    if (opt.wait !== false) await closed;
    return job;
  }

  const applySummary = (r) => {
    const results = arr(r.results);
    const failed = results.filter((x) => !x.ok && !x.skipped);
    const html = `<div class="summary"><div class="s"><b style="color:var(--green)">${r.applied || 0}</b><span>applied</span></div>
      <div class="s"><b style="color:${failed.length ? 'var(--red)' : 'var(--muted)'}">${failed.length}</b><span>failed (left unchanged)</span></div>
      <div class="s"><b>${r.skipped || 0}</b><span>not needed</span></div></div>
      ${failed.length ? `<div class="warnbox">${icon('warn')}<div>${failed.map((f) => `<b>${esc(f.name)}</b>: ${esc(f.message)}`).join('<br>')}</div></div>` : ''}
      ${r.reboot ? `<div class="warnbox">${icon('refresh')}<div>Some changes take effect after a restart.</div></div>` : ''}`;
    return { html, autoClose: results.length <= 1 && !failed.length };
  };
  const revertSummary = (r) => {
    const results = arr(r.results);
    const failed = results.filter((x) => !x.ok);
    const html = `<div class="summary"><div class="s"><b style="color:var(--green)">${r.restored || 0}</b><span>restored to original</span></div>
      <div class="s"><b style="color:${failed.length ? 'var(--red)' : 'var(--muted)'}">${failed.length}</b><span>could not be restored</span></div></div>
      ${failed.length ? `<div class="warnbox">${icon('warn')}<div>${failed.map((f) => `<b>${esc(f.name)}</b>: ${esc(f.message)}`).join('<br>')}<br>Use Windows System Restore for these.</div></div>` : ''}`;
    return { html, autoClose: results.length <= 1 && !failed.length };
  };

  async function afterChange() {
    Z.scan = null;
    Z.apps = null;
    Z.rps = null;
    try { await loadState(); } catch (e) { /* shown elsewhere */ }
    render();
  }

  async function applyIds(ids, title) {
    ids = arr(ids);
    if (!ids.length) { toast('Everything here is already applied.', 'ok'); return; }
    let job = await runJob(api('/api/apply', { ids }), { title, summary: applySummary });
    if (job && job.result && job.result.restorePointFailed) {
      const msg = (job.result.restorePoint && job.result.restorePoint.message) || 'Unknown error';
      const go2 = await confirmBox({
        title: 'Windows restore point could not be created',
        body: `<p>${esc(msg)}</p><p>Zenith's own backup still records the original value of everything before it is changed, so <b>Restore Original</b> can undo every change. Continue without a Windows restore point?</p>`,
        ok: 'Continue anyway', iconName: 'warn'
      });
      if (go2) job = await runJob(api('/api/apply', { ids, skipRestorePoint: true }), { title, summary: applySummary });
    }
    await afterChange();
  }

  async function revertIds(ids, title) {
    await runJob(api('/api/revert', { ids: arr(ids) }), { title, iconName: 'restore', summary: revertSummary });
    await afterChange();
  }

  async function restoreAll() {
    const n = arr(Z.state.ledger && Z.state.ledger.items).length;
    if (!n) { infoBox('Nothing to restore', '<p>Zenith has not changed anything on this PC yet, so your PC is already in its original state.</p>', 'shield'); return; }
    const ok = await confirmBox({
      title: 'Restore original state?',
      body: `<p>This undoes <b>all ${plural(n, 'change')}</b> Zenith has made and puts every registry value, service, scheduled task, power plan, startup app and removed app back exactly as it was before.</p><p>You can apply tweaks again afterwards at any time.</p>`,
      ok: 'Restore everything', danger: true, iconName: 'restore'
    });
    if (!ok) return;
    await runJob(api('/api/revert-all', {}), { title: 'Restoring original state', iconName: 'restore', summary: revertSummary });
    Z.startup = null;
    await afterChange();
  }

  async function rebootPrompt() {
    const ok = await confirmBox({ title: 'Restart now?', body: '<p>Save your work first. Windows restarts in 10 seconds.</p>', ok: 'Restart', iconName: 'refresh' });
    if (ok) { await api('/api/reboot', {}); toast('Restarting in 10 seconds...', 'ok'); }
  }

  function tweakInfo(id) {
    const t = byId(id);
    if (!t) return;
    const stateText = { applied: 'Applied by Zenith', drifted: 'Applied by Zenith, but changed back by Windows or another app', optimal: 'Already set this way on your PC - nothing to do', na: t.naReason, off: 'Not applied' }[t.state];
    const action = t.state === 'off' || t.state === 'drifted' ? `<button class="btn btn-primary" data-m="apply">${icon('bolt')} Apply</button>` : '';
    const undo = t.state === 'applied' || t.state === 'drifted' ? `<button class="btn" data-m="undo">${icon('restore')} Undo</button>` : '';
    const m = openModal(`<h2>${esc(t.name)}</h2>
      <div class="row" style="margin-top:10px;flex-wrap:wrap;gap:6px">${tweakBadges(t)}<span class="badge">${esc(catLabel(t.cat))}</span></div>
      <div class="mbody"><p>${esc(t.desc)}</p>${t.details ? `<p>${esc(t.details)}</p>` : ''}
      ${t.warning ? `<div class="warnbox">${icon('warn')}<div>${esc(t.warning)}</div></div>` : ''}
      <p style="margin-top:16px"><b>What Zenith changes</b> <span class="dim">(the original values are saved first)</span></p>
      <div class="changes mono">${arr(t.changes).map((c) => `<div>${esc(c)}</div>`).join('') || '<div>Nothing on this PC</div>'}</div>
      <p style="margin-top:12px" class="small">Status: <b>${esc(stateText)}</b>${t.appliedAt ? ' &middot; ' + esc(fmtDate(t.appliedAt)) : ''}</p></div>
      <div class="mfoot"><button class="btn btn-ghost" data-m="close">Close</button>${undo}${action}</div>`, { wide: true });
    m.el.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-m]');
      if (!b) return;
      m.close();
      if (b.dataset.m === 'apply') await toggleTweak(t.id, true);
      if (b.dataset.m === 'undo') await toggleTweak(t.id, false);
    });
  }

  async function toggleTweak(id, wantOn) {
    const t = byId(id);
    if (!t || Z.busy) { render(); return; }
    if (wantOn) {
      if (t.risk !== 'safe' || t.warning) {
        const ok = await confirmBox({
          title: t.name,
          body: `<p>${esc(t.desc)}</p>${t.warning ? `<div class="warnbox">${icon('warn')}<div>${esc(t.warning)}</div></div>` : ''}<p style="margin-top:12px">This is a <b>${esc(t.risk)}</b> tweak. You can undo it any time from this toggle or with Restore Original.</p>`,
          ok: 'Apply', iconName: t.risk === 'advanced' ? 'warn' : 'info'
        });
        if (!ok) { render(); return; }
      }
      await applyIds([id], t.name);
    } else {
      await revertIds([id], 'Undo: ' + t.name);
    }
  }

  async function applyPreset(name) {
    const s = Z.state;
    const ids = pendingIn(s.presets && s.presets[name]).map((t) => t.id);
    const label = { balanced: 'Balanced preset', performance: 'Performance preset', debloat: 'Debloat preset' }[name] || name;
    if (!ids.length) { toast(label + ' is already fully applied.', 'ok'); return; }
    const hasModerate = ids.some((id) => byId(id).risk !== 'safe');
    const ok = await confirmBox({
      title: 'Apply ' + label + '?',
      body: `<p>Zenith will apply <b>${plural(ids.length, 'tweak')}</b>${hasModerate ? ', including some <b>moderate</b> tweaks with small trade-offs (see their descriptions)' : ' - all of them marked safe'}.</p>
        <p>${s.settings.autoRestorePoint && !(s.session && s.session.restorePointDone) ? 'A Windows restore point is created first, and ' : ''}the original value of everything is backed up before it changes, so you can undo it all with <b>Restore Original</b>.</p>`,
      ok: 'Apply ' + ids.length, iconName: 'bolt'
    });
    if (ok) await applyIds(ids, label);
  }

  // ------------------------------------------------------------------ guides
  const GUIDES = {
    docp: ['Enable D.O.C.P. (XMP) for full RAM speed', `
      <p>Your memory speed is set in the motherboard BIOS. On ASUS boards like your ROG STRIX G15DK the profile is called <b>D.O.C.P.</b> (on others XMP or EXPO).</p>
      <ol><li>Restart the PC and tap <b>Delete</b> (or <b>F2</b>) until the BIOS opens.</li>
      <li>In EZ Mode, look for <b>D.O.C.P.</b> on the main screen and pick the profile shown (for example <b>DDR4-3200</b>). Otherwise press <b>F7</b> for Advanced Mode.</li>
      <li>Advanced Mode: open <b>Ai Tweaker</b> (or Extreme Tweaker) and set <b>Ai Overclock Tuner</b> to <b>D.O.C.P.</b>, then choose the profile.</li>
      <li>Press <b>F10</b> to save and restart. Zenith's My PC page should now show the new speed.</li></ol>
      <div class="warnbox">${icon('info')}<div>If the PC does not start, it restores the old setting by itself after a few tries (or clear CMOS). With four 16 GB sticks, 3200 MT/s is the dependable target. If no D.O.C.P. profile is offered, your sticks are plain 2400 MT/s modules - a 2x32 GB or 4x16 GB DDR4-3200 CL16 kit is then the best FPS upgrade for this PC.</div></div>`],
    rebar: ['Turn on Resizable BAR', `
      <p>Resizable BAR lets your Ryzen CPU access all 8 GB of the RTX 3070's memory at once. It gives 0-10% more FPS depending on the game.</p>
      <ol><li>Update your motherboard BIOS first if it is older than 2021 (ASUS support page for your model).</li>
      <li>In the BIOS (<b>Delete</b> at boot, <b>F7</b> Advanced Mode) go to <b>Advanced &gt; PCI Subsystem Settings</b>.</li>
      <li>Set <b>Above 4G Decoding</b> to <b>Enabled</b> and <b>Re-Size BAR Support</b> to <b>Auto</b>.</li>
      <li>Under <b>Boot &gt; CSM</b>, make sure CSM is <b>Disabled</b> (Windows 11 already boots in UEFI mode).</li>
      <li>Press <b>F10</b> to save. Check <b>NVIDIA Control Panel &gt; System Information</b>: "Resizable BAR: Yes".</li></ol>
      <div class="warnbox">${icon('info')}<div>Early RTX 3070 cards may need NVIDIA's free VBIOS update tool before Resizable BAR shows as enabled.</div></div>`]
  };
  const showGuide = (k) => { const g = GUIDES[k]; if (g) infoBox(g[0], g[1], 'wrench', true); };

  async function doCheckAction(a) {
    if (!a) return;
    if (a.type === 'guide') showGuide(a.target);
    else if (a.type === 'open') { await api('/api/open', { target: a.target }); }
    else if (a.type === 'page') go(a.target);
    else if (a.type === 'tweak') tweakInfo(a.target);
  }

  // ------------------------------------------------------------------ pages
  function checksHtml(checks, limit) {
    const order = { bad: 0, warn: 1, info: 2, good: 3 };
    let list = arr(checks).slice().sort((a, b) => order[a.level] - order[b.level]);
    if (limit) list = list.filter((c) => c.level !== 'good').slice(0, limit);
    if (!list.length) return `<div class="empty">${icon('check')} No problems found.</div>`;
    const ic = { good: 'check', warn: 'warn', bad: 'warn', info: 'info' };
    return list.map((c, i) => `<div class="check"><div class="lvl ${c.level}">${icon(ic[c.level])}</div><div style="min-width:0">
      <h4>${esc(c.title)}</h4><p>${esc(c.detail)}</p>
      ${c.action ? `<button class="btn btn-sm" data-action="check" data-i="${i}" data-limit="${limit || 0}">${esc(c.action.label)}</button>` : ''}</div></div>`).join('');
  }
  let lastChecks = { 0: [], 3: [] };
  function rememberChecks(checks, limit) {
    const order = { bad: 0, warn: 1, info: 2, good: 3 };
    let list = arr(checks).slice().sort((a, b) => order[a.level] - order[b.level]);
    if (limit) list = list.filter((c) => c.level !== 'good').slice(0, limit);
    lastChecks[limit || 0] = list;
  }

  function renderHome() {
    const s = Z.state;
    const score = s.score.percent;
    const pendingAll = tweaks().filter((t) => t.preset && (t.state === 'off' || t.state === 'drifted'));
    const recs = pendingAll.filter((t) => t.risk === 'safe').sort((a, b) => b.gain - a.gain).slice(0, 5);
    const active = tweaks().filter((t) => t.state === 'applied' || t.state === 'drifted').length;
    const live = Z.live || {};
    const scan = Z.scan;
    const rpCount = arr(s.ledger && s.ledger.restorePoints).filter((r) => r.ok).length;
    const startupN = scan ? scan.counts.startupEnabled : null;
    if (scan) rememberChecks(scan.checks, 3);
    return `<div class="dash">
      <div class="card hero">
        ${ring(score, 158, scoreColor(score), 'score', Math.round(score) + '%', 'Optimized')}
        <div style="min-width:0">
          <h2>${score >= 90 ? 'Tuned for gaming' : score >= 60 ? 'Getting there' : 'Room to improve'}</h2>
          <p class="lead">${icon('info')} ${pendingAll.length ? 'Your PC could run smoother' : 'Every recommended tweak is active'}</p>
          <span class="found"><b>${pendingAll.length}</b> optimizations found that can make your system run smoother</span>
          <div class="actions">
            <button class="btn btn-primary" data-action="preset" data-preset="balanced" ${Z.busy ? 'disabled' : ''}>${icon('bolt')} Optimize now</button>
            <button class="btn" data-go="optimize">Review optimizations</button>
          </div>
          ${scan ? `<div class="spec-chips">
            <span class="spec-chip">${icon('cpu')}${esc(String(scan.cpu.name || 'CPU').replace(/\s+\d+-Core Processor/i, ''))}</span>
            <span class="spec-chip">${icon('gpu')}${esc((arr(scan.gpus)[0] || {}).name || 'GPU')}</span>
            <span class="spec-chip">${icon('ram')}${esc(scan.memory.totalGB)} GB ${esc(scan.memory.type)}-${esc(scan.memory.speed)}</span>
            <span class="spec-chip">${icon('monitor')}${esc(scan.os.caption)} ${esc(scan.os.displayVersion)}</span></div>` : ''}
        </div>
      </div>
      <div class="live">
        <div class="card cpu">
          <div class="spark"><div class="label">${icon('cpu')} CPU usage</div><div id="spark-cpu" class="chart">${sparkline(Z.hist.cpu)}</div></div>
          ${ring(live.cpu || 0, 128, usageColor(live.cpu, '#22c55e'), 'cpu')}
        </div>
        <div class="card mini"><div class="label">${icon('gpu')} GPU usage</div>${ring(live.gpu || 0, 122, usageColor(live.gpu, '#3b82f6'), 'gpu')}<div class="meta" id="gpu-meta">${gpuMeta(live)}</div></div>
        <div class="card mini"><div class="label">${icon('ram')} RAM usage</div>${ring(live.ram || 0, 122, usageColor(live.ram, '#ff8a1f'), 'ram')}<div class="meta" id="ram-meta">${ramMeta(live)}</div></div>
      </div>
      <div class="stats">
        <div class="card stat">${icon('rocket')}<div class="num">${active}</div><div class="cap">Optimizations active</div><div class="pill ${active ? 'green' : 'yellow'}">${icon(active ? 'check' : 'warn')}</div><button class="btn btn-sm" data-go="optimize">View optimizations</button></div>
        <div class="card stat">${icon('cpu')}<div class="num" id="stat-procs">${live.processes || (scan ? scan.counts.processes : '-')}</div><div class="cap">Processes running</div><button class="btn btn-sm" data-go="debloat">Reduce background load</button></div>
        <div class="card stat">${icon('power')}<div class="num">${startupN == null ? '-' : startupN}</div><div class="cap">Apps start with Windows</div><button class="btn btn-sm" data-go="startup">Manage startup</button></div>
        <div class="card stat">${icon('shield')}<div class="num">${rpCount}</div><div class="cap">Restore points by Zenith</div><div class="pill ${rpCount ? 'green' : 'yellow'}">${icon(rpCount ? 'check' : 'clock')}</div><button class="btn btn-sm" data-go="backup">Backup & Restore</button></div>
      </div>
      <div class="card recs">
        <div class="card-title"><h2>${icon('sparkle')} Recommendations</h2><span class="muted small">Safe tweaks with the biggest impact</span></div>
        ${recs.length ? recs.map((t) => `<div class="rec"><div class="body"><h4>${esc(t.name)} <span class="badge gain">+${t.gain}%</span></h4><p>${esc(t.desc)}</p></div>
          <button class="info btn-ghost btn btn-sm" data-action="tweak-info" data-id="${esc(t.id)}" title="Details">${icon('info')}</button>${toggle('toggle-tweak', t.id, false, Z.busy, t.name)}</div>`).join('')
          + `<div style="margin-top:14px"><button class="btn btn-primary" data-action="apply-recs" data-ids="${esc(recs.map((t) => t.id).join(','))}" ${Z.busy ? 'disabled' : ''}>Apply all ${recs.length} optimizations</button></div>`
          : `<div class="empty">${icon('check')} All recommended safe tweaks are active.</div>`}
      </div>
      <div class="card checks">
        <div class="card-title"><h2>${icon('monitor')} PC health</h2><button class="btn btn-sm btn-ghost" data-go="pc">Full scan</button></div>
        ${scan ? checksHtml(scan.checks, 3) : '<div class="loading" style="padding:40px 0"><div class="spinner"></div>Scanning hardware...</div>'}
      </div>
      <div class="shortcuts">
        <div class="card shortcut" data-go="backup" role="button" tabindex="0">${icon('archive')}<span>Backups</span></div>
        <div class="card shortcut" data-go="games" role="button" tabindex="0">${icon('gamepad')}<span>Games</span><span class="tagnew">Boost</span></div>
        <div class="card shortcut" data-go="cleaner" role="button" tabindex="0">${icon('sparkle')}<span>Cleaner</span></div>
        <div class="card shortcut" data-go="pc" role="button" tabindex="0">${icon('help')}<span>PC Health</span></div>
      </div>
    </div>`;
  }
  const gpuMeta = (l) => (l.gpuTemp != null ? `${Math.round(l.gpuTemp)}&deg;C &middot; ` : '') + (l.vramTotalGB ? `${l.vramUsedGB} / ${l.vramTotalGB} GB VRAM` : '&nbsp;');
  const ramMeta = (l) => (l.ramTotalGB ? `${l.ramUsedGB} / ${l.ramTotalGB} GB` : '&nbsp;');

  function renderPC() {
    const s = Z.scan;
    if (!s) return '<div class="loading"><div class="spinner"></div><p>Scanning your hardware...</p></div>';
    rememberChecks(s.checks, 0);
    const gpu = arr(s.gpus)[0] || {};
    const st = s.storage || {};
    const usedPct = st.totalBytes ? (st.usedBytes * 100) / st.totalBytes : 0;
    const memBad = arr(s.checks).some((c) => c.id === 'ram-speed' && c.level === 'bad');
    const tb = (b) => fmtBytes(b);
    const kv = (rows) => `<dl class="kv">${rows.filter((r) => r[1] != null && r[1] !== '').map((r) => `<dt>${esc(r[0])}</dt><dd>${r[2] ? r[1] : esc(r[1])}</dd>`).join('')}</dl>`;
    const uptimeDays = s.os.uptimeHours / 24;
    return `
      <div class="specs">
        <div class="card spec"><div class="label">${icon('cpu')} Processor</div><div class="big">${esc(String(s.cpu.name || 'Unknown CPU').replace(/\s+\d+-Core Processor/i, ''))}</div><div class="sm">${s.cpu.cores} cores &middot; ${s.cpu.threads} threads &middot; ${(s.cpu.baseMHz / 1000).toFixed(2)} GHz</div></div>
        <div class="card spec"><div class="label">${icon('ram')} Installed RAM</div><div class="big">${esc(s.memory.totalGB)} GB</div><div class="sm">Speed: <span style="color:${memBad ? 'var(--red)' : 'inherit'}">${esc(s.memory.speed)} MT/s</span> &middot; ${esc(s.memory.type)} &middot; ${plural(s.memory.count, 'stick')}</div></div>
        <div class="card spec"><div class="label">${icon('gpu')} Graphics card</div><div class="big">${gpu.vramBytes ? Math.round(gpu.vramBytes / 1073741824) + ' GB' : '-'}</div><div class="sm">${esc(gpu.name || 'Unknown')}${gpu.nvidiaVersion ? ' &middot; driver ' + esc(gpu.nvidiaVersion) : ''}</div></div>
        <div class="card spec"><div class="label">${icon('disk')} Storage</div><div class="big">${tb(st.totalBytes)}</div><div class="sm">${tb(st.usedBytes)} of ${tb(st.totalBytes)} used</div><div class="progress ${usedPct > 85 ? 'red' : 'blue'}"><span style="width:${usedPct.toFixed(1)}%"></span></div></div>
      </div>
      <div class="card device-bar"><div class="spacer" style="min-width:0"><h3>${esc(s.device.name)}</h3><div class="muted small">${esc(s.device.model)}</div></div>
        <span class="muted small">Scanned ${esc(fmtDate(s.scannedAt))}</span><button class="btn btn-sm" data-action="rescan">${icon('refresh')} Rescan</button></div>
      <div class="cols">
        <div class="card checks"><div class="card-title"><h2>${icon('shield')} Health check</h2></div>${checksHtml(s.checks, 0)}</div>
        <div class="card">
          <div class="card-title"><h2>${icon('info')} Device info</h2></div>
          ${kv([['Device name', s.device.name], ['Processor', `${s.cpu.name} (${(s.cpu.baseMHz / 1000).toFixed(2)} GHz)`], ['Installed RAM', `${s.memory.totalGB} GB (${s.memory.usableGB} GB usable)`],
            ['Graphics card', gpu.name ? `${gpu.name} (${Math.round((gpu.vramBytes || 0) / 1073741824)} GB)` : null], ['Storage', `${tb(st.usedBytes)} of ${tb(st.totalBytes)} used`],
            ['Motherboard', s.device.board], ['BIOS', s.device.bios ? `${s.device.bios}${s.device.biosDate ? ' (' + s.device.biosDate + ')' : ''}` : null], ['System type', `${s.os.arch} operating system, x64-based processor`]])}
          <div class="card-title" style="margin-top:22px"><h2>${icon('monitor')} Windows info</h2></div>
          ${kv([['Edition', s.os.caption], ['Version', s.os.displayVersion], ['Installed on', s.os.installDate], ['OS build', s.os.build],
            ['Up time', uptimeDays >= 1 ? `${uptimeDays.toFixed(1)} days` : `${s.os.uptimeHours} hours`], ['Processes', String(s.counts.processes)], ['Running services', String(s.counts.runningServices)],
            ['Power plan', s.features.powerPlan], ['Memory Integrity', s.features.hvci == null ? null : s.features.hvci ? 'On' : 'Off'], ['GPU scheduling', s.features.hags ? 'On' : 'Off'], ['Game Mode', s.features.gameMode ? 'On' : 'Off']])}
        </div>
      </div>
      <div class="cols">
        <div class="card"><div class="card-title"><h2>${icon('ram')} Memory modules</h2></div>
          <table class="tbl"><thead><tr><th>Slot</th><th>Size</th><th>Running at</th><th>Part number</th></tr></thead><tbody>
          ${arr(s.memory.modules).map((m) => `<tr><td>${esc(m.slot)}</td><td>${esc(m.sizeGB)} GB</td><td>${esc(m.configured)} MT/s${m.rated && m.rated > m.configured ? ` <span class="badge moderate">rated ${esc(m.rated)}</span>` : ''}</td><td class="mono">${esc(m.part)}</td></tr>`).join('')}
          </tbody></table></div>
        <div class="card"><div class="card-title"><h2>${icon('monitor')} Displays</h2></div>
          ${arr(s.displays).length ? `<table class="tbl"><thead><tr><th>Monitor</th><th>Resolution</th><th>Refresh</th><th>Max</th></tr></thead><tbody>
          ${arr(s.displays).map((d) => `<tr><td>${esc(d.name)}${d.primary ? ' <span class="badge">Main</span>' : ''}</td><td>${d.width} x ${d.height}</td><td style="color:${d.maxHzAtRes > d.hz + 1 ? 'var(--red)' : 'inherit'}">${d.hz} Hz</td><td>${d.maxHzAtRes} Hz</td></tr>`).join('')}
          </tbody></table>` : '<div class="empty">No display information</div>'}</div>
      </div>
      <div class="cols">
        <div class="card"><div class="card-title"><h2>${icon('disk')} Drives</h2></div>
          ${arr(st.volumes).map((v) => { const p = v.size ? 100 - (v.free * 100) / v.size : 0; return `<div class="drive"><div class="row"><b>${esc(v.letter)}: ${esc(v.label || 'Local Disk')}</b><span class="muted small">${tb(v.free)} free of ${tb(v.size)}</span></div><div class="progress ${p > 85 ? 'red' : 'blue'}"><span style="width:${p.toFixed(1)}%"></span></div></div>`; }).join('')}
          <div style="margin-top:12px">${arr(st.disks).map((d) => `<div class="row small muted" style="margin-top:6px">${icon('disk')} ${esc(d.name)} &middot; ${esc(d.bus)} ${esc(d.media)} &middot; ${tb(d.size)} &middot; ${esc(d.health)}${d.system ? ' &middot; Windows' : ''}</div>`).join('')}</div></div>
        <div class="card"><div class="card-title"><h2>${icon('wifi')} Network</h2></div>
          ${arr(s.network).map((n) => `<div class="drive"><div class="row"><b>${esc(n.name)}</b><span class="badge ${n.up ? 'safe' : ''}">${n.up ? 'Connected' : 'Not connected'}</span></div><div class="muted small">${esc(n.desc)}${n.up ? ' &middot; ' + esc(n.speed) : ''}</div></div>`).join('') || '<div class="empty">No adapters</div>'}</div>
      </div>`;
  }

  function presetCard(key, title, desc, iconName, color, rec) {
    const ids = arr(Z.state.presets[key]);
    const list = ids.map(byId).filter((t) => t && t.state !== 'na');
    const done = list.filter(isOn).length;
    const pct = list.length ? (done * 100) / list.length : 0;
    const pending = pendingIn(ids).length;
    return `<div class="card preset${rec ? ' rec' : ''}">
      <div class="phead"><div class="picon ${color}">${icon(iconName)}</div><div><h3>${esc(title)}${rec ? ' <span class="badge gain">Recommended</span>' : ''}</h3><div class="muted small">${done} of ${list.length} active</div></div></div>
      <p>${desc}</p>
      <div class="pfoot"><div class="progress ${color === 'blue' ? 'blue' : color === 'orange' ? '' : 'green'}"><span style="width:${pct.toFixed(0)}%"></span></div>
      <button class="btn ${rec ? 'btn-primary' : ''} btn-sm" data-action="preset" data-preset="${key}" ${!pending || Z.busy ? 'disabled' : ''}>${pending ? 'Apply ' + pending : 'Applied'}</button></div></div>`;
  }

  function renderOptimize() {
    const advCount = tweaks().filter((t) => !t.preset && catPage(t.cat) === 'optimize').length;
    return `<div class="presets">
        ${presetCard('balanced', 'Balanced', 'Safe tweaks for every gaming PC: Game Mode, GPU scheduling, power plan, latency and debloat fixes. No trade-offs.', 'shield', 'green', true)}
        ${presetCard('performance', 'Performance', 'Balanced plus tweaks with small trade-offs (fewer service processes, SysMain off, network power saving off) for maximum FPS.', 'bolt', 'orange', false)}
        <div class="card preset"><div class="phead"><div class="picon blue">${icon('sliders')}</div><div><h3>Custom</h3><div class="muted small">${advCount} manual-only tweaks</div></div></div>
          <p>Pick individual tweaks below. Advanced and experimental tweaks are never applied by a preset - read their details first.</p>
          <div class="pfoot"><span class="muted small">Every toggle can be switched back off.</span></div></div>
      </div>
      <div class="toolbar"><div class="cats">${catChips('optimize', Z.ui.cat, 'cat')}</div>
        <div class="search">${icon('search')}<input type="search" id="q" placeholder="Search tweaks" value="${esc(Z.ui.q)}" aria-label="Search tweaks"></div>
        <label class="row small muted" style="gap:8px">${toggle('hide-applied', 'hide', Z.ui.hideApplied, false, 'Hide active tweaks')} Hide active</label></div>
      <div class="tweak-grid" id="tweak-grid">${tweakGrid('optimize', Z.ui.cat)}</div>`;
  }

  function renderDebloat() {
    const ids = arr(Z.state.presets.debloat);
    const pending = pendingIn(ids).length;
    const apps = Z.apps;
    if (apps && !Z.ui.appSel) Z.ui.appSel = new Set(apps.filter((a) => a.installed && a.recommended).map((a) => a.name));
    const sel = Z.ui.appSel || new Set();
    const installed = apps ? apps.filter((a) => a.installed) : [];
    const removed = apps ? apps.filter((a) => !a.installed && a.removedByZenith) : [];
    return `<div class="card hero" style="padding:20px 24px">
        <div class="picon orange" style="width:56px;height:56px;border-radius:16px;display:flex;align-items:center;justify-content:center;background:var(--accent-soft);color:var(--accent)">${icon('trash')}</div>
        <div style="flex:1;min-width:0"><h2 style="font-size:20px">Windows debloat</h2>
          <p class="muted" style="margin-top:4px">Turn off telemetry, ads, Widgets, Copilot, Bing search and always-on background services. Everything is reversible, and nothing that Windows Update, the Microsoft Store, Xbox sign-in or your games need is touched.</p></div>
        <button class="btn btn-primary" data-action="preset" data-preset="debloat" ${!pending || Z.busy ? 'disabled' : ''}>${icon('bolt')} ${pending ? `Apply ${pending} safe debloat tweaks` : 'All safe debloat tweaks active'}</button>
      </div>
      <div class="toolbar"><div class="cats">${catChips('debloat', Z.ui.dcat, 'dcat')}</div>
        <div class="search">${icon('search')}<input type="search" id="q" placeholder="Search" value="${esc(Z.ui.q)}" aria-label="Search tweaks"></div></div>
      <div class="tweak-grid" id="tweak-grid">${tweakGrid('debloat', Z.ui.dcat)}</div>
      <div class="section-title"><h2>${icon('archive')} Bloatware apps</h2>
        <button class="btn btn-primary btn-sm" data-action="remove-apps" ${!sel.size || Z.busy ? 'disabled' : ''}>Remove selected (${sel.size})</button></div>
      <div class="card list-card">
        ${!apps ? '<div class="loading" style="padding:40px"><div class="spinner"></div>Checking installed apps...</div>' : ''}
        ${apps && !installed.length && !removed.length ? '<div class="empty">No bloatware apps from the list are installed.</div>' : ''}
        <div class="list">
        ${installed.map((a) => `<label class="lrow"><input type="checkbox" class="checkbox" data-action="app-sel" data-name="${esc(a.name)}" ${sel.has(a.name) ? 'checked' : ''}>
          <div class="avatar" style="background:${avatarColor(a.label)}">${esc(a.label[0])}</div>
          <div class="body"><h4>${esc(a.label)}${a.recommended ? ' <span class="badge safe">Recommended</span>' : ''}</h4><div class="sub">${esc(a.note)} &middot; <span class="mono">${esc(a.name)}</span></div></div></label>`).join('')}
        ${removed.map((a) => `<div class="lrow"><div style="width:18px"></div><div class="avatar" style="background:#2a3550">${esc(a.label[0])}</div>
          <div class="body"><h4>${esc(a.label)} <span class="badge">Removed by Zenith</span></h4><div class="sub">${esc(a.note)}</div></div>
          <button class="btn btn-sm" data-action="restore-app" data-name="${esc(a.name)}" ${Z.busy ? 'disabled' : ''}>${icon('restore')} Restore</button></div>`).join('')}
        </div></div>
      <p class="muted small" style="margin-top:10px">Apps are removed for your account only. "Restore" (or Restore Original) reinstalls them from the copy Windows keeps; if Windows has cleaned that copy up, reinstall the app from the Microsoft Store.</p>`;
  }

  function renderStartup() {
    const items = Z.startup;
    if (!items) return '<div class="loading"><div class="spinner"></div><p>Reading startup apps...</p></div>';
    const on = items.filter((i) => i.enabled).length;
    const ms = /^(securityhealth|windows defender)/i;
    return `<div class="card hero" style="padding:20px 24px">
        ${ring(items.length ? (on * 100) / items.length : 0, 96, '#ff8a1f', null, String(on), 'enabled')}
        <div style="flex:1;min-width:0"><h2 style="font-size:20px">${plural(on, 'app')} start with Windows</h2>
        <p class="muted" style="margin-top:4px">Every startup app stays running in the background while you play. Turning one off only stops it starting automatically - it is not uninstalled, and you can still open it yourself. Zenith uses the same switch as Task Manager.</p></div>
        <button class="btn" data-action="reload-startup">${icon('refresh')} Refresh</button></div>
      <div class="card list-card" style="margin-top:18px"><div class="list">
        ${items.length ? items.map((i) => `<div class="lrow"><div class="avatar" style="background:${avatarColor(i.name)}">${esc((i.name || '?')[0].toUpperCase())}</div>
          <div class="body"><h4>${esc(i.name)} <span class="badge">${esc(i.scope)}</span>${ms.test(i.name) ? ' <span class="badge safe">Keep on</span>' : ''}</h4>
          <div class="sub">${i.publisher ? esc(i.publisher) + ' &middot; ' : ''}<span class="mono">${esc(i.command)}</span></div></div>
          <span class="small ${i.enabled ? '' : 'dim'}" style="width:62px;text-align:right">${i.enabled ? 'Enabled' : 'Disabled'}</span>
          ${toggle('toggle-startup', i.id, i.enabled, Z.busy, i.name)}</div>`).join('') : '<div class="empty">No startup apps found.</div>'}
      </div></div>`;
  }

  function renderCleaner() {
    const c = Z.cleaner;
    const res = Z.cleanerResult;
    const tip = `<div class="card" style="margin-top:18px"><div class="card-title"><h2>${icon('info')} What Zenith never deletes</h2></div>
      <ul class="tips"><li><b>Your files</b> - documents, downloads, pictures and game saves are never touched.</li>
      <li><b>Shader caches</b> (NVIDIA / DirectX) - deleting them makes games stutter while they rebuild, so Zenith keeps them.</li>
      <li><b>Files in use</b> - temporary files used in the last 24 hours and locked files are skipped.</li>
      <li>Want ~25 GB more? <a href="#" data-action="tweak-info" data-id="power.hibernate">Disable hibernation</a> deletes hiberfil.sys.</li></ul></div>`;
    if (!c) {
      return `<div class="card hero" style="padding:26px">
        <div class="picon" style="width:64px;height:64px;border-radius:18px;display:flex;align-items:center;justify-content:center;background:rgba(59,130,246,.14);color:var(--blue-2)">${icon('sparkle')}</div>
        <div style="flex:1"><h2 style="font-size:21px">Find space you can safely free</h2>
        <p class="muted" style="margin-top:4px">Zenith checks temporary files, update caches, crash dumps and other leftovers, and shows you exactly how much each one uses before anything is deleted.</p>
        ${res ? `<p style="margin-top:10px;color:var(--green)">${icon('check')} Last clean freed <b>${fmtBytes(res.freed)}</b>.</p>` : ''}</div>
        <button class="btn btn-primary btn-lg" data-action="clean-scan" ${Z.busy ? 'disabled' : ''}>${icon('search')} Analyze</button></div>${tip}`;
    }
    if (!Z.ui.cleanSel) Z.ui.cleanSel = new Set(c.filter((x) => x.default && x.bytes !== 0).map((x) => x.id));
    const sel = Z.ui.cleanSel;
    const total = c.filter((x) => sel.has(x.id) && x.bytes > 0).reduce((a, x) => a + x.bytes, 0);
    return `<div class="card clean-total"><div><div class="label">Selected to clean</div><div class="num">${fmtBytes(total)}</div></div>
        <div class="spacer"></div><button class="btn" data-action="clean-scan" ${Z.busy ? 'disabled' : ''}>${icon('refresh')} Re-analyze</button>
        <button class="btn btn-primary btn-lg" data-action="clean-run" ${!sel.size || Z.busy ? 'disabled' : ''}>${icon('sparkle')} Clean selected</button></div>
      <div class="card list-card" style="margin-top:18px"><div class="list">
        ${c.map((x) => `<label class="lrow"><input type="checkbox" class="checkbox" data-action="clean-sel" data-id="${esc(x.id)}" ${sel.has(x.id) ? 'checked' : ''}>
          <div class="body"><h4>${esc(x.label)}</h4><div class="sub">${esc(x.desc)}</div></div>
          <b style="min-width:80px;text-align:right">${x.bytes < 0 ? '<span class="muted small">varies</span>' : fmtBytes(x.bytes)}</b></label>`).join('')}
      </div></div>${tip}`;
  }

  function renderGames() {
    const games = Z.games;
    const boost = Z.boost;
    if (boost && !Z.ui.boostSel) Z.ui.boostSel = new Set(boost.filter((b) => b.default).map((b) => b.proc));
    const bsel = Z.ui.boostSel || new Set();
    const initials = (n) => n.split(/[\s:]+/).filter(Boolean).slice(0, 3).map((w) => w[0]).join('').toUpperCase();
    return `<div class="boost">
      <div class="card boost-hero">
        <div class="row"><div class="picon blue" style="width:48px;height:48px;border-radius:14px;display:flex;align-items:center;justify-content:center;background:rgba(59,130,246,.16);color:var(--blue-2)">${icon('rocket')}</div>
          <div><h2>Game Boost</h2><div class="muted small">Run it right before you start a match</div></div></div>
        <p class="muted">Closes the background apps you tick, frees cached standby memory and flushes the DNS cache. Nothing is changed permanently - closed apps simply start again next time you open them.</p>
        ${!boost ? '<div class="row muted small"><div class="spinner sm"></div> Looking for background apps...</div>'
          : boost.length ? `<div class="list">${boost.map((b) => `<label class="lrow" style="padding:9px 0"><input type="checkbox" class="checkbox" data-action="boost-sel" data-proc="${esc(b.proc)}" ${bsel.has(b.proc) ? 'checked' : ''}>
              <div class="body"><h4>${esc(b.label)}</h4><div class="sub">${plural(b.count, 'process', 'processes')} &middot; ${b.memMB} MB RAM</div></div></label>`).join('')}</div>`
            : '<p class="muted small">No known background apps are running right now.</p>'}
        <div><button class="btn btn-blue btn-lg" data-action="boost-run" ${Z.busy ? 'disabled' : ''}>${icon('bolt')} Boost now</button></div>
      </div>
      <div class="card"><div class="card-title"><h2>${icon('gpu')} Best settings for your RTX 3070</h2></div>
        <ul class="tips">
          <li><b>NVIDIA Reflex: On + Boost</b> in every game that has it - the biggest input-lag win there is.</li>
          <li><b>G-SYNC / FreeSync monitor?</b> Turn G-SYNC on in NVIDIA Control Panel, V-Sync <b>On</b> there and <b>Off</b> in-game, and cap FPS about 3 below your refresh rate (e.g. 141 for 144 Hz).</li>
          <li><b>DLSS Quality</b> at 1440p gives a large FPS boost with almost no visible difference.</li>
          <li>NVIDIA Control Panel &gt; Manage 3D settings: <b>Power management mode: Prefer maximum performance</b> and <b>Shader Cache Size: 10 GB</b> or more.</li>
          <li>Play in <b>borderless or exclusive fullscreen</b> on your main monitor and close browser tabs with video.</li>
        </ul>
        <div class="row" style="margin-top:6px"><button class="btn btn-sm" data-action="open" data-target="graphics">${icon('external')} Windows graphics settings</button><button class="btn btn-sm" data-action="open" data-target="nvidia-drivers">${icon('external')} NVIDIA drivers</button></div>
      </div></div>
      <div class="section-title"><h2>${icon('gamepad')} My games</h2><span class="muted small">Steam, Epic Games and Riot libraries</span></div>
      ${!games ? '<div class="loading" style="padding:60px 0"><div class="spinner"></div>Looking for games...</div>'
        : games.length ? `<div class="games">${games.map((g) => `<div class="card game"><div class="art" style="background-image:linear-gradient(160deg, ${avatarColor(g.name)}, #0e1424)">
            <div class="initials">${esc(initials(g.name))}</div>
            ${g.image ? `<img data-fallback src="${esc(g.image)}" alt="" referrerpolicy="no-referrer" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">` : ''}</div>
          <div class="gbody"><h4 title="${esc(g.name)}">${esc(g.name)}</h4><div class="gfoot"><span class="badge">${esc(g.platform)}</span>
          <button class="btn btn-primary btn-sm" data-action="launch" data-id="${esc(g.id)}">${icon('play')} Play</button></div></div></div>`).join('')}</div>`
          : '<div class="card empty">No Steam, Epic Games or Riot games were found on this PC.</div>'}`;
  }

  function renderBackup() {
    const s = Z.state;
    const L = s.ledger || {};
    const items = arr(L.items);
    const hist = arr(L.history);
    const rps = Z.rps;
    return `<div class="safety">
      <div class="card restore-hero"><div class="shield">${icon('shield')}</div>
        <div style="min-width:0"><h2>Restore Original State</h2>
        <p>Undo ${items.length ? `all <b style="color:var(--text)">${plural(items.length, 'change')}</b>` : 'every change'} Zenith has made and put your PC back exactly how it was - registry values, services, scheduled tasks, power plan, startup apps and removed apps.</p>
        <div class="row" style="flex-wrap:wrap"><button class="btn btn-danger btn-lg" data-action="restore-all" ${!items.length || Z.busy ? 'disabled' : ''}>${icon('restore')} Restore original state</button>
        <button class="btn" data-action="new-rp" ${Z.busy ? 'disabled' : ''}>${icon('shield')} Create restore point</button>
        <button class="btn" data-action="open" data-target="system-restore">${icon('external')} Windows System Restore</button></div></div></div>
      <div class="card"><div class="card-title"><h2>${icon('lock')} Three layers of protection</h2></div>
        <div class="layers">
          <div class="layer"><div class="n">1</div><div><h4>Zenith backup</h4><p>Before anything changes, its original value is saved to <span class="mono">${esc(L.path || '')}</span>. Undo uses exactly that copy.</p></div></div>
          <div class="layer"><div class="n">2</div><div><h4>Windows restore point</h4><p>${s.settings.autoRestorePoint ? 'Created automatically before the first change of every session.' : 'Automatic restore points are off in Settings.'} Roll back the whole system from Windows System Restore.</p></div></div>
          <div class="layer"><div class="n">3</div><div><h4>Emergency Restore.bat</h4><p>In the Zenith folder. Undoes everything from a console window, even if this app cannot open. If Windows ever fails to start, open <b>Troubleshoot &gt; Advanced options &gt; System Restore</b> from the recovery screen.</p></div></div>
        </div></div>
    </div>
    <div class="section-title"><h2>${icon('archive')} Changes made by Zenith</h2><span class="muted small">${plural(items.length, 'item')}</span></div>
    <div class="card list-card"><div class="list">
      ${items.length ? items.map((i) => `<div class="lrow"><div class="body"><h4>${esc(i.name)} <span class="badge">${esc(catLabel(i.category))}</span>${i.partial ? ' <span class="badge advanced">Undo incomplete</span>' : ''}</h4>
        <div class="sub">Applied ${esc(fmtDate(i.appliedAt))} &middot; ${plural(i.changes, 'saved original value')}</div></div>
        <button class="btn btn-sm" data-action="undo-entry" data-id="${esc(i.id)}" data-name="${esc(i.name)}" ${Z.busy ? 'disabled' : ''}>${icon('restore')} Undo</button></div>`).join('')
        : '<div class="empty">Zenith has not changed anything yet - your PC is in its original state.</div>'}
    </div></div>
    <div class="cols">
      <div class="card"><div class="card-title"><h2>${icon('shield')} Windows restore points</h2><button class="btn btn-sm btn-ghost" data-action="reload-rps">${icon('refresh')}</button></div>
        ${!rps ? '<div class="row muted small"><div class="spinner sm"></div> Loading...</div>'
          : rps.length ? `<div class="log">${rps.slice(0, 12).map((r) => `<div class="entry"><span class="when">${esc(fmtDate(r.time))}</span><span>${esc(r.description)}</span></div>`).join('')}</div>` : '<div class="empty">No restore points yet.</div>'}</div>
      <div class="card"><div class="card-title"><h2>${icon('clock')} Activity</h2></div>
        ${hist.length ? `<div class="log">${hist.map((h) => `<div class="entry"><span class="when">${esc(fmtDate(h.time))}</span><span class="${h.ok ? '' : 'bad'}"><b>${esc(h.action)}</b> &middot; ${esc(h.detail)}</span></div>`).join('')}</div>` : '<div class="empty">No activity yet.</div>'}</div>
    </div>`;
  }

  function renderSettings() {
    const s = Z.state;
    return `<div class="cols" style="margin-top:0">
      <div class="card"><div class="card-title"><h2>${icon('shield')} Safety</h2></div>
        <div class="lrow" style="padding:12px 0"><div class="body"><h4>Create a restore point before changes</h4><div class="sub" style="white-space:normal">Before the first change in each session, Zenith asks Windows to create a System Restore point. Recommended.</div></div>${toggle('setting', 'autoRestorePoint', s.settings.autoRestorePoint, false, 'Automatic restore points')}</div>
        <div class="lrow" style="padding:12px 0"><div class="body"><h4>Show advanced & experimental tweaks</h4><div class="sub" style="white-space:normal">Tweaks with real trade-offs (e.g. Memory Integrity, MSI mode). They are never part of a preset.</div></div>${toggle('setting', 'showAdvanced', s.settings.showAdvanced, false, 'Show advanced tweaks')}</div>
      </div>
      <div class="card"><div class="card-title"><h2>${icon('wrench')} Tools</h2></div>
        <div class="list">
          <div class="lrow" style="padding:11px 0"><div class="body"><h4>Desktop shortcut</h4><div class="sub">Start Zenith from your desktop with its own icon.</div></div><button class="btn btn-sm" data-action="shortcut">Create</button></div>
          <div class="lrow" style="padding:11px 0"><div class="body"><h4>Repair Windows files</h4><div class="sub">Runs DISM RestoreHealth and SFC to fix corrupted system files (15-30 min).</div></div><button class="btn btn-sm" data-action="repair" ${Z.busy ? 'disabled' : ''}>Run</button></div>
          <div class="lrow" style="padding:11px 0"><div class="body"><h4>Restart Explorer</h4><div class="sub">Applies taskbar, context-menu and File Explorer tweaks without signing out.</div></div><button class="btn btn-sm" data-action="explorer">Restart</button></div>
          <div class="lrow" style="padding:11px 0"><div class="body"><h4>Backup folder</h4><div class="sub mono">${esc(s.dataDir)}</div></div><button class="btn btn-sm" data-action="open" data-target="data-folder">Open</button></div>
          <div class="lrow" style="padding:11px 0"><div class="body"><h4>Restart PC</h4><div class="sub">Some tweaks only take effect after a restart.</div></div><button class="btn btn-sm" data-action="reboot">Restart</button></div>
        </div></div>
    </div>
    <div class="card" style="margin-top:18px"><div class="card-title"><h2>${icon('info')} About Zenith</h2><span class="muted small">v${esc(s.version)} &middot; Claude PC Tweaks</span></div>
      <p class="muted">Zenith is a transparent, open optimizer: every tweak shows exactly which setting it changes, saves the original first, and can be undone. Built and tuned for an AMD Ryzen 7 5800X, NVIDIA RTX 3070 and 64 GB DDR4 gaming PC on Windows 11.</p>
      <p style="margin-top:12px"><b>Zenith never:</b></p>
      <ul class="tips" style="margin-top:6px"><li>turns off Windows Defender, Windows Update, the firewall or UAC</li><li>removes the Microsoft Store, Edge, Xbox sign-in or any system component</li>
      <li>edits boot settings (BCD), disables the page file or CPU power states</li><li>runs a "registry cleaner" or deletes drivers or your personal files</li></ul>
    </div>`;
  }

  // ------------------------------------------------------------------ live monitor
  let liveTick = 0;
  async function pollLive() {
    liveTick++;
    const hidden = document.hidden;
    if (!hidden || liveTick % 12 === 0) {
      try {
        const l = await api('/api/live');
        Z.live = l;
        for (const k of ['cpu', 'gpu', 'ram']) { Z.hist[k].push(Number(l[k]) || 0); if (Z.hist[k].length > 60) Z.hist[k].shift(); }
        if (route() === 'home') {
          setRing('cpu', l.cpu); setRing('gpu', l.gpu); setRing('ram', l.ram);
          const sp = $('#spark-cpu'); if (sp) sp.innerHTML = sparkline(Z.hist.cpu);
          const gm = $('#gpu-meta'); if (gm) gm.innerHTML = gpuMeta(l);
          const rm = $('#ram-meta'); if (rm) rm.innerHTML = ramMeta(l);
          const pr = $('#stat-procs'); if (pr && l.processes) pr.textContent = l.processes;
        }
      } catch (e) { /* engine busy */ }
    }
    setTimeout(pollLive, 2500);
  }

  // ------------------------------------------------------------------ events
  document.addEventListener('click', async (e) => {
    const nav = e.target.closest('[data-go]');
    if (nav) { e.preventDefault(); go(nav.dataset.go); return; }
    const el = e.target.closest('[data-action]');
    if (!el || el.tagName === 'INPUT') return;
    const a = el.dataset.action;
    try {
      switch (a) {
        case 'tweak-info': e.preventDefault(); tweakInfo(el.dataset.id); break;
        case 'apply-one': await applyIds([el.dataset.id], byId(el.dataset.id).name); break;
        case 'preset': await applyPreset(el.dataset.preset); break;
        case 'apply-recs': {
          const ids = el.dataset.ids.split(',').filter(Boolean);
          await applyIds(ids, 'Applying ' + plural(ids.length, 'optimization'));
          break;
        }
        case 'cat': Z.ui.cat = el.dataset.cat; render(); break;
        case 'dcat': Z.ui.dcat = el.dataset.cat; render(); break;
        case 'restore-all': await restoreAll(); break;
        case 'reboot': await rebootPrompt(); break;
        case 'rescan': Z.scan = null; render(); await loadScan(true); render(); break;
        case 'check': { const list = lastChecks[Number(el.dataset.limit) || 0] || []; await doCheckAction((list[Number(el.dataset.i)] || {}).action); break; }
        case 'open': await api('/api/open', { target: el.dataset.target }); break;
        case 'undo-entry': await revertIds([el.dataset.id], 'Undo: ' + el.dataset.name); Z.startup = null; break;
        case 'new-rp':
          await runJob(api('/api/restore-point', {}), { title: 'Creating a Windows restore point', iconName: 'shield', summary: (r) => ({ html: r.ok ? `<div class="summary"><div class="s"><b style="color:var(--green)">${icon('check')}</b><span>${esc(r.message)}</span></div></div>` : `<div class="warnbox">${icon('warn')}<div>${esc(r.message)}</div></div>` }) });
          await afterChange();
          break;
        case 'reload-rps': Z.rps = null; render(); break;
        case 'reload-startup': Z.startup = null; render(); break;
        case 'remove-apps': {
          const names = Array.from(Z.ui.appSel || []);
          if (!names.length) break;
          const ok = await confirmBox({ title: `Remove ${plural(names.length, 'app')}?`, body: `<p>${names.map((n) => esc((Z.apps.find((x) => x.name === n) || {}).label || n)).join(', ')}</p><p>They are removed for your account. You can restore them from this page or with Restore Original.</p>`, ok: 'Remove', iconName: 'trash' });
          if (!ok) break;
          let job = await runJob(api('/api/apps/remove', { names }), { title: 'Removing apps', iconName: 'trash', summary: applySummary });
          if (job.result && job.result.restorePointFailed) {
            if (await confirmBox({ title: 'Windows restore point could not be created', body: `<p>${esc(job.result.restorePoint.message)}</p><p>Continue without it? Zenith's own backup can still restore the apps.</p>`, ok: 'Continue anyway', iconName: 'warn' })) {
              job = await runJob(api('/api/apps/remove', { names, skipRestorePoint: true }), { title: 'Removing apps', iconName: 'trash', summary: applySummary });
            }
          }
          Z.ui.appSel = null;
          await afterChange();
          break;
        }
        case 'restore-app':
          await runJob(api('/api/apps/restore', { names: [el.dataset.name] }), { title: 'Restoring app', iconName: 'restore', summary: revertSummary });
          await afterChange();
          break;
        case 'clean-scan': {
          const job = await runJob(api('/api/cleaner/scan', {}), { title: 'Analyzing disk space', iconName: 'search', summary: () => ({ html: '', autoClose: true }) });
          if (job.status === 'done') { Z.cleaner = arr(job.result.items); Z.ui.cleanSel = null; }
          render();
          break;
        }
        case 'clean-run': {
          const ids = Array.from(Z.ui.cleanSel || []);
          const job = await runJob(api('/api/cleaner/clean', { ids }), { title: 'Cleaning', iconName: 'sparkle', summary: (r) => ({ html: `<div class="summary"><div class="s"><b style="color:var(--green)">${fmtBytes(r.freed)}</b><span>freed</span></div></div>` }) });
          if (job.status === 'done') { Z.cleanerResult = job.result; Z.cleaner = null; Z.ui.cleanSel = null; Z.scan = null; }
          render();
          break;
        }
        case 'boost-run': {
          el.disabled = true;
          const r = await api('/api/boost', { procs: Array.from(Z.ui.boostSel || []) });
          toast(`Boosted: closed ${plural(arr(r.closed).length, 'app')}, ${r.purged ? 'freed standby memory, ' : ''}${r.dns ? 'flushed DNS' : ''}. Have a good game!`, 'ok');
          Z.boost = null; Z.ui.boostSel = null; render();
          break;
        }
        case 'launch': await api('/api/games/launch', { id: el.dataset.id }); toast('Launching...', 'ok'); break;
        case 'shortcut': { const r = await api('/api/shortcut', {}); toast('Shortcut created: ' + r.path, 'ok'); break; }
        case 'explorer': await api('/api/explorer-restart', {}); toast('Explorer restarted.', 'ok'); break;
        case 'repair':
          await runJob(api('/api/repair', {}), { title: 'Repairing Windows files', iconName: 'wrench', summary: (r) => ({ html: `<div class="warnbox">${icon('info')}<div>${esc(r.message)}</div></div>` }) });
          await afterChange();
          break;
        default: break;
      }
    } catch (err) {
      if (!lost) toast(err.message, 'err');
    }
  });

  document.addEventListener('change', async (e) => {
    const el = e.target;
    const a = el.dataset && el.dataset.action;
    if (!a) return;
    try {
      if (a === 'toggle-tweak') { await toggleTweak(el.dataset.id, el.checked); }
      else if (a === 'hide-applied') { Z.ui.hideApplied = el.checked; $('#tweak-grid').innerHTML = tweakGrid('optimize', Z.ui.cat); hydrateIcons($('#tweak-grid')); }
      else if (a === 'toggle-startup') {
        Z.busy = true;
        const r = await api('/api/startup', { id: el.dataset.id, enabled: el.checked });
        Z.busy = false;
        Z.startup = arr(r.items);
        Z.scan = null;
        toast((el.checked ? 'Enabled: ' : 'Disabled at startup: ') + (Z.startup.find((i) => i.id === el.dataset.id) || {}).name, 'ok');
        await loadState();
        render();
      } else if (a === 'setting') {
        const body = {}; body[el.dataset.id] = el.checked;
        Z.state.settings = await api('/api/settings', body);
        updateChrome();
        toast('Saved.', 'ok');
      } else if (a === 'app-sel') {
        if (!Z.ui.appSel) Z.ui.appSel = new Set();
        if (el.checked) Z.ui.appSel.add(el.dataset.name); else Z.ui.appSel.delete(el.dataset.name);
        const b = $('[data-action="remove-apps"]'); if (b) { b.textContent = `Remove selected (${Z.ui.appSel.size})`; b.disabled = !Z.ui.appSel.size; }
      } else if (a === 'clean-sel') {
        if (el.checked) Z.ui.cleanSel.add(el.dataset.id); else Z.ui.cleanSel.delete(el.dataset.id);
        render();
      } else if (a === 'boost-sel') {
        if (el.checked) Z.ui.boostSel.add(el.dataset.proc); else Z.ui.boostSel.delete(el.dataset.proc);
      }
    } catch (err) {
      Z.busy = false;
      if (!lost) toast(err.message, 'err');
      render();
    }
  });

  document.addEventListener('input', (e) => {
    if (e.target.id !== 'q') return;
    Z.ui.q = e.target.value;
    const r = route();
    const grid = $('#tweak-grid');
    if (grid) { grid.innerHTML = tweakGrid(r === 'debloat' ? 'debloat' : 'optimize', r === 'debloat' ? Z.ui.dcat : Z.ui.cat); hydrateIcons(grid); }
  });

  document.addEventListener('keydown', (e) => {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[role="button"][data-go]')) { e.preventDefault(); go(e.target.dataset.go); }
  });

  window.addEventListener('hashchange', () => { Z.ui.q = ''; render(); $('#view').scrollTop = 0; });
  window.addEventListener('pagehide', () => { try { navigator.sendBeacon('/api/bye?t=' + encodeURIComponent(token || '')); } catch (e) { /* ignore */ } });

  // ------------------------------------------------------------------ boot
  async function boot() {
    hydrateIcons();
    renderNav();
    if (!token) { connectionLost('This window was opened without a session.'); return; }
    try { await loadState(); } catch (e) { return; }
    render();
    pollLive();
  }
  boot();
})();
