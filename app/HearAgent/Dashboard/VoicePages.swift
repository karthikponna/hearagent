import AVFoundation
import SwiftUI

struct VoicePage: View {
    @Bindable var model: AppModel
    @State private var preview = VoicePreview()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            voiceCard
                .frame(maxWidth: .infinity)
            historyCard
                .frame(maxWidth: .infinity)
        }
        .onDisappear { preview.stop() }
    }

    // MARK: Voice

    private var voiceCard: some View {
        @Bindable var prefs = model.preferences
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Voice").font(.system(size: 15, weight: .semibold))
                if model.muted { Tag(text: "Muted", color: Theme.amber) }
            }
            HStack(alignment: .center, spacing: 14) {
                VoiceAvatar(speaking: preview.isPlaying || model.isPlaying).frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 6) {
                    voicePicker(prefs)
                    Text(prefs.voice.blurb).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 10)
                Button {
                    if preview.isPlaying { preview.stop() } else { preview.play(prefs.voice, speed: prefs.voiceSpeed, volume: model.volume) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preview.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 10, weight: .bold))
                        Text(preview.isPlaying ? "Stop" : "Preview")
                    }
                    .frame(minWidth: 64)
                }
                .buttonStyle(SoftButtonStyle(height: 30))
            }
            .padding(.top, 16)

            sliderRow("Speaking speed", value: Self.speed(prefs.voiceSpeed)) {
                Slider(value: $prefs.voiceSpeed, in: 0.7...1.2, step: 0.05).controlSize(.small).tint(Theme.accent)
                    .onChange(of: prefs.voiceSpeed) { preview.stop() }
                Ticks(count: 11).padding(.horizontal, 6)
            }
            .padding(.top, 22)

            Divider().overlay(Theme.line).padding(.vertical, 16)

            sliderRow("Volume", value: Format.percent(model.volume * 100)) {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(Theme.faint)
                    Slider(value: $model.volume, in: 0.1...1.0).controlSize(.small).tint(Theme.accent)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
            }

            Divider().overlay(Theme.line).padding(.top, 16).padding(.bottom, 4)
            SettingToggle(title: "Mute spoken updates", detail: "Nothing is spoken and no credits are used while muted.", isOn: $model.muted)
        }
        .card()
    }

    private func voicePicker(_ prefs: Preferences) -> some View {
        Menu {
            ForEach(NarratorVoice.allCases) { voice in
                Button {
                    preview.stop()
                    prefs.voice = voice
                } label: {
                    if voice == prefs.voice {
                        Label("\(voice.name) · \(voice.trait)", systemImage: "checkmark")
                    } else {
                        Text("\(voice.name) · \(voice.trait)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(prefs.voice.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("· \(prefs.voice.trait)").font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// "1.0×", "0.85×".
    private static func speed(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        if s.hasSuffix("0") { s.removeLast() }
        return s + "×"
    }

    private func sliderRow<Control: View>(_ title: String, value: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ink2)
            }
            control()
        }
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "Recent updates", icon: "clock.arrow.circlepath") {
                Text("This run · replays are free").font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
            .padding(.bottom, 6)
            if model.history.isEmpty {
                Text("Nothing spoken yet.").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ForEach(model.history) { update in
                    SpokenRow(model: model, update: update)
                    if update.id != model.history.last?.id { Divider().overlay(Theme.hairline).padding(.leading, 37) }
                }
            }
        }
        .card()
    }
}

/// Evenly spaced dots under a stepped slider.
private struct Ticks: View {
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(Theme.faint.opacity(0.6)).frame(width: 3, height: 3)
                if i < count - 1 { Spacer(minLength: 0) }
            }
        }
    }
}

/// Speaks a sample update in a system voice close to the chosen one. Stands in until
/// previews are generated by ElevenLabs.
@MainActor
@Observable
final class VoicePreview: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isPlaying = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    static let sample = "Hey, storefront just wrapped up: passkey sign-in works and all the tests pass."

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ voice: NarratorVoice, speed: Double, volume: Double) {
        stop()
        let utterance = AVSpeechUtterance(string: Self.sample)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == voice.previewLanguage }
        utterance.voice = candidates.first { $0.gender == (voice.previewIsFemale ? .female : .male) } ?? candidates.first
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        utterance.volume = Float(volume)
        isPlaying = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isPlaying = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isPlaying = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isPlaying = false }
    }
}

/// The voice's presence: a waveform glyph that moves while it speaks.
struct VoiceAvatar: View {
    var speaking = false

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.palette.discTop, Theme.palette.discBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.palette.discGlyph)
                    .symbolEffect(.variableColor.iterative, isActive: speaking)
            }
            .overlay(Circle().strokeBorder(Theme.ink.opacity(0.06), lineWidth: 1))
            .scaleEffect(speaking ? 1.05 : 1)
            .animation(.easeInOut(duration: 0.4), value: speaking)
    }
}
