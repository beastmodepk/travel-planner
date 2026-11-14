// Travel Planner web — pricing engine.
// A line-for-line port of the iOS PricingEngine (which ports the original
// web prototype's maths). Same dataset in -> same figures out, on every
// client. Pure functions; no DOM, no storage. Loaded as a classic script
// (no modules) so the site works from any static path, including the
// GitHub Pages subpath /travel-planner/.
(function (global) {
  'use strict';

  const round2 = (n) => Math.round(n * 100) / 100;

  function dayDiff(a, b) {
    const pa = a.split('-').map(Number);
    const pb = b.split('-').map(Number);
    return Math.round((Date.UTC(pb[0], pb[1] - 1, pb[2]) - Date.UTC(pa[0], pa[1] - 1, pa[2])) / 86400000);
  }

  function resolveWindow(catalog, selection, start, end) {
    if (selection === 'dec' || selection === 'jan') return { window: selection, estimated: false };
    const dec = catalog.windows.find((w) => w.id === 'dec');
    const jan = catalog.windows.find((w) => w.id === 'jan');
    if (start === dec.start && end === dec.end) return { window: 'dec', estimated: false };
    if (start === jan.start && end === jan.end) return { window: 'jan', estimated: false };
    const dDec = Math.abs(dayDiff(start, dec.start));
    const dJan = Math.abs(dayDiff(start, jan.start));
    return { window: dDec <= dJan ? 'dec' : 'jan', estimated: true };
  }

  function gearFigures(catalog, dest, skiDays, window) {
    const carryFree = dest.id === 'niseko' && window === 'jan';
    const premiumPerDay = Math.round(dest.rentalPerDay * 1.4);
    const days = skiDays === 1 ? 'day' : 'days';
    return [
      { key: 'rent', label: 'Rent a full package',
        detail: `${dest.rentalName} · $${dest.rentalPerDay}/day × ${skiDays} ${days}`,
        perPerson: round2(dest.rentalPerDay * skiDays), estimate: dest.rentalEstimate,
        linkUrl: dest.rentalUrl, linkLabel: 'Rentals' },
      { key: 'boots', label: 'Own boots, rent skis only',
        detail: `Skis-only rental · $${dest.bootsPerDay}/day × ${skiDays} ${days}`,
        perPerson: round2(dest.bootsPerDay * skiDays), estimate: dest.bootsEstimate,
        linkUrl: dest.rentalUrl, linkLabel: 'Rentals' },
      { key: 'carry', label: 'Fly your own skis',
        detail: carryFree
          ? '1 checked bag included in the Jan basic fare — your ski bag flies free, boots in the carry-on'
          : 'Checked ski bag, $90 round trip — boots in the carry-on',
        perPerson: carryFree ? 0 : catalog.carryBagFee, estimate: !carryFree,
        linkUrl: null, linkLabel: null },
      { key: 'premiumRent', label: 'Premium demo rentals',
        detail: `${dest.rentalName} · premium at $${premiumPerDay}/day × ${skiDays} ${days}`,
        perPerson: round2(premiumPerDay * skiDays), estimate: dest.rentalEstimate,
        linkUrl: dest.rentalUrl, linkLabel: 'Rentals' },
    ];
  }

  function nonEpicLift(catalog, dest, window, skiDays) {
    const table = catalog.nonEpicLift;
    if (dest.id === 'jackson') {
      const w = table.jackson[window];
      const base = w.threeOfFour;
      const extra = w.singleDay;
      if (skiDays === 3) return { perPerson: base, estimate: false, detail: '3-of-4-day ticket · official shop price' };
      if (skiDays === 4) return { perPerson: round2(base + extra), estimate: false, detail: `3-of-4-day ticket ($${base.toFixed(2)}) + 1 single day ($${extra.toFixed(2)}) · official shop price` };
      if (skiDays < 3) return { perPerson: round2(extra * skiDays), estimate: true, detail: `Single-day tickets · $${extra.toFixed(2)}/day × ${skiDays} day${skiDays === 1 ? '' : 's'} — extended from the researched single-day price` };
      return { perPerson: round2(base + extra * (skiDays - 3)), estimate: true, detail: `3-of-4-day ticket ($${base.toFixed(2)}) + ${skiDays - 3} single days at $${extra.toFixed(2)} — extended beyond the researched 3–4 days` };
    }
    if (dest.id === 'niseko') {
      const w = table.niseko[window];
      const three = w.threeDay;
      const four = w.fourDay;
      const marginal = four - three;
      if (skiDays === 3 || skiDays === 4) {
        const total = skiDays === 4 ? four : three;
        return { perPerson: total, estimate: true, detail: `Niseko United All-Mountain · ${w.seasonNote} · ${skiDays} days (~$${total.toFixed(2)} at ¥155/$)` };
      }
      if (skiDays < 3) return { perPerson: round2(three - marginal * (3 - skiDays)), estimate: true, detail: `Niseko United All-Mountain · ${w.seasonNote} · ${skiDays} day${skiDays === 1 ? '' : 's'} — extended from the researched 3-day rate at ¥155/$` };
      return { perPerson: round2(four + marginal * (skiDays - 4)), estimate: true, detail: `Niseko United All-Mountain · ${w.seasonNote} · ${skiDays} days — extended past 4 days at the researched per-day rate, ¥155/$` };
    }
    if (dest.id === 'alta') {
      const perDay = window === 'dec' ? table.alta.decPerDay : table.alta.janPerDay;
      return { perPerson: round2(perDay * skiDays), estimate: true, detail: `Day tickets · ~$${perDay.toFixed(2)}/day (Snowbird online from $195/day)` };
    }
    return null;
  }

  const googleFlightsUrl = (origin, dest, start, end) =>
    `https://www.google.com/travel/flights?q=Flights+from+${origin}+to+${dest.airport}+on+${start}+returning+${end}`;
  const expediaSearchUrl = (dest, start, end) =>
    `https://www.expedia.com/Hotel-Search?destination=${encodeURIComponent(dest.hotelSearchName)}&startDate=${start}&endDate=${end}`;
  const expediaHotelSearchUrl = (hotelName, dest, start, end, travellers) =>
    `https://www.expedia.com/Hotel-Search?destination=${encodeURIComponent(`${hotelName}, ${dest.hotelSearchName}`)}&startDate=${start}&endDate=${end}&rooms=1&adults=${travellers}`;
  const expediaDirectUrl = (expediaId, start, end, travellers) =>
    `https://www.expedia.com/Hotel.h${expediaId}.Hotel-Information?chkin=${start}&chkout=${end}&rm1=a${travellers}`;

  const TIERS = ['value', 'comfort', 'premium'];
  const TIER_LABEL = { value: 'Value', comfort: 'Comfort', premium: 'Premium' };

  // Flight options: Google-Flights-style lists per destination/window.
  // Default selection = the option flagged `anchor` for the request's fare
  // class (the exact researched fare); an explicit flightOptionId always
  // wins. Same rule as the iOS engine — see packages/dataset.
  function stopsLabel(leg) {
    if (leg.stops === 0) return 'Nonstop';
    return `${leg.stops} stop${leg.stops === 1 ? '' : 's'}${leg.via ? ` · ${leg.via}` : ''}`;
  }
  function stopsShort(leg) {
    return leg.stops === 0 ? 'Nonstop' : `${leg.stops} stop${leg.stops === 1 ? '' : 's'}`;
  }
  function selectFlight(options, fareClass, optionId) {
    if (!options || !options.length) return null;
    if (optionId) {
      const picked = options.find((o) => o.id === optionId);
      if (picked) return picked;
    }
    const anchor = options.find((o) => o.anchor && o.fareClass === fareClass);
    if (anchor) return anchor;
    const sameClass = options.filter((o) => o.fareClass === fareClass);
    const pool = sameClass.length ? sameClass : options;
    return pool.reduce((best, o) => (o.price < best.price ? o : best), pool[0]);
  }
  function flightOptionView(o, origin, airport, travellers, selectedId) {
    const dayTag = (leg) => (leg.arriveNextDay ? ` +${leg.arriveNextDay}` : '');
    return { id: o.id, airline: o.airline, fareClass: o.fareClass,
      pricePerPerson: o.price, amount: round2(o.price * travellers),
      tags: o.tags.slice(), bagIncluded: o.bagIncluded === true,
      outbound: { ...o.outbound }, inbound: { ...o.return },
      selected: o.id === selectedId,
      summary: `${o.airline} · ${o.outbound.depart} → ${o.outbound.arrive}${dayTag(o.outbound)} · ${stopsShort(o.outbound)}`,
      detail: `Out ${o.outbound.depart} → ${o.outbound.arrive}${dayTag(o.outbound)} · ${o.outbound.duration} · ${stopsLabel(o.outbound)} · Back ${o.return.depart} → ${o.return.arrive}${dayTag(o.return)} · ${o.return.duration} · ${stopsLabel(o.return)} · ${o.fareClass === 'flex' ? 'Flex fare (free changes)' : 'Basic fare'}${o.bagIncluded ? ' · 1 checked bag included' : ''} · round trip ${origin}–${airport}` };
  }

  function emptyResult(catalog, req, notes, unpriced) {
    return { source: 'dataset', sourceLabel: 'Researched dataset', checkedAt: catalog.checkedAt,
      priced: false, flight: null, flightOptions: [], transfers: null, hotelOptions: [], liftTicket: null,
      passProgram: null, passDays: req.skiDays, rentalPerDay: null, gearOptions: [],
      chosenGearKey: null, unpriced, notes };
  }

  function price(catalog, req) {
    // The catalog carries exactly two trip types (ski-west, ski-japan).
    // Anything else is a stale id from a removed type — fall back to
    // Ski — West Coast rather than leaving the trip unpriced.
    if (req.tripType !== 'ski-west' && req.tripType !== 'ski-japan') {
      req = { ...req, tripType: 'ski-west' };
    }
    const dest = req.custom ? null : catalog.destinations.find((d) => d.id === req.destinationId);
    if (!dest) {
      return emptyResult(catalog, req,
        [`"${req.destinationName}" is not in the researched dataset yet — no prices to show. Attach the AI research provider or research this resort to price it.`],
        ['destination']);
    }

    const notes = [];
    const unpriced = [];
    const { window, estimated: windowEstimated } = resolveWindow(catalog, req.windowSelection, req.departDate, req.returnDate);
    if (windowEstimated) notes.push('Custom dates priced from the nearest researched window (December / January) — treat the figures as estimates.');
    const nights = Math.max(1, dayDiff(req.departDate, req.returnDate));
    const t = req.travellers;
    const perParty = (pp) => round2(pp * t);
    const partyNote = t > 1 ? ` · × ${t} travellers` : '';

    let flight = null;
    let flightOptions = [];
    if (req.origin.toUpperCase() === catalog.origin) {
      const options = dest.flights[window] || [];
      const chosen = selectFlight(options, req.fareClass, req.flightOptionId || null);
      if (chosen) {
        flightOptions = options.map((o) => flightOptionView(o, req.origin.toUpperCase(), dest.airport, t, chosen.id));
        const view = flightOptions.find((v) => v.id === chosen.id);
        flight = { key: 'flight', label: `Flight · ${chosen.airline} · ${req.origin.toUpperCase()}–${dest.airport}`,
          detail: `${view.detail}${partyNote}`,
          summary: view.summary, optionId: chosen.id,
          amount: perParty(chosen.price), estimate: false,
          linkUrl: googleFlightsUrl(req.origin.toUpperCase(), dest, req.departDate, req.returnDate), linkLabel: 'Google Flights' };
      }
    } else {
      unpriced.push('flight');
      notes.push(`Flights from ${req.origin.toUpperCase()} are not in the researched dataset (it covers ${catalog.origin} departures) — flight cost is not included below.`);
    }

    const transfers = { key: 'transfers', label: 'Airport transfers',
      detail: `${dest.transfersDetail}${partyNote}`, amount: perParty(dest.transfers),
      estimate: true, linkUrl: null, linkLabel: null };

    const hotelOptions = TIERS.map((tier) => {
      const h = dest.hotels[window][tier];
      if (h.price == null || h.name == null) {
        return { key: tier, label: 'No premium hotel in the dataset',
          detail: 'Larger Hirafu hotels book direct — not in dataset', amount: null, estimate: false,
          linkUrl: expediaSearchUrl(dest, req.departDate, req.returnDate), linkLabel: 'Expedia', tags: h.tags.slice() };
      }
      const scaled = nights === 4 ? h.price : round2((h.price * nights) / 4);
      return { key: tier, label: h.name,
        detail: `${TIER_LABEL[tier]} tier · ${nights} night${nights === 1 ? '' : 's'} · 1 room, taxes & fees included${nights === 4 ? '' : ' (scaled from the researched 4-night price)'}`,
        amount: scaled, estimate: windowEstimated || nights !== 4,
        linkUrl: h.expediaId ? expediaDirectUrl(h.expediaId, req.departDate, req.returnDate, t)
                             : expediaHotelSearchUrl(h.name, dest, req.departDate, req.returnDate, t),
        linkLabel: `View ${h.name} on Expedia`, tags: h.tags.slice() };
    });

    const extendedDays = req.skiDays < 3 || req.skiDays > 4;
    if (extendedDays) notes.push(`${req.skiDays} ski day${req.skiDays === 1 ? '' : 's'} is outside the researched 3–4 day range — lift and rental figures are extended per day from the researched rates and marked as estimates.`);

    let liftTicket = null;
    let passProgram = null;
    if (dest.epic) {
      const p = catalog.epicPass;
      passProgram = { program: p.program, name: p.name,
        dayPassLadder: p.ladder.map((r) => ({ days: r.days, pricePerPerson: r.price, estimate: r.estimate })),
        fullPassPricePerPerson: p.fullPassPrice, note: p.note, linkUrl: p.linkUrl, linkLabel: p.linkLabel };
    } else {
      const lift = nonEpicLift(catalog, dest, window, req.skiDays);
      if (lift) {
        const ikonCovered = req.heldPass === 'ikon' && (dest.id === 'jackson' || dest.id === 'alta' || dest.id === 'niseko');
        liftTicket = { key: 'lift', label: 'Lift tickets',
          detail: ikonCovered ? 'Covered by your Ikon Pass' : `${lift.detail}${partyNote}`,
          amount: ikonCovered ? 0 : perParty(lift.perPerson),
          estimate: ikonCovered ? false : lift.estimate || extendedDays,
          linkUrl: dest.ticketUrl, linkLabel: dest.ticketLinkLabel };
      }
    }

    const gearOptions = gearFigures(catalog, dest, req.skiDays, window).map((g) => ({
      key: g.key, label: g.label, detail: `${g.detail}${partyNote}`, amount: perParty(g.perPerson),
      estimate: extendedDays && g.key !== 'carry' ? true : g.estimate,
      linkUrl: g.linkUrl, linkLabel: g.linkLabel }));
    let chosenGearKey;
    if (req.gear !== 'auto') {
      chosenGearKey = req.gear;
    } else {
      const pool = gearOptions.filter((g) => g.key !== 'premiumRent');
      chosenGearKey = pool.reduce((best, g) => ((g.amount ?? Infinity) < (best.amount ?? Infinity) ? g : best), pool[0]).key;
    }

    if (dest.id === 'niseko') {
      notes.push('From the US East Coast the Sat–Wed shape lands you in Niseko on Monday — realistically 1–2 ski days, not 3. Japan rewards a 6–7 day trip.');
      if (window === 'dec') notes.push('December flights to New Chitose: peak-date inventory was limited when checked; JAL/ANA direct may price lower — verify before booking.');
      if (window === 'jan') notes.push('Premium hotels in Niseko (January): larger Hirafu hotels book direct — not in dataset.');
      notes.push('Niseko is on Ikon, not Epic — it stays out of the Epic pass comparison below.');
    }
    if (dest.id === 'alta' && req.style === 'social') {
      notes.push("Alta's base in Sandy is a quiet suburb — for a social trip, Park City is the Utah pick (Social 9 vs 4).");
    }

    return { source: 'dataset', sourceLabel: 'Researched dataset', checkedAt: catalog.checkedAt,
      priced: true, flight, flightOptions, transfers, hotelOptions, liftTicket, passProgram,
      passDays: req.skiDays, rentalPerDay: dest.rentalPerDay, gearOptions, chosenGearKey, unpriced, notes };
  }

  // Plan-level Epic Pass engine: combined vs separate vs full, pro-rata
  // allocation (last trip absorbs rounding), held pass = $0.
  function buildPassPlan(results, travellers, heldPass) {
    const shares = {};
    const idx = results.map((r, i) => (r.passProgram ? i : -1)).filter((i) => i >= 0);
    const program = idx.length ? results[idx[0]].passProgram : null;
    if (!program || !idx.length) {
      return { view: { program: null, name: null, passDays: 0, heldByUser: false, options: [], recommendedKey: null, note: '', linkUrl: null, linkLabel: null }, shares };
    }
    const totalDays = idx.reduce((s, i) => s + (results[i].passDays || 0), 0);
    const held = heldPass === program.program;
    const ladderFor = (days) => program.dayPassLadder.find((l) => l.days === days);

    const combinedEntry = ladderFor(totalDays);
    const combined = { key: 'combined',
      label: `One ${program.name} Day Pass — ${totalDays} days`,
      detail: idx.length > 1 ? 'One pass covers the pass days on both trips' : "One pass covers this trip's pass days",
      amount: round2((combinedEntry ? combinedEntry.pricePerPerson : program.fullPassPricePerPerson) * travellers),
      estimate: combinedEntry ? combinedEntry.estimate : false };
    let separateAmount = 0;
    let separateEst = false;
    for (const i of idx) {
      const e = ladderFor(results[i].passDays || 3);
      separateAmount += (e ? e.pricePerPerson : program.fullPassPricePerPerson) * travellers;
      if (e && e.estimate) separateEst = true;
    }
    const separate = { key: 'separate', label: 'Separate Day Pass for each trip',
      detail: idx.map((i) => `${results[i].passDays || 3}-day pass`).join(' + '),
      amount: round2(separateAmount), estimate: separateEst };
    const full = { key: 'full', label: `Full ${program.name} Pass`,
      detail: 'Unlimited season access — only wins if you ski well beyond these two trips',
      amount: round2(program.fullPassPricePerPerson * travellers), estimate: false };
    const baseOptions = [combined, separate, full];

    let recommendedKey;
    if (held) recommendedKey = 'held';
    else recommendedKey = baseOptions.reduce((best, o) => (o.amount < best.amount ? o : best), baseOptions[0]).key;
    const options = [
      ...(held ? [{ key: 'held', label: `Your ${program.name} Pass`, detail: 'You already hold this pass — lift access is covered', amount: 0, estimate: false, recommended: true }] : []),
      ...baseOptions.map((o) => ({ ...o, recommended: o.key === recommendedKey })),
    ];

    if (held) {
      for (const i of idx) shares[i] = { amount: 0, estimate: false, label: `Lift — ${program.name} Pass`, detail: 'Covered by your pass', linkUrl: program.linkUrl, linkLabel: program.linkLabel };
    } else if (recommendedKey === 'separate') {
      for (const i of idx) {
        const days = results[i].passDays || 3;
        const e = ladderFor(days);
        shares[i] = { amount: round2((e ? e.pricePerPerson : program.fullPassPricePerPerson) * travellers),
          estimate: e ? e.estimate : false, label: `${program.name} Day Pass (${days}-day)`, detail: "This trip's own pass",
          linkUrl: program.linkUrl, linkLabel: program.linkLabel };
      }
    } else {
      const total = (baseOptions.find((o) => o.key === recommendedKey) || {}).amount || 0;
      const optEst = (baseOptions.find((o) => o.key === recommendedKey) || {}).estimate || false;
      let allocated = 0;
      idx.forEach((tripIdx, k) => {
        const days = results[tripIdx].passDays || 3;
        const isLast = k === idx.length - 1;
        const share = isLast ? round2(total - allocated) : round2((total * days) / totalDays);
        allocated += share;
        shares[tripIdx] = { amount: share, estimate: optEst || idx.length > 1,
          label: recommendedKey === 'full' ? `Full ${program.name} Pass share` : `${program.name} Day Pass (${totalDays}-day) share`,
          detail: `${days} of ${totalDays} pass days on this trip`, linkUrl: program.linkUrl, linkLabel: program.linkLabel };
      });
    }

    return { view: { program: program.program, name: `${program.name} Pass`, passDays: totalDays,
      heldByUser: held, options, recommendedKey, note: program.note,
      linkUrl: program.linkUrl, linkLabel: program.linkLabel }, shares };
  }

  // Assemble one trip's display lines + variants from a PricingResult.
  function assembleTrip(catalog, cfg, result, passShare, settings) {
    if (!result.priced) {
      return { priced: false, lines: [], total: null, partial: true, variants: [], notes: result.notes, result };
    }
    const lines = [];
    if (result.flight) lines.push({ ...result.flight });
    else if (result.unpriced.includes('flight')) {
      lines.push({ key: 'flight', label: 'Flight', detail: `Not priced for departures from ${settings.origin.toUpperCase()} in this source`, amount: null, estimate: false, linkUrl: null, linkLabel: null });
    }
    if (result.transfers) lines.push({ ...result.transfers });
    const hotel = result.hotelOptions.find((h) => h.key === cfg.hotelTier) || result.hotelOptions[0];
    if (hotel) lines.push({ key: 'hotel', label: `Hotel · ${hotel.label}`, detail: hotel.detail, amount: hotel.amount, estimate: hotel.estimate, linkUrl: hotel.linkUrl, linkLabel: hotel.linkLabel, tags: hotel.tags });
    if (result.liftTicket) lines.push({ ...result.liftTicket });
    if (passShare) lines.push({ key: 'lift', label: passShare.label, detail: passShare.detail, amount: passShare.amount, estimate: passShare.estimate, linkUrl: passShare.linkUrl, linkLabel: passShare.linkLabel });
    const gear = result.gearOptions.find((g) => g.key === result.chosenGearKey);
    if (gear) lines.push({ key: 'gear', label: `Gear · ${gear.label}`, detail: gear.detail, amount: gear.amount, estimate: gear.estimate, linkUrl: gear.linkUrl, linkLabel: gear.linkLabel });

    const total = round2(lines.reduce((s, l) => s + (l.amount || 0), 0));
    const partial = lines.some((l) => l.amount == null) || result.unpriced.length > 0;

    const flightLine = lines.find((l) => l.key === 'flight');
    const transfersLine = lines.find((l) => l.key === 'transfers');
    const liftLine = lines.find((l) => l.key === 'lift');
    const gearLine = lines.find((l) => l.key === 'gear');
    const variants = result.hotelOptions.map((h) => {
      const amounts = [flightLine && flightLine.amount, transfersLine && transfersLine.amount, h.amount, liftLine && liftLine.amount, gearLine && gearLine.amount];
      return { tier: h.key, hotelName: h.label, hotelTags: h.tags || [], isPrimary: h.key === cfg.hotelTier,
        flightAmount: flightLine ? flightLine.amount : null, flightEstimate: flightLine ? flightLine.estimate : false,
        transfersAmount: transfersLine ? transfersLine.amount : null, transfersEstimate: transfersLine ? transfersLine.estimate : false,
        hotelAmount: h.amount, hotelEstimate: h.estimate,
        liftAmount: liftLine ? liftLine.amount : null, liftEstimate: liftLine ? liftLine.estimate : false,
        liftLabel: liftLine ? liftLine.label : 'Lift / Pass',
        gearAmount: gearLine ? gearLine.amount : null, gearEstimate: gearLine ? gearLine.estimate : false,
        total: h.amount == null ? null : round2(amounts.reduce((s, a) => s + (a || 0), 0)),
        partial: amounts.some((a) => a == null) };
    });

    return { priced: true, lines, total, partial, variants, notes: result.notes, result };
  }

  function priceFrom(catalog, dest, window) {
    const w = catalog.windows.find((x) => x.id === window);
    const r = price(catalog, { origin: catalog.origin, tripType: dest.tripTypeID, destinationId: dest.id,
      destinationName: dest.name, custom: false, departDate: w.start, returnDate: w.end,
      windowSelection: window, skiDays: 3, travellers: 1, style: 'cheap', fareClass: 'basic', flightOptionId: null,
      hotelTier: 'value', gear: 'auto', heldPass: 'none' });
    if (!r.priced) return null;
    const hotel = Math.min(...r.hotelOptions.map((h) => h.amount).filter((a) => a != null));
    if (!isFinite(hotel)) return null;
    let total = (r.flight ? r.flight.amount : 0) + (r.transfers ? r.transfers.amount : 0) + hotel;
    if (r.liftTicket) total += r.liftTicket.amount || 0;
    else if (r.passProgram) {
      const rung = catalog.epicPass.ladder.find((x) => x.days === 3);
      total += rung ? rung.price : 0;
    }
    const gear = r.gearOptions.find((g) => g.key === r.chosenGearKey);
    if (gear) total += gear.amount || 0;
    return round2(total);
  }

  // Style presets + profile derivations (web parity).
  function applyStyle(cfg, style, socialTier, gearDefault) {
    // A style preset also clears any hand-picked flight: the preset's fare
    // class re-selects that class's anchor option.
    const next = { ...cfg, style, flightOptionId: null };
    switch (style) {
      case 'cheap': return { ...next, fareClass: 'basic', hotelTier: 'value', hotelSelections: ['value'], gear: gearDefault };
      case 'balanced': return { ...next, fareClass: 'basic', hotelTier: 'comfort', hotelSelections: ['comfort'], gear: gearDefault };
      case 'expensive': return { ...next, fareClass: 'flex', hotelTier: 'premium', hotelSelections: ['premium'], gear: 'premiumRent' };
      case 'social': return { ...next, fareClass: 'basic', hotelTier: socialTier, hotelSelections: [socialTier], gear: gearDefault };
      case 'snow': return { ...next, fareClass: 'basic', hotelTier: 'comfort', hotelSelections: ['comfort'], gear: gearDefault };
      default: return next;
    }
  }
  const profileGear = (p) => (p.gearOwned === 'own-skis' ? 'carry' : p.gearOwned === 'own-boots' ? 'boots' : 'auto');
  const profileStyle = (p) => (p.vibe === 'social' ? 'social' : p.travelStyle === 'cheap' ? 'cheap' : p.travelStyle === 'treat' ? 'expensive' : 'balanced');
  const GROUP_TRAVELLERS = { solo: 1, couple: 2, friends: 3, family: 4 };

  global.TPEngine = { round2, dayDiff, resolveWindow, gearFigures, nonEpicLift, price, buildPassPlan, assembleTrip, priceFrom, applyStyle, profileGear, profileStyle, GROUP_TRAVELLERS, expediaDirectUrl, expediaHotelSearchUrl, expediaSearchUrl, googleFlightsUrl, selectFlight, stopsLabel };
})(window);
