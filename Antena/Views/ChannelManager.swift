import SwiftUI

struct ChannelManager: View {
    @ObservedObject var session: TunerSession
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var number = ""
    @State private var mhz = ""
    @State private var standard = "ATSC 1.0"
    @State private var editingID: UUID?
    @State private var validation: String?
    @State private var city = ""
    @State private var importing = false
    @State private var catalogMessage: String?
    @State private var importID = UUID()
    @State private var catalogTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("Your channels")).font(.system(size: 26, weight: .bold))
                    Text(L10n.text("Antenna frequencies · ATSC 1.0")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("Over-the-air TV in your city")).font(.headline)
                HStack {
                    TextField(L10n.text("City, country or region"), text: $city).textFieldStyle(.roundedBorder)
                        .onSubmit { importCity() }
                    Menu { ForEach(CityCatalog.suggestedCities, id: \.self) { suggestion in
                        Button(suggestion) { city = suggestion }
                    } } label: { Image(systemName: "location") }.frame(width: 38)
                    if importing {
                        ProgressView().controlSize(.small)
                        Button(L10n.text("Cancel")) { importID = UUID(); catalogTask?.cancel(); importing = false; catalogMessage = L10n.text("Import canceled.") }
                    } else {
                        Button(L10n.text("Find and import")) { importCity() }
                            .disabled(city.trimmingCharacters(in: .whitespaces).isEmpty || session.scanning || session.isRecording)
                    }
                }.disabled(session.scanning || session.isRecording)
                Text(catalogMessage ?? L10n.text("Search cities worldwide. Available terrestrial listings and logos are imported; missing frequencies and incompatible standards remain catalog-only."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link(L10n.text("Catalog and logos: Wikipedia / Wikimedia"), destination: CityCatalog.catalogURL(city: library.city))
                    .font(.caption)
            }
            List {
                ForEach(library.channels) { channel in
                    HStack(spacing: 14) {
                        ChannelLogo(channel: channel).frame(width: 65, height: 35)
                        Text(channel.number).font(.system(size: 16, weight: .bold)).frame(width: 65, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name)
                            Text([channel.standardLabel, channel.receptionSummary].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { session.choose(channel); dismiss() } label: { Image(systemName: "play.fill") }.help(L10n.text("Watch channel")).disabled(!channel.canTune)
                        Button {
                            editingID = channel.id; name = channel.name; number = channel.number
                            mhz = channel.frequency > 0 ? String(format: "%.3f", Double(channel.frequency)/1_000_000) : ""
                            standard = channel.broadcastStandard ?? "ATSC 1.0"
                        } label: { Image(systemName: "pencil") }.help(L10n.text("Edit"))
                        Button {
                            library.channels.removeAll { $0.id == channel.id }
                        } label: { Image(systemName: "trash") }.help(L10n.text("Remove from list"))
                    }.padding(.vertical, 8)
                }
            }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 10)).disabled(session.scanning)
            HStack(spacing: 12) {
                TextField(L10n.text("Number · 6.1"), text: $number).frame(width: 100)
                TextField(L10n.text("Channel name"), text: $name)
                TextField("MHz · 515", text: $mhz).frame(width: 115)
                Button(editingID == nil ? L10n.text("Add") : L10n.text("Save")) { save() }.disabled(session.scanning)
                if editingID != nil { Button(L10n.text("Cancel")) { reset() } }
            }.textFieldStyle(.roundedBorder)
            Picker(L10n.text("Broadcast standard"), selection: $standard) {
                ForEach(["ATSC 1.0", "ATSC 3.0", "DVB-T", "DVB-T2", "ISDB-T", "DTMB", "Unknown"], id: \.self) { Text($0 == "Unknown" ? L10n.text("Unknown") : $0).tag($0) }
            }.frame(maxWidth: 300)
            Text(L10n.text("This receiver supports ATSC 1.0 only. International listings do not add support for other broadcast standards."))
                .font(.caption).foregroundStyle(.secondary)
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.scanning ? session.scanProgress : L10n.text("Scan over-the-air channels")).fontWeight(.semibold)
                    Text(L10n.text("Scanning covers RF 2–36 and temporarily interrupts live TV."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.scanning {
                    ProgressView().controlSize(.small)
                    Button(L10n.text("Cancel scan")) { session.cancelScan() }
                } else {
                    Button(L10n.text("Scan channels")) { session.scan() }.disabled(session.isRecording)
                }
            }
        }.padding(28).frame(width: 760).preferredColorScheme(.dark)
        .onAppear { city = library.city }
        .onDisappear { catalogTask?.cancel() }
    }
    private func importCity() {
        guard !session.isPreview else { return }
        guard !importing, !session.scanning, !session.isRecording else { return }
        importing = true
        catalogMessage = L10n.text("Looking up stations and logos…")
        let requestedCity = city
        let requestID = UUID()
        importID = requestID
        catalogTask = Task { @MainActor in
            do {
                let result = try await CityCatalog.lookup(city: requestedCity)
                try Task.checkCancellation()
                guard importID == requestID else { return }
                library.importChannels(result.channels, city: result.city)
                city = result.city
                catalogMessage = L10n.format("%d stations imported; %d have a compatible standard and confirmed frequency. Reception is unverified.", result.channels.count, result.compatibleCount) + (result.offline ? " " + L10n.text("Bundled Montréal catalog, updated October 22, 2026; offline.") : "")
            } catch is CancellationError {
                guard importID == requestID else { return }
                catalogMessage = L10n.text("Import canceled.")
            } catch {
                guard importID == requestID else { return }
                catalogMessage = error.localizedDescription
            }
            importing = false
        }
    }
    private func save() {
        guard let frequency = Double(mhz.replacingOccurrences(of: ",", with: ".")), frequency.isFinite,
              frequency >= 54, frequency <= 858, !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !number.trimmingCharacters(in: .whitespaces).isEmpty else {
            validation = L10n.text("Enter a name, number and frequency between 54 and 858 MHz."); return
        }
        var channel = library.channels.first { $0.id == editingID } ?? Channel(number: number, name: name, language: "ATSC", frequency: 0, tint: library.channels.count % 4)
        let hz = UInt32((frequency*1_000_000).rounded())
        if channel.frequency != hz { channel.verified = false }
        channel.number = number; channel.name = name; channel.frequency = hz
        if channel.broadcastStandard != standard { channel.verified = false }
        channel.broadcastStandard = standard
        if let i = library.channels.firstIndex(where: { $0.id == editingID }) { library.channels[i] = channel }
        else { library.channels.append(channel) }
        reset()
    }
    private func reset() { editingID = nil; name = ""; number = ""; mhz = ""; standard = "ATSC 1.0"; validation = nil }
}

#if DEBUG
#Preview("Channels and city") {
    AntenaPreview { session, library in
        ChannelManager(session: session, library: library)
    }
}
#endif
