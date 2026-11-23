// The /app-bank-keys page (own-bank-keys phase 3, #278): your own Teller and
// Plaid keys from the iPhone app, in the phone's sign-in sheet. See
// app-bank-keys.html. Saves through the web app's own browser-only routes.
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const PANELS = ['loading', 'signIn', 'codeStep', 'keys', 'stop', 'done'];
  const show = id => PANELS.forEach(x => $(x).classList.toggle('hidden', x !== id));
  const PROVIDERS = ['teller', 'plaid'];
  const NAMES = { teller: 'Teller', plaid: 'Plaid' };
  const ENVS = { sandbox: 'Sandbox', development: 'Development', production: 'Production' };
  let me = null;
  let bank = null;
  let changed = false;              // anything saved or removed, for the app
  const replacing = {};             // provider → true while its Replace form is open

  // The server answers errors with {"detail": "..."}.
  async function call(path, body, method) {
    const res = await fetch(path, {
      method: method || (body ? 'POST' : 'GET'), credentials: 'same-origin',
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
  function message(e) {
    return e instanceof TypeError ? 'Could not reach the server. Check your connection and try again.' : e.message;
  }
  function fail(id, e) {
    const el = $(id);
    el.textContent = message(e);
    el.classList.remove('hidden');
  }

  // Back to the app: the address closes the sheet. Only whether something
  // changed goes with it, never a key.
  function back(state) {
    show('done');
    location.href = 'walletweather://bank-keys?' + new URLSearchParams({ state: state });
  }
  function stop(title, text, state) {
    $('stopTitle').textContent = title;
    $('stopText').textContent = text;
    $('stopBack').onclick = () => back(state);
    show('stop');
  }
  document.querySelectorAll('[data-back]').forEach(b => b.addEventListener('click', () => back(b.dataset.back)));
  $('backBtn').addEventListener('click', () => back(changed ? 'changed' : 'closed'));

  // ---------- The cards ----------

  const ticked = p => !!(bank && (bank.providers || []).some(x => x.key === p && x.allowed));
  const mayEdit = p => !!(bank && bank.enabled && ticked(p));

  function say(p, text, good) {
    const el = $('status-' + p);
    el.textContent = text || '';
    el.className = text ? (good ? 'good' : 'error') : 'hidden';
  }
  function busy(p, text) {
    const el = $('status-' + p);
    el.textContent = text;
    el.className = 'muted';
    el.style.marginTop = '10px';
  }

  function when(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return '';
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  }

  function render() {
    const keys = bank.keys || {};
    const shown = PROVIDERS.filter(p => keys[p] || mayEdit(p));
    $('keysCodeWrap').classList.toggle('hidden', !(me && me.two_factor_enabled));
    PROVIDERS.forEach(p => {
      const k = keys[p];
      $('card-' + p).classList.toggle('hidden', !shown.includes(p));
      $('saved-' + p).classList.toggle('hidden', !k);
      $('none-' + p).classList.toggle('hidden', !!k || mayEdit(p));
      const idLabel = p === 'teller' ? 'Application id' : 'Client id';
      if (k) {
        const checked = k.checked_at ? 'checked ' + when(k.checked_at) : 'not checked yet';
        $('savedText-' + p).textContent = idLabel + ' ' + k.id + ' · ' + (ENVS[k.environment] || k.environment) + ' · ' + checked;
        const using = k.in_use || [];
        $('inUse-' + p).textContent = using.length
          ? 'Used by ' + using.join(', ') + '. Replacing them with a different ' + idLabel.toLowerCase()
            + ', or removing them, waits until ' + (using.length === 1 ? 'it is' : 'they are') + ' disconnected.'
          : '';
        $('inUse-' + p).classList.toggle('hidden', !using.length);
        $('replace-' + p).classList.toggle('hidden', !mayEdit(p) || !!replacing[p]);
        $('remove-' + p).classList.toggle('hidden', !!replacing[p]);
      }
      $('form-' + p).classList.toggle('hidden', !(mayEdit(p) && (!k || replacing[p])));
      $('cancel-' + p).classList.toggle('hidden', !(k && replacing[p]));
    });
    show('keys');
  }

  async function load() {
    try { bank = await call('/api/bank'); }
    catch (e) {
      if (e.status === 401) { signInThen(load); return; }
      stop("Can't show your keys", message(e), 'closed');
      return;
    }
    const keys = bank.keys || {};
    const any = PROVIDERS.some(p => keys[p]);
    if (!any && !bank.enabled) {
      stop('Bank sync is off', "An admin switches it on in the web app's Admin page. Then you can add your keys here.", 'off');
      return;
    }
    if (!any && !PROVIDERS.some(mayEdit)) {
      stop("You can't add keys yet",
           'An admin lets you connect through Teller or Plaid in the web app: Admin → Users. Then you can add your keys here.', 'off');
      return;
    }
    render();
  }

  function code() {
    return me && me.two_factor_enabled ? $('keysCode').value.trim() : '';
  }
  function needCode(p) {
    if (me && me.two_factor_enabled && !code()) {
      say(p, 'Type the code from your authenticator app first, at the top of this page.');
      $('keysCode').focus();
      return true;
    }
    return false;
  }

  async function fileBase64(file) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(bin);
  }

  async function save(p) {
    say(p, '');
    const val = id => $(id).value.trim();
    let body;
    if (p === 'teller') {
      body = { application_id: val('tellerApp'), environment: $('tellerEnv').value };
      const zip = $('tellerZip').files[0], certFile = $('tellerCertFile').files[0], keyFile = $('tellerKeyFile').files[0];
      if (!body.application_id) { say(p, 'Enter your Teller application id.'); return; }
      if (zip) body.zip_base64 = await fileBase64(zip);
      else if (certFile && keyFile) { body.certificate = await certFile.text(); body.private_key = await keyFile.text(); }
      else if (certFile || keyFile) { say(p, 'Pick both certificate.pem and private_key.pem.'); return; }
      else { body.certificate = val('tellerCertText'); body.private_key = val('tellerKeyText'); }
    } else {
      body = { client_id: val('plaidClient'), secret: val('plaidSecret'), environment: $('plaidEnv').value };
      if (!body.client_id || !body.secret) { say(p, 'Enter your Plaid client id and secret.'); return; }
    }
    if (needCode(p)) return;
    body.code = code() || null;
    $('save-' + p).disabled = true;
    busy(p, 'Checking with ' + NAMES[p] + '…');
    try {
      const r = await call('/api/bank/keys/' + p, body, 'PUT');
      changed = true;
      replacing[p] = false;
      bank.keys = r.keys;
      bank = await call('/api/bank').catch(() => bank);
      $('form-' + p).reset();
      render();
      say(p, 'Saved. ' + NAMES[p] + ' accepted these keys.', true);
    } catch (e) {
      say(p, message(e));
    } finally {
      $('save-' + p).disabled = false;
      $('keysCode').value = '';
    }
  }

  async function remove(p) {
    say(p, '');
    if (!window.confirm('Remove your ' + NAMES[p] + ' keys? You can add them again later.')) return;
    if (needCode(p)) return;
    $('remove-' + p).disabled = true;
    busy(p, 'Removing…');
    try {
      const r = await call('/api/bank/keys/remove', { provider: p, code: code() || null });
      changed = true;
      replacing[p] = false;
      bank.keys = r.keys;
      bank = await call('/api/bank').catch(() => bank);
      render();
      say(p, 'Your ' + NAMES[p] + ' keys are removed.', true);
    } catch (e) {
      say(p, message(e));
    } finally {
      $('remove-' + p).disabled = false;
      $('keysCode').value = '';
    }
  }

  PROVIDERS.forEach(p => {
    $('form-' + p).addEventListener('submit', ev => { ev.preventDefault(); save(p); });
    $('replace-' + p).addEventListener('click', () => { replacing[p] = true; say(p, ''); render(); });
    $('cancel-' + p).addEventListener('click', () => { replacing[p] = false; say(p, ''); render(); });
    $('remove-' + p).addEventListener('click', () => remove(p));
  });

  // ---------- Signing in ----------

  let afterSignIn = load;
  function signInThen(next) {
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
    if (config.app_title) document.title = 'Your bank keys · ' + config.app_title;
    if (config.google_enabled) {
      $('googleBtn').href = '/auth/login?next=' + encodeURIComponent(location.pathname);
      $('googleWrap').classList.remove('hidden');
    }
    try {
      me = await call('/api/me');
    } catch (e) {
      signInThen(load);
      if (e.status !== 401) fail('signInError', e);
      return;
    }
    await load();
  }
  start();
}());
