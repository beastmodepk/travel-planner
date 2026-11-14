// Travel Planner web — UI. Same features as the iOS app, driven by the
// same dataset.json (a drift-checked copy of packages/dataset) and the
// same pricing engine (engine.js). State lives in localStorage; all
// pricing happens on-device. No accounts, no tracking.
(function () {
  'use strict';
  const E = window.TPEngine;

  // Destination photos (remote, with the designed gradient fallback when a
  // host blocks hotlinking or a photo fails). Same six sources as the
  // approved wireframes.
  const PHOTOS = {
    'park-city': 'https://www.bridgeaspire.com/wp-content/uploads/2025/12/Park-City-Main-Street-Winter-Historic-District.jpg',
    'tahoe': 'https://9483a395ff419bf71e77-9a13f87be9803cb0a767980e2aee38c5.ssl.cf1.rackcdn.com/responsive/Native/1200px/u/ski-areas/ski-resort-heavenly.jpg',
    'alta': 'https://myfamilytravels.com/wp-content/uploads/Alta_Lodge_Utah.jpg',
    'jackson': 'https://www.jacksonhole.net/userfiles/files/Snowboard-02%20(1)%20edited.jpg',
    'breckenridge': 'https://www.skiworld.co.uk/blog/wp-content/uploads/2018/11/Breckenridge_BRK3619_Jeff_Scroggins.jpg',
    'niseko': 'https://www.niseko.ne.jp/en/wp-content/uploads/2022/11/welcome-back-to-niseko-japan.jpg',
  };

  const PHASES = [
    { id: 'plan', label: 'Plan trip', short: 'Plan' },
    { id: 'book', label: 'Book trip', short: 'Book' },
    { id: 'enjoy', label: 'Enjoy trip', short: 'Enjoy' },
    { id: 'past', label: 'Past trip', short: 'Past' },
  ];
  const phaseLabel = (id) => (PHASES.find((p) => p.id === id) || PHASES[0]).label;

  const DEFAULT_PROFILE = { name: '', email: '', homeAirport: 'BOS', level: 'intermediate', terrain: ['mix'], travelStyle: 'balanced', vibe: 'mix', remoteWork: false, gearOwned: 'rent', passHeld: 'none', group: 'solo', onboarded: false };
  const DEFAULT_TRIP_1 = { destination: 'park-city', title: '', tripType: 'ski-west', window: 'dec', startDate: '2026-12-19', endDate: '2026-12-23', skiDays: 3, style: 'social', fareClass: 'basic', flightOptionId: null, hotelTier: 'comfort', hotelSelections: ['comfort'], gear: 'auto', phase: 'plan' };
  const DEFAULT_TRIP_2 = { destination: 'tahoe', title: '', tripType: 'ski-west', window: 'jan', startDate: '2027-01-09', endDate: '2027-01-13', skiDays: 3, style: 'cheap', fareClass: 'basic', flightOptionId: null, hotelTier: 'value', hotelSelections: ['value'], gear: 'auto', phase: 'plan' };

  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (n) => (n == null ? 'Not priced' : '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
  const money0 = (n) => (n == null ? '—' : '~$' + Math.round(n).toLocaleString('en-US'));

  let catalog = null;
  let state = load();

  function defaultState() {
    return {
      profile: null,
      settings: { origin: 'BOS', travellers: 1, customDestinations: [] },
      trips: [],
      compare: [], // [{tripId, tier}] — opt-in only, max 3, priced live
      brochures: [], // queued brochure requests
      prefs: { tripSort: 'manual', gallerySort: 'curated', tripFilter: '', galleryFilter: '', galleryType: 'all', hotelSort: 'price', phaseTab: 'all', passExpanded: false },
      ui: { tab: 'explore', editorTripId: null, ob: null, hotelTag: 'All', dismissedSuggestions: {} },
    };
  }
  function load() {
    try {
      const raw = localStorage.getItem('tp-web-v1');
      if (raw) {
        const parsed = JSON.parse(raw);
        const d = defaultState();
        return { ...d, ...parsed, settings: { ...d.settings, ...(parsed.settings || {}) }, prefs: { ...d.prefs, ...(parsed.prefs || {}) }, ui: { ...d.ui, ...(parsed.ui || {}), ob: null } };
      }
    } catch (e) { /* fresh start */ }
    return defaultState();
  }
  function save() {
    try { localStorage.setItem('tp-web-v1', JSON.stringify({ ...state, ui: { ...state.ui, ob: null } })); } catch (e) { /* private mode */ }
  }

  const destById = (id) => catalog.destinations.find((d) => d.id === id) || null;
  const tripTypeById = (id) => catalog.tripTypes.find((t) => t.id === id) || catalog.tripTypes[0];
  const destName = (trip) => {
    if (trip.custom) return trip.destination;
    const d = destById(trip.destination);
    return d ? d.name : trip.destination;
  };
  const tripTitle = (trip) => (trip.title && trip.title.trim() ? trip.title : destName(trip));

  function requestFor(trip) {
    const ready = trip.tripType === 'ski-west' || trip.tripType === 'ski-japan';
    return {
      origin: (state.settings.origin || 'BOS').toUpperCase(),
      tripType: trip.tripType,
      destinationId: trip.destination,
      destinationName: destName(trip),
      custom: trip.custom || !ready,
      departDate: trip.startDate, returnDate: trip.endDate,
      windowSelection: trip.window, skiDays: trip.skiDays,
      travellers: state.settings.travellers, style: trip.style,
      fareClass: trip.fareClass, flightOptionId: trip.flightOptionId || null,
      hotelTier: trip.hotelTier, gear: trip.gear,
      heldPass: state.profile ? state.profile.passHeld : 'none',
    };
  }

  // Whole-plan pricing, recomputed on render (cheap, on-device).
  function plan() {
    const results = state.trips.map((t) => E.price(catalog, requestFor(t)));
    const { view: pass, shares } = E.buildPassPlan(results, state.settings.travellers, state.profile ? state.profile.passHeld : 'none');
    const assembled = state.trips.map((t, i) => E.assembleTrip(catalog, t, results[i], shares[i], state.settings));
    const warnings = state.trips.map((t, i) => {
      const w = [];
      const r = results[i];
      if (!r.priced) return w;
      const hotel = r.hotelOptions.find((h) => h.key === t.hotelTier);
      if (state.profile && state.profile.remoteWork && hotel && hotel.label.toLowerCase().includes('hostel')) {
        w.push("You work remotely on trips — a hostel pod won't give you a proper room and wifi for workdays. Pick a comfort or premium hotel.");
      }
      if (state.profile && (state.profile.level === 'beginner' || state.profile.level === 'first-time') && (t.destination === 'alta' || t.destination === 'jackson')) {
        w.push('Steep learning curve here for a new skier — Park City, Tahoe and Breckenridge have gentler terrain to learn on.');
      }
      return w;
    });
    const totals = assembled.map((a) => a.total).filter((x) => x != null);
    return { results, pass, assembled, warnings,
      grandTotal: totals.length ? E.round2(totals.reduce((s, x) => s + x, 0)) : null,
      grandPartial: assembled.some((a) => a.partial || a.total == null) };
  }

  function phaseSuggestion(trip) {
    const today = new Date();
    const todayStr = today.toISOString().slice(0, 10);
    if (trip.phase !== 'past' && trip.endDate < todayStr) {
      return { target: 'past', message: `This trip ended ${trip.endDate} — move it to Past trip?` };
    }
    if (trip.phase === 'book' && trip.startDate <= todayStr && todayStr <= trip.endDate) {
      return { target: 'enjoy', message: "You're on this trip — move it to Enjoy trip?" };
    }
    return null;
  }

  // ── Onboarding ──────────────────────────────────────────────────────────
  const LEVELS = [
    { v: 'first-time', l: 'First time', h: 'Never skied — yet' },
    { v: 'beginner', l: 'Beginner', h: 'Greens and easy blues' },
    { v: 'intermediate', l: 'Intermediate', h: 'Blues all day, some blacks' },
    { v: 'advanced', l: 'Advanced', h: 'Blacks and steeps' },
    { v: 'expert', l: 'Expert', h: 'Anywhere on the mountain' },
  ];
  const TERRAIN = [
    { v: 'groomers', l: 'Groomers & blues' }, { v: 'bowls', l: 'Bowls' },
    { v: 'steeps', l: 'Steeps & blacks' }, { v: 'parks', l: 'Parks' }, { v: 'mix', l: 'A mix of everything' },
  ];
  const TRAVEL_STYLES = [
    { v: 'cheap', l: 'Cheap as possible', h: 'Every dollar counts' },
    { v: 'balanced', l: 'Balanced', h: 'Smart spends, no splurges' },
    { v: 'treat', l: 'Treat myself', h: 'The good stuff' },
  ];
  const VIBES = [
    { v: 'social', l: 'Social & nightlife', h: 'Bars, people, going out' },
    { v: 'quiet', l: 'Quiet & scenery', h: 'Calm first, early nights' },
    { v: 'mix', l: 'A mix', h: 'Depends on the day' },
  ];
  const GEAR_OWNED = [
    { v: 'own-skis', l: 'Own skis & boots', h: 'Defaults to flying with them' },
    { v: 'own-boots', l: 'Own boots only', h: 'Defaults to renting skis only' },
    { v: 'rent', l: 'Rent everything', h: 'Defaults to the cheapest rental' },
  ];
  const PASSES = [
    { v: 'none', l: 'None' }, { v: 'epic', l: 'Epic Pass', h: 'Epic days price at $0' },
    { v: 'ikon', l: 'Ikon Pass', h: 'Ikon resorts price at $0' }, { v: 'other', l: 'Other pass' },
  ];
  const GROUPS = [
    { v: 'solo', l: 'Solo' }, { v: 'couple', l: 'Couple' }, { v: 'friends', l: 'Friends' }, { v: 'family', l: 'Family' },
  ];

  function startOnboarding() {
    state.ui.ob = { step: 0, answers: { ...DEFAULT_PROFILE }, skipped: false };
    render();
  }
  function obSet(key, value, advance) {
    const ob = state.ui.ob;
    ob.answers[key] = value;
    if (advance) ob.step = Math.min(ob.step + 1, 9);
    render();
  }
  function obFinish(skipped) {
    const ob = state.ui.ob;
    const p = skipped ? { ...DEFAULT_PROFILE } : { ...ob.answers };
    p.onboarded = true;
    if (!p.homeAirport || p.homeAirport.trim().length < 3) p.homeAirport = 'BOS';
    state.profile = p;
    state.settings.origin = p.homeAirport.toUpperCase();
    state.settings.travellers = skipped ? 1 : E.GROUP_TRAVELLERS[p.group] || 1;
    if (!state.trips.length) {
      state.trips = skipped ? [{ ...DEFAULT_TRIP_1, id: uid() }, { ...DEFAULT_TRIP_2, id: uid() }] : defaultsFromProfile(p);
    }
    state.ui.ob = null;
    state.ui.tab = 'payoff';
    save();
    render();
  }
  function defaultsFromProfile(p) {
    const gear = E.profileGear(p);
    const style = E.profileStyle(p);
    const pc = destById('park-city');
    const tahoe = destById('tahoe');
    const t1 = E.applyStyle({ ...DEFAULT_TRIP_1, id: uid(), gear }, style, pc ? pc.socialTier : 'comfort', gear);
    const style2 = style === 'cheap' ? 'balanced' : 'cheap';
    const t2 = E.applyStyle({ ...DEFAULT_TRIP_2, id: uid(), gear }, style2, tahoe ? tahoe.socialTier : 'premium', gear);
    return [t1, t2];
  }

  function optRows(options, current, key, advance) {
    return options.map((o) => `
      <button class="optrow ${current === o.v ? 'sel' : ''}" onclick="TP.obSet('${key}', '${o.v}', ${advance ? 'true' : 'false'})">
        <span>${esc(o.l)}</span>${o.h ? `<span class="hint">${esc(o.h)}</span>` : ''}
      </button>`).join('');
  }

  function renderOnboarding() {
    const ob = state.ui.ob;
    const a = ob.answers;
    const step = ob.step;
    const segs = Array.from({ length: 10 }, (_, i) => `<span class="${i <= step ? 'on' : ''}"></span>`).join('');
    let body = '';
    const heading = (t, s) => `<h1>${esc(t)}</h1><p>${esc(s)}</p>`;
    if (step === 0) {
      body = `<p class="faint" style="letter-spacing:3px;font-size:11px;font-weight:700">TRAVEL PLANNER</p>
        ${heading("What's your name?", 'So Travel Planner can greet you properly — for any trip, not just ski.')}
        <input class="field" id="ob-name" type="text" placeholder="Your name" value="${esc(a.name)}" oninput="TP.obName(this.value)">
        <button class="btn-primary" ${a.name.trim() ? '' : 'disabled'} onclick="TP.obNext()">Continue</button>
        <p><button class="btn-secondary" onclick="TP.obSkip()">Skip — show me trips</button></p>`;
    } else if (step === 1) {
      body = `${heading('Your home airport?', 'Flights are priced from here. Three-letter code.')}
        <input class="field" id="ob-airport" type="text" placeholder="BOS" maxlength="5" value="${esc(a.homeAirport)}" oninput="TP.obAirport(this.value)" style="text-transform:uppercase">
        <button class="btn-primary" ${a.homeAirport.trim().length < 3 ? 'disabled' : ''} onclick="TP.obNext()">Continue</button>`;
    } else if (step === 2) {
      body = heading('If you ski, how do you ski?', 'Only used for ski trips (West Coast & Japan). Other trip types ignore it.') + optRows(LEVELS, a.level, 'level', true);
    } else if (step === 3) {
      body = heading('Terrain you love (for ski)', 'Pick any — ski resorts that match get flagged for you.') + `
        <div class="chips">${TERRAIN.map((o) => `<button class="chip ${a.terrain.includes(o.v) ? 'sel' : ''}" onclick="TP.obTerrain('${o.v}')">${a.terrain.includes(o.v) ? '✓ ' : ''}${esc(o.l)}</button>`).join('')}</div>
        <p style="margin-top:16px"><button class="btn-primary" ${a.terrain.length ? '' : 'disabled'} onclick="TP.obNext()">Continue</button></p>`;
    } else if (step === 4) {
      body = heading('Your travel style', 'Sets the default trip style — changeable per trip.') + optRows(TRAVEL_STYLES, a.travelStyle, 'travelStyle', true);
    } else if (step === 5) {
      body = heading('Trip vibe', 'Social trips default to the Best Social style.') + optRows(VIBES, a.vibe, 'vibe', true);
    } else if (step === 6) {
      body = heading('Work remotely on trips?', "If yes, we'll flag lodging that can't support workdays.") + `
        <button class="optrow ${a.remoteWork ? 'sel' : ''}" onclick="TP.obSet('remoteWork', true, true)"><span>Yes — need a proper room &amp; wifi</span></button>
        <button class="optrow ${!a.remoteWork ? 'sel' : ''}" onclick="TP.obSet('remoteWork', false, true)"><span>No — fully off</span></button>`;
    } else if (step === 7) {
      body = heading('Your ski gear', 'Sets the default gear choice on ski trips only.') + optRows(GEAR_OWNED, a.gearOwned, 'gearOwned', true);
    } else if (step === 8) {
      body = heading('Ski passes you hold', 'Held passes price covered lift days at $0 on ski trips.') + optRows(PASSES, a.passHeld, 'passHeld', true);
    } else {
      body = heading('Typical group', 'Sets the default traveller count.') + optRows(GROUPS, a.group, 'group', false) + `
        <p style="margin-top:16px"><button class="btn-primary" onclick="TP.obFinish()">Start planning</button></p>`;
    }
    return `<div class="wrap">
      <div class="toolbar"><span class="faint" style="letter-spacing:2px;font-size:12px;font-weight:600">STEP ${step + 1} OF 10</span><span class="spacer"></span>
      <button class="btn-tertiary" onclick="TP.obSkip()">Skip for now</button></div>
      <div class="segs">${segs}</div>
      <div style="padding:22px 0">${body}</div>
      ${step > 0 ? '<button class="btn-tertiary" onclick="TP.obBack()">Back</button>' : ''}
    </div>`;
  }

  // ── Shared bits ─────────────────────────────────────────────────────────
  function photoHTML(dest, strip) {
    const url = PHOTOS[dest.id];
    const img = url ? `<img src="${esc(url)}" alt="${esc(dest.photoAlt)}" loading="lazy" onerror="this.remove()">` : '';
    return `<div class="photo ${strip ? 'photo-strip' : ''}">${img}<div class="scrim"></div>`;
  }
  function tabbar() {
    const tab = state.ui.tab;
    const on = (t) => (tab === t || (t === 'trips' && tab === 'editor') ? 'on' : '');
    return `<nav class="tabbar">
      <button class="${on('explore')}" onclick="TP.go('explore')">Explore</button>
      <button class="${on('trips')}" onclick="TP.go('trips')">Trips</button>
      <button class="${on('compare')}" onclick="TP.go('compare')">Compare${state.compare.length ? `<span class="cbadge">${state.compare.length}</span>` : ''}</button>
      <button class="${on('more')}" onclick="TP.go('more')">More</button>
    </nav>`;
  }

  // ── Explore ─────────────────────────────────────────────────────────────
  function priceFromBest(dest) {
    const dec = E.priceFrom(catalog, dest, 'dec');
    const jan = E.priceFrom(catalog, dest, 'jan');
    const vals = [dec, jan].filter((x) => x != null);
    if (!vals.length) return { value: null, window: 'Jan' };
    const value = Math.min(...vals);
    return { value, window: jan != null && (dec == null || jan <= dec) ? 'Jan' : 'Dec' };
  }

  function renderExplore() {
    const prefs = state.prefs;
    const name = state.profile && state.profile.name ? `, ${esc(state.profile.name)}` : '';
    let list = catalog.destinations.slice();
    if (prefs.galleryType !== 'all') list = list.filter((d) => d.tripTypeID === prefs.galleryType);
    const q = prefs.galleryFilter.trim().toLowerCase();
    if (q) list = list.filter((d) => d.name.toLowerCase().includes(q) || d.state.toLowerCase().includes(q) || d.shortName.toLowerCase().includes(q));
    const pf = (d) => priceFromBest(d).value;
    switch (prefs.gallerySort) {
      case 'name': list.sort((a, b) => a.name.localeCompare(b.name)); break;
      case 'price-asc': list.sort((a, b) => (pf(a) ?? Infinity) - (pf(b) ?? Infinity)); break;
      case 'price-desc': list.sort((a, b) => (pf(b) ?? 0) - (pf(a) ?? 0)); break;
      case 'snow': list.sort((a, b) => b.snowScore - a.snowScore); break;
      case 'social': list.sort((a, b) => b.socialScore - a.socialScore); break;
    }
    const selectedType = catalog.tripTypes.find((t) => t.id === prefs.galleryType);
    let gallery = '';
    if (prefs.galleryType !== 'all' && selectedType && selectedType.status === 'soon') {
      gallery = `<div class="card"><div class="card-body">
        <h2 style="margin-top:0">${esc(selectedType.label)}</h2>
        <p>${esc(selectedType.blurb)}</p>
        <p class="faint">Trips of this type can be planned and saved today; pricing arrives with research — nothing is invented in the meantime.</p>
      </div></div>`;
    } else if (!list.length) {
      gallery = `<div class="empty-dash"><p><strong>Nothing matches “${esc(prefs.galleryFilter)}”</strong></p>
        <button class="btn-tertiary" onclick="TP.setPref('galleryFilter','')">Clear filter</button></div>`;
    } else {
      gallery = list.map((dest) => {
        const from = priceFromBest(dest);
        const planned = state.trips.find((t) => !t.custom && t.destination === dest.id);
        return `<div class="card">
          ${photoHTML(dest, false)}
            <div class="photo-body">
              <span class="badge plate">${esc(tripTypeById(dest.tripTypeID).shortLabel)}</span>
              <span class="badge plate">Social ${dest.socialScore} · Snow ${dest.snowScore}</span>
              <div class="nm" style="margin-top:10px">${esc(dest.name)}, ${esc(dest.state)}</div>
              <p style="margin:4px 0 10px">${esc(dest.blurb)}</p>
              <div class="toolbar">
                <div><div class="faint" style="font-size:12px">${from.window} from</div>
                <div class="total-big">${money0(from.value)}</div></div>
                <span class="spacer"></span>
                ${planned
                  ? `<button class="btn-secondary btn-inline" style="width:150px" onclick="TP.viewTrip('${planned.id}')">View trip ↓</button>`
                  : `<button class="btn-primary btn-inline" style="width:170px" onclick="TP.planTrip('${dest.id}')">Plan this trip</button>`}
              </div>
            </div>
          </div></div>
        </div>`;
      }).join('');
    }
    return `<div class="wrap">
      <h1>Hello${name}</h1>
      <p class="dim">Flying from ${esc(state.settings.origin)} · ${state.settings.travellers} traveller${state.settings.travellers === 1 ? '' : 's'}</p>
      <input class="field" type="search" placeholder="Filter by name or place…" value="${esc(prefs.galleryFilter)}" oninput="TP.setPref('galleryFilter', this.value)">
      <div class="chips scroll">
        <button class="chip ${prefs.galleryType === 'all' ? 'sel' : ''}" onclick="TP.setPref('galleryType','all')">All types</button>
        ${catalog.tripTypes.map((t) => `<button class="chip ${prefs.galleryType === t.id ? 'sel' : ''}" onclick="TP.setPref('galleryType','${t.id}')">${esc(t.shortLabel)}${t.status === 'soon' ? ' · Soon' : ''}</button>`).join('')}
      </div>
      <p>Prices from: January · from ${esc(state.settings.origin)} · 1 traveller · 3 ski days · cheapest stay &amp; gear — a starting point, not a firm quote.</p>
      <div class="toolbar"><span class="faint">Sort</span>
        <select class="field" style="width:auto;margin:0" onchange="TP.setPref('gallerySort', this.value)" aria-label="Sort destinations">
          ${[['curated', 'Featured'], ['name', 'Name A–Z'], ['price-asc', 'Price · low to high'], ['price-desc', 'Price · high to low'], ['snow', 'Best snow'], ['social', 'Most social']].map(([v, l]) => `<option value="${v}" ${prefs.gallerySort === v ? 'selected' : ''}>${l}</option>`).join('')}
        </select>
      </div>
      ${gallery}
    </div>${tabbar()}`;
  }

  // ── Trips ───────────────────────────────────────────────────────────────
  function sortedTrips(list, planObj) {
    const prefs = state.prefs;
    const out = list.slice();
    switch (prefs.tripSort) {
      case 'name': out.sort((a, b) => tripTitle(a).localeCompare(tripTitle(b))); break;
      case 'price-asc': out.sort((a, b) => ((planObj.assembled[state.trips.indexOf(a)] || {}).total ?? Infinity) - ((planObj.assembled[state.trips.indexOf(b)] || {}).total ?? Infinity)); break;
      case 'price-desc': out.sort((a, b) => ((planObj.assembled[state.trips.indexOf(b)] || {}).total ?? 0) - ((planObj.assembled[state.trips.indexOf(a)] || {}).total ?? 0)); break;
      case 'date': out.sort((a, b) => a.startDate.localeCompare(b.startDate)); break;
      default: break; // manual = insertion order
    }
    return out;
  }

  function tripCard(trip, assembled, highlight) {
    const dest = trip.custom ? null : destById(trip.destination);
    const flightLine = assembled && assembled.lines ? assembled.lines.find((l) => l.key === 'flight' && l.summary) : null;
    const styleLabel = (catalog.styles.find((s) => s.id === trip.style) || {}).label || trip.style;
    const suggestion = phaseSuggestion(trip);
    const dismissed = state.ui.dismissedSuggestions[trip.id];
    const picked = state.compare.some((c) => c.tripId === trip.id && c.tier === trip.hotelTier);
    const compareBtn = picked
      ? `<button class="btn-secondary" onclick="TP.toggleCompare('${trip.id}','${trip.hotelTier}')">In Compare ✓</button>`
      : state.compare.length >= 3
        ? `<button class="btn-secondary" disabled>Compare is full (3 max)</button>`
        : `<button class="btn-primary" onclick="TP.toggleCompare('${trip.id}','${trip.hotelTier}')">Add to compare</button>`;
    return `<div class="card ${highlight ? 'highlight' : ''}" id="trip-${trip.id}">
      ${dest ? photoHTML(dest, true) : '<div class="photo photo-strip"><div class="scrim"></div>'}
        <div class="photo-body">
          <span class="badge fill">${esc(phaseLabel(trip.phase))}</span>
          <select class="field" style="width:auto;display:inline-block;margin-left:8px;min-height:44px" onchange="TP.setPhase('${trip.id}', this.value)" aria-label="Move trip to another phase">
            ${PHASES.map((p) => `<option value="${p.id}" ${trip.phase === p.id ? 'selected' : ''}>Move: ${esc(p.label)}</option>`).join('')}
          </select>
        </div>
      </div>
      <div class="card-body">
        <h3 style="margin-top:0">${esc(tripTitle(trip))}</h3>
        <p class="dim" style="margin:2px 0">${esc(trip.startDate)} – ${esc(trip.endDate)} · ${trip.skiDays} ski day${trip.skiDays === 1 ? '' : 's'} · ${esc(styleLabel)}</p>
        ${flightLine ? `<p class="faint" style="margin:2px 0;font-size:13px">✈ ${esc(flightLine.summary)} · ${money(flightLine.amount)}</p>` : ''}
        ${suggestion && !dismissed ? `<div class="warn"><p style="margin:0 0 6px;color:var(--ink)">${esc(suggestion.message)}</p>
          <button class="btn-tertiary" onclick="TP.setPhase('${trip.id}','${suggestion.target}')">Move</button>
          <button class="btn-tertiary" onclick="TP.dismissSuggestion('${trip.id}')">Not now</button></div>` : ''}
        <p class="faint" style="margin:10px 0 2px;font-size:12.5px">Trip total</p>
        ${assembled && assembled.total != null
          ? `<div class="total-big">${money(assembled.total)}</div>${assembled.partial ? '<p class="faint" style="margin:2px 0">Partial — some lines not priced</p>' : ''}`
          : `<p style="margin:2px 0"><strong>Not priced yet</strong></p>`}
        <div class="toolbar" style="margin-top:12px">
          <button class="btn-secondary" style="flex:1" onclick="TP.openEditor('${trip.id}')">Edit details</button>
          <span style="flex:1">${compareBtn}</span>
        </div>
      </div>
    </div>`;
  }

  function passPanel(planObj) {
    const pass = planObj.pass;
    const expanded = state.prefs.passExpanded;
    if (!pass.program) {
      return `<div class="card"><div class="card-body toolbar">
        <strong>The Epic Pass decision</strong><span class="spacer"></span><span class="faint">No Epic trips in plan</span>
      </div></div>`;
    }
    const rec = pass.options.find((o) => o.recommended);
    const separate = pass.options.find((o) => o.key === 'separate');
    const saving = rec && separate && (rec.key === 'combined' || rec.key === 'full') && separate.amount > rec.amount
      ? `<p><strong>Saves ${money(E.round2(separate.amount - rec.amount))} vs separate passes</strong></p>` : '';
    return `<div class="card"><div class="card-body">
      <button class="optrow" style="border:none;padding:0;margin:0" onclick="TP.togglePass()">
        <strong>The Epic Pass decision</strong><span>${expanded ? '▴' : '▾'}</span>
      </button>
      ${expanded ? `
        ${pass.options.map((o) => `<div class="row"><span class="lbl">${esc(o.label)} ${o.recommended ? '<span class="badge fill">Recommended</span>' : ''}<small style="display:block">${esc(o.detail)}</small></span><span class="val price">${money(o.amount)}${o.estimate ? ' ~' : ''}</span></div>`).join('')}
        ${saving}
        <p class="note-box">${esc(pass.note)}</p>
        <p><a href="${esc(pass.linkUrl)}" target="_blank" rel="noopener">${esc(pass.linkLabel || 'Epic Pass')} ↗</a></p>` : ''}
    </div></div>`;
  }

  function renderTrips() {
    const planObj = plan();
    const prefs = state.prefs;
    const counts = { all: state.trips.length };
    for (const p of PHASES) counts[p.id] = state.trips.filter((t) => t.phase === p.id).length;
    const q = prefs.tripFilter.trim().toLowerCase();
    const matches = (t) => !q || tripTitle(t).toLowerCase().includes(q) || destName(t).toLowerCase().includes(q);
    let main;
    let past = [];
    if (prefs.phaseTab === 'all') {
      main = state.trips.filter((t) => t.phase !== 'past' && matches(t));
      past = state.trips.filter((t) => t.phase === 'past' && matches(t));
    } else {
      main = state.trips.filter((t) => t.phase === prefs.phaseTab && matches(t));
    }
    main = sortedTrips(main, planObj);
    past = sortedTrips(past, planObj);
    const cardFor = (t) => tripCard(t, planObj.assembled[state.trips.indexOf(t)], state.ui.highlightTripId === t.id);
    return `<div class="wrap">
      <div class="toolbar"><h1 style="flex:1">Your trips</h1>
        <button class="btn-secondary btn-inline" onclick="TP.openBrochure()">✉ Get brochure email</button></div>
      <div class="toolbar">
        <input class="field" style="flex:1;margin:0" type="search" placeholder="Filter by name or place…" value="${esc(prefs.tripFilter)}" oninput="TP.setPref('tripFilter', this.value)">
        <select class="field" style="width:auto;margin:0" onchange="TP.setPref('tripSort', this.value)" aria-label="Sort trips">
          ${[['manual', 'My order'], ['name', 'Name A–Z'], ['price-asc', 'Price · low to high'], ['price-desc', 'Price · high to low'], ['date', 'Date']].map(([v, l]) => `<option value="${v}" ${prefs.tripSort === v ? 'selected' : ''}>${l}</option>`).join('')}
        </select>
      </div>
      <div class="chips scroll" style="margin-top:10px">
        <button class="chip ${prefs.phaseTab === 'all' ? 'sel' : ''}" onclick="TP.setPref('phaseTab','all')">All trips (${counts.all})</button>
        ${PHASES.map((p) => `<button class="chip ${prefs.phaseTab === p.id ? 'sel' : ''}" onclick="TP.setPref('phaseTab','${p.id}')">${esc(p.label)} (${counts[p.id]})</button>`).join('')}
      </div>
      ${passPanel(planObj)}
      ${main.length ? main.map(cardFor).join('') : '<p class="faint" style="text-align:center;padding:24px 0">No trips here yet — plan one from Explore.</p>'}
      ${prefs.phaseTab === 'all' ? `<details class="past"><summary>Past trips (${past.length})</summary>
        ${past.length ? past.map(cardFor).join('') : '<p class="faint">No past trips yet.</p>'}</details>` : ''}
      <p style="margin-top:18px"><button class="btn-secondary" onclick="TP.addTripPrompt()">＋ Add a trip</button></p>
      <div id="add-trip-slot"></div>
    </div>${tabbar()}`;
  }

  // ── Editor (the only place the breakdown lives) ─────────────────────────
  function renderEditor() {
    const trip = state.trips.find((t) => t.id === state.ui.editorTripId);
    if (!trip) { state.ui.tab = 'trips'; return renderTrips(); }
    const planObj = plan();
    const idx = state.trips.indexOf(trip);
    const assembled = planObj.assembled[idx];
    const result = planObj.results[idx];
    const dest = trip.custom ? null : destById(trip.destination);
    const gearDefault = state.profile ? E.profileGear(state.profile) : 'auto';

    const phaseSeg = `<div class="chips">${PHASES.map((p) => `<button class="chip ${trip.phase === p.id ? 'sel' : ''}" onclick="TP.setPhase('${trip.id}','${p.id}')">${esc(p.short)}</button>`).join('')}</div>`;

    const typeOptions = catalog.tripTypes.map((t) => `<option value="${t.id}" ${trip.tripType === t.id ? 'selected' : ''}>${esc(t.label)}${t.status === 'soon' ? ' (coming soon)' : ''}</option>`).join('');
    const destOptions = catalog.destinations.filter((d) => d.tripTypeID === trip.tripType)
      .map((d) => `<option value="${d.id}" ${!trip.custom && trip.destination === d.id ? 'selected' : ''}>${esc(d.name)}, ${esc(d.state)}</option>`).join('');
    const customOptions = state.settings.customDestinations.map((c) => `<option value="${esc(c.name)}" ${trip.custom && trip.destination === c.name ? 'selected' : ''}>${esc(c.name)} (custom)</option>`).join('');

    const styleChips = catalog.styles.map((s) => `<button class="chip ${trip.style === s.id ? 'sel' : ''}" onclick="TP.applyStyle('${trip.id}','${s.id}')">${esc(s.label)}</button>`).join('');
    const styleBlurb = (catalog.styles.find((s) => s.id === trip.style) || {}).blurb || '';

    // Hotels
    const tagSet = new Set();
    result.hotelOptions.forEach((h) => (h.tags || []).forEach((t) => tagSet.add(t)));
    const tagChips = ['All', ...[...tagSet].sort()].map((t) => `<button class="chip ${state.ui.hotelTag === t ? 'sel' : ''}" onclick="TP.setHotelTag('${esc(t)}')">${esc(t)}</button>`).join('');
    let hotelOpts = result.hotelOptions.slice();
    if (state.ui.hotelTag !== 'All') hotelOpts = hotelOpts.filter((h) => (h.tags || []).includes(state.ui.hotelTag));
    if (state.prefs.hotelSort === 'price') hotelOpts.sort((a, b) => (a.amount ?? Infinity) - (b.amount ?? Infinity));
    else hotelOpts.sort((a, b) => a.label.localeCompare(b.label));
    const hotelRows = result.priced ? hotelOpts.map((h) => {
      const selected = trip.hotelSelections.includes(h.key);
      const primary = trip.hotelTier === h.key;
      const lastSelected = selected && trip.hotelSelections.length === 1;
      const picked = state.compare.some((c) => c.tripId === trip.id && c.tier === h.key);
      return `<div class="hotelrow">
        <button class="optrow" style="border:none;padding:0;margin:0" onclick="TP.toggleHotel('${trip.id}','${h.key}')">
          <span><span style="font-size:19px">${selected ? '☑' : '☐'}</span> <strong>${esc(h.label)}</strong> ${primary ? '<span class="badge fill">Primary</span>' : ''}<br>
          <span class="hint">${esc((h.tags || []).join(' · '))}</span>${lastSelected ? '<br><span class="hint">Keep at least one hotel</span>' : ''}</span>
          <span class="price"><strong>${money(h.amount)}${h.estimate ? ' ~' : ''}</strong></span>
        </button>
        <div class="links">
          ${primary ? '' : `<button class="linklike" onclick="TP.makePrimary('${trip.id}','${h.key}')">Make primary</button>`}
          ${picked
            ? `<button class="linklike" onclick="TP.toggleCompare('${trip.id}','${h.key}')">In Compare ✓</button>`
            : state.compare.length >= 3
              ? '<span class="faint" style="display:inline-flex;align-items:center;min-height:44px">Compare is full (3 max)</span>'
              : `<button class="linklike" onclick="TP.toggleCompare('${trip.id}','${h.key}')">Add to compare</button>`}
          ${h.linkUrl ? `<a href="${esc(h.linkUrl)}" target="_blank" rel="noopener">View on Expedia</a>` : ''}
        </div>
      </div>`;
    }).join('') : '';

    const gearRows = result.priced && result.gearOptions.length ? result.gearOptions.map((g) => `
      <button class="optrow ${result.chosenGearKey === g.key ? 'sel' : ''}" onclick="TP.setGear('${trip.id}','${g.key}')">
        <span>${result.chosenGearKey === g.key ? '●' : '○'} ${esc(g.label)}<br><span class="hint">${esc(g.detail)}</span></span>
        <span class="price">${money(g.amount)}${g.estimate ? ' ~' : ''}</span>
      </button>`).join('') : '<p class="faint">Gear pricing arrives with destination pricing.</p>';

    const warnings = planObj.warnings[idx] || [];
    const breakdown = assembled.priced ? `
      ${assembled.lines.map((l) => `<div class="row"><span class="lbl">${esc(l.label)}<small style="display:block">${esc(l.detail)}</small>${l.linkUrl ? `<a href="${esc(l.linkUrl)}" target="_blank" rel="noopener" style="font-size:13px">${esc(l.linkLabel || 'Open')} ↗</a>` : ''}</span><span class="val price">${money(l.amount)}${l.estimate ? ' ~' : ''}</span></div>`).join('')}
      <p class="faint" style="font-size:13px">Prices: ${esc(result.sourceLabel)}, checked ${esc(result.checkedAt)}. ~ = estimate.</p>`
      : `<p>${esc((result.notes || [])[0] || "Not priced yet — this trip type or place isn't in the researched dataset.")}</p>`;

    return `<div class="wrap">
      <button class="btn-tertiary" onclick="TP.go('trips')">‹ Your trips</button>
      ${dest ? photoHTML(dest, true) + '</div>' : ''}
      <h1>${esc(tripTitle(trip))}</h1>
      <h2>Phase</h2>${phaseSeg}
      <h2>Basics</h2>
      <label class="flabel" for="ed-title">Trip name (optional)</label>
      <input class="field" id="ed-title" type="text" value="${esc(trip.title)}" placeholder="${esc(destName(trip))}" oninput="TP.setField('${trip.id}','title',this.value)">
      <label class="flabel" for="ed-type">Trip type</label>
      <select class="field" id="ed-type" onchange="TP.setTripType('${trip.id}', this.value)">${typeOptions}</select>
      <label class="flabel" for="ed-dest">Destination</label>
      <select class="field" id="ed-dest" onchange="TP.setDestination('${trip.id}', this.value)">${destOptions}${customOptions}</select>
      <div class="chips" style="margin-top:8px">
        <button class="chip ${trip.window === 'dec' ? 'sel' : ''}" onclick="TP.setWindow('${trip.id}','dec')">December</button>
        <button class="chip ${trip.window === 'jan' ? 'sel' : ''}" onclick="TP.setWindow('${trip.id}','jan')">January</button>
        <button class="chip ${trip.window === 'custom' ? 'sel' : ''}" onclick="TP.setWindow('${trip.id}','custom')">Custom dates</button>
      </div>
      <div class="toolbar">
        <span style="flex:1"><label class="flabel" for="ed-start">From</label><input class="field" id="ed-start" type="date" value="${trip.startDate}" onchange="TP.setDates('${trip.id}', this.value, '${trip.endDate}')"></span>
        <span style="flex:1"><label class="flabel" for="ed-end">To</label><input class="field" id="ed-end" type="date" value="${trip.endDate}" onchange="TP.setDates('${trip.id}', '${trip.startDate}', this.value)"></span>
      </div>
      <h2>Ski days &amp; fare</h2>
      <div class="toolbar"><span class="dim">Ski days</span><span class="spacer"></span>
        <button class="chip" onclick="TP.setDays('${trip.id}', ${Math.max(1, trip.skiDays - 1)})" aria-label="Fewer ski days">−</button>
        <strong>${trip.skiDays} day${trip.skiDays === 1 ? '' : 's'}</strong>
        <button class="chip" onclick="TP.setDays('${trip.id}', ${Math.min(10, trip.skiDays + 1)})" aria-label="More ski days">+</button></div>
      <p class="faint" style="font-size:13px">${trip.skiDays >= 3 && trip.skiDays <= 4 ? 'Researched range — figures from the Nov 13, 2026 dataset.' : 'Extended estimate — outside the researched 3–4 day range, extended per day and marked ~.'}</p>
      <div class="chips">
        <button class="chip ${trip.fareClass === 'basic' ? 'sel' : ''}" onclick="TP.setField('${trip.id}','fareClass','basic')">Basic</button>
        <button class="chip ${trip.fareClass === 'flex' ? 'sel' : ''}" onclick="TP.setField('${trip.id}','fareClass','flex')">Flex</button>
      </div>
      <h2>Style</h2>
      <p class="faint" style="font-size:13px">A style preset sets fare class, hotel pick and gear at once — then tune anything.</p>
      <div class="chips">${styleChips}</div>
      <p class="dim">${esc(styleBlurb)}</p>
      ${result.priced ? `<h2>Hotels — pick a few</h2>
      <p class="faint" style="font-size:13px">The Primary drives the trip total. Price checked Nov 13, 2026 — Expedia's live price may have moved.</p>
      <div class="toolbar"><div class="chips scroll">${tagChips}</div>
      <select class="field" style="width:auto;margin:0" onchange="TP.setPref('hotelSort', this.value)" aria-label="Sort hotels">
        <option value="price" ${state.prefs.hotelSort === 'price' ? 'selected' : ''}>Sort: Price</option>
        <option value="name" ${state.prefs.hotelSort === 'name' ? 'selected' : ''}>Sort: Name</option>
      </select></div>
      ${hotelRows}` : ''}
      <h2>Gear</h2>${gearRows}
      ${(warnings.length || result.notes.length) ? `<h2>Good to know</h2>
        ${warnings.map((w) => `<p>⚠ ${esc(w)}</p>`).join('')}
        ${result.notes.map((n) => `<p>· ${esc(n)}</p>`).join('')}` : ''}
      <h2>Breakdown</h2>${breakdown}
      <div class="sticky-total">
        <span><span class="faint" style="font-size:12px;display:block">Trip total</span><span class="total-big">${money(assembled.total)}</span></span>
        <span class="spacer"></span>
        <button class="btn-primary btn-inline" style="width:130px" onclick="TP.go('trips')">Done</button>
      </div>
    </div>${tabbar()}`;
  }

  function renderAddTrip() {
    return `<div class="wrap">
      <button class="btn-tertiary" onclick="TP.go('trips')">‹ Your trips</button>
      <h1>Add a trip</h1>
      <h2>Destinations</h2>
      ${catalog.destinations.map((d) => `<button class="optrow" onclick="TP.addTrip('${d.id}')"><span><strong>${esc(d.name)}, ${esc(d.state)}</strong></span><span class="hint">${esc(tripTypeById(d.tripTypeID).shortLabel)}</span></button>`).join('')}
      <h2>Custom place</h2>
      <input class="field" id="custom-name" type="text" placeholder="Place name (e.g. Revelstoke)">
      <button class="btn-secondary" onclick="TP.addCustomTrip()">Add custom place</button>
      <p class="faint" style="font-size:13px">Custom places save with dates and style, but stay unpriced until they're researched into the dataset. Cap: 20 custom places (currently ${state.settings.customDestinations.length}).</p>
    </div>${tabbar()}`;
  }

  // ── Compare ─────────────────────────────────────────────────────────────
  function renderCompare() {
    const planObj = plan();
    const cols = state.compare.map((pick) => {
      const trip = state.trips.find((t) => t.id === pick.tripId);
      if (!trip) return null;
      const assembled = planObj.assembled[state.trips.indexOf(trip)];
      const variant = assembled.variants.find((v) => v.tier === pick.tier);
      if (!variant) return null;
      return { pick, trip, variant };
    }).filter(Boolean);

    if (!cols.length) {
      return `<div class="wrap"><h1>Compare</h1>
        <div class="empty-dash">
          <p style="font-size:19px;color:var(--ink)"><strong>Nothing here yet</strong></p>
          <p>Tap <strong>Add to compare</strong> on any listing to line it up here.</p>
          <button class="btn-secondary btn-inline" onclick="TP.go('explore')">Browse destinations</button>
        </div></div>${tabbar()}`;
    }
    const rowsDef = [
      ['Flight', (v) => [v.flightAmount, v.flightEstimate]],
      ['Transfers', (v) => [v.transfersAmount, v.transfersEstimate]],
      ['Hotel', (v) => [v.hotelAmount, v.hotelEstimate]],
      ['Lift / Pass', (v) => [v.liftAmount, v.liftEstimate]],
      ['Gear', (v) => [v.gearAmount, v.gearEstimate]],
      ['Total', (v) => [v.total, false]],
    ];
    const rows = rowsDef.map(([label, get]) => {
      const vals = cols.map((c) => get(c.variant));
      const min = Math.min(...vals.map((v) => v[0]).filter((x) => x != null));
      const cells = cols.map((c, i) => {
        const [amount, estimate] = vals[i];
        const lowest = cols.length > 1 && amount != null && amount === min;
        return `<td class="${lowest ? 'lowest' : ''}">${money(amount)}${estimate && label !== 'Total' ? ' ~' : ''}${lowest ? '<small>LOWEST</small>' : ''}</td>`;
      }).join('');
      return `<tr><td>${label}</td>${cells}</tr>`;
    }).join('');
    return `<div class="wrap"><h1>Compare</h1>
      <div class="chips">
        ${cols.map((c) => `<button class="chip" onclick="TP.toggleCompare('${c.trip.id}','${c.pick.tier}')">${esc((c.trip.custom ? c.trip.destination : (destById(c.trip.destination) || {}).shortName || c.trip.destination))} ✕</button>`).join('')}
        <button class="btn-tertiary" onclick="TP.clearCompare()">Clear all</button>
      </div>
      <div class="cmp"><table>
        <tr><th></th>${cols.map((c) => `<th>${esc(c.variant.hotelName)}</th>`).join('')}</tr>
        ${rows}
      </table></div>
      <p class="faint" style="font-size:13px">White cell marked LOWEST = cheapest in that row. Nothing is compared until you add it.</p>
      ${cols.length === 1 ? '<p class="faint" style="font-size:13px">Add a second listing to see LOWEST markers.</p>' : ''}
    </div>${tabbar()}`;
  }

  // ── Brochure chooser + queue ────────────────────────────────────────────
  function renderBrochureSheet() {
    const planObj = plan();
    const chosen = state.ui.brochureSel || {};
    const email = state.ui.brochureEmail != null ? state.ui.brochureEmail : (state.profile ? state.profile.email : '');
    let rowsHTML = '';
    let any = false;
    state.trips.forEach((trip, i) => {
      const assembled = planObj.assembled[i];
      assembled.variants.forEach((v) => {
        any = true;
        const key = `${trip.id}:${v.tier}`;
        const priced = v.total != null;
        const checked = chosen[key] && priced;
        rowsHTML += `<button class="pickrow" ${priced ? '' : 'disabled'} onclick="TP.brochureToggle('${key}')">
          <span class="check">${checked ? '☑' : '☐'}</span>
          <span style="flex:1"><strong>${esc(tripTitle(trip))} — ${esc(v.hotelName)}</strong> ${v.isPrimary ? '<span class="badge fill">Primary</span>' : ''}<br>
          <span class="faint" style="font-size:12.5px">${esc(trip.startDate)} – ${esc(trip.endDate)}</span>
          ${priced ? '' : '<br><span class="faint" style="font-size:12.5px">Not priced: this stay isn\'t in the dataset</span>'}</span>
          <span class="price"><strong>${money(v.total)}</strong></span>
        </button>`;
      });
    });
    const count = Object.keys(chosen).filter((k) => chosen[k]).length;
    const done = state.ui.brochureDone;
    return `<div class="sheet-back" onclick="if(event.target===this)TP.closeBrochure()">
      <div class="sheet" role="dialog" aria-label="Get brochure email">
        <h2 style="margin-top:0">Get brochure email</h2>
        ${done ? `
          <p style="font-size:19px;color:var(--ink)">✓ <strong>Queued for assistant</strong></p>
          <p>To ${esc(done.recipient)} · ${esc(done.when)}</p>
          ${done.items.map((s) => `<div class="row"><span class="lbl" style="color:var(--ink)">${esc(s)}</span><span class="badge">Queued</span></div>`).join('')}
          <p class="faint" style="font-size:13px">Queued is not sent — the assistant sends queued brochures from partheysmusebot@gmail.com. Track them in More › Brochures.</p>
          <button class="btn-primary" onclick="TP.closeBrochure()">Done</button>`
        : `
          <p>One brochure per ticked stay — a PDF summary (downloadable here) plus the plan as email text, queued for the assistant to send.</p>
          ${any ? rowsHTML : '<p class="faint">No priced trips yet — price a trip first, then queue its brochure.</p>'}
          <label class="flabel" for="bro-email">Email for the brochures</label>
          <input class="field" id="bro-email" type="email" value="${esc(email)}" oninput="TP.brochureEmailIn(this.value)">
          ${state.ui.brochureError ? `<p class="note-box" style="color:var(--ink)">${esc(state.ui.brochureError)}</p>` : ''}
          <p class="faint">${count} selected</p>
          <button class="btn-primary" onclick="TP.brochureSend()">Send ${count} brochure${count === 1 ? '' : 's'}</button>
          <p><button class="btn-tertiary" onclick="TP.closeBrochure()">Cancel</button></p>`}
      </div>
    </div>`;
  }

  function brochureCompose(trip, assembled, variant) {
    const typeLabel = tripTypeById(trip.tripType).label;
    const styleLabel = (catalog.styles.find((s) => s.id === trip.style) || {}).label || trip.style;
    const lines = assembled.lines.map((l) => (l.key === 'hotel'
      ? `Hotel · ${variant.hotelName} — ${money(variant.hotelAmount)}${variant.hotelEstimate ? ' ~' : ''}`
      : `${l.label} — ${money(l.amount)}${l.estimate ? ' ~' : ''}\n  ${l.detail}`));
    return [
      'TRAVEL PLANNER — TRIP BROCHURE', '',
      `${tripTitle(trip)} · ${typeLabel}`,
      `${trip.startDate} – ${trip.endDate} · ${trip.skiDays} ski day${trip.skiDays === 1 ? '' : 's'} · ${styleLabel} · ${state.settings.travellers} traveller${state.settings.travellers === 1 ? '' : 's'}`,
      `Stay: ${variant.hotelName}${variant.isPrimary ? ' (Primary)' : ''}`, '',
      'BREAKDOWN', ...lines, '',
      `TOTAL: ${money(variant.total)}${variant.partial ? ' (partial — some lines not priced)' : ''}`, '',
      `Prices: ${assembled.result.sourceLabel}, checked ${assembled.result.checkedAt}. Figures marked ~ are estimates. Nothing is booked by this app — booking links go to the sellers.`,
      ...(assembled.result.notes.length ? ['', 'NOTES', ...assembled.result.notes.map((n) => `· ${n}`)] : []),
    ].join('\n');
  }

  // ── More / Profile / Settings / About / Brochures ───────────────────────
  function renderMore() {
    const queued = state.brochures.filter((b) => b.status === 'queued').length;
    return `<div class="wrap"><h1>More</h1>
      <button class="optrow" onclick="TP.go('profile')"><span><strong>Profile</strong><br><span class="hint">Name, email, airport, ski level, passes…</span></span><span>›</span></button>
      <button class="optrow" onclick="TP.go('brochures')"><span><strong>Brochures</strong><br><span class="hint">Queued and sent trip brochures</span></span><span>${queued ? `<span class="badge fill">${queued} queued</span> ` : ''}›</span></button>
      <button class="optrow" onclick="TP.goPasses()"><span><strong>Passes &amp; tickets</strong><br><span class="hint">Opens your trips with the Epic Pass panel expanded</span></span><span>›</span></button>
      <button class="optrow" onclick="TP.go('settings')"><span><strong>Planner settings</strong><br><span class="hint">Origin airport &amp; travellers for new searches</span></span><span>›</span></button>
      <button class="optrow" onclick="TP.go('about')"><span><strong>About &amp; data sources</strong><br><span class="hint">Where the numbers come from — and what the app never does</span></span><span>›</span></button>
      <p class="faint" style="font-size:13px">No accounts, no tracking, nothing leaves your browser — your plan stays in this browser's local storage only. The assistant sends queued brochures from the assistant mailbox.</p>
    </div>${tabbar()}`;
  }

  function renderBrochures() {
    const rows = state.brochures.slice().reverse().map((b) => `
      <div class="card"><div class="card-body">
        <div class="toolbar"><strong style="flex:1">${esc(b.title)}</strong><span class="badge">${esc(b.status === 'queued' ? 'Queued' : b.status === 'sent' ? 'Sent' : 'Failed')}</span></div>
        <p class="faint">To ${esc(b.recipient)} · ${esc(b.createdAt)}</p>
        <div class="toolbar">
          <button class="btn-tertiary" onclick="TP.downloadBrochure('${b.id}', 'text')">Download text</button>
          <button class="btn-tertiary" onclick="TP.printBrochure('${b.id}')">Print / save PDF</button>
          ${b.status === 'queued' ? `<button class="btn-tertiary" onclick="TP.markBrochure('${b.id}', 'sent')">Mark as sent</button>` : ''}
          ${b.status !== 'failed' ? `<button class="btn-tertiary" onclick="TP.markBrochure('${b.id}', 'failed')">Mark as failed</button>` : ''}
        </div>
      </div></div>`).join('');
    return `<div class="wrap">
      <button class="btn-tertiary" onclick="TP.go('more')">‹ More</button>
      <h1>Brochures</h1>
      <p>Every brochure you queue, newest first. "Queued for assistant" means the assistant holds it to send from partheysmusebot@gmail.com.</p>
      ${state.brochures.length ? rows : '<p class="faint">No brochures yet — queue one from Your trips › Get brochure email.</p>'}
    </div>${tabbar()}`;
  }

  function renderProfile() {
    const p = state.profile || DEFAULT_PROFILE;
    const multi = (options, current, key) => `<div class="chips">${options.map((o) => `<button class="chip ${current.includes(o.v) ? 'sel' : ''}" onclick="TP.profileTerrain('${o.v}')">${current.includes(o.v) ? '✓ ' : ''}${esc(o.l)}</button>`).join('')}</div>`;
    const sel = (options, current, key) => options.map((o) => `
      <button class="optrow ${current === o.v ? 'sel' : ''}" onclick="TP.profileSet('${key}', '${o.v}')">
        <span>${esc(o.l)}</span>${o.h ? `<span class="hint">${esc(o.h)}</span>` : ''}
      </button>`).join('');
    return `<div class="wrap">
      <button class="btn-tertiary" onclick="TP.go('more')">‹ More</button>
      <h1>Your profile</h1>
      <p>The answers that personalise every trip. Same ten questions as onboarding.</p>
      <label class="flabel" for="pf-name">Name</label>
      <input class="field" id="pf-name" type="text" value="${esc(p.name)}" placeholder="Your name" oninput="TP.profileField('name', this.value)">
      <label class="flabel" for="pf-email">Email (where brochures go)</label>
      <input class="field" id="pf-email" type="email" value="${esc(p.email)}" placeholder="you@example.com" oninput="TP.profileField('email', this.value)">
      <label class="flabel" for="pf-air">Home airport (3-letter code)</label>
      <input class="field" id="pf-air" type="text" maxlength="5" value="${esc(p.homeAirport)}" style="text-transform:uppercase" oninput="TP.profileAirport(this.value)">
      <h3>Ski level</h3>${sel(LEVELS, p.level, 'level')}
      <h3>Terrain you love</h3>${multi(TERRAIN, p.terrain, 'terrain')}
      <h3>Your travel style</h3>${sel(TRAVEL_STYLES, p.travelStyle, 'travelStyle')}
      <h3>Trip vibe</h3>${sel(VIBES, p.vibe, 'vibe')}
      <h3>Work remotely on trips?</h3>
      <button class="optrow ${p.remoteWork ? 'sel' : ''}" onclick="TP.profileSet('remoteWork', true)"><span>Yes — need a proper room &amp; wifi</span></button>
      <button class="optrow ${!p.remoteWork ? 'sel' : ''}" onclick="TP.profileSet('remoteWork', false)"><span>No — fully off</span></button>
      <h3>Your ski gear</h3>${sel(GEAR_OWNED, p.gearOwned, 'gearOwned')}
      <h3>Ski passes you hold</h3>${sel(PASSES, p.passHeld, 'passHeld')}
      <h3>Typical group</h3>${sel(GROUPS, p.group, 'group')}
      <h3>Planner defaults</h3>
      <p>Applying re-seeds styles &amp; defaults on your existing trips (dates, names and phases stay).</p>
      <button class="btn-secondary" onclick="TP.applyProfile('ask')">Apply profile defaults to my trips</button>
      ${state.ui.profileConfirm ? `<div class="warn">
        <p style="color:var(--ink);margin-top:0"><strong>Apply profile defaults to ${state.trips.length} trip${state.trips.length === 1 ? '' : 's'}?</strong></p>
        <p>Each trip's style, fare, hotels and gear are re-seeded from your profile. Dates, names and phases stay.</p>
        <button class="btn-primary" onclick="TP.applyProfile('yes')">Apply</button>
        <button class="btn-tertiary" onclick="TP.applyProfile('no')">Cancel</button>
      </div>` : ''}
    </div>${tabbar()}`;
  }

  function renderSettings() {
    return `<div class="wrap">
      <button class="btn-tertiary" onclick="TP.go('more')">‹ More</button>
      <h1>Planner settings</h1>
      <label class="flabel" for="st-origin">Origin airport</label>
      <input class="field" id="st-origin" type="text" maxlength="5" value="${esc(state.settings.origin)}" style="text-transform:uppercase" placeholder="BOS" oninput="TP.settingsOrigin(this.value)">
      <p class="faint" style="font-size:13px">Flights are priced from Boston (BOS) in the current dataset — another origin shows flights as unpriced until it's researched.</p>
      <label class="flabel">Travellers</label>
      <div class="toolbar"><button class="chip" onclick="TP.settingsTravellers(${Math.max(1, state.settings.travellers - 1)})">−</button>
        <strong>${state.settings.travellers}</strong>
        <button class="chip" onclick="TP.settingsTravellers(${Math.min(8, state.settings.travellers + 1)})">+</button></div>
      <p class="faint" style="font-size:13px">Flights, transfers and the pass multiply per person; the hotel is per room. Applies to every trip.</p>
      <p class="faint" style="font-size:13px">No Appearance setting: Travel Planner is jet black, by design.</p>
      <h2>Start over</h2>
      <p class="dim">Erases your trips, profile, Compare picks and queued brochures from this browser.</p>
      ${state.ui.resetConfirm ? `<div class="warn"><p style="color:var(--ink)"><strong>Erase everything in this browser?</strong></p>
        <button class="btn-primary" onclick="TP.resetAll()">Erase everything</button>
        <button class="btn-tertiary" onclick="TP.cancelReset()">Keep my planner</button></div>`
        : '<button class="btn-secondary" onclick="TP.askReset()">Erase everything</button>'}
    </div>${tabbar()}`;
  }

  function renderAbout() {
    return `<div class="wrap">
      <button class="btn-tertiary" onclick="TP.go('more')">‹ More</button>
      <h1>About &amp; data sources</h1>
      <p>Travel Planner prices trips from a researched dataset and never books anything. Booking buttons open the seller's own site (Expedia for hotels, Google Flights for air) with your dates pre-filled — you always buy directly, at their live price.</p>
      <h2>Where the numbers come from</h2>
      ${catalog.about.sources.map((s) => `<p><strong>${esc(s.label)}</strong> — ${esc(s.detail)}</p>`).join('')}
      <h2>The Epic Pass ladder</h2>
      <p>Rungs: ${catalog.epicLadder.map(([days, price, exact]) => `${days}-day ${money(price)}${exact ? '' : ' ~'}`).join(' · ')} · Full Epic Pass ${money(catalog.fullPassPrice)}.</p>
      <p class="faint">~ = estimate rung — only the 3-day ($386) and 6-day ($640) rungs are exact published prices.</p>
      <h2>Privacy</h2>
      <p>No accounts, no tracking, no analytics. Your profile, trips and brochures live in this browser's local storage and never leave it, except a brochure you explicitly queue for the assistant to send from partheysmusebot@gmail.com.</p>
      <p class="faint">Travel Planner v1.0 · Dataset checked ${esc(catalog.checkedAt)}</p>
    </div>${tabbar()}`;
  }

  function renderPayoff() {
    const planObj = plan();
    return `<div class="wrap">
      <h1>Here's your first plan${state.profile && state.profile.name ? `, ${esc(state.profile.name)}` : ''}</h1>
      <p>Two trips, priced from your answers. Nothing is booked — every line has a booking link when you're ready.</p>
      ${state.trips.map((t, i) => tripCard(t, planObj.assembled[i], false)).join('')}
      <p style="margin-top:18px"><button class="btn-primary" onclick="TP.go('explore')">Explore destinations</button></p>
    </div>${tabbar()}`;
  }

  // ── Render dispatch ─────────────────────────────────────────────────────
  function render() {
    const el = document.getElementById('app');
    let html;
    if (!state.profile && !state.ui.ob) {
      state.ui.ob = { step: 0, answers: { ...DEFAULT_PROFILE }, skipped: false };
    }
    if (state.ui.ob) html = renderOnboarding();
    else {
      switch (state.ui.tab) {
        case 'trips': html = renderTrips(); break;
        case 'editor': html = renderEditor(); break;
        case 'addtrip': html = renderAddTrip(); break;
        case 'compare': html = renderCompare(); break;
        case 'more': html = renderMore(); break;
        case 'profile': html = renderProfile(); break;
        case 'settings': html = renderSettings(); break;
        case 'about': html = renderAbout(); break;
        case 'brochures': html = renderBrochures(); break;
        case 'payoff': html = renderPayoff(); break;
        default: html = renderExplore();
      }
    }
    if (state.ui.brochureOpen) html += renderBrochureSheet();
    el.innerHTML = html;
    const focusId = state.ui.focusId;
    if (focusId) {
      state.ui.focusId = null;
      const f = document.getElementById(focusId);
      if (f) { f.focus(); const v = f.value; f.value = ''; f.value = v; }
    }
    if (state.ui.highlightTripId) {
      const card = document.getElementById('trip-' + state.ui.highlightTripId);
      if (card) card.scrollIntoView({ block: 'center' });
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  function mutate(fn) { fn(); save(); render(); }
  function tripById(id) { return state.trips.find((t) => t.id === id); }

  window.TP = {
    go(tab) { state.ui.tab = tab; window.scrollTo(0, 0); render(); },
    goPasses() { state.prefs.passExpanded = true; state.ui.tab = 'trips'; save(); render(); },
    setPref(key, value) {
      state.prefs[key] = value;
      const active = document.activeElement;
      state.ui.focusId = value && active && (active.tagName === 'INPUT') ? active.id : null;
      save(); render();
    },
    // Onboarding
    obNext() { state.ui.ob.step = Math.min(state.ui.ob.step + 1, 9); render(); },
    obBack() { state.ui.ob.step = Math.max(state.ui.ob.step - 1, 0); render(); },
    obSkip() { obFinish(true); },
    obFinish() { obFinish(false); },
    obSet(key, value, advance) { obSet(key, value, advance); },
    obName(v) { state.ui.ob.answers.name = v; const b = document.querySelector('.btn-primary'); if (b) b.disabled = !v.trim(); },
    obAirport(v) {
      state.ui.ob.answers.homeAirport = v.toUpperCase();
      if (v.trim().length >= 3) { state.ui.ob.step = 2; render(); }
      else { const b = document.querySelector('.btn-primary'); if (b) b.disabled = v.trim().length < 3; }
    },
    obTerrain(v) {
      const a = state.ui.ob.answers.terrain;
      state.ui.ob.answers.terrain = a.includes(v) ? a.filter((x) => x !== v) : [...a.filter((x) => x !== 'mix' || v !== 'mix'), v];
      render();
    },
    planTrip(destId) {
      const dest = destById(destId);
      const profile = state.profile || DEFAULT_PROFILE;
      const gear = E.profileGear(profile);
      const style = dest ? E.profileStyle(profile) : 'balanced';
      const base = { id: uid(), title: '', tripType: dest ? dest.tripTypeID : 'ski-west', destination: destId, custom: false, window: 'jan', startDate: '2027-01-09', endDate: '2027-01-13', skiDays: 3, style, fareClass: 'basic', hotelTier: 'comfort', hotelSelections: ['comfort'], gear, phase: 'plan' };
      const styled = dest ? E.applyStyle(base, style, dest.socialTier, gear) : base;
      mutate(() => { state.trips.push(styled); state.ui.highlightTripId = styled.id; state.ui.tab = 'trips'; });
    },
    viewTrip(id) { state.ui.highlightTripId = id; state.ui.tab = 'trips'; render(); },
    openEditor(id) { state.ui.editorTripId = id; state.ui.tab = 'editor'; render(); },
    setPhase(id, phase) { mutate(() => { tripById(id).phase = phase; }); },
    dismissSuggestion(id) { state.ui.dismissedSuggestions[id] = true; render(); },
    togglePass() { mutate(() => { state.prefs.passExpanded = !state.prefs.passExpanded; }); },
    addTripPrompt() { state.ui.tab = 'addtrip'; render(); },
    addTrip(destId) {
      const dest = destById(destId);
      mutate(() => {
        state.trips.push({ id: uid(), title: '', tripType: dest.tripTypeID, destination: destId, custom: false, window: 'jan', startDate: '2027-01-09', endDate: '2027-01-13', skiDays: 3, style: 'balanced', fareClass: 'basic', hotelTier: 'comfort', hotelSelections: ['comfort'], gear: 'auto', phase: 'plan' });
        state.ui.tab = 'trips';
      });
    },
    addCustomTrip() {
      const input = document.getElementById('custom-name');
      const name = input ? input.value.trim() : '';
      if (!name) return;
      mutate(() => {
        if (!state.settings.customDestinations.some((c) => c.name === name) && state.settings.customDestinations.length < 20) {
          state.settings.customDestinations.push({ name });
        }
        state.trips.push({ id: uid(), title: '', tripType: 'ski-west', destination: name, custom: true, window: 'custom', startDate: '2027-01-09', endDate: '2027-01-13', skiDays: 3, style: 'balanced', fareClass: 'basic', hotelTier: 'comfort', hotelSelections: ['comfort'], gear: 'auto', phase: 'plan' });
        state.ui.tab = 'trips';
      });
    },
    // Editor
    setField(id, key, value) {
      // Text fields never re-render (focus would be lost mid-typing);
      // fare class is price-affecting so it re-renders.
      const trip = tripById(id);
      trip[key] = value;
      save();
      if (key === 'fareClass') render();
    },
    setTripType(id, typeId) { mutate(() => { const t = tripById(id); t.tripType = typeId; t.custom = false; const d = catalog.destinations.find((x) => x.tripTypeID === typeId); if (d) t.destination = d.id; }); },
    setDestination(id, value) {
      mutate(() => {
        const t = tripById(id);
        const isCustom = state.settings.customDestinations.some((c) => c.name === value);
        t.custom = isCustom; t.destination = value;
        if (!isCustom) { const d = destById(value); if (d) t.tripType = d.tripTypeID; }
      });
    },
    setWindow(id, w) { mutate(() => { const t = tripById(id); t.window = w; if (w === 'dec') { t.startDate = '2026-12-19'; t.endDate = '2026-12-23'; } if (w === 'jan') { t.startDate = '2027-01-09'; t.endDate = '2027-01-13'; } }); },
    setDates(id, start, end) { mutate(() => { const t = tripById(id); t.startDate = start; t.endDate = end; t.window = 'custom'; }); },
    setDays(id, days) { mutate(() => { tripById(id).skiDays = Math.min(10, Math.max(1, days)); }); },
    applyStyle(id, styleId) {
      mutate(() => {
        const t = tripById(id);
        const dest = t.custom ? null : destById(t.destination);
        const styled = E.applyStyle(t, styleId, dest ? dest.socialTier : 'comfort', t.gear);
        Object.assign(t, styled);
      });
    },
    setGear(id, gear) { mutate(() => { tripById(id).gear = gear; }); },
    setHotelTag(tag) { state.ui.hotelTag = tag; render(); },
    toggleHotel(id, key) {
      mutate(() => {
        const t = tripById(id);
        if (t.hotelSelections.includes(key)) {
          if (t.hotelSelections.length === 1) return;
          t.hotelSelections = t.hotelSelections.filter((k) => k !== key);
          if (t.hotelTier === key) t.hotelTier = t.hotelSelections[0];
        } else {
          if (t.hotelSelections.length >= 3) return;
          t.hotelSelections = [...t.hotelSelections, key].slice(0, 3);
        }
      });
    },
    makePrimary(id, key) { mutate(() => { tripById(id).hotelTier = key; }); },
    // Compare
    toggleCompare(tripId, tier) {
      mutate(() => {
        const i = state.compare.findIndex((c) => c.tripId === tripId && c.tier === tier);
        if (i >= 0) state.compare.splice(i, 1);
        else if (state.compare.length < 3) state.compare.push({ tripId, tier });
      });
    },
    clearCompare() { mutate(() => { state.compare = []; }); },
    // Brochure
    openBrochure() {
      const planObj = plan();
      const sel = {};
      state.trips.forEach((trip, i) => {
        planObj.assembled[i].variants.forEach((v) => { if (v.isPrimary && v.total != null) sel[`${trip.id}:${v.tier}`] = true; });
      });
      state.ui.brochureSel = sel;
      state.ui.brochureOpen = true;
      state.ui.brochureDone = null;
      state.ui.brochureError = null;
      state.ui.brochureEmail = null;
      render();
    },
    closeBrochure() { state.ui.brochureOpen = false; render(); },
    brochureToggle(key) { state.ui.brochureSel[key] = !state.ui.brochureSel[key]; render(); },
    brochureEmailIn(v) { state.ui.brochureEmail = v; if (state.ui.brochureError) { state.ui.brochureError = null; render(); } },
    brochureSend() {
      const email = (state.ui.brochureEmail != null ? state.ui.brochureEmail : (state.profile ? state.profile.email : '')).trim();
      const keys = Object.keys(state.ui.brochureSel || {}).filter((k) => state.ui.brochureSel[k]);
      if (!keys.length) { state.ui.brochureError = 'Pick at least one stay above to queue its brochure.'; render(); return; }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { state.ui.brochureError = 'That email doesn\'t look complete — check it and try again.'; render(); return; }
      const planObj = plan();
      const items = [];
      for (const key of keys) {
        const [tripId, tier] = key.split(':');
        const trip = tripById(tripId);
        if (!trip) continue;
        const idx = state.trips.indexOf(trip);
        const assembled = planObj.assembled[idx];
        const variant = assembled.variants.find((v) => v.tier === tier);
        if (!variant || variant.total == null) continue;
        const text = brochureCompose(trip, assembled, variant);
        const title = `${tripTitle(trip)} — ${variant.hotelName}`;
        state.brochures.push({ id: uid(), title, recipient: email, status: 'queued', createdAt: new Date().toLocaleString('en-US'), text });
        items.push(title);
      }
      if (!items.length) { state.ui.brochureError = 'None of the picked stays could be priced — pick a stay with a total.'; render(); return; }
      state.ui.brochureDone = { recipient: email, when: new Date().toLocaleString('en-US'), items };
      save(); render();
    },
    downloadBrochure(id, kind) {
      const b = state.brochures.find((x) => x.id === id);
      if (!b) return;
      const blob = new Blob([b.text], { type: 'text/plain' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = b.title.replace(/[^a-z0-9]+/gi, '-') + '.txt';
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    },
    printBrochure(id) {
      const b = state.brochures.find((x) => x.id === id);
      if (!b) return;
      const w = window.open('', '_blank');
      if (!w) return;
      w.document.write('<html><head><title>' + esc(b.title) + '</title></head><body style="font-family:monospace;white-space:pre-wrap;padding:32px">' + esc(b.text) + '</body></html>');
      w.document.close();
      w.focus();
      w.print();
    },
    markBrochure(id, status) { mutate(() => { const b = state.brochures.find((x) => x.id === id); if (b) b.status = status; }); },
    // Profile & settings
    profileField(key, value) { if (!state.profile) state.profile = { ...DEFAULT_PROFILE }; state.profile[key] = value; save(); },
    profileAirport(v) { if (!state.profile) state.profile = { ...DEFAULT_PROFILE }; state.profile.homeAirport = v.toUpperCase(); state.settings.origin = v.toUpperCase(); save(); },
    profileSet(key, value) { mutate(() => { if (!state.profile) state.profile = { ...DEFAULT_PROFILE }; state.profile[key] = value; }); },
    profileTerrain(v) {
      mutate(() => {
        if (!state.profile) state.profile = { ...DEFAULT_PROFILE };
        const a = state.profile.terrain;
        state.profile.terrain = a.includes(v) ? a.filter((x) => x !== v) : [...a, v];
      });
    },
    applyProfile(mode) {
      if (mode === 'ask') { state.ui.profileConfirm = true; render(); return; }
      if (mode === 'no') { state.ui.profileConfirm = false; render(); return; }
      mutate(() => {
        const p = state.profile;
        const gear = E.profileGear(p);
        const style = E.profileStyle(p);
        state.settings.origin = p.homeAirport.toUpperCase();
        state.settings.travellers = E.GROUP_TRAVELLERS[p.group] || 1;
        state.trips = state.trips.map((t) => {
          if (t.custom) return t;
          const dest = destById(t.destination);
          return dest ? E.applyStyle({ ...t, gear }, style, dest.socialTier, gear) : t;
        });
        state.ui.profileConfirm = false;
      });
    },
    settingsOrigin(v) { state.settings.origin = v.toUpperCase(); save(); },
    settingsTravellers(n) { mutate(() => { state.settings.travellers = Math.min(8, Math.max(1, n)); }); },
    askReset() { state.ui.resetConfirm = true; render(); },
    cancelReset() { state.ui.resetConfirm = false; render(); },
    resetAll() {
      localStorage.removeItem('tp-web-v1');
      state = defaultState();
      state.ui.ob = { step: 0, answers: { ...DEFAULT_PROFILE }, skipped: false };
      render();
    },
  };

  // ── Boot ────────────────────────────────────────────────────────────────
  fetch('dataset.json')
    .then((r) => { if (!r.ok) throw new Error('dataset ' + r.status); return r.json(); })
    .then((json) => { catalog = json; render(); })
    .catch((err) => {
      document.getElementById('app').innerHTML = '<div class="wrap"><h1>Couldn\'t load the dataset</h1><p>' + esc(err.message) + '</p><p>The researched prices ship with the app as dataset.json — check it sits next to index.html.</p></div>';
    });
})();
