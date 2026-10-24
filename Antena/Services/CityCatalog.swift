import Foundation

struct CityCatalog {
    struct Result {
        let city: String
        let channels: [Channel]
        let offline: Bool
        var compatibleCount: Int { channels.filter(\.canTune).count }
    }
    enum Failure: LocalizedError {
        case unavailable, ambiguousCity
        var errorDescription: String? {
            switch self {
            case .unavailable: return L10n.text("No verifiable terrestrial TV listings were found. Try the city’s English name with its country, or add a station manually.")
            case .ambiguousCity: return L10n.text("The city could not be identified unambiguously. Enter its name with the country or region.")
            }
        }
    }
    static let suggestedCities = ["Montréal", "Toronto", "Los Angeles", "New York City", "Mexico City", "London", "Madrid", "Paris", "Tokyo", "São Paulo", "Sydney"]
    static func normalized(_ city: String) -> String {
        city.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func frequency(rf: Int) -> UInt32? {
        switch rf {
        case 2...4: return UInt32(57 + (rf-2)*6)*1_000_000
        case 5...6: return UInt32(79 + (rf-5)*6)*1_000_000
        case 7...13: return UInt32(177 + (rf-7)*6)*1_000_000
        case 14...36: return UInt32(473 + (rf-14)*6)*1_000_000
        default: return nil
        }
    }
    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap {
            $0.numberOfRanges > 1 && $0.range(at: 1).location != NSNotFound ? source.substring(with: $0.range(at: 1)) : nil
        }
    }
    static func field(_ name: String, in text: String) -> String? {
        matches("(?mi)^\\|\\s*" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*([^\\n]+)", in: text).first
    }
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<ref[^>]*>.*?</ref>|<[^>]+>|\\{\\{[^{}]*\\}\\}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[\\[(?:[^|\\]]*\\|)?([^\\]]+)\\]\\]", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "'''?", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func json(_ parameters: [String: String], host: String = "en.wikipedia.org") async throws -> [String: Any] {
        try Task.checkCancellation()
        var url = URLComponents(string: "https://\(host)/w/api.php")!
        url.queryItems = parameters.merging(["format": "json", "formatversion": "2"]) { a, _ in a }.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue("AntenaDesktop/0.1 (terrestrial television catalog)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unavailable }
        return result
    }
    private static func article(_ title: String) async throws -> String {
        let response = try await json(["action": "parse", "page": title, "prop": "wikitext", "redirects": "1"])
        guard let parse = response["parse"] as? [String: Any], let text = parse["wikitext"] as? String else { throw Failure.unavailable }
        return text
    }
    static func catalogURL(city: String) -> URL {
        var components = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
        components.queryItems = [URLQueryItem(name: "search", value: "television " + city)]
        return components.url!
    }
    static func logoURL(file: String) async -> String? {
        let title = file.hasPrefix("File:") ? file : "File:" + file
        for host in ["en.wikipedia.org", "commons.wikimedia.org"] {
            guard let response = try? await json(["action": "query", "titles": title, "prop": "imageinfo", "iiprop": "url", "iiurlwidth": "300"], host: host),
                  let query = response["query"] as? [String: Any], let pages = query["pages"] as? [[String: Any]],
                  let info = (pages.first?["imageinfo"] as? [[String: Any]])?.first,
                  let url = (info["thumburl"] ?? info["url"]) as? String else { continue }
            return url
        }
        return nil
    }
    struct Place {
        var title: String
        var country: String?
    }
    private static func resolveExact(_ input: String) async throws -> Place {
        let response = try await json(["action": "query", "titles": input, "redirects": "1", "prop": "pageprops|langlinks", "lllang": "en", "lllimit": "1"])
        guard let query = response["query"] as? [String: Any], let page = (query["pages"] as? [[String: Any]])?.first,
              page["missing"] == nil, let title = page["title"] as? String,
              let props = page["pageprops"] as? [String: Any], props["disambiguation"] == nil,
              let entity = props["wikibase_item"] as? String else { throw Failure.ambiguousCity }
        let wikidata = try await json(["action": "wbgetentities", "ids": entity, "props": "claims"], host: "www.wikidata.org")
        let entities = wikidata["entities"] as? [String: Any]
        let object = entities?[entity] as? [String: Any]
        let claims = object?["claims"] as? [String: Any]
        // A city must have a country and a geographic coordinate. Do not treat
        // an unrelated identically named article as a place.
        guard claims?["P625"] != nil, let countries = claims?["P17"] as? [[String: Any]],
              let main = countries.first?["mainsnak"] as? [String: Any],
              let value = main["datavalue"] as? [String: Any], let country = value["value"] as? [String: Any],
              let id = country["id"] as? String else { throw Failure.ambiguousCity }
        return Place(title: title, country: id)
    }
    private static func resolve(_ input: String) async throws -> Place {
        do { return try await resolveExact(input) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            let components = input.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard components.count == 2 else { throw error }
            let qualifier = normalized(components[1])
            if let place = try? await resolveExact(components[0]), let country = place.country {
                let response = try await json(["action": "wbgetentities", "ids": country, "props": "labels|aliases", "languages": "en|es|fr"], host: "www.wikidata.org")
                let object = (response["entities"] as? [String: Any])?[country] as? [String: Any]
                let labels = (object?["labels"] as? [String: [String: Any]])?.values.compactMap { $0["value"] as? String } ?? []
                let aliases = (object?["aliases"] as? [String: [[String: Any]]])?.values.flatMap { $0.compactMap { $0["value"] as? String } } ?? []
                if (labels + aliases).contains(where: { normalized($0) == qualifier }) { return place }
            }
            // For homonyms such as London, Ontario, require the requested region
            // in the candidate title rather than silently choosing another city.
            let response = try await json(["action": "query", "list": "search", "srsearch": input, "srnamespace": "0", "srlimit": "8"])
            let query = response["query"] as? [String: Any]
            let titles = (query?["search"] as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? []
            let matches = titles.filter { normalized($0).hasPrefix(normalized(components[0])) && normalized($0).contains(qualifier) }
            guard matches.count == 1 else { throw Failure.ambiguousCity }
            return try await resolveExact(matches[0])
        }
    }

    static func televisionSection(_ text: String) -> String? {
        guard let heading = text.range(of: "(?mi)^(={2,5})\\s*(?:Television|TV stations|Broadcast television|Television stations|Media|Mass media|Broadcasting)[^\\n]*?\\1\\s*$", options: .regularExpression) else { return nil }
        let rest = String(text[heading.upperBound...])
        let level = text[heading].prefix { $0 == "=" }.count
        let pattern = "(?m)^={2,\(level)}[^=].*?={2,\(level)}\\s*$"
        if let next = rest.range(of: pattern, options: .regularExpression) { return String(rest[..<next.lowerBound]) }
        return rest
    }
    static func linkedArticles(_ text: String) -> [String] {
        var seen: Set<String> = []
        return matches("\\[\\[([^|\\]#]+)(?:[|#][^\\]]*)?\\]\\]", in: text).map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.contains(":") && !$0.isEmpty && seen.insert($0).inserted
        }
    }
    /// Parse only explicit terrestrial metadata. Unknown frequencies remain zero
    /// as a catalog-only entry; a virtual channel is never converted to RF.
    static func stationMetadata(_ text: String, title: String, city: String, country: String?, seed: Channel? = nil) -> Channel? {
        if let closed = field("closed", in: text) ?? field("closed_date", in: text), !plain(closed).isEmpty { return seed }
        let hasStationBox = text.range(of: "(?i)\\{\\{\\s*Infobox (?:television|TV) (?:station|channel|network)", options: .regularExpression) != nil
        let terrestrialKeys = ["terr_serv_1", "terrestrial", "digital", "digital_channel", "terr_chan_1"]
        let terrestrial = terrestrialKeys.compactMap { field($0, in: text) }.joined(separator: " ")
        guard seed != nil || (hasStationBox && !terrestrial.isEmpty) else { return nil }
        let actualCall = field("callsign", in: text).map(plain)
        // Redirected relays must not borrow the parent's transmitter frequency.
        if let actualCall, title.range(of: "^[CWKX][A-Z0-9-]{2,}$", options: .regularExpression) != nil,
           normalized(actualCall) != normalized(title), seed == nil { return nil }
        let countryIsATSC = ["Q16", "Q30", "Q96"].contains(country ?? "")
        let digital = field("digital", in: text) ?? field("digital_channel", in: text) ?? ""
        let signal = digital + " " + terrestrial
        let standard: String
        if field("atsc3", in: text)?.lowercased() == "yes" || signal.range(of: "ATSC\\s*3", options: [.regularExpression, .caseInsensitive]) != nil { standard = "ATSC 3.0" }
        else if signal.localizedCaseInsensitiveContains("DVB-T2") { standard = "DVB-T2" }
        else if signal.localizedCaseInsensitiveContains("DVB-T") || signal.localizedCaseInsensitiveContains("Freeview") { standard = "DVB-T" }
        else if signal.localizedCaseInsensitiveContains("ISDB") { standard = "ISDB-T" }
        else if signal.localizedCaseInsensitiveContains("DTMB") { standard = "DTMB" }
        else if countryIsATSC || seed != nil || signal.localizedCaseInsensitiveContains("ATSC") || signal.localizedCaseInsensitiveContains("8VSB") { standard = "ATSC 1.0" }
        else { standard = "Unknown" }
        var channel = seed ?? Channel(number: "—", name: title, language: "—", frequency: 0)
        channel.broadcastStandard = seed != nil && standard == "ATSC 1.0" ? seed?.broadcastStandard : standard
        channel.countryID = country
        channel.catalogCity = city
        if let actualCall, !actualCall.isEmpty { channel.callSign = actualCall }
        let virtual = field("virtual", in: text) ?? field("virtual_channel", in: text) ?? field("terr_chan_1", in: text) ?? ""
        if let number = matches("(?i)^(?:channel\\s*)?([0-9]{1,3}(?:\\.[0-9]+)?)\\b", in: plain(virtual)).first {
            channel.number = standard == "ATSC 1.0" && !number.contains(".") ? number + ".1" : number
        }
        if standard == "ATSC 1.0", (countryIsATSC || seed != nil), let raw = matches("^([0-9]{1,2})\\b", in: digital).first,
           let rf = Int(raw), let hz = frequency(rf: rf) { channel.frequency = hz }
        else if seed == nil { channel.frequency = 0 }
        // Explicit MHz values can be cataloged for other standards, but canTune
        // still rejects them for this ATSC-only receiver.
        if channel.frequency == 0, let mhz = matches("(?i)([0-9]{2,3}(?:\\.[0-9]+)?)\\s*MHz", in: signal).first,
           let number = Double(mhz), number >= 54, number <= 858 { channel.frequency = UInt32((number * 1_000_000).rounded()) }
        if let rawName = field("name", in: text), !rawName.contains("<br"), !rawName.contains("{{"), !plain(rawName).isEmpty { channel.name = plain(rawName) }
        if let language = field("language", in: text).map(plain), !language.isEmpty { channel.language = language }
        var components = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
        components.queryItems = [URLQueryItem(name: "title", value: title)]
        channel.sourceURL = components.url!.absoluteString
        return channel
    }
    static func logoFile(in text: String) -> String? {
        guard let raw = field("logo", in: text) ?? field("image", in: text) else { return nil }
        if field("logo", in: text) == nil && !raw.localizedCaseInsensitiveContains("logo") { return nil }
        if let file = matches("(?i)(?:File|Image):([^|\\]]+)", in: raw).first { return file.trimmingCharacters(in: .whitespaces) }
        guard !raw.contains("{{"), !raw.contains("[[") else { return nil }
        let file = raw.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return file.range(of: "(?i)\\.(?:svg|png|jpe?g|webp)$", options: .regularExpression) != nil ? file : nil
    }

    static func station(_ call: String, city: String, seed: Channel? = nil, country: String? = "Q16") async -> Channel? {
        guard let text = try? await article(call) else { return seed }
        guard var channel = stationMetadata(text, title: call, city: city, country: country, seed: seed) else { return nil }
        if let file = logoFile(in: text) { channel.logoURL = await logoURL(file: file) }
        return channel
    }
    static func lookup(city input: String) async throws -> Result {
        let requested = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty, requested.count <= 160 else { throw Failure.ambiguousCity }
        let montreal = ["montreal", "montreal, canada", "montreal, quebec"].contains(normalized(requested))
        let seeds = montreal ? Channel.montreal : []
        do {
            let place = montreal ? Place(title: "Montreal", country: "Q16") : try await resolve(requested)
            let displayCity = montreal ? "Montréal" : place.title
            var candidates: [String] = []
            if montreal { candidates = seeds.compactMap(\.callSign) }
            else {
                // Search geography-specific pages and the city's own media section.
                // Do not fall back to country-wide stations as if they were local.
                for title in ["Media in " + place.title, "Television in " + place.title, "List of television stations in " + place.title, place.title] {
                    try Task.checkCancellation()
                    guard let text = try? await article(title) else { continue }
                    let section = televisionSection(text)
                    if let section { candidates += linkedArticles(section) }
                    else if title.hasPrefix("List of television stations") || title.hasPrefix("Media in ") { candidates += linkedArticles(text) }
                }
                var seen: Set<String> = []
                candidates = Array(candidates.filter { seen.insert($0).inserted }.prefix(60))
            }
            guard !candidates.isEmpty else { throw Failure.unavailable }
            var found: [Channel] = []
            for start in stride(from: 0, to: candidates.count, by: 3) {
                try Task.checkCancellation()
                let batch = Array(candidates[start..<min(start + 3, candidates.count)])
                let channels = await withTaskGroup(of: Channel?.self, returning: [Channel].self) { group in
                    for call in batch {
                        let seed = seeds.first { $0.callSign == call }
                        group.addTask { await station(call, city: displayCity, seed: seed, country: place.country) }
                    }
                    var result: [Channel] = []
                    for await value in group { if let value { result.append(value) } }
                    return result
                }
                found += channels
            }
            try Task.checkCancellation()
            guard !found.isEmpty else { throw Failure.unavailable }
            return Result(city: displayCity, channels: found.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }, offline: false)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            if montreal { return Result(city: "Montréal", channels: seeds, offline: true) }
            throw error
        }
    }
}
