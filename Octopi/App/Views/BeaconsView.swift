import OctopiCore
import SwiftUI

struct BeaconsView: View {
    @Environment(AppModel.self) private var model
    @State private var pairing: BluetoothService.NearbyBeacon?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeading(text: "My beacons")
                if model.beacons.isEmpty {
                    Text("No beacons paired yet.").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.beacons) { beacon in
                    BeaconCard(beacon: beacon)
                }
                Text("Nearby, not paired").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                if model.nearbyUnpairedBeacons.isEmpty {
                    Text(model.isSimulating || model.bluetooth.isPoweredOn ? "Listening for beacons. Hold a beacon close to the phone." : "Bluetooth is \(model.bluetooth.stateDescription.lowercased()).")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.nearbyUnpairedBeacons) { nearby in
                    Button {
                        pairing = nearby
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Beacon \(nearby.advertisement.identifier.rawValue.suffix(4))").font(.title3.weight(.semibold))
                            Text("Signal \(Int(nearby.rssi)) dBm\(nearby.advertisement.batteryPercent.map { ", battery \($0) percent" } ?? "")").font(.subheadline).foregroundStyle(Color.detailText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.secondary)
                    .accessibilityLabel("Pair beacon ending \(nearby.advertisement.identifier.rawValue.suffix(4)), signal \(Int(nearby.rssi))")
                    .accessibilityHint("Opens a name picker, then pairs it.")
                    .accessibilityIdentifier("beacon.pair.\(nearby.advertisement.serial)")
                }
            }
            .padding(20)
        }
        .navigationTitle("My beacons")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pairing) { nearby in
            NavigationStack {
                NamePicker(title: "Name this beacon", quickNames: ["Keys", "Bag", "Wallet", "Car", "Cane", "Camp"], onPick: { name in
                    model.pair(nearby, name: name ?? "Beacon \(nearby.advertisement.identifier.rawValue.suffix(4))")
                    pairing = nil
                }, onCancel: { pairing = nil })
            }
        }
    }
}

struct BeaconCard: View {
    @Environment(AppModel.self) private var model
    var beacon: PairedBeacon
    @State private var confirmingUnpair = false

    private var status: String {
        var parts: [String] = []
        if let seen = beacon.lastSeen {
            let age = Date().timeIntervalSince(seen)
            parts.append(age < 15 ? "in range" : "last heard \(AppModel.age(age)) ago")
        } else { parts.append("not heard yet") }
        if let battery = beacon.batteryPercent { parts.append("battery \(battery) percent") }
        if beacon.isHandedOff { parts.append("handed off") }
        if model.settings.simpleModeBeaconSerial == beacon.serial { parts.append("simple mode target") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(beacon.name).font(.title2.weight(.semibold))
            Text(status).font(.subheadline).foregroundStyle(Color.detailText)
            Toggle("Handed off to someone else", isOn: Binding(get: { beacon.isHandedOff }, set: { model.setHandedOff(beacon, $0) }))
                .font(.body)
                .accessibilityHint("When on, Octopi will not warn you that this beacon was left behind.")
            Button(model.settings.simpleModeBeaconSerial == beacon.serial ? "Band locks onto this beacon" : "Use for band Simple mode") {
                model.setSimpleModeBeacon(model.settings.simpleModeBeaconSerial == beacon.serial ? nil : beacon)
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Simple mode lets the band guide you to this beacon without the phone.")
            Button("Unpair \(beacon.name)") { confirmingUnpair = true }.buttonStyle(.destructive)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Unpair \(beacon.name)?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { model.unpair(beacon) }
            Button("Keep", role: .cancel) {}
        }
    }
}
