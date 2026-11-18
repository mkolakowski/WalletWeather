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

  // Python's str < str: by code point, not UTF-16 unit or locale.
  function cmpStr(a, b) {
    if (a === b) return 0;
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
      if (ref && dayNumber(ref) < start && truthy(t.is_actual)) opening += t.amount;
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
      if (!anchor) continue;
      const a = dayNumber(anchor);
      if (!(start <= a && a <= end)) continue;

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
    events.sort((x, y) => cmpStr(sortDay(x), sortDay(y))
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
    const byActual = events.map((_, i) => i).sort((i, j) => cmpStr(actualDay(events[i]), actualDay(events[j])));
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
        if (cmpStr(od, d) < 0 || (od === d && pos[j] <= pos[i])) amounts.push(truthy(other.forecast_amount) ? other.forecast_amount : 0.0);
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
      if (cmpStr(r.actual_date || r.forecast_date || "", cutoff) <= 0) {
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

    events.sort((x, y) => cmpStr(x.date, y.date)
      || cmpStr(x.account_name, y.account_name)
      || cmpStr(x.description.toLowerCase(), y.description.toLowerCase()));
    return { start: input.start, end: input.end, events: events, daily_balances: daily };
  }

  // ---------- Entry point ----------

  const functions = {
    forecast: forecast,
    actualBalanceAsOf: actualBalanceAsOf,
    upcomingDates: upcomingDates,
    calendar: calendar,
  };

  // What the hosts call: a function name and a JSON string in, a JSON
  // string out.
  function run(name, json) {
    if (!Object.prototype.hasOwnProperty.call(functions, name)) throw new Error("WalletWeatherCore has no function " + name);
    return JSON.stringify(functions[name](JSON.parse(json)));
  }

  root.WalletWeatherCore = {
    version: "0.1.0",
    run: run,
    forecast: forecast,
    actualBalanceAsOf: actualBalanceAsOf,
    upcomingDates: upcomingDates,
    calendar: calendar,
    // For the tests: the date and rounding helpers.
    _dayNumber: dayNumber,
    _isoOf: isoOf,
    _round2: round2,
    _pySum: pySum,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
