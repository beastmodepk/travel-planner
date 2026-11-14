import Foundation

/// Pure pricing maths, ported 1:1 from the web app
/// (`server/src/pricing.ts` + `providers/dataset.ts` + the plan-level pass
/// engine in `actions.ts`). No I/O, no UI — the same inputs produce the same
/// figures on every client, which is what the golden tests pin down.
enum PricingEngine {

    static func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }

    // MARK: Dates (yyyy-mm-dd, UTC — matches the web's Date.UTC maths)

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateString(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func date(fromString s: String) -> Date? { dayFormatter.date(from: s) }

    /// Whole days from a to b (b − a).
    static func dayDiff(_ a: String, _ b: String) -> Int {
        guard let da = date(fromString: a), let db = date(fromString: b) else { return 0 }
        return Int((db.timeIntervalSince(da) / 86400).rounded())
    }

    // MARK: Window resolution

    /// Which priced window a trip draws from, and whether that is an estimate.
    static func resolveWindow(
        selection: WindowSelection, start: String, end: String, catalog: Catalog
    ) -> (window: String, estimated: Bool) {
        if selection == .dec || selection == .jan { return (selection.rawValue, false) }
        guard let dec = catalog.window(id: "dec"), let jan = catalog.window(id: "jan") else {
            return ("dec", true)
        }
        if start == dec.start && end == dec.end { return ("dec", false) }
        if start == jan.start && end == jan.end { return ("jan", false) }
        let dDec = abs(dayDiff(start, dec.start))
        let dJan = abs(dayDiff(start, jan.start))
        return (dDec <= dJan ? "dec" : "jan", true)
    }

    // MARK: Gear figures

    struct GearFigure {
        var key: String  // "rent" | "carry" | "boots" | "premiumRent"
        var label: String
        var detail: String
        var perPerson: Double
        var estimate: Bool
        var linkUrl: String?
        var linkLabel: String?
    }

    static func gearFigures(dest: Destination, skiDays: Int, window: String, catalog: Catalog) -> [GearFigure] {
        // The Jan Niseko basic fare includes a checked bag — your skis fly free.
        let carryFree = dest.id == "niseko" && window == "jan"
        let premiumPerDay = Double(Int((dest.rentalPerDay * 1.4).rounded()))
        return [
            GearFigure(
                key: "rent", label: "Rent a full package",
                detail: "\(dest.rentalName) · $\(moneyShort(dest.rentalPerDay))/day × \(skiDays) day\(skiDays == 1 ? "" : "s")",
                perPerson: round2(dest.rentalPerDay * Double(skiDays)),
                estimate: dest.rentalEstimate, linkUrl: dest.rentalUrl, linkLabel: "Rentals"),
            GearFigure(
                key: "boots", label: "Own boots, rent skis only",
                detail: "Skis-only rental · $\(moneyShort(dest.bootsPerDay))/day × \(skiDays) day\(skiDays == 1 ? "" : "s")",
                perPerson: round2(dest.bootsPerDay * Double(skiDays)),
                estimate: dest.bootsEstimate, linkUrl: dest.rentalUrl, linkLabel: "Rentals"),
            GearFigure(
                key: "carry", label: "Fly your own skis",
                detail: carryFree
                    ? "1 checked bag included in the Jan basic fare — your ski bag flies free, boots in the carry-on"
                    : "Checked ski bag, $90 round trip — boots in the carry-on",
                perPerson: carryFree ? 0 : catalog.carryBagFee,
                estimate: !carryFree, linkUrl: nil, linkLabel: nil),
            GearFigure(
                key: "premiumRent", label: "Premium demo rentals",
                detail: "\(dest.rentalName) · premium at $\(moneyShort(premiumPerDay))/day × \(skiDays) day\(skiDays == 1 ? "" : "s")",
                perPerson: round2(premiumPerDay * Double(skiDays)),
                estimate: dest.rentalEstimate, linkUrl: dest.rentalUrl, linkLabel: "Rentals"),
        ]
    }

    private static func moneyShort(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(format: "%.2f", n)
    }

    // MARK: Non-Epic lift tickets

    struct LiftFigure {
        var perPerson: Double
        var estimate: Bool
        var detail: String
    }

    /// Day-ticket figure for the non-Epic destinations; nil for Epic resorts.
    static func nonEpicLift(dest: Destination, window: String, skiDays: Int, catalog: Catalog) -> LiftFigure? {
        let table = catalog.nonEpicLift
        if dest.id == "jackson" {
            // Researched anchors: 3-of-4-day ticket (base) + single-day price.
            guard let w = table.jackson[window] else { return nil }
            let base = w.threeOfFour
            let extra = w.singleDay
            if skiDays == 3 {
                return LiftFigure(perPerson: base, estimate: false, detail: "3-of-4-day ticket · official shop price")
            }
            if skiDays == 4 {
                return LiftFigure(perPerson: round2(base + extra), estimate: false,
                                  detail: "3-of-4-day ticket (\(moneyFull(base))) + 1 single day (\(moneyFull(extra))) · official shop price")
            }
            if skiDays < 3 {
                return LiftFigure(perPerson: round2(extra * Double(skiDays)), estimate: true,
                                  detail: "Single-day tickets · \(moneyFull(extra))/day × \(skiDays) day\(skiDays == 1 ? "" : "s") — extended from the researched single-day price")
            }
            return LiftFigure(perPerson: round2(base + extra * Double(skiDays - 3)), estimate: true,
                              detail: "3-of-4-day ticket (\(moneyFull(base))) + \(skiDays - 3) single days at \(moneyFull(extra)) — extended beyond the researched 3–4 days")
        }
        if dest.id == "niseko" {
            // Niseko United All-Mountain, official 2026-27 at ¥155/$.
            guard let w = table.niseko[window] else { return nil }
            let three = w.threeDay
            let four = w.fourDay
            let marginal = four - three
            if skiDays == 3 || skiDays == 4 {
                let total = skiDays == 4 ? four : three
                return LiftFigure(perPerson: total, estimate: true,
                                  detail: "Niseko United All-Mountain · \(w.seasonNote) · \(skiDays) days (~\(moneyFull(total)) at ¥155/$)")
            }
            if skiDays < 3 {
                return LiftFigure(perPerson: round2(three - marginal * Double(3 - skiDays)), estimate: true,
                                  detail: "Niseko United All-Mountain · \(w.seasonNote) · \(skiDays) day\(skiDays == 1 ? "" : "s") — extended from the researched 3-day rate at ¥155/$")
            }
            return LiftFigure(perPerson: round2(four + marginal * Double(skiDays - 4)), estimate: true,
                              detail: "Niseko United All-Mountain · \(w.seasonNote) · \(skiDays) days — extended past 4 days at the researched per-day rate, ¥155/$")
        }
        if dest.id == "alta" {
            let perDay = window == "dec" ? table.alta.decPerDay : table.alta.janPerDay
            return LiftFigure(perPerson: round2(perDay * Double(skiDays)), estimate: true,
                              detail: "Day tickets · ~\(moneyFull(perDay))/day (Snowbird online from $195/day)")
        }
        return nil
    }

    private static func moneyFull(_ n: Double) -> String { "$" + String(format: "%.2f", n) }

    // MARK: Links

    static func googleFlightsUrl(origin: String, dest: Destination, start: String, end: String) -> String {
        "https://www.google.com/travel/flights?q=Flights+from+\(origin)+to+\(dest.airport)+on+\(start)+returning+\(end)"
    }

    static func expediaSearchUrl(dest: Destination, start: String, end: String) -> String {
        let q = dest.hotelSearchName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dest.hotelSearchName
        return "https://www.expedia.com/Hotel-Search?destination=\(q)&startDate=\(start)&endDate=\(end)"
    }

    static func expediaHotelSearchUrl(hotelName: String, dest: Destination, start: String, end: String, travellers: Int) -> String {
        let q = "\(hotelName), \(dest.hotelSearchName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hotelName
        return "https://www.expedia.com/Hotel-Search?destination=\(q)&startDate=\(start)&endDate=\(end)&rooms=1&adults=\(travellers)"
    }

    /// Direct Expedia property deep link — stable Hotel.h{ID} form.
    static func expediaDirectUrl(expediaId: String, start: String, end: String, travellers: Int) -> String {
        "https://www.expedia.com/Hotel.h\(expediaId).Hotel-Information?chkin=\(start)&chkout=\(end)&rm1=a\(travellers)"
    }

    // MARK: Single-trip pricing (the DatasetProvider core)

    static func price(_ req: PricingRequest, catalog: Catalog) -> PricingResult {
        func empty(notes: [String], unpriced: [String]) -> PricingResult {
            PricingResult(
                source: "dataset", sourceLabel: "Researched dataset", checkedAt: catalog.checkedAt,
                priced: false, flight: nil, transfers: nil, hotelOptions: [], liftTicket: nil,
                passProgram: nil, passDays: req.skiDays, rentalPerDay: nil, gearOptions: [],
                chosenGearKey: nil, unpriced: unpriced, notes: notes)
        }

        if req.tripType != "ski-west" && req.tripType != "ski-japan" {
            let label = catalog.tripType(id: req.tripType).label
            return empty(
                notes: ["Pricing for \(label) trips is coming soon — your dates, style and place are saved here. No numbers have been invented for this type yet; Ski — West Coast and Ski — Japan are fully priced today."],
                unpriced: ["trip-type"])
        }
        guard !req.custom, let dest = catalog.destination(id: req.destinationId) else {
            return empty(
                notes: ["\"\(req.destinationName)\" is not in the researched dataset yet — no prices to show. Attach the AI research provider or research this resort to price it."],
                unpriced: ["destination"])
        }

        var notes: [String] = []
        var unpriced: [String] = []
        let (window, windowEstimated) = resolveWindow(
            selection: req.windowSelection, start: req.departDate, end: req.returnDate, catalog: catalog)
        if windowEstimated {
            notes.append("Custom dates priced from the nearest researched window (December / January) — treat the figures as estimates.")
        }
        let nights = max(1, dayDiff(req.departDate, req.returnDate))
        let t = req.travellers
        let perParty = { (perPerson: Double) in round2(perPerson * Double(t)) }
        let partyNote = t > 1 ? " · × \(t) travellers" : ""

        // Flight — the dataset only covers departures from the dataset origin.
        var flight: PricedOption?
        if req.origin.uppercased() == catalog.origin {
            if let fare = dest.flight(window: window, fareClass: req.fareClass),
               let detail = dest.flightDetail[window] {
                flight = PricedOption(
                    key: "flight",
                    label: "Flight · \(detail)",
                    detail: "\(req.fareClass == .flex ? "Flex fare (free changes)" : "Basic fare (cheapest sensible)") · round trip \(req.origin)–\(dest.airport)\(partyNote)",
                    amount: perParty(fare), estimate: false,
                    linkUrl: googleFlightsUrl(origin: req.origin.uppercased(), dest: dest, start: req.departDate, end: req.returnDate),
                    linkLabel: "Google Flights")
            }
        } else {
            unpriced.append("flight")
            notes.append("Flights from \(req.origin.uppercased()) are not in the researched dataset (it covers \(catalog.origin) departures) — flight cost is not included below.")
        }

        let transfers = PricedOption(
            key: "transfers", label: "Airport transfers",
            detail: "\(dest.transfersDetail)\(partyNote)",
            amount: perParty(dest.transfers), estimate: true, linkUrl: nil, linkLabel: nil)

        let tierLabels: [HotelTier: String] = [.value: "Value", .comfort: "Comfort", .premium: "Premium"]
        let hotelOptions: [PricedOption] = HotelTier.allCases.map { tier in
            guard let h = dest.hotel(window: window, tier: tier) else {
                return PricedOption(key: tier.rawValue, label: "No hotel in the dataset",
                                    detail: "", amount: nil, estimate: false, linkUrl: nil, linkLabel: nil, tags: [])
            }
            guard let name = h.name, let price = h.price else {
                return PricedOption(
                    key: tier.rawValue, label: "No premium hotel in the dataset",
                    detail: "Larger Hirafu hotels book direct — not in dataset",
                    amount: nil, estimate: false,
                    linkUrl: expediaSearchUrl(dest: dest, start: req.departDate, end: req.returnDate),
                    linkLabel: "Expedia", tags: h.tags)
            }
            let scaled = nights == 4 ? price : round2(price * Double(nights) / 4)
            return PricedOption(
                key: tier.rawValue, label: name,
                detail: "\(tierLabels[tier] ?? tier.label) tier · \(nights) night\(nights == 1 ? "" : "s") · 1 room, taxes & fees included\(nights == 4 ? "" : " (scaled from the researched 4-night price)")",
                amount: scaled, estimate: windowEstimated || nights != 4,
                linkUrl: h.expediaId.map { expediaDirectUrl(expediaId: $0, start: req.departDate, end: req.returnDate, travellers: t) }
                    ?? expediaHotelSearchUrl(hotelName: name, dest: dest, start: req.departDate, end: req.returnDate, travellers: t),
                linkLabel: "View \(name) on Expedia", tags: h.tags)
        }

        let extendedDays = req.skiDays < 3 || req.skiDays > 4
        if extendedDays {
            notes.append("\(req.skiDays) ski day\(req.skiDays == 1 ? "" : "s") is outside the researched 3–4 day range — lift and rental figures are extended per day from the researched rates and marked as estimates.")
        }

        // Lift: Epic resorts expose the pass program (priced at plan level);
        // the others price day tickets directly.
        var liftTicket: PricedOption?
        var passProgram: PassProgram?
        if dest.epic {
            let p = catalog.epicPass
            passProgram = PassProgram(
                program: p.program, name: p.name,
                dayPassLadder: p.ladder.map { (days: $0.days, pricePerPerson: $0.price, estimate: $0.estimate) },
                fullPassPricePerPerson: p.fullPassPrice, note: p.note,
                linkUrl: p.linkUrl, linkLabel: p.linkLabel)
        } else if let lift = nonEpicLift(dest: dest, window: window, skiDays: req.skiDays, catalog: catalog) {
            let ikonCovered = req.heldPass == .ikon && (dest.id == "jackson" || dest.id == "alta" || dest.id == "niseko")
            liftTicket = PricedOption(
                key: "lift", label: "Lift tickets",
                detail: ikonCovered ? "Covered by your Ikon Pass" : "\(lift.detail)\(partyNote)",
                amount: ikonCovered ? 0 : perParty(lift.perPerson),
                estimate: ikonCovered ? false : lift.estimate || extendedDays,
                linkUrl: dest.ticketUrl, linkLabel: dest.ticketLinkLabel)
        }

        let gearOptions: [PricedOption] = gearFigures(dest: dest, skiDays: req.skiDays, window: window, catalog: catalog).map { g in
            PricedOption(
                key: g.key, label: g.label, detail: "\(g.detail)\(partyNote)",
                amount: perParty(g.perPerson),
                estimate: extendedDays && g.key != "carry" ? true : g.estimate,
                linkUrl: g.linkUrl, linkLabel: g.linkLabel)
        }
        let chosenGearKey: String?
        if req.gear != .auto {
            chosenGearKey = req.gear.rawValue
        } else {
            // Auto = cheapest figure excluding premium rentals.
            let pool = gearOptions.filter { $0.key != GearChoice.premiumRent.rawValue }
            chosenGearKey = pool.min(by: { ($0.amount ?? .infinity) < ($1.amount ?? .infinity) })?.key
        }

        if dest.id == "niseko" {
            notes.append("From the US East Coast the Sat–Wed shape lands you in Niseko on Monday — realistically 1–2 ski days, not 3. Japan rewards a 6–7 day trip.")
            if window == "dec" {
                notes.append("December flights to New Chitose: peak-date inventory was limited when checked; JAL/ANA direct may price lower — verify before booking.")
            }
            if window == "jan" {
                notes.append("Premium hotels in Niseko (January): larger Hirafu hotels book direct — not in dataset.")
            }
            notes.append("Niseko is on Ikon, not Epic — it stays out of the Epic pass comparison below.")
        }
        if dest.id == "alta" && req.style == .social {
            notes.append("Alta's base in Sandy is a quiet suburb — for a social trip, Park City is the Utah pick (Social 9 vs 4).")
        }

        return PricingResult(
            source: "dataset", sourceLabel: "Researched dataset", checkedAt: catalog.checkedAt,
            priced: true, flight: flight, transfers: transfers, hotelOptions: hotelOptions,
            liftTicket: liftTicket, passProgram: passProgram, passDays: req.skiDays,
            rentalPerDay: dest.rentalPerDay, gearOptions: gearOptions,
            chosenGearKey: chosenGearKey, unpriced: unpriced, notes: notes)
    }

    // MARK: Plan-level Epic Pass engine

    struct PassOption {
        var key: String  // "held" | "combined" | "separate" | "full"
        var label: String
        var detail: String
        var amount: Double
        var estimate: Bool
        var recommended: Bool
    }

    struct PassShare {
        var amount: Double
        var estimate: Bool
        var label: String
        var detail: String
        var linkUrl: String?
        var linkLabel: String?
    }

    struct PassPlan {
        var program: String?
        var name: String?
        var passDays: Int
        var heldByUser: Bool
        var options: [PassOption]
        var recommendedKey: String?
        var note: String
        var linkUrl: String?
        var linkLabel: String?
        /// Per-trip-index lift line for Epic trips.
        var shares: [Int: PassShare]

        static let empty = PassPlan(
            program: nil, name: nil, passDays: 0, heldByUser: false, options: [],
            recommendedKey: nil, note: "", linkUrl: nil, linkLabel: nil, shares: [:])
    }

    /// Compares one combined Day Pass vs separate passes vs the full pass
    /// across every Epic trip in the plan, recommends the cheapest, and
    /// allocates the recommended cost back into each trip (pro-rata by pass
    /// days; the last trip absorbs the rounding remainder, so shares always
    /// sum exactly to the option total). A held pass prices every share $0.
    static func buildPassPlan(results: [PricingResult], travellers: Int, heldPass: HeldPass) -> PassPlan {
        let idx = results.indices.filter { results[$0].passProgram != nil }
        guard let firstIdx = idx.first, let program = results[firstIdx].passProgram else {
            return .empty
        }
        let totalDays = idx.reduce(0) { $0 + results[$1].passDays }
        let held = heldPass.rawValue == program.program
        let ladderFor = { (days: Int) in program.dayPassLadder.first { $0.days == days } }

        let combinedEntry = ladderFor(totalDays)
        let combined = PassOption(
            key: "combined",
            label: "One \(program.name) Day Pass — \(totalDays) days",
            detail: idx.count > 1 ? "One pass covers the pass days on both trips" : "One pass covers this trip's pass days",
            amount: round2((combinedEntry?.pricePerPerson ?? program.fullPassPricePerPerson) * Double(travellers)),
            estimate: combinedEntry?.estimate ?? false, recommended: false)

        var separateAmount = 0.0
        var separateEst = false
        for i in idx {
            let e = ladderFor(results[i].passDays)
            separateAmount += (e?.pricePerPerson ?? program.fullPassPricePerPerson) * Double(travellers)
            if e?.estimate == true { separateEst = true }
        }
        let separate = PassOption(
            key: "separate", label: "Separate Day Pass for each trip",
            detail: idx.map { "\(results[$0].passDays)-day pass" }.joined(separator: " + "),
            amount: round2(separateAmount), estimate: separateEst, recommended: false)

        let full = PassOption(
            key: "full", label: "Full \(program.name) Pass",
            detail: "Unlimited season access — only wins if you ski well beyond these two trips",
            amount: round2(program.fullPassPricePerPerson * Double(travellers)),
            estimate: false, recommended: false)

        let baseOptions = [combined, separate, full]
        let recommendedKey: String
        if held {
            recommendedKey = "held"
        } else {
            recommendedKey = baseOptions.min(by: { $0.amount < $1.amount })?.key ?? "combined"
        }
        var options: [PassOption] = []
        if held {
            options.append(PassOption(
                key: "held", label: "Your \(program.name) Pass",
                detail: "You already hold this pass — lift access is covered",
                amount: 0, estimate: false, recommended: true))
        }
        options += baseOptions.map { o in
            var o = o
            o.recommended = o.key == recommendedKey
            return o
        }

        var shares: [Int: PassShare] = [:]
        if held {
            for i in idx {
                shares[i] = PassShare(
                    amount: 0, estimate: false, label: "Lift — \(program.name) Pass",
                    detail: "Covered by your pass", linkUrl: program.linkUrl, linkLabel: program.linkLabel)
            }
        } else if recommendedKey == "separate" {
            for i in idx {
                let days = results[i].passDays
                let e = ladderFor(days)
                shares[i] = PassShare(
                    amount: round2((e?.pricePerPerson ?? program.fullPassPricePerPerson) * Double(travellers)),
                    estimate: e?.estimate ?? false,
                    label: "\(program.name) Day Pass (\(days)-day)", detail: "This trip's own pass",
                    linkUrl: program.linkUrl, linkLabel: program.linkLabel)
            }
        } else {
            let total = baseOptions.first { $0.key == recommendedKey }?.amount ?? 0
            let optionEstimate = baseOptions.first { $0.key == recommendedKey }?.estimate ?? false
            var allocated = 0.0
            for (k, tripIdx) in idx.enumerated() {
                let days = results[tripIdx].passDays
                let isLast = k == idx.count - 1
                let share = isLast ? round2(total - allocated) : round2(total * Double(days) / Double(totalDays))
                allocated += share
                shares[tripIdx] = PassShare(
                    amount: share, estimate: optionEstimate || idx.count > 1,
                    label: recommendedKey == "full" ? "Full \(program.name) Pass share" : "\(program.name) Day Pass (\(totalDays)-day) share",
                    detail: "\(days) of \(totalDays) pass days on this trip",
                    linkUrl: program.linkUrl, linkLabel: program.linkLabel)
            }
        }

        return PassPlan(
            program: program.program, name: "\(program.name) Pass", passDays: totalDays,
            heldByUser: held, options: options, recommendedKey: recommendedKey,
            note: program.note, linkUrl: program.linkUrl, linkLabel: program.linkLabel,
            shares: shares)
    }

    // MARK: Gallery price-from

    /// Cheapest sensible configuration for a destination/window: basic fare,
    /// value hotel (cheapest priced tier), day tickets or a standalone Day
    /// Pass, auto gear. A starting point, not a firm quote — UIs show "~".
    static func priceFrom(dest: Destination, window: String, catalog: Catalog) -> Double? {
        let req = PricingRequest(
            origin: catalog.origin, tripType: dest.tripTypeID, destinationId: dest.id,
            destinationName: dest.name, custom: false,
            departDate: catalog.window(id: window)?.start ?? "", returnDate: catalog.window(id: window)?.end ?? "",
            windowSelection: WindowSelection(rawValue: window) ?? .custom,
            skiDays: 3, travellers: 1, style: .cheap, fareClass: .basic,
            hotelTier: .value, gear: .auto, heldPass: .none)
        let r = price(req, catalog: catalog)
        guard r.priced else { return nil }
        // Cheapest priced hotel tier (not necessarily "value" by name).
        let hotel = r.hotelOptions.compactMap(\.amount).min()
        guard let hotel else { return nil }
        var total = (r.flight?.amount ?? 0) + (r.transfers?.amount ?? 0) + hotel
        if let lift = r.liftTicket?.amount {
            total += lift
        } else if r.passProgram != nil {
            total += catalog.epicPass.rung(days: 3)?.price ?? 0
        }
        if let key = r.chosenGearKey, let gear = r.gearOptions.first(where: { $0.key == key }) {
            total += gear.amount ?? 0
        }
        return round2(total)
    }
}
