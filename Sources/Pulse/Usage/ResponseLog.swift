// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What the servers said during one account's check, for Settings'
/// connection diagnostics: each request's address, status, type and body.
///
/// **Why.** A reading turns a reply into one of a few reasons, and a reason is
/// a guess about what the reply meant: OpenCode Go's "subscription required"
/// was a 403, and every 403 read as a refused key, so a lapsed plan sent
/// someone to replace a key that worked. The reply itself settles it.
///
/// **What is kept, and what never is.** The method, the address without its
/// query (a key can travel in one), the status, the content type and the
/// first `bodyLimit` characters of the body — **never a request header**, so
/// no key, token or cookie Pulse sends; and in the body, every value under a
/// name that sounds like a credential, and every long unbroken run of the
/// characters tokens are made of, replaced by `mask` (`redacted`). A reply can
/// still name the account — an email, a plan, a balance — which is why it is
/// shown to the person and kept out of the shareable report
/// (`ConnectionDiagnostic.report`).
///
/// **Memory only, the last check only.** One check's replies ride on the
/// raw reading into `ConnectionDiagnostic` and are replaced by the next;
/// nothing is written to disk.
///
/// Requests are recorded by `URLSession.recordedData(for:)`, which the
/// providers use for every request they make while their check runs
/// (`capture`), and the status pages while their pane reads them
/// (`capturing`, to say why a read failed). A request made outside either —
/// a sign-in, the background outage check — records nothing.
enum ResponseLog {
    struct Entry: Equatable, Sendable {
        let at: Date
        let method: String
        /// Scheme, host and path; never the query.
        let address: String
        /// Nil when no reply came back.
        let status: Int?
        let contentType: String?
        /// Redacted and cut to `bodyLimit`; the failure, when there was no reply.
        let body: String
        let byteCount: Int
    }

    static let bodyLimit = 4000
    /// The most requests one check keeps: the last ones, which decided it.
    static let entryLimit = 8
    static let mask = "••••"

    /// One check's entries, appended to from whichever task makes a request.
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Entry] = []

        func append(_ entry: Entry) {
            lock.withLock {
                stored.append(entry)
                if stored.count > ResponseLog.entryLimit { stored.removeFirst(stored.count - ResponseLog.entryLimit) }
            }
        }

        var entries: [Entry] { lock.withLock { stored } }
    }

    @TaskLocal static var collector: Collector?

    /// Runs one account's check with its requests recorded, and returns them
    /// with its reading.
    static func capture(_ check: @Sendable () async -> ProviderUsage) async -> ProviderUsage {
        var (reading, entries) = await capturing(check)
        reading.responses = entries
        return reading
    }

    /// Runs `work` with its requests recorded, and returns them with its
    /// result — a status page's read, for saying why it failed.
    static func capturing<Value: Sendable>(_ work: @Sendable () async -> Value) async -> (Value, [Entry]) {
        let collector = Collector()
        let value = await $collector.withValue(collector) { await work() }
        return (value, collector.entries)
    }

    /// Why a read came back with nothing, in one line: the last request that
    /// got no 200 — its status, or its failure — or, when every request was
    /// answered, that the answer was not one Pulse could use.
    static func failure(of entries: [Entry]) -> String {
        guard let failed = entries.last(where: { $0.status != 200 }) else {
            return entries.isEmpty
                ? String.localized("No request was made.")
                : String.localized("The page answered, but not with anything Pulse reads for this provider.")
        }
        guard let status = failed.status else { return failed.body }
        return String.localized("The page answered HTTP \(String(status)).")
    }

    static func record(_ request: URLRequest, response: URLResponse?, data: Data?, error: (any Error)?, at date: Date = Date()) {
        guard let collector else { return }
        collector.append(entry(request, response: response, data: data, error: error, at: date))
    }

    static func entry(_ request: URLRequest, response: URLResponse?, data: Data?, error: (any Error)?, at date: Date) -> Entry {
        let http = response as? HTTPURLResponse
        let body: String
        if let error {
            let failure = error as NSError
            body = "\(failure.domain) \(failure.code): \(failure.localizedDescription)"
        } else {
            body = text(of: data ?? Data(), contentType: http?.value(forHTTPHeaderField: "Content-Type"))
        }
        return Entry(
            at: date,
            method: request.httpMethod ?? "GET",
            address: address(of: response?.url ?? request.url),
            status: http?.statusCode,
            contentType: http?.value(forHTTPHeaderField: "Content-Type"),
            body: body,
            byteCount: data?.count ?? 0
        )
    }

    static func address(of url: URL?) -> String {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.string ?? ""
    }

    /// The body as text, redacted and cut. JSON comes back laid out with its
    /// keys sorted; anything else as it came.
    static func text(of data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let laidOut = try? JSONSerialization.data(
               withJSONObject: redacted(object), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
           ) {
            return cut(String(decoding: laidOut, as: UTF8.self))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return String.localized("\(String(data.count)) bytes, not text")
        }
        return cut(redacted(text))
    }

    /// A name that sounds like a credential: its value is never kept.
    static func isSecretName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["token", "secret", "password", "passwd", "cookie", "session", "credential", "signature",
                "authorization", "apikey", "api_key", "api-key", "private", "jwt", "bearer", "otp"]
            .contains { lowered.contains($0) }
            || lowered == "key" || lowered.hasSuffix("_key") || lowered.hasSuffix("key") && lowered.count <= 12
    }

    static func redacted(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            var result: [String: Any] = [:]
            for (name, value) in dictionary {
                // Text only: "input_tokens": 1200 is a count, not a credential.
                if isSecretName(name), value is String {
                    result[name] = mask
                } else {
                    result[name] = redacted(value)
                }
            }
            return result
        }
        if let array = object as? [Any] { return array.map(redacted) }
        if let text = object as? String { return redacted(text) }
        return object
    }

    /// A run of the characters keys and tokens are made of — letters,
    /// digits, `-_.~+/=` — that looks random: 40 or more with a digit in it,
    /// or 24 or more mixing capitals, small letters and digits. A long model
    /// name ("claude-opus-4-6-20260101") or a UUID survives; an `sk-…` key, a
    /// JWT or a session cookie does not.
    static func redacted(_ text: String) -> String {
        guard let pattern = try? Regex(#"[A-Za-z0-9\-_.~+/=]{24,}"#) else { return text }
        return text.replacing(pattern) { match in
            let run = text[match.range]
            let digits = run.contains(where: \.isNumber)
            let mixed = digits && run.contains(where: \.isUppercase) && run.contains(where: \.isLowercase)
            return (run.count >= 40 && digits) || mixed ? mask : String(run)
        }
    }

    private static func cut(_ text: String) -> String {
        guard text.count > bodyLimit else { return text }
        return String(text.prefix(bodyLimit)) + "\n…"
    }
}

extension URLSession {
    /// `data(for:delegate:)`, with the reply kept for the connection
    /// diagnostics while an account's check is running (`ResponseLog`).
    func recordedData(
        for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await data(for: request, delegate: delegate)
            ResponseLog.record(request, response: response, data: data, error: nil)
            return (data, response)
        } catch {
            ResponseLog.record(request, response: nil, data: nil, error: error)
            throw error
        }
    }
}
