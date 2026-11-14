import Foundation
import Observation
import SwiftData
import UIKit

/// Composes a trip-variant brochure (plain text + PDF), writes the PDF to
/// Documents/Brochures, records a BrochureRequest, and hands it to the
/// configured EmailProvider. Mirrors the web's brochure flow: one request
/// per selected variant, honest "Queued for assistant" status.
@Observable
@MainActor
final class BrochureService {
    let catalog: Catalog
    private let provider: any EmailProvider

    init(catalog: Catalog, provider: any EmailProvider = QueuedEmailProvider()) {
        self.catalog = catalog
        self.provider = provider
    }

    static func money(_ n: Double?) -> String {
        guard let n else { return "Not priced" }
        return "$" + String(format: "%.2f", n)
    }

    static func lineText(_ line: PricedOption) -> String {
        let amount = line.amount.map { "\(money($0))\(line.estimate ? " ~" : "")" } ?? "Not priced"
        return "\(line.label) — \(amount)\n  \(line.detail)"
    }

    /// Plain-text brochure body — also the email text.
    func composeText(trip: Trip, pricing: TripPricing, variant: VariantPricing, travellers: Int) -> String {
        let destName = trip.destinationID.flatMap { catalog.destination(id: $0)?.name } ?? trip.customDestinationName ?? "Trip"
        let title = trip.title.isEmpty ? destName : trip.title
        let typeLabel = catalog.tripType(id: trip.tripTypeID).label
        let styleLabel = catalog.style(id: trip.styleRaw)?.label ?? trip.styleRaw
        let dates = "\(PricingEngine.dateString(trip.startDate)) – \(PricingEngine.dateString(trip.endDate))"
        var out: [String] = []
        out.append("TRAVEL PLANNER — TRIP BROCHURE")
        out.append("")
        out.append("\(title) · \(typeLabel)")
        out.append("\(dates) · \(trip.activityDays) ski day\(trip.activityDays == 1 ? "" : "s") · \(styleLabel) · \(travellers) traveller\(travellers == 1 ? "" : "s")")
        out.append("Stay: \(variant.hotelName)\(variant.isPrimary ? " (Primary)" : "")")
        out.append("")
        out.append("BREAKDOWN")
        for line in pricing.lines {
            // The brochure prices the chosen variant: swap the hotel line.
            if line.key == "hotel" {
                out.append("Hotel · \(variant.hotelName) — \(Self.money(variant.hotelAmount))\(variant.hotelEstimate ? " ~" : "")")
            } else {
                out.append(Self.lineText(line))
            }
        }
        out.append("")
        out.append("TOTAL: \(Self.money(variant.total))\(variant.partial ? " (partial — some lines not priced)" : "")")
        out.append("")
        out.append("Prices: \(pricing.result.sourceLabel), checked \(pricing.result.checkedAt). Figures marked ~ are estimates. Nothing is booked by this app — booking links go to the sellers.")
        if !pricing.result.notes.isEmpty {
            out.append("")
            out.append("NOTES")
            for note in pricing.result.notes { out.append("· \(note)") }
        }
        return out.joined(separator: "\n")
    }

    /// One-page PDF rendering of the same brochure (black on white — PDFs print).
    func makePDF(text: String, title: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: UIColor.black,
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black,
            ]
            title.draw(in: CGRect(x: 48, y: 48, width: 516, height: 24), withAttributes: titleAttrs)
            text.draw(in: CGRect(x: 48, y: 84, width: 516, height: 660), withAttributes: bodyAttrs)
        }
    }

    static func brochuresDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("Brochures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Queues one brochure per (trip, variant) selection. Returns the created
    /// requests; failures are per-request rows with status .failed and a
    /// specific detail — nothing fails silently.
    func queue(
        selections: [(trip: Trip, pricing: TripPricing, variant: VariantPricing)],
        recipient: String,
        travellers: Int,
        context: ModelContext
    ) async -> [BrochureRequest] {
        var created: [BrochureRequest] = []
        for (trip, pricing, variant) in selections {
            let destName = trip.destinationID.flatMap { catalog.destination(id: $0)?.name } ?? trip.customDestinationName ?? "Trip"
            let title = trip.title.isEmpty ? destName : trip.title
            let text = composeText(trip: trip, pricing: pricing, variant: variant, travellers: travellers)
            let subject = "Your Travel Planner brochure — \(title) (\(variant.hotelName))"
            let summary = "\(title) · \(variant.hotelName) · \(Self.money(variant.total))"

            let request = BrochureRequest()
            request.recipient = recipient
            request.subject = subject
            request.summary = summary
            request.emailText = text
            request.tripTitle = title
            request.destinationName = destName
            request.providerID = provider.id

            do {
                let pdf = makePDF(text: text, title: subject)
                let fileName = "\(request.id.uuidString).pdf"
                let url = try Self.brochuresDirectory().appendingPathComponent(fileName)
                try pdf.write(to: url, options: .atomic)
                request.pdfFileName = fileName

                let email = EmailRequest(
                    to: recipient, subject: subject, textBody: text,
                    pdfFileURL: url, pdfFilename: "\(title) brochure.pdf",
                    planSummary: summary)
                let result = await provider.send(email)
                request.status = BrochureStatus(rawValue: result.status.rawValue) ?? .queued
                if result.status == .sent { request.sentAt = Date() }
            } catch {
                request.status = .failed
                request.summary = "\(summary) — couldn't queue: \(error.localizedDescription)"
            }
            context.insert(request)
            created.append(request)
        }
        try? context.save()
        return created
    }

    static func pdfURL(for request: BrochureRequest) -> URL? {
        guard !request.pdfFileName.isEmpty,
              let dir = try? brochuresDirectory() else { return nil }
        let url = dir.appendingPathComponent(request.pdfFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
