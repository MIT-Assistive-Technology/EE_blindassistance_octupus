import SwiftUI

struct PlannedPathView: View {
    @Binding var planned: PlannedPath
    var lines: [PathLine]
    var facingDegrees: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var compared: [String: PathScore] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section("Start") {
                    HStack {
                        Button("Set direction") { if let facingDegrees { planned.facingDegrees = facingDegrees } }
                            .disabled(facingDegrees == nil)
                        Spacer()
                        TextField("Degrees", value: $planned.facingDegrees, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("°").foregroundStyle(.secondary)
                    }
                }
                Section("Legs") {
                    ForEach($planned.legs) { $leg in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Meters", value: $leg.meters, format: .number)
                                    .keyboardType(.decimalPad)
                                Text("m").foregroundStyle(.secondary)
                            }
                            HStack {
                                TextField("Turn", value: $leg.turnDegrees, format: .number)
                                    .keyboardType(.numbersAndPunctuation)
                                Text("°").foregroundStyle(.secondary)
                                Button("Straight") { leg.turnDegrees = 0 }
                                Button("Left") { leg.turnDegrees = 90 }
                                Button("Right") { leg.turnDegrees = -90 }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                        .padding(.vertical, 10)
                    }
                    .onDelete { planned.legs.remove(atOffsets: $0) }
                    Button("Add leg") { planned.legs.append(PlannedLeg(meters: 10, turnDegrees: 0)) }
                }
                Section("Presets") {
                    Button("Straight 20 m") { planned = .straight() }
                    Button("Out and back 20 m") { planned = .outAndBack() }
                    Button("Square 20 m") { planned = .square() }
                }
                Section {
                    Button("Compared") { compare() }
                        .disabled(lines.isEmpty || planned.legs.isEmpty)
                    ForEach(lines) { line in
                        if let score = compared[line.id] {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(line.name).font(.headline)
                                Text(String(format: "End %.1f m", score.endError))
                                Text(String(format: "Miss %.1f m", score.meanMiss))
                                if abs(score.fittedYawDegrees) >= 1 {
                                    Text(String(format: "Turn %.0f°", score.fittedYawDegrees))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .navigationTitle("Planned path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: planned) { compared = [:] }
            .onChange(of: lines.map(\.id)) { compared = [:] }
        }
    }

    private func compare() {
        guard !planned.legs.isEmpty else { compared = [:]; return }
        let reference = planned.line()
        var next: [String: PathScore] = [:]
        for line in lines { next[line.id] = PathScore.measure(line, planned: reference) }
        compared = next
    }
}
