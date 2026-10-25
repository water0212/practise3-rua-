import SwiftUI
import Combine

@MainActor
final class RuaGame: ObservableObject {
    private struct Save: Codable {
        var hearts: Double = 0
        var totalPets: Double = 0
        var touchLevel: Int = 0
        var helpers: Int = 0
    }

    private static let saveKey = "rua.save.v1"
    @Published private var save: Save

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.saveKey),
           let stored = try? JSONDecoder().decode(Save.self, from: data) {
            save = stored
        } else {
            save = Save()
        }
    }

    var hearts: Double { save.hearts }
    var totalPets: Double { save.totalPets }
    var power: Double { Double(save.touchLevel + 1) }
    var helpers: Int { save.helpers }
    var touchCost: Double { 10 * pow(1.6, Double(save.touchLevel)) }
    var helperCost: Double { 30 * pow(1.7, Double(save.helpers)) }

    func pet() {
        save.hearts += power
        save.totalPets += 1
        persist()
    }

    func tick() {
        guard save.helpers > 0 else { return }
        save.hearts += Double(save.helpers)
        save.totalPets += Double(save.helpers)
        persist()
    }

    func upgradeTouch() {
        guard save.touchLevel < 100, save.hearts >= touchCost else { return }
        save.hearts -= touchCost
        save.touchLevel += 1
        persist()
    }

    func buyHelper() {
        guard save.helpers < 100, save.hearts >= helperCost else { return }
        save.hearts -= helperCost
        save.helpers += 1
        persist()
    }

    var touchMaxed: Bool { save.touchLevel >= 100 }
    var helpersMaxed: Bool { save.helpers >= 100 }

    func persist() {
        guard let data = try? JSONEncoder().encode(save) else { return }
        UserDefaults.standard.set(data, forKey: Self.saveKey)
    }
}

@MainActor
struct ContentView: View {
    @StateObject private var game = RuaGame()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPatting = false
    @State private var showHeart = false
    @State private var floatingValue = "+1"
    @State private var animationTask: Task<Void, Never>?
    @State private var hapticTrigger = 0
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let ink = Color(red: 0.34, green: 0.25, blue: 0.31)
    private let pink = Color(red: 0.89, green: 0.43, blue: 0.57)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("摸摸小日子").font(.largeTitle.bold())
                        Text("每一次摸摸，都存一點喜歡")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    HStack {
                        Label(number(game.hearts), systemImage: "heart.fill")
                            .font(.title.bold()).foregroundStyle(pink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("每次 +\(number(game.power))")
                            Text("每秒 +\(game.helpers)")
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                    .padding(20)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))

                    petButton(size: min(geometry.size.width - 40, 360))

                    Text("點一下，rua 一下 ♡")
                        .font(.headline).foregroundStyle(pink)
                    Text("累計摸摸 \(number(game.totalPets)) 次")
                        .font(.caption).foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        upgradeRow(
                            title: "溫柔摸摸", subtitle: "每次摸摸多 1 顆愛心",
                            symbol: "hand.draw.fill", cost: game.touchCost,
                            enabled: game.hearts >= game.touchCost && !game.touchMaxed,
                            maxed: game.touchMaxed, action: game.upgradeTouch
                        )
                        upgradeRow(
                            title: "摸摸小幫手", subtitle: "每秒自動摸摸 +1 · 已有 \(game.helpers) 位",
                            symbol: "sparkles", cost: game.helperCost,
                            enabled: game.hearts >= game.helperCost && !game.helpersMaxed,
                            maxed: game.helpersMaxed, action: game.buyHelper
                        )
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 1, green: 0.95, blue: 0.92).ignoresSafeArea())
            .foregroundStyle(ink)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .onReceive(clock) { _ in
            guard scenePhase == .active else { return }
            game.tick()
            if game.helpers > 0 && animationTask == nil {
                animatePet(value: "+\(game.helpers)")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                game.persist()
                stopAnimation()
            }
        }
        .onDisappear { stopAnimation() }
    }

    private func petButton(size: CGFloat) -> some View {
        Button {
            let value = game.power
            game.pet()
            hapticTrigger += 1
            animatePet(value: "+\(number(value))")
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.65)).padding(10)
                Image("Character")
                    .resizable().scaledToFit()
                    .frame(width: size * 0.88, height: size * 0.88)
                    .scaleEffect(x: isPatting ? 1.06 : 1,
                                 y: isPatting ? 0.91 : 1, anchor: .bottom)
                    .offset(y: size * 0.07)

                // The two PNGs have different transparent margins.
                // Each pose gets its own placement so the wrist stays aligned.
                Image(isPatting ? "HandOpen" : "HandRest")
                    .resizable().scaledToFit()
                    .frame(width: size * 0.58, height: size * 0.58)
                    .offset(x: -size * 0.04,
                            y: isPatting ? -size * 0.20 : -size * 0.23)

                Text("♥ \(floatingValue)")
                    .font(.title2.bold()).foregroundStyle(pink)
                    .padding(10).background(.white.opacity(0.9), in: Capsule())
                    .offset(x: size * 0.22, y: showHeart ? -size * 0.34 : -size * 0.15)
                    .opacity(showHeart ? 1 : 0)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("摸摸角色")
        .accessibilityHint("獲得 \(number(game.power)) 顆愛心")
    }

    private func upgradeRow(title: String, subtitle: String, symbol: String,
                            cost: Double, enabled: Bool, maxed: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2)
                    .frame(width: 38).foregroundStyle(pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(maxed ? "已滿級" : "♥ \(number(cost))")
                    .font(.subheadline.bold()).foregroundStyle(pink)
            }
            .padding(16)
            .background(.white.opacity(enabled ? 0.95 : 0.5),
                        in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func animatePet(value: String) {
        animationTask?.cancel()
        isPatting = false
        showHeart = false
        floatingValue = value
        animationTask = Task { @MainActor in
            // Give consecutive taps a fresh animation cycle.
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return }
            withAnimation(.easeOut(duration: 0.10)) { isPatting = true }
            withAnimation(.easeOut(duration: 0.24)) { showHeart = true }
            do { try await Task.sleep(for: .milliseconds(130)) }
            catch { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                isPatting = false
            }
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            withAnimation(.easeOut(duration: 0.15)) { showHeart = false }
            animationTask = nil
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isPatting = false
        showHeart = false
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

#Preview { ContentView() }
