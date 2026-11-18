import SwiftUI

struct ContourReviewSettingsView: View {
    @ObservedObject var store: DesktopContourPreferencesStore
    let onBack: () -> Void

    private var showScaleNumbersBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.showScaleNumbers },
            set: { value in store.update { $0.showScaleNumbers = value } }
        )
    }

    private var edgeThresholdBinding: Binding<Double> {
        Binding(
            get: { store.preferences.edgeThreshold },
            set: { value in store.update { $0.edgeThreshold = value } }
        )
    }

    private var overlayOpacityBinding: Binding<Double> {
        Binding(
            get: { store.preferences.overlayOpacity },
            set: { value in store.update { $0.overlayOpacity = value } }
        )
    }

    private var lineWeightBinding: Binding<Int> {
        Binding(
            get: { store.preferences.lineWeight },
            set: { value in store.update { $0.lineWeight = value } }
        )
    }

    private var reduceNoiseBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.reduceNoise },
            set: { value in store.update { $0.reduceNoise = value } }
        )
    }

    var body: some View {
        SettingsDetailScaffold(
            title: "Contour Review",
            subtitle: "Defaults for new photo comparisons",
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Show scale numbers
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show scale numbers")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Text("Applies to newly opened comparisons in Pattern Studio, Photo Contours, and Numbered Scales. Visibility only; confirmed counts do not change.")
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle("Show scale numbers", isOn: showScaleNumbersBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(AdaColors.navy)
                            .accessibilityIdentifier("settings.contour.showScaleNumbers")
                    }

                    Divider().overlay(AdaColors.line)

                    // 2. Edge threshold
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Edge threshold")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Spacer()
                            Text(store.preferences.edgeThreshold, format: .number.precision(.fractionLength(2)))
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AdaColors.navy)
                                .accessibilityIdentifier("settings.contour.edgeThresholdValue")
                        }

                        Slider(
                            value: edgeThresholdBinding,
                            in: DesktopContourPreferences.edgeThresholdRange,
                            step: 0.01
                        )
                        .tint(AdaColors.navy)
                        .accessibilityLabel("Edge threshold")
                        .accessibilityValue(String(format: "%.2f", store.preferences.edgeThreshold))
                        .accessibilityIdentifier("settings.contour.edgeThresholdSlider")

                        HStack(spacing: 8) {
                            thresholdPresetButton("Fine · 0.04", value: 0.04)
                            thresholdPresetButton("Balanced · 0.08", value: 0.08)
                            thresholdPresetButton("Strong · 0.15", value: 0.15)
                            Spacer(minLength: 0)
                        }

                        Text("Photo Contours edge threshold (0.01–0.50). Pattern Studio sensitivity/smoothness and Numbered Scales proposal boundaries retain their own controls.")
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().overlay(AdaColors.line)

                    // 3. Overlay opacity
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Overlay opacity")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Spacer()
                            Text("\(Int((store.preferences.overlayOpacity * 100).rounded()))%")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AdaColors.navy)
                                .accessibilityIdentifier("settings.contour.overlayOpacityValue")
                        }

                        Slider(
                            value: overlayOpacityBinding,
                            in: DesktopContourPreferences.overlayOpacityRange,
                            step: 0.05
                        )
                        .tint(AdaColors.navy)
                        .accessibilityLabel("Overlay opacity")
                        .accessibilityValue("\(Int((store.preferences.overlayOpacity * 100).rounded())) percent")
                        .accessibilityIdentifier("settings.contour.overlayOpacitySlider")
                    }

                    Divider().overlay(AdaColors.line)

                    // 4. Line weight
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Line weight")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Text("Stroke weight for Photo Contours overlays.")
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                        Spacer(minLength: 12)
                        Picker("Line weight", selection: lineWeightBinding) {
                            Text("Thin").tag(1)
                            Text("Med").tag(2)
                            Text("Bold").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("settings.contour.lineWeightPicker")
                    }

                    Divider().overlay(AdaColors.line)

                    // 5. Reduce noise
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reduce noise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Text("Smooth background water and edge noise in Photo Contours.")
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                        Spacer(minLength: 12)
                        Toggle("Reduce noise", isOn: reduceNoiseBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(AdaColors.navy)
                            .accessibilityIdentifier("settings.contour.reduceNoise")
                    }

                    Divider().overlay(AdaColors.line)

                    HStack {
                        Button("Reset Defaults") {
                            store.resetDefaults()
                        }
                        .buttonStyle(AdaPillButtonStyle(secondary: true))
                        .disabled(store.isFactoryDefault)
                        .accessibilityIdentifier("settings.contour.resetDefaultsButton")
                        Spacer(minLength: 0)
                    }
                }
                .padding(24)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                )

                Text("These values initialize newly opened photo comparisons in Photo ID and Not Sure. Open comparisons keep their current session settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func thresholdPresetButton(_ title: String, value: Double) -> some View {
        let selected = abs(store.preferences.edgeThreshold - value) < 0.005
        return Button(title) {
            store.update { $0.edgeThreshold = value }
        }
        .font(.system(size: 11, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? .white : AdaColors.ink)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(selected ? AdaColors.navy : AdaColors.canvas, in: Capsule())
        .buttonStyle(.plain)
    }
}
