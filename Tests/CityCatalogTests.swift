import Foundation

@main struct CityCatalogTests {
    static func main() async throws {
        precondition(CityCatalog.frequency(rf: 2) == 57_000_000)
        precondition(CityCatalog.frequency(rf: 6) == 85_000_000)
        precondition(CityCatalog.frequency(rf: 11) == 201_000_000)
        precondition(CityCatalog.frequency(rf: 19) == 503_000_000)
        precondition(CityCatalog.frequency(rf: 36) == 605_000_000)
        precondition(CityCatalog.frequency(rf: 47) == nil) // Virtual 47 isn't RF 47.
        precondition(CityCatalog.normalized("  Montréal ") == "montreal")
        let old = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"number\":\"6.1\",\"name\":\"CBC\",\"language\":\"English\",\"frequency\":515000000,\"favorite\":true,\"verified\":true,\"tint\":0}".utf8)
        let channel = try JSONDecoder().decode(Channel.self, from: old)
        precondition(channel.logoURL == nil && channel.favorite)
        let ici = Channel.montreal.first { $0.number == "47.1" }!
        precondition(ici.frequency == 575_000_000 && ici.rf == 31)
        precondition(Channel.montreal.count == 10)
        let text = "| virtual = 10\n| digital = 11 ([[VHF]])\n| logo = TVA logo 2020.svg\n"
        precondition(CityCatalog.field("digital", in: text) == "11 ([[VHF]])")
        let us = "{{Infobox television station\n| callsign = KTEST\n| digital = 36 (UHF)\n| virtual = 4.1\n| logo = Test.svg\n}}"
        let american = CityCatalog.stationMetadata(us, title: "KTEST", city: "Example, USA", country: "Q30")!
        precondition(american.canTune && american.frequency == 605_000_000 && american.broadcastStandard == "ATSC 1.0")
        let european = "{{Infobox television channel\n| name = Example TV\n| terr_serv_1 = DVB-T2\n| terr_chan_1 = Channel 7, 602 MHz\n}}"
        let foreign = CityCatalog.stationMetadata(european, title: "Example TV", city: "Example, Europe", country: "Q145")!
        precondition(!foreign.canTune && foreign.frequency == 602_000_000 && foreign.broadcastStandard == "DVB-T2")
        let unknown = CityCatalog.stationMetadata(european.replacingOccurrences(of: ", 602 MHz", with: ""), title: "Example TV", city: "Example", country: "Q145")!
        precondition(unknown.frequency == 0 && !unknown.canTune, "Virtual channel must not become RF")
        let nextGen = CityCatalog.stationMetadata(us + "\n| atsc3 = yes", title: "KTEST", city: "Example", country: "Q30")!
        precondition(!nextGen.canTune && nextGen.broadcastStandard == "ATSC 3.0")
        precondition(CityCatalog.stationMetadata("{{Infobox newspaper\n| digital = 20", title: "Daily News", city: "Example", country: "Q30") == nil)
        let section = CityCatalog.televisionSection("== Media ==\n[[Station A]] and [[Station B|B]]\n== Sports ==\n[[Unrelated]]")!
        precondition(CityCatalog.linkedArticles(section) == ["Station A", "Station B"])
        precondition(CityCatalog.catalogURL(city: "Québec, Canada").absoluteString.contains("search="))
        precondition(CityCatalog.logoFile(in: "| logo = [[File:Example logo.svg|120px]]") == "Example logo.svg")
        precondition(CityCatalog.logoFile(in: "| image = A building.jpg") == nil)
        if CommandLine.arguments.contains("--network") {
            let result = try await CityCatalog.lookup(city: "Montréal")
            precondition(!result.offline && result.channels.count == 10)
            precondition(result.channels.first { $0.number == "10.1" }?.frequency == 201_000_000)
            print("NETWORK PASS: \(result.city), \(result.channels.count) channels, \(result.channels.filter { $0.logoURL != nil }.count) online logos")
        }
        if let index = CommandLine.arguments.firstIndex(of: "--city"), index+1 < CommandLine.arguments.count {
            let result = try await CityCatalog.lookup(city: CommandLine.arguments[index+1])
            print("CITY: \(result.city) \(result.channels.count)")
            for c in result.channels { print("\(c.number) \(c.name) \(c.frequency) logo=\(c.logoURL != nil)") }
        }
        print("PASS: RF/virtual distinction, legacy data, city normalization, Montreal catalog")
    }
}
