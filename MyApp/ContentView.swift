import SwiftUI
import Combine

@MainActor
final class RuaGame: ObservableObject {

    @Published private var heartsValue: Double = 0
    @Published private var totalRuasValue: Double = 0
    @Published private var touchLevel: Int = 0
    @Published private var helperCount: Int = 0
    
    var hearts: Double { heartsValue }
    var totalRuas: Double { totalRuasValue }
    var power: Double { Double(touchLevel + 1) }
    var helpers: Int { helperCount }

    var touchCost: Double {
        10 * pow(1.6, Double(touchLevel))
    }

    var helperCost: Double {
        30 * pow(1.7, Double(helperCount))
    }

    func rua() {
        heartsValue += power
        totalRuasValue += 1
    }

    func tick() {
        guard helperCount > 0 else { return }

        heartsValue += Double(helperCount)
        totalRuasValue += Double(helperCount)
    }

    func upgradeTouch() {
        guard touchLevel < 100,
              heartsValue >= touchCost else { return }

        heartsValue -= touchCost
        touchLevel += 1
    }

    func buyHelper() {
        guard helperCount < 100,
              heartsValue >= helperCost else { return }

        heartsValue -= helperCost
        helperCount += 1
    }

    var touchMaxed: Bool { touchLevel >= 100 }
    var helpersMaxed: Bool { helperCount >= 100 }
}
struct FloatingHeart: View {
    let value: String

    @State private var floating = false
    
    var body: some View {
        Text("♥ \(value)")
            .font(.title2.bold())
            .foregroundStyle(.pink)
            .padding(8)
            .background(.white.opacity(0.85), in: Capsule())
            .offset(y: floating ? -80 : 0)
            .opacity(floating ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    floating = true
                }
            }
    }
}
struct HeartEffect: Identifiable {
    let id = UUID()
    let value: String
}
@MainActor
struct ContentView: View {
    @StateObject private var game = RuaGame()
    @Environment(\.scenePhase)
    private var scenePhase
    @State private var isPatting = false
    @State private var hapticTrigger = 0
    @State private var floatingHearts: [HeartEffect] = []
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let ink = Color(red: 0.34, green: 0.25, blue: 0.31)
    private let pink = Color(red: 0.89, green: 0.43, blue: 0.57)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("rua").font(.largeTitle.bold())
                        Text("牠很可愛，請rua牠")
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

                    ruaButton(size: min(geometry.size.width - 40, 360))

                    Text("rua一下")
                        .font(.headline).foregroundStyle(pink)
                    Text("你一共rua了 \(number(game.totalRuas)) 次")
                        .font(.caption).foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        upgradeRow(
                            title: "用力rua", subtitle: "每次rua多1 顆愛心",
                            symbol: "hand.draw.fill", cost: game.touchCost,
                            enabled: game.hearts >= game.touchCost && !game.touchMaxed,
                            maxed: game.touchMaxed, action: game.upgradeTouch
                        )
                        upgradeRow(
                            title: "自動rua", subtitle: "每秒rua+1 · 已有 \(game.helpers) 次",
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

            if game.helpers > 0 {
                game.tick()
                spawnHeart(value: "+\(game.helpers)")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                isPatting = false
            }
        }
        .onDisappear { isPatting = false }
    }

    private func ruaButton(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.65))
                .padding(10)

            Image("Character")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.88, height: size * 0.88)
                .scaleEffect(
                    x: isPatting ? 1.06 : 1,
                    y: isPatting ? 0.87 : 1,
                    anchor: .bottom
                )
                .offset(y: size * 0.07)

            Image(isPatting ? "HandOpen" : "HandRest")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(
                    x: -size * 0.04,
                    y: isPatting ? -size * 0.20 : -size * 0.23
                )

            ForEach(floatingHearts) { heart in
                FloatingHeart(value: heart.value)
                    .id(heart.id)
                    .offset(x: size * -0.4, y: -size * 0.75)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPatting else { return }

                    let value = game.power
                    game.rua()
                    hapticTrigger += 1

                    spawnHeart(value: "+\(number(value))")

                    withAnimation(.easeOut(duration: 0.05)) {
                        isPatting = true
                    }
                }
                .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.05)) {
                                isPatting = false
                            }
                }
        )
        .accessibilityLabel("摸摸角色")
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

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
    
    private func spawnHeart(value: String) {
        let heart = HeartEffect(value: value)

        floatingHearts.append(heart)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))

            floatingHearts.removeAll {
                $0.id == heart.id
            }
        }
    }
}

#Preview { ContentView() }
