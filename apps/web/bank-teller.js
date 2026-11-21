// The /bank/teller page (bank-providers phase 1, #254): sets Teller Connect
// up with what /api/bank/teller/setup says, and hands the access token from
// its onSuccess to /api/bank/teller/enroll. Nothing is kept in the page.
// Opened from the iPhone app's /app-connect-bank (?app=1, #258), it sends the
// sheet back to the app when done instead of saying to close the tab.
(function () {
  'use strict';
  const go = document.getElementById('go');
  const say = document.getElementById('say');
  const q = new URLSearchParams(location.search);
  const attempt = q.get('attempt') || '';
  const fromApp = q.get('app') === '1';

  // Back to the iPhone app (#258): the address closes the sign-in sheet.
  function backToApp(params) {
    location.href = 'walletweather://bank-connected?' + new URLSearchParams(params);
  }
  let backState = 'cancelled';
  function offerBack(state) {
    if (!fromApp) return;
    backState = state;
    if (document.getElementById('backToApp')) return;
    const b = document.createElement('button');
    b.id = 'backToApp';
    b.type = 'button';
    b.textContent = 'Back to the app';
    b.style.marginTop = '10px';
    b.addEventListener('click', function () { backToApp({ state: backState }); });
    go.parentNode.insertBefore(b, say);
  }

  function tell(text, kind) {
    say.textContent = text || '';
    say.className = kind || '';
  }
  function reason(res, body) {
    try { const d = JSON.parse(body).detail; if (typeof d === 'string') return d; } catch (_) { /* not JSON */ }
    return res.status === 401 ? 'Sign in to WalletWeather in this browser first, then open this page again from Settings → Bank sync.'
      : 'Something went wrong (HTTP ' + res.status + ').';
  }
  async function call(path, opts) {
    const res = await fetch(path, Object.assign({ headers: { 'Content-Type': 'application/json' },
                                                  credentials: 'same-origin' }, opts || {}));
    const body = await res.text();
    if (!res.ok) throw new Error(reason(res, body));
    return JSON.parse(body);
  }

  async function start() {
    if (!attempt) { go.textContent = 'Connect'; tell('Open this page from Settings → Bank sync.', 'bad'); return; }
    offerBack('cancelled');
    if (typeof window.TellerConnect === 'undefined') {
      go.textContent = 'Connect';
      tell("Teller's script didn't load. Check your connection or an ad blocker, then reload this page.", 'bad');
      return;
    }
    let setup;
    try { setup = await call('/api/bank/teller/setup?attempt=' + encodeURIComponent(attempt)); }
    catch (e) { go.textContent = 'Connect'; tell(e.message, 'bad'); return; }
    const connect = window.TellerConnect.setup({
      applicationId: setup.application_id,
      environment: setup.environment,
      products: ['transactions'],
      selectAccount: 'disabled',
      nonce: setup.nonce,
      onSuccess: async function (enrollment) {
        go.disabled = true;
        tell('Saving the connection…');
        try {
          const r = await call('/api/bank/teller/enroll', { method: 'POST',
            body: JSON.stringify({ attempt: attempt, access_token: enrollment.accessToken }) });
          go.classList.add('hidden');
          if (fromApp) {
            tell('Connected ' + (r.name || 'your bank') + '. Back to the app…', 'good');
            backToApp({ connection: String(r.connection_id) });
            return;
          }
          tell('Connected ' + (r.name || 'your bank') + ' (' + r.accounts + ' account' + (r.accounts === 1 ? '' : 's')
               + '). Close this tab and match its accounts in Settings → Bank sync.', 'good');
        } catch (e) {
          go.disabled = false;
          tell(e.message, 'bad');
        }
      },
      onExit: function () {
        tell('Closed without connecting a bank. Press Connect to try again.');
        offerBack('exited');
      },
      onFailure: function (f) { tell('Teller said: ' + ((f && f.message) || 'it could not connect.'), 'bad'); },
    });
    go.textContent = 'Connect with Teller';
    go.disabled = false;
    go.addEventListener('click', function () { tell(''); connect.open(); });
  }
  start();
}());
