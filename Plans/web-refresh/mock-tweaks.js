// web-refresh mock-up only (Plans/web-refresh.md): the small markup changes the review's After
// pictures needed, made in the browser. Shows what each phase has to build properly.
(() => {
  const MARK = `<svg class="mock-mark" viewBox="0 0 32 32" fill="none" aria-hidden="true">
    <rect x="3.5" y="7.5" width="21" height="17" rx="4" stroke="currentColor" stroke-width="2"/>
    <path d="M24.5 13.5h4v6h-4a3 3 0 0 1 0-6z" stroke="currentColor" stroke-width="1.8" fill="var(--bg)"/>
    <polyline points="7,21 11,17.5 14.5,19.5 20,12.5" stroke="var(--good)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`;
  // 1. The app's mark beside its name (top bar) and above it (sign-in)
  document.querySelectorAll('header h1, .login h1').forEach(h => {
    if (h.dataset.mocked) return; h.dataset.mocked = 1;
    if (h.closest('header')) h.insertAdjacentHTML('afterbegin', MARK);
    else h.insertAdjacentHTML('beforebegin', MARK);
  });
  // 2. Email + Log out collapse into one account button
  const who = document.getElementById('userEmail');
  if (who && !document.querySelector('.mock-avatar')) {
    const out = who.nextElementSibling;
    who.style.display = 'none'; if (out) out.style.display = 'none';
    const b = document.createElement('button');
    b.className = 'mock-avatar'; b.title = 'Account';
    b.innerHTML = '<span class="av">DA</span><span class="who">Demo Admin<small>' + who.textContent.trim() + '</small></span>';
    who.parentElement.appendChild(b);
    window.dispatchEvent(new Event('resize'));
  }
  // 3. Dates people read: "Nov 19" instead of 2026-11-19
  const M = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const yearNow = String(new Date().getFullYear());
  const walker = document.createTreeWalker(document.getElementById('app'), NodeFilter.SHOW_TEXT);
  const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const n of nodes) {
    if (!/\d{4}-\d{2}-\d{2}/.test(n.nodeValue)) continue;
    if (n.parentElement && n.parentElement.closest('script,style,select,option,input,textarea')) continue;
    n.nodeValue = n.nodeValue.replace(/(\d{4})-(\d{2})-(\d{2})/g,
      (_, y, m, d) => `${M[+m - 1]} ${+d}` + (y === yearNow ? '' : `, ${y}`));
  }
  // 4. Net worth chart: whole axis labels, set inside the plot
  const host = document.getElementById('networthChart');
  if (host && !host.querySelector('.mock-axis')) {
    const svg = host.querySelector('svg');
    if (svg) {
      const vb = svg.viewBox.baseVal, sr = svg.getBoundingClientRect(), hr = host.getBoundingClientRect();
      svg.querySelectorAll('text[text-anchor="end"]').forEach(t => {
        if (!/^-?\$/.test(t.textContent.trim())) return;
        t.style.display = 'none';
        const v = parseFloat(t.textContent.replace(/[^0-9.-]/g, ''));
        const d = document.createElement('div'); d.className = 'mock-axis';
        d.textContent = Math.abs(v) >= 1000 ? '$' + (v / 1000).toFixed(1) + 'k' : '$' + v.toFixed(0);
        d.style.left = (sr.left - hr.left + (34 / vb.width) * sr.width) + 'px';
        d.style.top = (sr.top - hr.top + ((+t.getAttribute('y') - 3) / vb.height) * sr.height) + 'px';
        host.appendChild(d);
      });
    }
  }
  // 5. Icons for the page buttons (shown by the bolder, sidebar variant)
  const ICO = {
    navDashboard: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    navNetworth: '<path d="M12 3 3 8l9 5 9-5-9-5z"/><path d="m3 13 9 5 9-5"/>',
    navAccounts: '<path d="M3 20h18"/><path d="m4 15 5-5 4 3 7-8"/>',
    navSubscriptions: '<path d="M17 3l3 3-3 3"/><path d="M4 11V9a3 3 0 0 1 3-3h13"/><path d="M7 21l-3-3 3-3"/><path d="M20 13v2a3 3 0 0 1-3 3H4"/>',
    navCalendar: '<rect x="3" y="5" width="18" height="16" rx="2.5"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    navReports: '<path d="M4 20V10M10 20V4M16 20v-8M21 20H3"/>',
    navSettings: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
    navAdmin: '<path d="M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.500 7-10V6l-7-3z"/>',
  };
  for (const [id, d] of Object.entries(ICO)) {
    const btn = document.getElementById(id);
    if (btn && !btn.querySelector('.mock-ico'))
      btn.insertAdjacentHTML('afterbegin', '<svg class="mock-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>');
  }
  // 6. Admin: sections instead of one long page
  const admin = document.getElementById('pageAdmin');
  if (admin && !admin.classList.contains('mock-sections') && admin.querySelector(':scope > .panel')) {
    const panels = [...admin.querySelectorAll(':scope > .panel')];
    const groups = [['General', [0]], ['Sign-in security', [1, 5]], ['Bank and email', [2, 3]], ['Users', [4, 6]], ['Backups', [7]], ['Audit log', [8]]];
    const nav = document.createElement('div'); nav.className = 'settings-tabs';
    const pick = (name) => groups.forEach(([g, idx], i) => { nav.children[i].classList.toggle('active', g === name);
      idx.forEach(k => panels[k] && panels[k].classList.toggle('mock-off', g !== name)); });
    groups.forEach(([g]) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = g; b.onclick = () => pick(g); nav.appendChild(b); });
    admin.insertBefore(nav, admin.firstChild); admin.classList.add('mock-sections'); pick(window.__mockAdminTab || 'Users'); window.__mockAdminPick = pick;
    window.dispatchEvent(new Event('resize'));
  }
  // plain words on the user row's buttons
  document.querySelectorAll('#pageAdmin td button').forEach(b => {
    const t = b.textContent.trim();
    if (t === '🔑') b.textContent = 'Reset password';
    else if (t === '🗑' || t === '🗑️') b.textContent = 'Delete';
    else if (/Disable$/.test(t)) b.textContent = 'Disable';
    else if (/Enable$/.test(t)) b.textContent = 'Enable';
  });
  // 7. Theme picker: each card previews its theme
  const cards = document.querySelectorAll('.theme-card');
  if (cards.length && !document.querySelector('.mp')) {
    const toks = {};
    for (const sheet of document.styleSheets) { let rules; try { rules = sheet.cssRules; } catch (e) { continue; }
      for (const r of rules) { if (!r.selectorText) continue;
        const m = r.selectorText.match(/^:root(?:\[data-theme="(\w+)"\])?$/); if (!m) continue;
        const name = m[1] || 'dark'; toks[name] = toks[name] || {};
        for (const p of r.style) if (p.startsWith('--')) toks[name][p.slice(2)] = r.style.getPropertyValue(p).trim(); } }
    const half = (t) => `<div style="background:${t.bg}"><div class="mp-bar"><i style="background:${t.accent}"></i><i style="background:${t.border}"></i><i style="background:${t.border}"></i></div>
      <div class="mp-card" style="background:${t.panel};border-color:${t.border}"><b style="color:${t.text}">$4,794.98</b>
      <div class="mp-row"><span style="color:${t.good}">+$545</span><span style="color:${t.bad}">−$72</span><em style="background:${t.accent};color:${t['on-accent']}">Add</em></div></div></div>`;
    cards.forEach(c => { const k = c.dataset.themeKey, pv = c.querySelector('.preview'); if (!pv) return;
      const t = toks[k] && Object.assign({}, toks.dark, toks[k]);
      pv.innerHTML = '<div class="mp">' + (k === 'system' ? half(toks.dark) + half(Object.assign({}, toks.dark, toks.light)) : half(t || toks.dark)) + '</div>';
      if (!c.querySelector('.hint')) c.insertAdjacentHTML('beforeend', '<div class="hint">Default light</div>'); });
  }
})();
