import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Пространство"
        case .activity: return "Аналитика"
        case .settings: return "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .activity: return "chart.bar"
        case .settings: return "slider.horizontal.3"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .today: return "square.grid.2x2.fill"
        case .activity: return "chart.bar.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}
