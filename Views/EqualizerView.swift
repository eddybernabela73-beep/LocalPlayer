import SwiftUI

struct EqualizerView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    // EQ presets [Sub, Bass, Mid, Hi-Mid, Treble]
    private let presets: [(String, [Float])] = [
        ("Plano",      [0,  0,  0,  0,  0]),
        ("Bass Boost", [6,  5,  0, -1, -2]),
        ("Vocal",      [-2, 0,  4,  3,  1]),
        ("Rock",       [3,  2,  0,  2,  3]),
        ("Hip-Hop",    [5,  4,  1,  1,  2]),
        ("Pop",        [1,  2,  3,  2,  1]),
        ("Jazz",       [2,  1,  0,  2,  3]),
        ("Clásica",    [0, -1,  0,  2,  3]),
    ]

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            VStack(spacing: 0) {
                // EQ sliders
                eqSliders
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                Divider().padding(.vertical, 16)

                // Presets
                presetsGrid
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Ecualizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Resetear") { vm.resetEQ() }
                        .foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - EQ Sliders

    private var eqSliders: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                eqBand(index: i)
            }
        }
        .frame(height: 220)
    }

    private func eqBand(index: Int) -> some View {
        @Bindable var vm = vm
        let label = AudioPlayerService.eqBandLabels[index]
        let gain  = vm.eqGains[index]

        return VStack(spacing: 8) {
            Text(gainLabel(gain))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(gainColor(gain))
                .frame(height: 16)

            // Vertical slider
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Track
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(width: 6)
                        .frame(maxWidth: .infinity)

                    // Fill
                    Capsule()
                        .fill(gainColor(gain))
                        .frame(width: 6, height: max(4, thumbOffset(gain: gain, height: geo.size.height)))
                        .frame(maxWidth: .infinity, alignment: .bottom)

                    // Center line
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .offset(y: -geo.size.height / 2)

                    // Thumb
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .frame(width: 22, height: 22)
                        .frame(maxWidth: .infinity)
                        .offset(y: -thumbOffset(gain: gain, height: geo.size.height))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let normalized = 1 - val.location.y / geo.size.height
                            let clamped = max(0, min(1, normalized))
                            let newGain = Float(clamped * 24 - 12)
                            vm.eqGains[index] = max(-12, min(12, newGain))
                        }
                )
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func thumbOffset(gain: Float, height: CGFloat) -> CGFloat {
        let normalized = CGFloat((gain + 12) / 24)
        return normalized * height
    }

    private func gainLabel(_ gain: Float) -> String {
        let g = Int(gain.rounded())
        return g == 0 ? "0" : g > 0 ? "+\(g)" : "\(g)"
    }

    private func gainColor(_ gain: Float) -> Color {
        if gain > 6  { return .orange }
        if gain > 0  { return .blue }
        if gain < -6 { return .red }
        if gain < 0  { return .purple }
        return .secondary
    }

    // MARK: - Presets

    private var presetsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                ForEach(presets, id: \.0) { name, gains in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            for (i, g) in gains.enumerated() {
                                if i < 5 { vm.eqGains[i] = g }
                            }
                        }
                    } label: {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isActive(gains) ? Color.blue : Color(.systemGray5))
                            .foregroundStyle(isActive(gains) ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func isActive(_ gains: [Float]) -> Bool {
        zip(vm.eqGains, gains).allSatisfy { abs($0 - $1) < 0.5 }
    }
}
