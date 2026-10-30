import SwiftUI

struct CaptureFolderPicker: View {
    let tags: [Tag]
    @Binding var choice: CaptureFolderChoice
    @Binding var newName: String
    var onContinue: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chip("Без папки", symbol: "tray", value: .unassigned)
                    chip("Новая папка", symbol: "folder.badge.plus", value: .newFolder)
                    ForEach(tags) { tag in
                        chip(tag.name, symbol: tag.folderIconName, value: .existing(tag.id), tint: tag.color)
                    }
                }.padding(.vertical, 2)
            }
            if choice == .newFolder {
                HStack(spacing: 9) {
                    Image(systemName: "folder.badge.plus").foregroundStyle(Theme.Colors.accent)
                    TextField("Название папки", text: $newName)
                        .textFieldStyle(.plain).submitLabel(.next).onSubmit(onContinue)
                        .accessibilityIdentifier("capture-new-folder-name")
                }
                .font(.system(size: 13)).padding(.horizontal, 12).frame(height: 40)
                .background(Theme.Colors.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                Text("Без названия — назовём папку по задаче.")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.textMuted)
            }
        }.foregroundStyle(Theme.Colors.textPrimary)
    }

    private func chip(_ title: String, symbol: String, value: CaptureFolderChoice, tint: Color? = nil) -> some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { choice = value }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(
                    choice == value ? Theme.Colors.onAccent : tint ?? Theme.Colors.textSecondary)
                Text(title).lineLimit(1)
                if choice == value { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(choice == value ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
            .padding(.horizontal, 11).frame(height: 34)
            .background(choice == value ? Theme.Colors.accent : Theme.Colors.fill, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(choice == value ? .isSelected : [])
            .accessibilityIdentifier(
                value == .newFolder
                    ? "capture-folder-new" : value == .unassigned ? "capture-folder-none" : "capture-folder-" + title)
    }
}

// MARK: - Eyebrow Label
struct EyebrowLabel: View {
    let text: String
    var count: Int? = nil
    var color: Color = Theme.Colors.textMuted

    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
            if let count {
                Text("\(count)")
                    .opacity(0.7)
            }
        }
        .font(Theme.Typography.eyebrow)
        .tracking(Theme.Typography.eyebrowTracking)
        .foregroundColor(color)
        .lineLimit(1)
    }
}

// MARK: - Section Title
struct SectionTitle: View {
    let text: String
    var count: Int? = nil
    var color: Color = Theme.Colors.textMuted

    var body: some View {
        HStack(spacing: 7) {
            Text(text)
                .foregroundColor(color)
            if let count {
                Text("\(count)")
                    .foregroundColor(Theme.Colors.textMuted)
            }
        }
        .font(Theme.Typography.section)
        .tracking(0.6)
        .lineLimit(1)
    }
}

// MARK: - Task Checkbox
struct TaskCheckbox: View {
    let isDone: Bool
    var isPriority: Bool = false
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? Theme.Colors.inverse : Color.clear)
            Circle()
                .strokeBorder(strokeColor, lineWidth: isPriority && !isDone ? 2 : 1.5)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .heavy))
                    .foregroundColor(Theme.Colors.onInverse)
            }
        }
        .frame(width: size, height: size)
    }

    private var strokeColor: Color {
        if isDone { return Theme.Colors.inverse }
        return isPriority ? Theme.Colors.priority : Theme.Colors.ruleStrong
    }
}

// MARK: - Scope Tab
struct ScopeTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var color: Color? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle()
                        .fill(isSelected ? Theme.Colors.onAccent : color)
                        .frame(width: 6, height: 6)
                }

                #if os(iOS)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                #else
                Text(title.uppercased())
                    .font(Theme.Typography.numeric(11, weight: isSelected ? .bold : .medium))
                    .tracking(0.4)
                    .lineLimit(1)
                #endif

                if let count, count > 0 {
                    Text("\(count)")
                        .contentTransition(.numericText())
                        .font(Theme.Typography.numeric(11, weight: isSelected ? .bold : .regular))
                        .opacity(isSelected ? 0.7 : 1)
                }
            }
            .foregroundColor(isSelected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
            .padding(.horizontal, 12)
            #if os(iOS)
            .frame(height: 36)
            .background(Capsule().fill(isSelected ? Theme.Colors.accent : Theme.Colors.fill.opacity(0.55)))
            #else
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.Colors.accent : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.ruleStrong, lineWidth: 1)
            )
            #endif
            .fixedSize()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: isSelected)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: count)
    }
}

// MARK: - Context Chip
struct ContextChip: View {
    let title: String
    var color: Color? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let color {
                    Circle()
                        .fill(isSelected ? Theme.Colors.onAccent : color)
                        .frame(width: 7, height: 7)
                }

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(Theme.Typography.numeric(11))
                        .opacity(0.7)
                }
            }
            .foregroundColor(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.Colors.accent : Theme.Colors.fill)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.ruleStrong, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress Line
struct ProgressLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    var tint: Color = Theme.Colors.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress)
    }
}

// MARK: - Group Card
struct GroupCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.borderSubtle, lineWidth: 0.5)
        )
    }
}
struct Hairline: View {
    var leading: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

// MARK: - Stat Block
struct StatBlock: View {
    let value: String
    let label: String
    var tint: Color = Theme.Colors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Theme.Typography.figure(30))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            EyebrowLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Submit Button
struct SubmitCircleButton: View {
    let isEnabled: Bool
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Theme.Colors.accent : Theme.Colors.fillStrong)
                Image(systemName: "arrow.up")
                    .font(.system(size: size * 0.45, weight: .heavy))
                    .foregroundColor(isEnabled ? Theme.Colors.onAccent : Theme.Colors.textMuted)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Priority Toggle
struct PriorityToggleButton: View {
    @Binding var isOn: Bool
    var size: CGFloat = 32

    var body: some View {
        Button {
            Haptics.selection()
            isOn.toggle()
        } label: {
            ZStack {
                Image(systemName: "flame")
                    .opacity(isOn ? 0 : 1)
                Image(systemName: "flame.fill")
                    .opacity(isOn ? 1 : 0)
            }
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundColor(isOn ? Theme.Colors.priority : Theme.Colors.textMuted)
            .frame(width: size, height: size)
            .background(Circle().fill(isOn ? Theme.Colors.priority.opacity(0.16) : Color.clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Снять высокий приоритет" : "Высокий приоритет")
    }
}

struct FloatingGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var id: String? = nil
    var namespace: Namespace.ID? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.Colors.surfaceElevated, in: shape)
                .overlay(shape.stroke(Theme.Colors.ruleStrong, lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            if let namespace {
                content.glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID(id, in: namespace)
                    .glassEffectTransition(.matchedGeometry)
            } else {
                content.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Theme.Colors.ruleStrong, lineWidth: 0.5))
        }
    }
}

/// Matches the Today title's date row and spacing without showing a subtitle.
struct ScreenHeading: View {
    let text: String
    var body: some View {
        Text(text.capitalized)
            .font(Theme.Typography.display)
            .tracking(Theme.Typography.displayTracking)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(height: 43, alignment: .leading)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PageIntro: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.8).foregroundStyle(
                    Theme.Colors.textPrimary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            Image("BrandLogo").resizable().frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
        }.padding(.top, 14).padding(.bottom, 8)
    }
}
