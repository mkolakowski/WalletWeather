/*
 * WalletWeather core: the money logic shared by the server, the iPhone app
 * and (later) the web app. Plans/standalone.md, phase 1 (#232).
 *
 * One classic script, no modules, no dependencies and no build step, so the
 * same file runs in the server's embedded engine (quickjs-ng), in
 * JavaScriptCore on the iPhone and in a browser <script> tag. It defines one
 * global, `WalletWeatherCore`.
 *
 * Every function is pure: the rows go in as plain JSON (what the database
 * holds, already decrypted) and the API's JSON comes out, in the same shape
 * the server sends today. `run(name, json)` is the one entry point the hosts
 * call, with a JSON string in and a JSON string out.
 *
 * Rules that keep the answers identical to the server's:
 * - Money is a JavaScript number, the same IEEE 754 double as the server's
 *   Python float, added up in the same order, with Python's compensated
 *   sum() where the server uses sum(). The server stores amounts unrounded,
 *   so whole cents would give different answers.
 * - Dates are "YYYY-MM-DD" strings, turned into day numbers for arithmetic.
 *   Never `Date`, so no time zone can move a day.
 * - Strings sort by code point, as Python does, never by locale.
 * - Sorts are stable (as Python's are), and every input list keeps its order.
 *
 * The answer key in packages/core/answer-key/ is what the server produced
 * for the same rows; apps/server/tests/test_core_answer_key.py checks this
 * file against it.
 */
(function (root) {
  "use strict";

  // ---------- Dates ----------

  // Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's
  // days_from_civil), so date arithmetic is integer arithmetic.
  function dayNumber(iso) {
    let y = +iso.slice(0, 4);
    const m = +iso.slice(5, 7);
    const d = +iso.slice(8, 10);
    y -= m <= 2 ? 1 : 0;
    const era = Math.floor(y / 400);
    const yoe = y - era * 400;
    const doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
    const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    return era * 146097 + doe - 719468;
  }

  function pad(n, width) {
    let s = String(n);
    while (s.length < width) s = "0" + s;
    return s;
  }

  function isoOf(z) {
    z += 719468;
    const era = Math.floor(z / 146097);
    const doe = z - era * 146097;
    const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    const mp = Math.floor((5 * doy + 2) / 153);
    const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
    const m = mp + (mp < 10 ? 3 : -9);
    const y = yoe + era * 400 + (m <= 2 ? 1 : 0);
    return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2);
  }

  function isLeap(y) {
    return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  }

  function monthLength(y, m) {
    return [31, isLeap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
  }

  function ymd(iso) {
    return [+iso.slice(0, 4), +iso.slice(5, 7), +iso.slice(8, 10)];
  }

  function isoFromParts(y, m, d) {
    return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2);
  }

  // ---------- Strings and numbers ----------

  // Two "YYYY-MM-DD" dates: plain string order is date order.
  function cmpIso(a, b) {
    return a < b ? -1 : a > b ? 1 : 0;
  }

  // Python's str < str: by code point, not UTF-16 unit or locale.
  const SURROGATE = /[\uD800-\uDFFF]/;
  function cmpStr(a, b) {
    if (a === b) return 0;
    // Without surrogate pairs, UTF-16 order is code point order.
    if (!SURROGATE.test(a) && !SURROGATE.test(b)) return a < b ? -1 : 1;
    const ia = a[Symbol.iterator]();
    const ib = b[Symbol.iterator]();
    for (;;) {
      const x = ia.next();
      const y = ib.next();
      if (x.done) return y.done ? 0 : -1;
      if (y.done) return 1;
      if (x.value !== y.value) return x.value.codePointAt(0) < y.value.codePointAt(0) ? -1 : 1;
    }
  }

  // Python's round(x, 2) on a float: the exact binary value rounded half to
  // even at two decimals, then the nearest double to that.
  function round2(x) {
    if (!isFinite(x) || x === 0) return x;
    const neg = x < 0;
    const s = Math.abs(x).toFixed(100);
    const dot = s.indexOf(".");
    let whole = s.slice(0, dot);
    const frac = s.slice(dot + 1);
    let kept = frac.slice(0, 2);
    const next = +frac[2];
    const restNonZero = /[1-9]/.test(frac.slice(3));
    let up = next > 5 || (next === 5 && (restNonZero || +kept[1] % 2 === 1));
    if (up) {
      // Add one hundredth to whole.kept, as decimal strings.
      let n = (BigInt(whole + kept) + 1n).toString();
      while (n.length < 3) n = "0" + n;
      whole = n.slice(0, -2);
      kept = n.slice(-2);
    }
    const v = parseFloat(whole + "." + kept);
    return neg ? -v : v;
  }

  // Python 3.12's sum() over floats: Neumaier's compensated summation, the
  // compensation added at the end. The server uses sum() in a few places,
  // and plain addition there can land a half cent the other way.
  function pySum(values) {
    let f = 0;
    let c = 0;
    for (const x of values) {
      const t = f + x;
      if (Math.abs(f) >= Math.abs(x)) c += (f - t) + x;
      else c += (x - t) + f;
      f = t;
    }
    if (c !== 0 && isFinite(c)) f += c;
    return f;
  }

  // Python's truthiness, for fields the server tests with `if x` / `or`.
  function truthy(v) {
    return !(v === null || v === undefined || v === false || v === 0 || v === "");
  }

  function sortTags(tags) {
    return (tags || []).slice().sort((a, b) => cmpStr(a.name.toLowerCase(), b.name.toLowerCase()));
  }

  // ---------- Repeating items ----------

  // forecast._occurrences: [{day, amount, description}] for a repeating item
  // within [start, end], both day numbers.
  function occurrences(rec, start, end) {
    const out = [];
    let effEnd = end;
    if (rec.end_date != null && dayNumber(rec.end_date) < effEnd) effEnd = dayNumber(rec.end_date);
    if (effEnd < start) return out;

    if (rec.frequency === "monthly_day" && truthy(rec.day_of_month)) {
      // anchor_date is an optional start date for a monthly item.
      let effStart = start;
      if (rec.anchor_date != null && dayNumber(rec.anchor_date) > effStart) effStart = dayNumber(rec.anchor_date);
      if (effEnd < effStart) return out;
      let [y, m] = ymd(isoOf(effStart));
      while (dayNumber(isoFromParts(y, m, 1)) <= effEnd) {
        const day = Math.min(rec.day_of_month, monthLength(y, m));
        const occ = dayNumber(isoFromParts(y, m, day));
        if (effStart <= occ && occ <= effEnd) out.push({ day: occ, amount: rec.amount, description: rec.description });
        if (m === 12) { y += 1; m = 1; } else { m += 1; }
      }
    } else if ((rec.frequency === "weekly" || rec.frequency === "biweekly") && truthy(rec.anchor_date)) {
      // The anchor is the first date and sets the rhythm.
      const step = rec.frequency === "weekly" ? 7 : 14;
      let occ = dayNumber(rec.anchor_date);
      if (occ < start) occ += step * Math.ceil((start - occ) / step);
      while (occ <= effEnd) {
        out.push({ day: occ, amount: rec.amount, description: rec.description });
        occ += step;
      }
    }
    return out;
  }

  // forecast.upcoming_dates: the next `count` dates from `today`, leaving out
  // skipped and paid dates; [] for an item that's switched off.
  function upcomingDates(input) {
    const rec = input.recurring;
    if (!truthy(rec.active)) return [];
    const today = dayNumber(input.today);
    const skipped = new Set(input.skipped || []);
    const paid = new Set(input.paid || []);
    const count = input.count == null ? 6 : input.count;
    const out = [];
    for (const occ of occurrences(rec, today, today + 400)) {
      const iso = isoOf(occ.day);
      if (skipped.has(iso) || paid.has(iso)) continue;
      out.push(iso);
      if (out.length >= count) break;
    }
    return out;
  }

  // ---------- Forecast ----------

  // forecast.build_forecast. `input`:
  //   start, end            the window, "YYYY-MM-DD"
  //   starting_balance      the account's starting balance
  //   transactions          every transaction on the account, in the
  //                         database's order: id, recurring_id, category_id,
  //                         category (its name), transfer_id, description,
  //                         notes, amount, forecast_amount, forecast_date,
  //                         actual_date, is_actual, bank_match, has_bank_ref,
  //                         has_mail_ref, bank_left, tags [{id, name, color}]
  //   recurring             the account's active repeating items: id,
  //                         frequency, day_of_month, anchor_date, end_date,
  //                         amount, description, notes, category,
  //                         category_id, tags
  //   skips                 [{recurring_id, date}] dates deleted from the
  //                         forecast
  function forecast(input) {
    const start = dayNumber(input.start);
    const end = dayNumber(input.end);
    const txns = input.transactions || [];

    // Opening balance: the starting balance plus every cleared line before
    // the window.
    let opening = input.starting_balance;
    for (const t of txns) {
      const ref = t.actual_date || t.forecast_date;
      if (ref && ref < input.start && truthy(t.is_actual)) opening += t.amount;
    }

    const events = [];
    const txnByRecDate = new Set();
    for (const t of txns) {
      if (t.recurring_id && t.forecast_date) txnByRecDate.add(t.recurring_id + "|" + t.forecast_date);

      // A cleared line belongs to the window holding its actual date;
      // anything else to its planned date.
      let anchor;
      if (truthy(t.is_actual) && t.actual_date) anchor = t.actual_date;
      else anchor = t.forecast_date || t.actual_date;
      if (!anchor || anchor < input.start || anchor > input.end) continue;

      const forecastAmt = t.forecast_amount != null ? t.forecast_amount : (!truthy(t.is_actual) ? t.amount : null);
      let shownAmount, shownDate;
      if (truthy(t.is_actual)) {
        shownAmount = t.amount;
        shownDate = t.actual_date || null;
      } else {
        shownAmount = forecastAmt;
        shownDate = t.forecast_date || null;
      }
      events.push({
        anchor_date: anchor,
        forecast_date: t.forecast_date || null,
        actual_date: shownDate,
        description: t.description,
        category: t.category == null ? null : t.category,
        category_id: t.category_id == null ? null : t.category_id,
        notes: t.notes == null ? null : t.notes,
        forecast_amount: forecastAmt,
        actual_amount: shownAmount,
        is_actual_real: t.is_actual == null ? null : t.is_actual,
        recurring_id: t.recurring_id == null ? null : t.recurring_id,
        transaction_id: t.id,
        transfer_id: t.transfer_id == null ? null : t.transfer_id,
        bank_match: t.bank_match == null ? null : t.bank_match,
        match_source: truthy(t.bank_match) ? (truthy(t.has_mail_ref) ? "alert" : "bank") : null,
        // Still on the Unmatched list: main._unmatched_query's test.
        bank_unmatched: Boolean((truthy(t.has_bank_ref) || truthy(t.has_mail_ref)) && t.bank_match == null
          && !truthy(t.bank_left) && t.recurring_id == null && t.transfer_id == null && truthy(t.is_actual)),
        tags: sortTags(t.tags),
      });
    }

    // Projected dates of the repeating items that no line covers yet.
    const skipped = new Set((input.skips || []).map((s) => s.recurring_id + "|" + s.date));
    for (const rec of input.recurring || []) {
      if (!truthy(rec.active === undefined ? true : rec.active)) continue;
      for (const occ of occurrences(rec, start, end)) {
        const iso = isoOf(occ.day);
        const key = rec.id + "|" + iso;
        if (txnByRecDate.has(key) || skipped.has(key)) continue;
        events.push({
          anchor_date: iso,
          forecast_date: iso,
          actual_date: iso,
          description: occ.description,
          category: rec.category == null ? null : rec.category,
          category_id: rec.category_id == null ? null : rec.category_id,
          notes: rec.notes == null ? null : rec.notes,
          forecast_amount: occ.amount,
          actual_amount: occ.amount,
          is_actual_real: false,
          recurring_id: rec.id,
          transaction_id: null,
          transfer_id: null,
          bank_match: null,
          match_source: null,
          bank_unmatched: false,
          tags: sortTags(rec.tags),
        });
      }
    }

    // By planned date, cleared lines after pending ones on the same day.
    const sortDay = (e) => e.forecast_date || e.anchor_date;
    events.sort((x, y) => cmpIso(sortDay(x), sortDay(y))
      || (x.actual_amount == null ? 0 : 1) - (y.actual_amount == null ? 0 : 1));

    // Planned running balance, in that order.
    const fbals = [];
    let fbal = opening;
    for (const ev of events) {
      fbal += ev.forecast_amount != null ? ev.forecast_amount : 0.0;
      fbals.push(fbal);
    }

    // Actual running balance (actual amount, else planned), in actual-date
    // order, so a line that cleared late picks up that day's balance.
    const actualDay = (e) => e.actual_date || e.anchor_date;
    const byActual = events.map((_, i) => i).sort((i, j) => cmpIso(actualDay(events[i]), actualDay(events[j])));
    const abals = new Array(events.length).fill(0.0);
    let abal = opening;
    for (const i of byActual) {
      const f = events[i].forecast_amount;
      const a = events[i].actual_amount;
      abal += a != null ? a : (f != null ? f : 0.0);
      abals[i] = abal;
    }

    // Δ Bal: each line's actual balance against the planned balance at the
    // same point in time.
    const pos = new Array(events.length);
    byActual.forEach((i, k) => { pos[i] = k; });
    const plannedDay = (e) => e.forecast_date || e.anchor_date;
    const plannedAt = events.map((ev, i) => {
      const d = actualDay(ev);
      const amounts = [];
      events.forEach((other, j) => {
        const od = plannedDay(other);
        if (od < d || (od === d && pos[j] <= pos[i])) amounts.push(truthy(other.forecast_amount) ? other.forecast_amount : 0.0);
      });
      return opening + pySum(amounts);
    });

    const rows = events.map((ev, i) => {
      const f = ev.forecast_amount;
      const a = ev.actual_amount;
      return {
        forecast_date: ev.forecast_date,
        actual_date: ev.actual_date,
        description: ev.description,
        category: ev.category,
        category_id: ev.category_id,
        notes: ev.notes,
        forecast_amount: f,
        forecast_balance: fbals[i],
        actual_amount: a,
        actual_balance: abals[i],
        diff_amount: a != null && f != null ? a - f : null,
        diff_balance: abals[i] - plannedAt[i],
        is_actual_real: ev.is_actual_real,
        recurring_id: ev.recurring_id,
        transaction_id: ev.transaction_id,
        transfer_id: ev.transfer_id,
        bank_match: ev.bank_match,
        match_source: ev.match_source,
        bank_unmatched: ev.bank_unmatched,
        tags: ev.tags,
      };
    });

    return {
      opening_balance: opening,
      forecast_ending_balance: fbal,
      actual_ending_balance: abal,
      rows: rows,
    };
  }

  // forecast.actual_balance_as_of: the Actual bal column's value at the last
  // row through `as_of`, in that date's month. `input` is a forecast input
  // without start and end (tags aren't needed), plus `as_of`.
  function actualBalanceAsOf(input) {
    const [y, m] = ymd(input.as_of);
    const data = forecast(Object.assign({}, input, {
      start: isoFromParts(y, m, 1),
      end: isoFromParts(y, m, monthLength(y, m)),
    }));
    const cutoff = input.as_of;
    const amounts = [];
    for (const r of data.rows) {
      if ((r.actual_date || r.forecast_date || "") <= cutoff) {
        amounts.push(r.actual_amount != null ? r.actual_amount : (truthy(r.forecast_amount) ? r.forecast_amount : 0.0));
      }
    }
    return round2(data.opening_balance + pySum(amounts));
  }

  // ---------- Calendar ----------

  // main.calendar_events. `input`:
  //   start, end        the window
  //   single_account    true when one account was asked for (the only time
  //                     daily balances are worked out)
  //   categories        the caller's categories [{id, name, color}]
  //   accounts          [{id, name, ...a forecast input without start/end}]
  function calendar(input) {
    const catMeta = {};
    for (const c of input.categories || []) catMeta[c.name] = { id: c.id, color: c.color == null ? null : c.color };

    const events = [];
    const daily = input.single_account ? {} : null;
    const start = dayNumber(input.start);
    const end = dayNumber(input.end);
    for (const acc of input.accounts || []) {
      const data = forecast(Object.assign({}, acc, { start: input.start, end: input.end }));
      if (daily !== null) {
        const dayToBalance = {};
        for (const r of data.rows) {
          const key = r.actual_date || r.forecast_date;
          if (key) dayToBalance[key] = r.actual_balance;
        }
        let running = data.opening_balance;
        for (let d = start; d <= end; d++) {
          const key = isoOf(d);
          if (Object.prototype.hasOwnProperty.call(dayToBalance, key)) running = dayToBalance[key];
          daily[key] = round2(running);
        }
      }
      for (const r of data.rows) {
        const d = r.forecast_date || r.actual_date;
        if (!d) continue;
        const catName = r.category;
        const meta = truthy(catName) && Object.prototype.hasOwnProperty.call(catMeta, catName) ? catMeta[catName] : null;
        events.push({
          date: d,
          account_id: acc.id,
          account_name: acc.name,
          description: r.description || "",
          amount: r.actual_amount != null ? r.actual_amount : r.forecast_amount,
          forecast_amount: r.forecast_amount,
          actual_amount: r.actual_amount,
          category_id: meta ? meta.id : null,
          category_name: catName,
          category_color: meta ? meta.color : null,
          tags: r.tags || [],
          recurring_id: r.recurring_id,
          transaction_id: r.transaction_id,
          transfer_id: r.transfer_id,
          is_actual_real: r.is_actual_real,
          notes: r.notes,
        });
      }
    }

    events.sort((x, y) => cmpIso(x.date, y.date)
      || cmpStr(x.account_name, y.account_name)
      || cmpStr(x.description.toLowerCase(), y.description.toLowerCase()));
    return { start: input.start, end: input.end, events: events, daily_balances: daily };
  }

  // ---------- Dashboard ----------

  const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December"];

  // strftime("%B %Y") in the C locale, which the server runs in.
  function monthLabel(iso) {
    const [y, m] = ymd(iso);
    return MONTHS[m - 1] + " " + y;
  }

  function monthWindow(today) {
    const [y, m] = ymd(today);
    return [isoFromParts(y, m, 1), isoFromParts(y, m, monthLength(y, m))];
  }

  // main.dashboard: one card per account for today's month. `input`:
  //   today       the viewer's date
  //   accounts    [{id, name, ...a forecast input without start/end}]
  function dashboard(input) {
    const today = input.today;
    const [start, end] = monthWindow(today);
    const label = monthLabel(start);
    const cards = [];
    for (const acc of input.accounts || []) {
      const data = forecast(Object.assign({}, acc, { start: start, end: end }));
      const rows = data.rows;
      // Lines not cleared yet, from today to the month's end.
      let upcomingCount = 0;
      let upcomingNet = 0.0;
      for (const r of rows) {
        if (truthy(r.is_actual_real)) continue;
        const ref = r.forecast_date || r.actual_date;
        if (ref && ref >= today) {
          upcomingCount += 1;
          upcomingNet += truthy(r.forecast_amount) ? r.forecast_amount : 0.0;
        }
      }
      const current = round2(actualBalanceAsOf(Object.assign({}, acc, { as_of: today })));
      const card = {
        id: acc.id,
        name: acc.name,
        month_label: label,
        opening_balance: data.opening_balance,
        forecast_end: data.forecast_ending_balance,
        actual_end: data.actual_ending_balance,
      };
      if (!rows.length) {
        Object.assign(card, {
          forecast_high: data.opening_balance, forecast_high_date: null,
          forecast_low: data.opening_balance, forecast_low_date: null,
          actual_high: data.opening_balance, actual_low: data.opening_balance,
          row_count: 0,
        });
      } else {
        let fHigh = rows[0].forecast_balance, fLow = fHigh;
        let fHighDate = rows[0].forecast_date, fLowDate = fHighDate;
        let aHigh = rows[0].actual_balance, aLow = aHigh;
        for (const r of rows) {
          if (r.forecast_balance > fHigh) { fHigh = r.forecast_balance; fHighDate = r.forecast_date; }
          if (r.forecast_balance < fLow) { fLow = r.forecast_balance; fLowDate = r.forecast_date; }
          if (r.actual_balance > aHigh) aHigh = r.actual_balance;
          if (r.actual_balance < aLow) aLow = r.actual_balance;
        }
        Object.assign(card, {
          forecast_high: fHigh, forecast_high_date: fHighDate,
          forecast_low: fLow, forecast_low_date: fLowDate,
          actual_high: aHigh, actual_low: aLow,
          row_count: rows.length,
        });
      }
      card.upcoming_count = upcomingCount;
      card.upcoming_net = round2(upcomingNet);
      card.current_balance = current;
      cards.push(card);
    }
    return { cards: cards };
  }

  // main._resolve_dashboard_window: [start, end, label].
  function dashboardWindow(window, today) {
    const t = dayNumber(today);
    if (window === "30d") return [isoOf(t - 29), today, "Last 30 days"];
    if (window === "90d") return [isoOf(t - 89), today, "Last 90 days"];
    const [start, end] = monthWindow(today);
    return [start, end, monthLabel(start)];
  }

  // main.dashboard_charts: spending by category, totals and the daily
  // balance for each account. `input`:
  //   window       "month", "30d" or "90d" (checked by the host)
  //   today        the viewer's date
  //   categories   the caller's categories [{id, name, color}]
  //   accounts     [{id, name, ...a forecast input without start/end}]
  function dashboardCharts(input) {
    const [start, end, label] = dashboardWindow(input.window, input.today);
    const colors = new Map();
    for (const c of input.categories || []) colors.set(c.name, c.color == null ? null : c.color);
    const UNCAT = "(uncategorized)";
    const accountsOut = [];
    for (const acc of input.accounts || []) {
      const data = forecast(Object.assign({}, acc, { start: start, end: end }));
      const rows = data.rows;
      const buckets = new Map();
      const bucket = (cat) => {
        if (!buckets.has(cat)) buckets.set(cat, { spending_actual: 0.0, spending_forecast: 0.0 });
        return buckets.get(cat);
      };
      let fIncome = 0.0, aIncome = 0.0, fSpend = 0.0, aSpend = 0.0;
      for (const r of rows) {
        // Transfer legs move money between accounts: not spending or income.
        if (r.transfer_id != null) continue;
        const cat = truthy(r.category) ? r.category : UNCAT;
        const f = r.forecast_amount;
        const a = r.actual_amount;
        if (f != null) {
          if (f > 0) fIncome += f;
          else if (f < 0) { fSpend += f; bucket(cat).spending_forecast += -f; }
        }
        if (a != null) {
          if (a > 0) aIncome += a;
          else if (a < 0) { aSpend += a; bucket(cat).spending_actual += -a; }
        }
      }
      const cats = [];
      for (const [name, b] of buckets) {
        if (b.spending_actual > 0 || b.spending_forecast > 0) {
          cats.push({
            name: name, color: colors.has(name) ? colors.get(name) : null,
            spending_actual: round2(b.spending_actual), spending_forecast: round2(b.spending_forecast),
          });
        }
      }
      // Most spent first; Python's reverse sort keeps ties in their order.
      cats.sort((x, y) => (y.spending_actual - x.spending_actual) || (y.spending_forecast - x.spending_forecast));

      const dayToBalance = new Map();
      for (const r of rows) {
        const d = r.actual_date || r.forecast_date;
        if (d) dayToBalance.set(d, r.actual_balance);
      }
      const trend = [];
      let running = data.opening_balance;
      for (let d = dayNumber(start); d <= dayNumber(end); d++) {
        const key = isoOf(d);
        if (dayToBalance.has(key)) running = dayToBalance.get(key);
        trend.push({ date: key, balance: round2(running) });
      }
      accountsOut.push({
        account_id: acc.id,
        account_name: acc.name,
        totals: {
          income_actual: round2(aIncome),
          spending_actual: round2(-aSpend),
          net_actual: round2(aIncome + aSpend),
          income_forecast: round2(fIncome),
          spending_forecast: round2(-fSpend),
          net_forecast: round2(fIncome + fSpend),
        },
        categories: cats,
        balance_trend: trend,
        opening_balance: round2(data.opening_balance),
        forecast_end: round2(data.forecast_ending_balance),
        actual_end: round2(data.actual_ending_balance),
      });
    }
    return { window: input.window, label: label, start: start, end: end, accounts: accountsOut };
  }

  // ---------- Text ----------

  // Python's str.strip(): the characters str.isspace() calls whitespace
  // (JavaScript's trim() takes a slightly different set).
  const PY_SPACE = "[\\t\\n\\v\\f\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]";
  const PY_STRIP = new RegExp("^" + PY_SPACE + "+|" + PY_SPACE + "+$", "g");
  function pyStrip(s) {
    return s.replace(PY_STRIP, "");
  }

  // Python's str.casefold(), for matching and sorting without case. Lower,
  // upper and lower again folds "ß" and "ẞ" to "ss" as casefold() does; a
  // final sigma becomes σ; the dotless ı stays itself (it has no case pair
  // in casefold()). Checked against Python over every assigned code point.
  function casefold(s) {
    return s.split("ı")
      .map((p) => p.toLowerCase().toUpperCase().toLowerCase().replace(/ς/g, "σ"))
      .join("ı");
  }

  // ---------- Bills & income ----------

  // A month's worth of each rhythm, for the monthly and yearly figures.
  const MONTHLY_FACTOR = { monthly_day: 1.0, biweekly: 26.0 / 12.0, weekly: 52.0 / 12.0 };

  function monthlyFactor(frequency) {
    return Object.prototype.hasOwnProperty.call(MONTHLY_FACTOR, frequency) ? MONTHLY_FACTOR[frequency] : null;
  }

  function byRecurring(list) {
    const out = {};
    for (const row of list || []) (out[row.recurring_id] = out[row.recurring_id] || []).push(row.date);
    return out;
  }

  function roundOrNull(x) {
    return x === null ? null : round2(x);
  }

  // One repeating item as Bills & income lists it (main._recurring_row and
  // /api/recurring's extras). `skips` and `paid` are its dates, every one.
  function recurringItem(rec, account, today, skips, paid) {
    const amount = rec.amount;
    const factor = monthlyFactor(rec.frequency);
    // monthly/yearly: the signed amount over a month (income positive,
    // bills negative); monthly_cost/yearly_cost: bills only, as a positive
    // cost. Null on a rhythm with no factor.
    const monthly = factor === null ? null : amount * factor;
    const cost = monthly !== null && amount < 0 ? -monthly : null;
    const nexts = upcomingDates({
      recurring: rec, today: today,
      skipped: skips.filter((d) => d >= today), paid: paid.filter((d) => d >= today),
    });
    return {
      id: rec.id,
      description: rec.description,
      amount: amount,
      frequency: rec.frequency,
      day_of_month: rec.day_of_month,
      anchor_date: rec.anchor_date,
      end_date: rec.end_date,
      category_id: rec.category_id,
      category_name: rec.category == null ? null : rec.category,
      notes: rec.notes,
      active: rec.active,
      expired: rec.end_date != null && rec.end_date < today,
      monthly: roundOrNull(monthly),
      yearly: monthly === null ? null : round2(monthly * 12),
      monthly_cost: roundOrNull(cost),
      yearly_cost: cost === null ? null : round2(cost * 12),
      skipped_count: skips.length,
      tags: sortTags(rec.tags),
      match_days: rec.match_days,
      match_percent: rec.match_percent,
      match_text: rec.match_text,
      account_id: account.id,
      account_name: account.name,
      account_level: account.level || "read",
      category_color: rec.category_color == null ? null : rec.category_color,
      // The iOS app's next date and "skip once" choices (#89).
      next_date: nexts.length ? nexts[0] : null,
      next_dates: nexts,
    };
  }

  // Every account's items with their dates looked up, [{account, rec, item}].
  function recurringItems(accounts, today, keep) {
    const out = [];
    for (const account of accounts || []) {
      const skips = byRecurring(account.skips);
      const paid = byRecurring(account.paid);
      for (const rec of account.recurring || []) {
        if (keep && !keep(rec)) continue;
        out.push({ rec: rec, item: recurringItem(rec, account, today, skips[rec.id] || [], paid[rec.id] || []) });
      }
    }
    return out;
  }

  // /api/recurring: the Bills & income page. `input`:
  //   today       the viewer's date
  //   archived    true for the ended items, false for the rest
  //   accounts    [{id, name, level, recurring, skips, paid}] in the order
  //               the page covers them:
  //     recurring   every repeating item on the account, switched off ones
  //                 too, as the forecast takes them, plus category_color,
  //                 match_days, match_percent and match_text
  //     skips       [{recurring_id, date}] every date deleted from the forecast
  //     paid        [{recurring_id, date}] the planned date of every line
  //                 from an item that's been marked paid
  // `totals` covers the listed items that are switched on and have a known
  // rhythm: bills and income a month and a year, and the net.
  function recurringList(input) {
    const today = input.today;
    const archived = !!input.archived;
    const items = [];
    let billsN = 0, incomeN = 0, billsM = 0, incomeM = 0;
    for (const found of recurringItems(input.accounts, today)) {
      if (archived !== found.item.expired) continue;
      items.push(found.item);
      const factor = monthlyFactor(found.rec.frequency);
      if (!truthy(found.rec.active) || factor === null) continue;
      // Unrounded, so the yearly totals don't drift by cents.
      const monthly = found.rec.amount * factor;
      if (monthly < 0) { billsN += 1; billsM += -monthly; } else { incomeN += 1; incomeM += monthly; }
    }
    items.sort((a, b) => cmpStr(a.description.toLowerCase(), b.description.toLowerCase())
      || cmpStr(a.account_name.toLowerCase(), b.account_name.toLowerCase()) || a.id - b.id);
    return {
      items: items,
      totals: {
        bills_count: billsN,
        bills_monthly: round2(billsM),
        bills_yearly: round2(billsM * 12),
        income_count: incomeN,
        income_monthly: round2(incomeM),
        income_yearly: round2(incomeM * 12),
        net_monthly: round2(incomeM - billsM),
        net_yearly: round2((incomeM - billsM) * 12),
      },
    };
  }

  // ---------- Search ----------

  // Newest first: the paid date, then the planned date (lines without one
  // last), then the newest line.
  function laterFirst(x, y) {
    if (x === y || (x == null && y == null)) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x < y ? 1 : -1;
  }

  function newestFirst(a, b) {
    return laterFirst(a.actual_date, b.actual_date) || laterFirst(a.forecast_date, b.forecast_date) || b.id - a.id;
  }

  function accountNames(accounts) {
    const out = {};
    for (const a of accounts || []) out[a.id] = a.name;
    return out;
  }

  // A transaction as the searches answer it.
  function searchRow(t, names) {
    return {
      id: t.id,
      account_id: t.account_id,
      account_name: Object.prototype.hasOwnProperty.call(names, t.account_id) ? names[t.account_id] : null,
      description: t.description || "",
      amount: t.amount,
      forecast_amount: t.forecast_amount == null ? null : t.forecast_amount,
      actual_date: t.actual_date == null ? null : t.actual_date,
      forecast_date: t.forecast_date == null ? null : t.forecast_date,
      is_actual: t.is_actual,
      category_id: t.category_id == null ? null : t.category_id,
      category_name: t.category == null ? null : t.category,
      recurring_id: t.recurring_id == null ? null : t.recurring_id,
      transfer_id: t.transfer_id == null ? null : t.transfer_id,
      notes: t.notes || null,
    };
  }

  // /api/transactions/search. `input`:
  //   q, account_id, category_id, tag_id, date_from, date_to, min_amount,
  //   max_amount, kind ("income", "spending", "transfers" or null),
  //   include_transfers, limit, offset   the route's filters (the host
  //                checks the account and the tag are the viewer's)
  //   accounts     [{id, name}] the accounts the viewer can see
  //   transactions every line on those accounts: id, account_id,
  //                description, notes, amount, forecast_amount,
  //                actual_date, forecast_date, is_actual, category_id,
  //                category (its name), recurring_id, transfer_id, tags
  function searchTransactions(input) {
    const names = accountNames(input.accounts);
    const kind = input.kind == null ? null : input.kind;
    const includeTransfers = input.include_transfers == null ? true : !!input.include_transfers;
    const dropTransfers = (!includeTransfers || kind === "income" || kind === "spending") && kind !== "transfers";
    const needle = pyStrip(input.q || "").toLowerCase();
    const has = (v) => v !== null && v !== undefined;
    const found = (input.transactions || []).filter((t) => {
      if (!Object.prototype.hasOwnProperty.call(names, t.account_id)) return false;
      if (has(input.account_id) && t.account_id !== input.account_id) return false;
      if (has(input.category_id) && t.category_id !== input.category_id) return false;
      if (has(input.tag_id) && !(t.tags || []).some((tag) => tag.id === input.tag_id)) return false;
      if (has(input.date_from) && !((t.actual_date != null && t.actual_date >= input.date_from)
        || (t.forecast_date != null && t.forecast_date >= input.date_from))) return false;
      if (has(input.date_to) && !((t.actual_date != null && t.actual_date <= input.date_to)
        || (t.forecast_date != null && t.forecast_date <= input.date_to))) return false;
      if (dropTransfers && t.transfer_id != null) return false;
      if (kind === "transfers" && t.transfer_id == null) return false;
      const amount = t.amount;
      if (has(input.min_amount) && amount < input.min_amount) return false;
      if (has(input.max_amount) && amount > input.max_amount) return false;
      if (kind === "income" && amount <= 0) return false;
      if (kind === "spending" && amount >= 0) return false;
      if (needle && !(t.description || "").toLowerCase().includes(needle)
        && !(t.notes || "").toLowerCase().includes(needle)) return false;
      return true;
    }).sort(newestFirst);
    const limit = input.limit == null ? 100 : input.limit;
    const offset = input.offset == null ? 0 : input.offset;
    const from = Math.max(0, offset);
    const page = found.slice(from, from + Math.min(Math.max(1, limit), 1000)).map((t) => {
      const row = searchRow(t, names);
      row.tags = sortTags(t.tags);
      return row;
    });
    return { total: found.length, results: page, limit: limit, offset: offset };
  }

  // /api/search: everything matching `q`, grouped by kind, up to `limit` a
  // group (1 to 100) with each group's full count. `input`:
  //   q, limit, today
  //   accounts      the accounts the viewer can see, as recurringList takes
  //                 them, each with current_balance (unrounded)
  //   transactions  every line on them, as searchTransactions takes them
  //   categories    [{id, name, color}] the viewer's own
  //   tags          [{id, name, color}] the viewer's own
  //   reports       [{id, name, pinned}] the viewer's saved reports, in
  //                 their order
  // Matching is a "contains" on casefolded text: names, and descriptions
  // and notes for transactions and bills.
  function search(input) {
    const q = input.q || "";
    const limit = Math.max(1, Math.min(input.limit == null ? 20 : input.limit, 100));
    const needle = casefold(pyStrip(q));
    const groups = ["transactions", "recurring", "accounts", "categories", "tags", "reports"];
    const out = { query: needle ? pyStrip(q) : "" };
    if (!needle) {
      for (const g of groups) out[g] = { total: 0, results: [] };
      return out;
    }
    const hit = (...texts) => texts.some((t) => truthy(t) && casefold(t).includes(needle));
    const group = (rows) => ({ total: rows.length, results: rows.slice(0, limit) });
    const byName = (a, b) => cmpStr(casefold(a.name), casefold(b.name)) || a.id - b.id;
    const accounts = input.accounts || [];
    const names = accountNames(accounts);
    const txns = input.transactions || [];

    const lines = txns.filter((t) => Object.prototype.hasOwnProperty.call(names, t.account_id)
      && hit(t.description, t.notes)).sort(newestFirst).map((t) => {
      const row = searchRow(t, names);
      // Plus the day it's on: paid, or else planned.
      row.date = t.actual_date != null ? t.actual_date : t.forecast_date != null ? t.forecast_date : null;
      return row;
    });

    // Bills and income: those still running first, then the ended ones.
    const bills = recurringItems(accounts, input.today, (rec) => hit(rec.description, rec.notes))
      .map((f) => f.item)
      .sort((a, b) => (a.expired === b.expired ? 0 : a.expired ? 1 : -1)
        || cmpStr(casefold(a.description), casefold(b.description)) || a.id - b.id);

    const foundAccounts = accounts.filter((a) => hit(a.name)).map((a) => ({
      id: a.id, name: a.name, current_balance: round2(a.current_balance || 0), level: a.level || "read",
    })).sort(byName);

    // Categories and tags: with how many lines on the visible accounts carry each.
    const catCounts = {}, tagCounts = {};
    for (const t of txns) {
      if (!Object.prototype.hasOwnProperty.call(names, t.account_id)) continue;
      if (t.category_id != null) catCounts[t.category_id] = (catCounts[t.category_id] || 0) + 1;
      for (const tag of t.tags || []) tagCounts[tag.id] = (tagCounts[tag.id] || 0) + 1;
    }
    const counted = (rows, counts) => (rows || []).filter((r) => hit(r.name)).map((r) => ({
      id: r.id, name: r.name, color: r.color == null ? null : r.color, transaction_count: counts[r.id] || 0,
    })).sort(byName);

    out.transactions = group(lines);
    out.recurring = group(bills);
    out.accounts = group(foundAccounts);
    out.categories = group(counted(input.categories, catCounts));
    out.tags = group(counted(input.tags, tagCounts));
    out.reports = group((input.reports || []).filter((r) => hit(r.name))
      .map((r) => ({ id: r.id, name: r.name, pinned: !!r.pinned })));
    return out;
  }

  // ---------- CSV import ----------

  // The web app's CSV import (main._parse_csv_rows and the preview and
  // commit routes around it; Plans/standalone.md, phase 9, #243). Python's
  // csv.reader, datetime.strptime and float() are copied closely, so a file
  // gives the same rows here as on the server.

  const PY_SPACE_ONE = new RegExp("^" + PY_SPACE + "$");
  const ND = /^\p{Nd}$/u;

  // A Unicode decimal digit's value (Python's int() and float() take them
  // all): its place in its run of ten.
  function digitValue(ch) {
    let cp = ch.codePointAt(0);
    let start = cp;
    while (start > 0 && ND.test(String.fromCodePoint(start - 1))) start--;
    return (cp - start) % 10;
  }

  // Every Unicode decimal digit as its ASCII digit, Python-style.
  function asciiDigits(s) {
    let out = "";
    for (const ch of s) out += ch.length === 1 && ch >= "0" && ch <= "9" ? ch : ND.test(ch) ? String(digitValue(ch)) : ch;
    return out;
  }

  // Python's csv.reader, default (excel) dialect, over a StringIO: lines end
  // at "\n" only, and "\r" or "\n" outside quotes ends a record. Python
  // raises on a line break inside an unquoted field followed by more text
  // and on a field over its limit; so does this.
  const CSV_FIELD_LIMIT = 131072;
  function csvReader(text) {
    const rows = [];
    const START_RECORD = 0, START_FIELD = 1, IN_FIELD = 2, IN_QUOTED_FIELD = 3, QUOTE_IN_QUOTED_FIELD = 4, EAT_CRNL = 5;
    let state = START_RECORD;
    let fields = [];
    let field = [];
    function save() {
      fields.push(field.join(""));
      field = [];
    }
    function add(c) {
      if (field.length >= CSV_FIELD_LIMIT) throw new Error("field larger than field limit (" + CSV_FIELD_LIMIT + ")");
      field.push(c);
    }
    const breaks = (c) => c === "\n" || c === "\r";
    // c is one character, or null for the end of a line.
    function step(c) {
      switch (state) {
        case START_RECORD:
          if (c === null) return;
          if (breaks(c)) { state = EAT_CRNL; return; }
          state = START_FIELD;
        // falls through
        case START_FIELD:
          if (c === null || breaks(c)) { save(); state = c === null ? START_RECORD : EAT_CRNL; }
          else if (c === '"') state = IN_QUOTED_FIELD;
          else if (c === ",") save();
          else { add(c); state = IN_FIELD; }
          return;
        case IN_FIELD:
          if (c === null || breaks(c)) { save(); state = c === null ? START_RECORD : EAT_CRNL; }
          else if (c === ",") { save(); state = START_FIELD; }
          else add(c);
          return;
        case IN_QUOTED_FIELD:
          if (c === null) return;
          if (c === '"') state = QUOTE_IN_QUOTED_FIELD;
          else add(c);
          return;
        case QUOTE_IN_QUOTED_FIELD:
          if (c === '"') { add(c); state = IN_QUOTED_FIELD; }
          else if (c === ",") { save(); state = START_FIELD; }
          else if (c === null || breaks(c)) { save(); state = c === null ? START_RECORD : EAT_CRNL; }
          else { add(c); state = IN_FIELD; }
          return;
        case EAT_CRNL:
          if (c !== null && breaks(c)) return;
          if (c === null) { state = START_RECORD; return; }
          throw new Error("new-line character seen in unquoted field - do you need to open the file with newline=''?");
      }
    }
    let at = 0;
    while (at < text.length) {
      const nl = text.indexOf("\n", at);
      const line = nl < 0 ? text.slice(at) : text.slice(at, nl + 1);
      at = nl < 0 ? text.length : nl + 1;
      for (const c of line) step(c);
      step(null);
      if (state === START_RECORD) {
        rows.push(fields);
        fields = [];
      }
    }
    // The file ended inside a quoted field: Python keeps what it has.
    if (state !== START_RECORD && (field.length !== 0 || state === IN_QUOTED_FIELD)) {
      save();
      rows.push(fields);
    }
    return rows;
  }

  // Python's str[:n], counting code points.
  function cutCodePoints(s, n) {
    if (s.length <= n) return s;
    return Array.from(s).slice(0, n).join("");
  }

  // _detect_columns: the usual bank column names.
  function detectColumns(headers) {
    const m = { date: null, description: null, amount: null, debit: null, credit: null, category: null, notes: null,
      tags: null, frequency: null, end_date: null, recurring_group: null };
    const rules = [
      ["date", ["date", "transaction date", "posted date", "post date"]],
      ["description", ["description", "details", "memo", "merchant", "name", "payee"]],
      ["amount", ["amount", "value", "transaction amount"]],
      ["debit", ["debit", "withdrawal", "withdrawals", "outflow"]],
      ["credit", ["credit", "deposit", "deposits", "inflow"]],
      ["category", ["category"]],
      ["tags", ["tags", "tag", "labels"]],
      ["notes", ["notes", "note"]],
      ["frequency", ["frequency", "recurring", "repeat", "recurrence"]],
      ["end_date", ["end date", "recurring end date", "until"]],
      ["recurring_group", ["recurring group", "group"]],
    ];
    headers.forEach((raw, i) => {
      const h = pyStrip(raw || "").toLowerCase();
      // An if/elif chain: the first rule whose column is still free and
      // whose names hold the header takes it.
      for (const [key, names] of rules) {
        if (m[key] === null && names.indexOf(h) >= 0) { m[key] = i; break; }
      }
    });
    return m;
  }

  const FREQUENCY_ALIASES = {
    "monthly": "monthly_day", "monthly_day": "monthly_day", "month": "monthly_day",
    "weekly": "weekly", "week": "weekly",
    "biweekly": "biweekly", "bi-weekly": "biweekly", "bi weekly": "biweekly",
    "fortnightly": "biweekly", "every 2 weeks": "biweekly", "every two weeks": "biweekly",
  };

  function normalizeFrequency(raw) {
    if (!raw) return null;
    const key = pyStrip(raw).toLowerCase();
    return Object.prototype.hasOwnProperty.call(FREQUENCY_ALIASES, key) ? FREQUENCY_ALIASES[key] : null;
  }

  // Python's float() on text already stripped: Unicode digits, "_" between
  // digits, "inf" and "nan" (which _parse_csv_amount turns away anyway).
  const PY_FLOAT = /^[+-]?(?:(?:\d(?:_?\d)*)?\.\d(?:_?\d)*|\d(?:_?\d)*\.?)(?:[eE][+-]?\d(?:_?\d)*)?$/;
  const PY_FLOAT_WORD = /^[+-]?(?:inf|infinity|nan)$/i;
  function pyFloat(s) {
    let t = "";
    for (const ch of s) t += PY_SPACE_ONE.test(ch) ? " " : ch;
    t = asciiDigits(t).replace(/^ +| +$/g, "");
    if (PY_FLOAT_WORD.test(t)) return t.indexOf("n") >= 0 && /nan/i.test(t) ? NaN : t[0] === "-" ? -Infinity : Infinity;
    if (!PY_FLOAT.test(t)) return null;
    return Number(t.replace(/_/g, ""));
  }

  // _parse_csv_amount.
  function parseCsvAmount(raw) {
    if (raw === null || raw === undefined) return null;
    let s = pyStrip(String(raw));
    if (!s) return null;
    const neg = s.startsWith("(") && s.endsWith(")");
    s = pyStrip(s.replace(/[()$£€,]/g, ""));
    const v = pyFloat(s);
    if (v === null || !isFinite(v) || Math.abs(v) > 1e12) return null;
    return neg ? -v : v;
  }

  // datetime.strptime for the formats _parse_csv_date tries, built as
  // Python's _strptime builds them: its patterns for each directive, the
  // format's whitespace as \s+, case-insensitive, matched from the start
  // and refused when text is left over.
  const CSV_MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
  const DIRECTIVES = {
    d: "(3[0-1]|[1-2]\\p{Nd}|0[1-9]|[1-9]| [1-9])",
    m: "(1[0-2]|0[1-9]|[1-9])",
    y: "(\\p{Nd}\\p{Nd})",
    Y: "(\\p{Nd}\\p{Nd}\\p{Nd}\\p{Nd})",
    b: "(" + CSV_MONTHS.join("|") + ")",
  };
  const DATE_FORMATS = ["%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d/%m/%Y", "%d/%m/%y",
    "%Y/%m/%d", "%m-%d-%Y", "%d-%m-%Y", "%b %d, %Y", "%d %b %Y"].map((format) => {
    const order = [];
    let source = "";
    for (let i = 0; i < format.length; i++) {
      if (format[i] === "%") {
        const d = format[++i];
        order.push(d);
        source += DIRECTIVES[d];
      } else if (format[i] === " ") {
        source += PY_SPACE + "+";
      } else {
        source += format[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      }
    }
    return { re: new RegExp("^(?:" + source + ")", "iu"), order: order };
  });

  function pyInt(s) {
    let n = 0;
    for (const ch of s) n = n * 10 + (ch >= "0" && ch <= "9" ? +ch : digitValue(ch));
    return n;
  }

  function daysIn(year, month) {
    return [31, (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0 ? 29 : 28,
      31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  }

  // _parse_csv_date: "YYYY-MM-DD", or null.
  function parseCsvDate(raw) {
    if (raw === null || raw === undefined) return null;
    const s = pyStrip(String(raw));
    if (!s) return null;
    for (const f of DATE_FORMATS) {
      const found = f.re.exec(s);
      if (!found || found[0].length !== s.length) continue;
      let year = 1900, month = 1, day = 1, ok = true;
      f.order.forEach((d, i) => {
        const v = found[i + 1];
        if (d === "Y") year = pyInt(v);
        else if (d === "y") { year = pyInt(v); year += year <= 68 ? 2000 : 1900; }
        else if (d === "m") month = pyInt(v);
        else if (d === "d") day = pyInt(pyStrip(v));
        else if (d === "b") { month = CSV_MONTHS.indexOf(v.toLowerCase()) + 1; if (month === 0) ok = false; }
      });
      if (!ok || year < 1 || day > daysIn(year, month)) continue;
      return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2);
    }
    return null;
  }

  const DESCRIPTION_MAX = 500;
  const NOTES_MAX = 256;

  // _parse_csv_rows: {rows, skipped, headers, mapping}.
  function parseCsvRows(text, hasHeader, mapping, signConvention) {
    const all = csvReader(text);
    if (!all.length) return { rows: [], skipped: [], headers: [], mapping: mapping || {} };
    let headers, body;
    if (hasHeader) {
      headers = all[0];
      body = all.slice(1);
    } else {
      headers = all[0].map((_, i) => "col_" + (i + 1));
      body = all;
    }
    if (mapping === null || mapping === undefined) mapping = detectColumns(headers);
    const rows = [];
    const skipped = [];
    body.forEach((row, idx) => {
      function cell(key) {
        const i = Object.prototype.hasOwnProperty.call(mapping, key) ? mapping[key] : null;
        if (i === null || i === undefined || !(i >= 0 && i < row.length)) return null;
        return row[i];
      }
      const d = parseCsvDate(cell("date"));
      const desc = cutCodePoints(pyStrip(cell("description") || ""), DESCRIPTION_MAX) || "(no description)";
      let amt;
      if (signConvention === "debit_credit") {
        const deb = parseCsvAmount(cell("debit")) || 0;
        const cred = parseCsvAmount(cell("credit")) || 0;
        amt = deb || cred ? cred - deb : null;
      } else {
        amt = parseCsvAmount(cell("amount"));
        if (signConvention === "amount_invert" && amt !== null) amt = -amt;
      }
      let notes = cell("notes");
      if (notes) notes = cutCodePoints(pyStrip(notes), NOTES_MAX) || null;
      const categoryName = pyStrip(cell("category") || "") || null;
      const tagsRaw = cell("tags");
      const tagNames = tagsRaw ? tagsRaw.split(/[;,]/).map(pyStrip).filter((p) => p) : [];
      const freqRaw = pyStrip(cell("frequency") || "") || null;
      const frequency = freqRaw ? normalizeFrequency(freqRaw) : null;
      if (freqRaw && frequency === null) {
        skipped.push({ row_index: idx, row: row, reason: 'unrecognized frequency "' + freqRaw + '"' });
        return;
      }
      const endDate = parseCsvDate(cell("end_date"));
      const group = pyStrip(cell("recurring_group") || "") || null;
      if (d === null || amt === null) {
        skipped.push({ row_index: idx, row: row, reason: "missing date or amount" });
        return;
      }
      rows.push({
        row_index: idx, date: d, description: desc, amount: amt, notes: notes, category_name: categoryName,
        tag_names: tagNames, frequency: frequency, end_date: endDate, recurring_group: group, raw: row,
      });
    });
    return { rows: rows, skipped: skipped, headers: headers, mapping: mapping };
  }

  // What the preview and the import both work from: the file's rows, the
  // account's lines as duplicate keys, its bills by (rhythm, name), and the
  // categories and tags by name without case (the last of a name wins, as
  // in the server's dict).
  function csvContext(input) {
    const parsed = parseCsvRows(input.csv_text, input.has_header !== false, input.mapping === undefined ? null : input.mapping,
      input.sign_convention || "amount");
    const keyOf = (date, amount, description) => date + "\u0000" + round2(amount) + "\u0000" + pyStrip(description).toLowerCase();
    const lineKeys = new Set((input.lines || []).map((l) => keyOf(l.date, l.amount, l.description || "")));
    const templates = {};
    for (const r of input.recurring || []) {
      const k = r.frequency + "\u0000" + pyStrip(r.description || "").toLowerCase();
      if (!Object.prototype.hasOwnProperty.call(templates, k)) templates[k] = r.id;
    }
    const byName = (list) => {
      const out = {};
      for (const x of list || []) out[pyStrip(x.name).toLowerCase()] = x.id;
      return out;
    };
    const categories = byName(input.categories);
    const tags = byName(input.tags);
    const groupKey = (r) => pyStrip(r.recurring_group || r.description).toLowerCase();
    // _resolve_recurring_groups: each (rhythm, group) and the bill it joins,
    // judged by the group's latest row (the first of equal dates).
    const groups = new Map();
    for (const r of parsed.rows) {
      if (!r.frequency) continue;
      const g = r.frequency + "\u0000" + groupKey(r);
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g).push(r);
    }
    const resolved = new Map();
    for (const [g, list] of groups) {
      let seed = list[0];
      for (const r of list) if (r.date > seed.date) seed = r;
      const id = templates[seed.frequency + "\u0000" + pyStrip(seed.description).toLowerCase()];
      resolved.set(g, { existing: id === undefined ? null : id, seed: seed });
    }
    const has = (map, k) => Object.prototype.hasOwnProperty.call(map, k);
    return {
      parsed: parsed, lineKeys: lineKeys, keyOf: keyOf, resolved: resolved,
      groupOf: (r) => r.frequency + "\u0000" + groupKey(r),
      categoryOf: (r, fallback) => {
        const name = r.category_name;
        if (name) {
          const k = pyStrip(name).toLowerCase();
          if (has(categories, k)) return categories[k];
        }
        return fallback;
      },
      categoryMatched: (r) => !!r.category_name && has(categories, pyStrip(r.category_name).toLowerCase()),
      tagsOf: (r) => {
        const matched = [], unmatched = [];
        for (const name of r.tag_names) {
          const k = pyStrip(name).toLowerCase();
          if (has(tags, k)) matched.push(tags[k]);
          else unmatched.push(name);
        }
        return { matched: matched, unmatched: unmatched };
      },
    };
  }

  // POST /api/accounts/{id}/import/preview. Input: csv_text, has_header,
  // mapping (null to detect), sign_convention, and from the account: lines
  // [{date, amount, description}] (the date paid, else planned), recurring
  // [{id, frequency, description}], categories and tags [{id, name}].
  function csvPreview(input) {
    const ctx = csvContext(input);
    const rows = ctx.parsed.rows;
    let duplicates = 0, repeating = 0;
    for (const r of rows) {
      r.duplicate = ctx.lineKeys.has(ctx.keyOf(r.date, r.amount, r.description));
      if (r.duplicate) duplicates++;
      r.category_matched = ctx.categoryMatched(r);
      r.tags_unmatched = ctx.tagsOf(r).unmatched;
      if (r.frequency) {
        repeating++;
        r.recurring_template = ctx.resolved.get(ctx.groupOf(r)).existing === null ? "new" : "existing";
      } else {
        r.recurring_template = null;
      }
    }
    return {
      headers: ctx.parsed.headers,
      mapping: ctx.parsed.mapping,
      rows: rows.slice(0, 200),
      row_count: rows.length,
      skipped: ctx.parsed.skipped.slice(0, 50),
      skipped_count: ctx.parsed.skipped.length,
      duplicate_count: duplicates,
      recurring_count: repeating,
      sign_convention: input.sign_convention || "amount",
      has_header: input.has_header !== false,
    };
  }

  // POST /api/accounts/{id}/import/commit, as a plan the host carries out:
  // the bills to make (in the order the server makes them), the lines to
  // add (each with its bill: {"new": place} or {"id": an existing one}, and
  // its tags, each once, #248) and the answer. Input as csvPreview, plus
  // default_category_id and skip_duplicates.
  function csvCommit(input) {
    const ctx = csvContext(input);
    const skip = input.skip_duplicates !== false;
    const fallback = input.default_category_id === undefined ? null : input.default_category_id;
    const existing = skip ? ctx.lineKeys : new Set();
    const made = new Map();
    const templates = [];
    const transactions = [];
    let inserted = 0, linked = 0, duplicates = 0;
    for (const r of ctx.parsed.rows) {
      const category = ctx.categoryOf(r, fallback);
      let recurring = null;
      if (r.frequency) {
        const g = ctx.groupOf(r);
        const info = ctx.resolved.get(g);
        if (info.existing !== null) {
          recurring = { id: info.existing };
        } else {
          if (!made.has(g)) {
            const seed = info.seed;
            const monthly = seed.frequency === "monthly_day";
            templates.push({
              category_id: ctx.categoryOf(seed, fallback),
              frequency: seed.frequency,
              day_of_month: monthly ? +seed.date.slice(8, 10) : null,
              anchor_date: monthly ? null : seed.date,
              end_date: seed.end_date,
              description: seed.description,
              amount: seed.amount,
              notes: seed.notes || null,
            });
            made.set(g, templates.length - 1);
          }
          recurring = { "new": made.get(g) };
        }
      }
      const key = ctx.keyOf(r.date, r.amount, r.description);
      if (skip && existing.has(key)) {
        duplicates++;
        continue;
      }
      existing.add(key);
      const tagIDs = Array.from(new Set(ctx.tagsOf(r).matched)).sort((a, b) => a - b);
      transactions.push({
        date: r.date, description: r.description, amount: r.amount, notes: r.notes || null,
        category_id: category, recurring: recurring, tag_ids: tagIDs,
      });
      inserted++;
      if (recurring !== null) linked++;
    }
    return {
      result: { ok: true, inserted: inserted, recurring_created: templates.length, recurring_linked: linked,
        duplicates_skipped: duplicates, total_rows: ctx.parsed.rows.length },
      templates: templates,
      transactions: transactions,
    };
  }

  // ---------- Bank matching ----------
  // Which planned bill or line a bank line pays, and the Unmatched list
  // (bank-sync phase 4, #196; taught names, #224; the match pop-in, #222,
  // #223, #231). Plans/standalone.md, phase 8 (#239).
  //
  // The server keeps amounts here as Python Decimals, compared exactly, so
  // the matching takes amounts as decimal strings ("-65.43", "10.005") and
  // works on them as exact decimals (a number is taken as Python's
  // str(float) would write it). Amounts it answers are floats, as the
  // server's float(Decimal) gives them.
  //
  // The rows every function below takes (the account's own):
  //   recurring:    every bill on the account, active or not: a forecast
  //                 row (id, frequency, day_of_month, anchor_date, end_date,
  //                 active, description, amount) with match_days,
  //                 match_percent and match_text (its taught name, or null).
  //   skips:        [{recurring_id, date}], the dates deleted from the forecast.
  //   transactions: every line on the account: id, recurring_id,
  //                 transfer_id, description, notes, amount, forecast_date,
  //                 actual_date, is_actual, bank_match, has_bank_ref,
  //                 has_mail_ref, bank_left.

  // An exact decimal: n * 10^-e, n a BigInt.
  function dec(v) {
    const s = typeof v === "number" ? String(v) : String(v).trim();
    const m = /^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(s);
    if (!m || (m[2] === "" && (m[3] || "") === "")) throw new Error("WalletWeatherCore: not an amount: " + s);
    const frac = m[3] || "";
    let n = BigInt((m[2] || "0") + frac);
    let e = frac.length - (m[4] ? parseInt(m[4], 10) : 0);
    if (e < 0) { n *= 10n ** BigInt(-e); e = 0; }
    return { n: m[1] === "-" ? -n : n, e: e };
  }
  function decAlign(a, b) {
    const e = Math.max(a.e, b.e);
    return [a.n * 10n ** BigInt(e - a.e), b.n * 10n ** BigInt(e - b.e), e];
  }
  function decSub(a, b) {
    const [x, y, e] = decAlign(a, b);
    return { n: x - y, e: e };
  }
  function decAbs(a) {
    return { n: a.n < 0n ? -a.n : a.n, e: a.e };
  }
  function decCmp(a, b) {
    const [x, y] = decAlign(a, b);
    return x < y ? -1 : x > y ? 1 : 0;
  }
  // Python's float(Decimal): the nearest double.
  function decFloat(a) {
    return parseFloat(a.n.toString() + "e-" + a.e);
  }

  // Python's str.isdigit(): Unicode decimal digits and the other digits
  // (superscripts, circled digits, ...). Checked against Python.
  const OTHER_DIGITS = [[0xB2, 0xB3], [0xB9, 0xB9], [0x1369, 0x1371], [0x19DA, 0x19DA], [0x2070, 0x2070],
    [0x2074, 0x2079], [0x2080, 0x2089], [0x2460, 0x2468], [0x2474, 0x247C], [0x2488, 0x2490],
    [0x24EA, 0x24EA], [0x24F5, 0x24FD], [0x24FF, 0x24FF], [0x2776, 0x277E], [0x2780, 0x2788],
    [0x278A, 0x2792], [0x10A40, 0x10A43], [0x10E60, 0x10E68], [0x11052, 0x1105A], [0x1F100, 0x1F10A]];
  function isDigit(ch) {
    if (ND.test(ch)) return true;
    const cp = ch.codePointAt(0);
    return OTHER_DIGITS.some(([lo, hi]) => lo <= cp && cp <= hi);
  }

  const PY_SPACES = new RegExp(PY_SPACE + "+", "g");
  const MATCH_SPLIT = new RegExp("(?:" + PY_SPACE + "|[*#])+");
  // _match_key: how a taught name is compared (#224, #230), ignoring case,
  // spaces and codes. Split on spaces, "*" and "#", drop each piece with a
  // digit in it, so "AMAZON MKTPL*2K4AB1" and "AMAZON MKTPL*9XZ3" are both
  // "amazon mktpl". A name with nothing left is compared as itself.
  function matchKey(text) {
    const plain = pyStrip((text || "").toLowerCase()).split(PY_SPACES).filter((w) => w).join(" ");
    const words = plain.split(MATCH_SPLIT).filter((w) => w && !Array.from(w).some(isDigit));
    return words.join(" ") || plain;
  }

  // simplefin.short_name: a synced line's name when the bank's text carries
  // more than a name, the part before " / " without a leading "Withdrawal"
  // or "Deposit" (#213); null when there's nothing to shorten.
  const NAME_MAX = 120;
  const DIRECTION = new RegExp("^(?:(?:ACH|POS|Debit Card|Online|Mobile|External)" + PY_SPACE + "+)?" +
    "(?:Withdrawal|Deposit)(?:" + PY_SPACE + "+|$)", "iu");
  function shortName(text) {
    if (!text || text.indexOf(" / ") < 0) return null;
    const head = pyStrip(pyStrip(text.split(" / ")[0]).replace(DIRECTION, ""));
    return head ? cutCodePoints(head, NAME_MAX) : null;
  }

  // The name a bill learns from a synced line (_line_name): its short name,
  // worked out again from the bank's text in its notes, else its name.
  function lineName(t) {
    return (t.notes ? shortName(t.notes) : null) || t.description;
  }

  // _bank_text_of: the bank's full text when the name was shortened from it.
  function bankTextOf(t) {
    if (t.notes && shortName(t.notes) === t.description) return t.notes;
    return t.description;
  }

  function lineSource(t) {
    return t.has_mail_ref ? "alert" : "bank";
  }

  function lineDay(t) {
    return t.actual_date || t.forecast_date;
  }

  // _unmatched_query: synced lines that paid no planned line and are still
  // to look at.
  function isUnmatched(t) {
    return !!(t.has_bank_ref || t.has_mail_ref) && t.bank_match == null && !t.bank_left &&
      t.recurring_id == null && t.transfer_id == null && !!t.is_actual;
  }

  const MATCH_BY_HAND_DAYS = 60;
  const DEFAULT_MATCH_DAYS = 5;

  // _bills_to_match: the active bills, the bill dates already on a line
  // (any line of the account with the bill and a date), the active bills'
  // deleted dates and their taught names.
  function billsToMatch(input) {
    const recs = (input.recurring || []).filter((r) => r.active === true);
    const active = new Set(recs.map((r) => r.id));
    const covered = new Set();
    for (const t of input.transactions || []) {
      if (t.recurring_id != null && t.forecast_date != null) covered.add(t.recurring_id + "|" + t.forecast_date);
    }
    const skipped = new Set();
    for (const s of input.skips || []) if (active.has(s.recurring_id)) skipped.add(s.recurring_id + "|" + s.date);
    const taught = new Map();
    for (const r of recs) if (r.match_text) taught.set(r.id, matchKey(r.match_text));
    return { recs: recs, covered: covered, skipped: skipped, taught: taught };
  }

  function isOpen(bills, rid, iso) {
    return !bills.covered.has(rid + "|" + iso) && !bills.skipped.has(rid + "|" + iso);
  }

  // _bill_for_bank_line: {rec, day} the bank line pays, or null (no match,
  // or a tie). It goes the bill's way, is within the bill's match_percent of
  // its amount and within match_days of an open date; the nearest date
  // wins. A bill taught the line's name takes it at any amount going its
  // way within its days, and is preferred over the bills that fit by amount.
  function billForBankLine(bills, dayIso, amountDec, name) {
    const taught = bills.taught;
    const key = name && taught.size ? matchKey(name) : null;
    const day = dayNumber(dayIso);
    let found = [];
    for (const rec of bills.recs) {
      const planned = dec(rec.amount);
      if (planned.n === 0n || amountDec.n === 0n || (planned.n < 0n) !== (amountDec.n < 0n)) continue;
      const named = key !== null && taught.get(rec.id) === key;
      if (!named) {
        // abs(amount - planned) > abs(planned) * match_percent / 100
        const diff = decAbs(decSub(amountDec, planned));
        const limit = decAbs(planned);
        if (decCmp({ n: diff.n * 100n, e: diff.e }, { n: limit.n * BigInt(rec.match_percent), e: limit.e }) > 0) continue;
      }
      for (const o of occurrences(rec, day - rec.match_days, day + rec.match_days)) {
        const iso = isoOf(o.day);
        if (isOpen(bills, rec.id, iso)) found.push({ apart: Math.abs(o.day - day), rec: rec, day: iso });
      }
    }
    if (key !== null) {
      const mine = found.filter((f) => taught.get(f.rec.id) === key);
      if (mine.length) found = mine;
    }
    if (!found.length) return null;
    found.sort((a, b) => a.apart - b.apart);
    if (found.length > 1 && found[1].apart === found[0].apart) return null;
    return { rec: found[0].rec, day: found[0].day };
  }

  // Bank sync's matching (_bank_sync_locked): the new bank lines in the
  // order they arrive, each paying a bill's date or not. Input: the
  // account's rows (above) and lines: [{date, amount, text}], text the
  // bank's own. A line is matched by its short name when it has one. Each
  // answer is {recurring_id, forecast_date} or null (it lands as its own
  // line); a date one line pays isn't open to the next.
  function bankMatch(input) {
    const bills = billsToMatch(input);
    return (input.lines || []).map((line) => {
      const hit = billForBankLine(bills, line.date, dec(line.amount), shortName(line.text) || line.text);
      if (!hit) return null;
      bills.covered.add(hit.rec.id + "|" + hit.day);
      return { recurring_id: hit.rec.id, forecast_date: hit.day };
    });
  }

  // GET /api/accounts/{id}/bank-unmatched: the Unmatched list, newest first.
  // Input: transactions (above).
  function bankUnmatched(input) {
    const rows = (input.transactions || []).filter(isUnmatched).sort((a, b) => {
      // ORDER BY actual_date DESC (PostgreSQL puts no date first), id DESC.
      if (a.actual_date !== b.actual_date) {
        if (a.actual_date == null) return -1;
        if (b.actual_date == null) return 1;
        return cmpIso(b.actual_date, a.actual_date);
      }
      return b.id - a.id;
    });
    return {
      count: rows.length,
      lines: rows.map((t) => ({ id: t.id, date: lineDay(t), description: t.description,
        amount: decFloat(dec(t.amount)), notes: t.notes, source: lineSource(t) })),
    };
  }

  function unmatchedLine(input, id) {
    const t = (input.transactions || []).find((x) => x.id === id);
    if (!t || !isUnmatched(t)) throw new Error("That line isn't on the Unmatched list.");
    return t;
  }

  function lower(s) {
    return s.toLowerCase();
  }

  // _match_choices: the candidates as the match pop-in shows them (#222).
  function matchChoices(cands, amountDec, dayIso, reach) {
    const day = dayNumber(dayIso);
    const groups = new Map();
    for (const c of cands) {
      const planned = dec(c.amount);
      const opt = { transaction_id: c.transaction_id, recurring_id: c.recurring_id, forecast_date: c.forecast_date,
        amount: c.amount, description: c.description, days_apart: c.days_apart };
      opt.days_after = day - dayNumber(c.forecast_date);
      opt.amount_diff = decFloat(decSub(amountDec, planned));
      opt.same_direction = (planned.n < 0n) === (amountDec.n < 0n) && planned.n !== 0n;
      const r = c.recurring_id != null && reach.has(c.recurring_id) ? reach.get(c.recurring_id) : DEFAULT_MATCH_DAYS;
      opt.within_days = c.days_apart <= r;
      const key = c.recurring_id != null ? "r" + c.recurring_id : "t" + c.transaction_id;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(opt);
    }
    const choices = [];
    for (const opts of groups.values()) {
      let best = opts[0];
      for (const o of opts) {
        if (o.days_apart < best.days_apart || (o.days_apart === best.days_apart && cmpIso(o.forecast_date, best.forecast_date) < 0)) best = o;
      }
      choices.push(Object.assign({}, best, { dates: opts.slice().sort((a, b) => cmpIso(a.forecast_date, b.forecast_date)) }));
    }
    choices.sort((a, b) => (a.same_direction === b.same_direction ? 0 : a.same_direction ? -1 : 1) ||
      a.days_apart - b.days_apart || Math.abs(a.amount_diff) - Math.abs(b.amount_diff) ||
      cmpStr(lower(a.description), lower(b.description)));
    return choices;
  }

  // GET /api/accounts/{id}/bank-unmatched/{line}/candidates: the account's
  // planned lines and open bill dates within 60 days of an Unmatched line,
  // nearest first, whatever a bill's match settings say, and the same as
  // the match pop-in's choices. Input: the account's rows (above) and
  // transaction_id, the Unmatched line's.
  function bankCandidates(input) {
    const line = unmatchedLine(input, input.transaction_id);
    const dayIso = lineDay(line);
    const day = dayNumber(dayIso);
    const lo = day - MATCH_BY_HAND_DAYS;
    const hi = day + MATCH_BY_HAND_DAYS;
    const out = [];
    for (const t of input.transactions || []) {
      if (t.is_actual || t.transfer_id != null || t.forecast_date == null) continue;
      const fd = dayNumber(t.forecast_date);
      if (fd < lo || fd > hi) continue;
      out.push({ transaction_id: t.id, recurring_id: t.recurring_id, forecast_date: t.forecast_date,
        description: t.description, amount: decFloat(dec(t.amount)), days_apart: Math.abs(fd - day) });
    }
    const bills = billsToMatch(input);
    for (const rec of bills.recs) {
      for (const o of occurrences(rec, lo, hi)) {
        const iso = isoOf(o.day);
        if (!isOpen(bills, rec.id, iso)) continue;
        out.push({ transaction_id: null, recurring_id: rec.id, forecast_date: iso, description: rec.description,
          amount: decFloat(dec(rec.amount)), days_apart: Math.abs(o.day - day) });
      }
    }
    out.sort((a, b) => a.days_apart - b.days_apart || cmpIso(a.forecast_date, b.forecast_date) ||
      cmpStr(lower(a.description), lower(b.description)));
    const amount = dec(line.amount);
    const bankText = bankTextOf(line);
    const reach = new Map(bills.recs.map((r) => [r.id, r.match_days]));
    return {
      line: { id: line.id, date: dayIso, description: line.description, amount: decFloat(amount),
        source: lineSource(line), bank_text: bankText !== line.description ? bankText : null,
        learn_name: lineName(line) },
      candidates: out.slice(0, 50),
      choices: matchChoices(out, amount, dayIso, reach).slice(0, 50),
    };
  }

  // _planned_target: a planned line a bank line could pay, or the server's
  // error saying why not.
  function plannedTarget(input, given) {
    if (given.transaction_id != null) {
      const t = (input.transactions || []).find((x) => x.id === given.transaction_id);
      if (!t) throw new Error("Planned line not found");
      if (t.is_actual || t.transfer_id != null || t.forecast_date == null) {
        throw new Error("That line is already paid, or is a transfer: pick a planned line.");
      }
      return { transaction_id: t.id, recurring_id: t.recurring_id, forecast_date: t.forecast_date,
        description: t.description, amount: decFloat(dec(t.amount)) };
    }
    if (given.recurring_id != null && given.forecast_date != null) {
      const rec = (input.recurring || []).find((r) => r.id === given.recurring_id);
      if (!rec) throw new Error("Bill not found");
      const d = dayNumber(given.forecast_date);
      if (!occurrences(rec, d, d).some((o) => o.day === d)) throw new Error("That bill has no date on that day.");
      if (!isOpen(billsToMatch(input), rec.id, given.forecast_date)) {
        throw new Error("That date is already paid or was deleted: pick a planned line.");
      }
      return { transaction_id: null, recurring_id: rec.id, forecast_date: given.forecast_date,
        description: rec.description, amount: decFloat(dec(rec.amount)) };
    }
    throw new Error("Give transaction_id, or recurring_id and forecast_date.");
  }

  // GET /api/accounts/{id}/bank-unmatched/near: the Unmatched lines that
  // could pay one planned line (#223), within 60 days of its date, lines
  // going its way first, then the nearest. Input: the account's rows
  // (above) and planned: {transaction_id} or {recurring_id, forecast_date}.
  function bankNear(input) {
    const planned = plannedTarget(input, input.planned || {});
    const day = dayNumber(planned.forecast_date);
    const want = dec(planned.amount);
    const rec = planned.recurring_id != null ? (input.recurring || []).find((r) => r.id === planned.recurring_id) : null;
    const days = rec ? rec.match_days : DEFAULT_MATCH_DAYS;
    const out = [];
    for (const t of input.transactions || []) {
      if (!isUnmatched(t)) continue;
      const whenIso = lineDay(t);
      if (whenIso == null) continue;
      const when = dayNumber(whenIso);
      if (when < day - MATCH_BY_HAND_DAYS || when > day + MATCH_BY_HAND_DAYS) continue;
      const text = bankTextOf(t);
      const amount = dec(t.amount);
      out.push({ id: t.id, date: whenIso, description: t.description, amount: decFloat(amount),
        source: lineSource(t), bank_text: text !== t.description ? text : null, learn_name: lineName(t),
        days_apart: Math.abs(when - day), days_after: when - day, amount_diff: decFloat(decSub(amount, want)),
        same_direction: (amount.n < 0n) === (want.n < 0n) && want.n !== 0n,
        within_days: Math.abs(when - day) <= days });
    }
    out.sort((a, b) => (a.same_direction === b.same_direction ? 0 : a.same_direction ? -1 : 1) ||
      a.days_apart - b.days_apart || Math.abs(a.amount_diff) - Math.abs(b.amount_diff) || a.id - b.id);
    return { planned: planned, match_days: days, lines: out.slice(0, 50) };
  }

  // _catch_up_taught: after a bill is taught a name (matching by hand with
  // "remember", #224), the Unmatched lines with that name pay its open
  // dates, oldest first, each within the bill's days at any amount going
  // its way. Input: the account's rows (above), the bill's match_text
  // already set, and recurring_id. Answers [{transaction_id,
  // forecast_date}]: the Unmatched line and the date it pays.
  function bankCatchUp(input) {
    const rec = (input.recurring || []).find((r) => r.id === input.recurring_id);
    if (!rec) throw new Error("Bill not found");
    const key = matchKey(rec.match_text);
    const bills = billsToMatch(input);
    const only = { recs: [rec], covered: bills.covered, skipped: bills.skipped, taught: new Map([[rec.id, key]]) };
    const lines = (input.transactions || []).filter(isUnmatched).sort((a, b) => {
      // ORDER BY actual_date (PostgreSQL puts no date last), id.
      if (a.actual_date !== b.actual_date) {
        if (a.actual_date == null) return 1;
        if (b.actual_date == null) return -1;
        return cmpIso(a.actual_date, b.actual_date);
      }
      return a.id - b.id;
    });
    const out = [];
    for (const t of lines) {
      const name = lineName(t);
      if (matchKey(name) !== key) continue;
      const hit = billForBankLine(only, lineDay(t), dec(t.amount), name);
      if (!hit) continue;
      only.covered.add(rec.id + "|" + hit.day);
      out.push({ transaction_id: t.id, forecast_date: hit.day });
    }
    return out;
  }

  // ---------- Entry point ----------

  // forecast._occurrences for the hosts: a repeating item's dates in a
  // window, [{date, amount, description}].
  function occurrenceDates(input) {
    return occurrences(input.recurring, dayNumber(input.start), dayNumber(input.end))
      .map((o) => ({ date: isoOf(o.day), amount: o.amount, description: o.description }));
  }

  const functions = {
    forecast: forecast,
    occurrences: occurrenceDates,
    dashboard: dashboard,
    dashboardCharts: dashboardCharts,
    actualBalanceAsOf: actualBalanceAsOf,
    upcomingDates: upcomingDates,
    calendar: calendar,
    recurringList: recurringList,
    searchTransactions: searchTransactions,
    search: search,
    csvPreview: csvPreview,
    csvCommit: csvCommit,
    bankMatch: bankMatch,
    bankUnmatched: bankUnmatched,
    bankCandidates: bankCandidates,
    bankNear: bankNear,
    bankCatchUp: bankCatchUp,
  };

  // What the hosts call: a function name and a JSON string in, a JSON
  // string out.
  function run(name, json) {
    if (!Object.prototype.hasOwnProperty.call(functions, name)) throw new Error("WalletWeatherCore has no function " + name);
    return JSON.stringify(functions[name](JSON.parse(json)));
  }

  root.WalletWeatherCore = {
    version: "0.5.0",
    run: run,
    forecast: forecast,
    actualBalanceAsOf: actualBalanceAsOf,
    upcomingDates: upcomingDates,
    calendar: calendar,
    dashboard: dashboard,
    dashboardCharts: dashboardCharts,
    occurrences: occurrenceDates,
    recurringList: recurringList,
    searchTransactions: searchTransactions,
    search: search,
    csvPreview: csvPreview,
    csvCommit: csvCommit,
    bankMatch: bankMatch,
    bankUnmatched: bankUnmatched,
    bankCandidates: bankCandidates,
    bankNear: bankNear,
    bankCatchUp: bankCatchUp,
    // For the tests: the date and rounding helpers.
    _dayNumber: dayNumber,
    _isoOf: isoOf,
    _round2: round2,
    _pySum: pySum,
    _pyStrip: pyStrip,
    _casefold: casefold,
    _csvReader: csvReader,
    _parseCsvDate: parseCsvDate,
    _parseCsvAmount: parseCsvAmount,
    _matchKey: matchKey,
    _shortName: shortName,
    _isDigit: isDigit,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
