import SwiftUI

enum MonoAIActivity { case idle, listening, thinking, speaking, done }

struct MonoAIOrb: View {
    let activity: MonoAIActivity
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let energy = activity == .listening ? level : activity == .thinking || activity == .speaking ? 0.5 : 0.12
            Image("MonoAIEmblem")
                .resizable().scaledToFit()
                .scaleEffect(reduceMotion ? 1 : 1 + sin(time * 1.6) * 0.025 + energy * 0.035)
                .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * 0.65) * (activity == .thinking ? 5 : 2)))
                .offset(y: reduceMotion ? 0 : sin(time * 1.3) * 3)
                .overlay(alignment: .bottomTrailing) {
                    if activity == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundStyle(Theme.Colors.accent)
                            .background(Theme.Colors.background, in: Circle()).padding(8)
                    }
                }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
