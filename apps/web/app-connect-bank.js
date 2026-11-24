// The /app-connect-bank page (bank-providers phase 5, #258): the iPhone app's
// "Connect a bank", in the phone's sign-in sheet. See app-connect-bank.html.
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const PANELS = ['loading', 'signIn', 'codeStep', 'choose', 'stop', 'done'];
  const show = id => PANELS.forEach(x => $(x).classList.toggle('hidden', x !== id));
  const attempt = (new URLSearchParams(location.search).get('attempt') || '').slice(0, 64);
  let me = null;

  // The server answers errors with {"detail": "..."}.
  async function call(path, body) {
    const res = await fetch(path, {
      method: body ? 'POST' : 'GET', credentials: 'same-origin',
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
    let data = null;
    try { data = await res.json(); } catch (_) { /* not JSON */ }
    if (!res.ok) {
      const d = data && data.detail;
      const err = new Error(typeof d === 'string' ? d : 'Something went wrong (HTTP ' + res.status + '). Try again.');
      err.status = res.status;
      throw err;
    }
    return data;
  }
  function fail(id, e) {
    const el = $(id);
    el.textContent = e instanceof TypeError ? 'Could not reach the server. Check your connection and try again.' : e.message;
    el.classList.remove('hidden');
  }

  // Back to the app: the address closes the sheet. Only "done" and the
  // connection's number go with it, never anything from the bank.
  function back(params) {
    show('done');
    location.href = 'walletweather://bank-connected?' + new URLSearchParams(params);
  }
  function stop(title, text, state) {
    $('stopTitle').textContent = title;
    $('stopText').textContent = text;
    $('stopBack').onclick = () => back({ state: state });
    show('stop');
  }
  document.querySelectorAll('[data-back]').forEach(b => b.addEventListener('click', () => back({ state: b.dataset.back })));

  // ---------- Coming back from Teller or Plaid ----------

  async function finish() {
    $('loadingText').textContent = 'Checking with your bank…';
    show('loading');
    // Plaid may take a moment to report a finished session.
    for (let i = 0; i < 10; i++) {
      let r;
      try { r = await call('/api/bank/connect/check', { attempt: attempt }); }
      catch (e) {
        if (e.status === 401) { await signInThen(finish); return; }
        stop("Couldn't finish connecting", e instanceof TypeError ? 'Could not reach the server.' : e.message, 'failed');
        return;
      }
      if (r.state === 'done') { back({ connection: String(r.connection_id) }); return; }
      if (r.state === 'exited') { back({ state: 'exited' }); return; }
      if (r.state === 'expired') {
        stop('That took too long', 'The connection was started too long ago. Go back to the app and try again.', 'expired');
        return;
      }
      await new Promise(done => setTimeout(done, 1500));
    }
    stop('Not finished yet', "Your bank hasn't finished connecting. Go back to the app; if it connected, it shows there after a moment.", 'failed');
  }

  // ---------- Choosing a provider ----------

  async function choose() {
    let bank;
    try { bank = await call('/api/bank'); }
    catch (e) { stop("Can't connect a bank here", e.message, 'failed'); return; }
    if (!bank.enabled) {
      stop('Bank sync is off', 'An admin switches it on in the web app\'s Admin page. Then you can connect your bank here.', 'off');
      return;
    }
    // Only the providers an admin lets this person use (#264), and only once
    // they've saved their own keys for it (#276).
    const ticked = (bank.providers || []).filter(p => (p.key === 'teller' || p.key === 'plaid') && p.allowed !== false);
    const offered = ticked.filter(p => p.available);
    if (!ticked.length) {
      stop("You can't connect a bank yet",
           'An admin lets you connect through Teller or Plaid in the web app: Admin → Users.', 'off');
      return;
    }
    if (!offered.length) {
      stop('Add your keys first',
           'Teller and Plaid each need keys from a developer account of your own. Add them with Your bank keys under More → Bank sync in the app, or in the web app: Settings → Bank sync. SimpleFIN is connected there.', 'off');
      return;
    }
    offered.forEach(p => $('card-' + p.key).classList.remove('hidden'));
    const code = !!(me && me.two_factor_enabled);
    $('startCodeWrap').classList.toggle('hidden', !code);
    show('choose');
  }
  document.querySelectorAll('button[data-provider]').forEach(b => b.addEventListener('click', async () => {
    $('chooseError').classList.add('hidden');
    const code = $('startCode').value.trim();
    if (me && me.two_factor_enabled && !code) {
      fail('chooseError', new Error('Type the code from your authenticator app first.'));
      $('startCode').focus();
      return;
    }
    document.querySelectorAll('button[data-provider]').forEach(x => { x.disabled = true; });
    try {
      const r = await call('/api/bank/connect/start', { provider: b.dataset.provider, code: code || null, app: true });
      $('loadingText').textContent = 'Opening ' + (b.dataset.provider === 'plaid' ? 'Plaid' : 'Teller') + '…';
      show('loading');
      location.href = r.url;
    } catch (e) {
      fail('chooseError', e);
      $('startCode').value = '';
    } finally {
      document.querySelectorAll('button[data-provider]').forEach(x => { x.disabled = false; });
    }
  }));

  // ---------- Signing in ----------

  let afterSignIn = choose;
  async function signInThen(next) {
    afterSignIn = next;
    show('signIn');
    $('email').focus();
  }
  async function signedIn() {
    me = await call('/api/me');
    await afterSignIn();
  }
  $('signIn').addEventListener('submit', async ev => {
    ev.preventDefault();
    $('signInError').classList.add('hidden');
    $('signInBtn').disabled = true;
    try {
      const r = await call('/api/auth/login', { email: $('email').value, password: $('password').value });
      if (r && r.two_factor_required) {
        $('code').value = '';
        show('codeStep');
        $('code').focus();
        return;
      }
      await signedIn();
    } catch (e) {
      fail('signInError', e);
    } finally {
      $('signInBtn').disabled = false;
    }
  });
  $('codeStep').addEventListener('submit', async ev => {
    ev.preventDefault();
    $('codeError').classList.add('hidden');
    $('codeBtn').disabled = true;
    try {
      await call('/api/auth/login/two-factor', { code: $('code').value });
      await signedIn();
    } catch (e) {
      fail('codeError', e);
    } finally {
      $('codeBtn').disabled = false;
    }
  });

  async function start() {
    let config = {};
    try { config = await call('/api/auth/config'); } catch (_) { /* keep the defaults */ }
    if (config.app_title) document.title = 'Connect a bank · ' + config.app_title;
    if (config.google_enabled) {
      $('googleBtn').href = '/auth/login?next=' + encodeURIComponent(location.pathname + location.search);
      $('googleWrap').classList.remove('hidden');
    }
    const next = /^[A-Za-z0-9_-]{16,64}$/.test(attempt) ? finish : choose;
    try {
      me = await call('/api/me');
    } catch (e) {
      await signInThen(next);
      if (e.status !== 401) fail('signInError', e);
      return;
    }
    await next();
  }
  start();
}());
