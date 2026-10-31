import SwiftUI

/// A satin folder with a recessed symbol pressed into the front pocket.
struct FolderArtwork: View {
    var tint: Color
    var icon: String = "square.stack.3d.up.fill"
    var count: Int?
    var progress: Double = 0
    var members: [SharedMember] = []
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var dark: Bool { scheme == .dark }
    private var pocketTop: Color { tint.mix(with: .white, by: dark ? 0.12 : 0.40) }
    private var pocketBottom: Color { dark ? tint.mix(with: .black, by: 0.28) : tint.mix(with: .white, by: 0.08) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Ellipse()
                    .fill(.black.opacity(dark ? 0.18 : 0.07))
                    .frame(width: width * 0.69, height: height * 0.09)
                    .blur(radius: 8)
                    .offset(y: height * 0.43)

                FolderBackCover()
                    .fill(
                        LinearGradient(
                            colors: [tint.mix(with: .white, by: 0.08), tint.mix(with: .black, by: dark ? 0.46 : 0.24)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(FolderBackCover().strokeBorderHighlight(dark: dark))
                    .frame(width: width * 0.82, height: height * 0.79)
                    .offset(y: -height * 0.015)

                FolderPocket()
                    .fill(
                        LinearGradient(
                            colors: [pocketTop, pocketBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                        FolderPocket().fill(
                            RadialGradient(
                                colors: [.white.opacity(dark ? 0.12 : 0.22), .clear],
                                center: .topLeading, startRadius: 0, endRadius: width * 0.9))
                    }
                    .overlay {
                        FolderPocket().stroke(
                            LinearGradient(
                                colors: [.white.opacity(dark ? 0.24 : 0.95), .black.opacity(dark ? 0.14 : 0.045)],
                                startPoint: .top, endPoint: .bottom), lineWidth: 0.9)
                    }
                    .shadow(color: .black.opacity(dark ? 0.22 : 0.065), radius: hovered ? 12 : 8, y: hovered ? 10 : 6)
                    .overlay(alignment: .bottomLeading) {
                        if !members.isEmpty {
                            SharedMemberAvatars(members: members, size: min(26, width * 0.17))
                                .padding(.leading, width * 0.085)
                                .padding(.bottom, height * 0.09)
                        } else if width > 100 {
                            pocketDetail(width: width)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        recessedSymbol(width: width)
                            .padding(.trailing, width * 0.10)
                            .padding(.bottom, height * 0.12)
                    }
                    .frame(width: width * 0.86, height: height * 0.69)
                    .offset(y: height * 0.12)
            }
            .frame(width: width, height: height)
            .offset(y: hovered ? -3 : 0)
        }
        .onHover { value in
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) { hovered = value }
        }
        .accessibilityHidden(true)
    }

    private func recessedSymbol(width: CGFloat) -> some View {
        let symbol = icon == "tag.fill" ? "square.stack.3d.up.fill" : icon
        let depth = max(0.6, width * 0.007)
        return Image(systemName: symbol)
            .resizable().scaledToFit()
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(
                tint.mix(with: .black, by: dark ? 0.64 : 0.52)
                    .shadow(.inner(color: .black.opacity(dark ? 0.55 : 0.3), radius: depth, x: 0, y: depth))
            )
            .frame(width: width * 0.25, height: width * 0.25)
            .shadow(color: .white.opacity(dark ? 0.28 : 0.7), radius: depth * 0.4, x: 0, y: depth)
    }

    private func pocketDetail(width: CGFloat) -> some View {
        HStack(spacing: 7) {
            if let count {
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(dark ? Color.white.opacity(0.85) : Color.black.opacity(0.65))
                    .padding(.horizontal, 6).frame(height: 17)
                    .background(.black.opacity(dark ? 0.12 : 0.025), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(dark ? 0.07 : 0.7), lineWidth: 0.7))
                Capsule().fill(dark ? .white.opacity(0.22) : .black.opacity(0.16)).frame(width: 25, height: 2)
                    .overlay(alignment: .leading) {
                        Capsule().fill(dark ? .white.opacity(0.8) : .black.opacity(0.55))
                            .frame(width: 25 * min(1, max(0, progress)), height: 2)
                    }
            }
        }
        .padding(.leading, width * 0.085)
        .padding(.bottom, width * 0.08)
    }
}

struct SharedMemberAvatar: View {
    let member: SharedMember
    var size: CGFloat = 28

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(member.avatarColorIndex == 1 ? Theme.Colors.cloudDancer : Theme.Colors.darkestHour)
            .frame(width: size, height: size)
            .background(
                [Theme.Colors.sunGlare, Theme.Colors.blueViolet, Theme.Colors.exuberantOrange][member.avatarColorIndex],
                in: Circle()
            )
            .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
            .accessibilityLabel(member.displayName)
    }
}

struct SharedMemberAvatars: View {
    let members: [SharedMember]
    var size: CGFloat = 28
    var limit = 3

    var body: some View {
        HStack(spacing: -size * 0.26) {
            ForEach(Array(members.prefix(limit).enumerated()), id: \.element.id) { index, member in
                SharedMemberAvatar(member: member, size: size).zIndex(Double(limit - index))
            }
            if members.count > limit {
                Text("+\(members.count - limit)")
                    .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: size, height: size)
                    .background(Theme.Colors.fillStrong, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Участники: " + members.map(\.displayName).joined(separator: ", "))
    }
}

private struct FolderBackCover: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.12, y: 0))
        p.addLine(to: CGPoint(x: w * 0.34, y: 0))
        p.addCurve(
            to: CGPoint(x: w * 0.55, y: h * 0.13),
            control1: CGPoint(x: w * 0.43, y: 0), control2: CGPoint(x: w * 0.43, y: h * 0.13))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.13))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.27), control: CGPoint(x: w, y: h * 0.13))
        p.addLine(to: CGPoint(x: w, y: h * 0.86))
        p.addQuadCurve(to: CGPoint(x: w * 0.87, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w * 0.13, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.86), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.15))
        p.addQuadCurve(to: CGPoint(x: w * 0.12, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}

private struct FolderPocket: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * 0.29))
        p.addCurve(
            to: CGPoint(x: w * 0.2, y: h * 0.035),
            control1: CGPoint(x: 0, y: h * 0.08), control2: CGPoint(x: w * 0.07, y: h * 0.035))
        p.addLine(to: CGPoint(x: w * 0.34, y: h * 0.035))
        p.addCurve(
            to: CGPoint(x: w * 0.57, y: h * 0.16),
            control1: CGPoint(x: w * 0.45, y: h * 0.035), control2: CGPoint(x: w * 0.44, y: h * 0.16))
        p.addLine(to: CGPoint(x: w * 0.81, y: h * 0.16))
        p.addCurve(
            to: CGPoint(x: w, y: h * 0.39),
            control1: CGPoint(x: w * 0.95, y: h * 0.16), control2: CGPoint(x: w, y: h * 0.23))
        p.addLine(to: CGPoint(x: w, y: h * 0.78))
        p.addCurve(
            to: CGPoint(x: w * 0.8, y: h),
            control1: CGPoint(x: w, y: h * 0.95), control2: CGPoint(x: w * 0.94, y: h))
        p.addLine(to: CGPoint(x: w * 0.19, y: h))
        p.addCurve(
            to: CGPoint(x: 0, y: h * 0.78),
            control1: CGPoint(x: w * 0.04, y: h), control2: CGPoint(x: 0, y: h * 0.96))
        p.closeSubpath()
        return p
    }
}

private extension Shape {
    func strokeBorderHighlight(dark: Bool) -> some View {
        stroke(
            LinearGradient(
                colors: [.white.opacity(dark ? 0.18 : 0.9), .black.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
    }
}

struct SoftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct WorkspaceWidgetSpan: LayoutValueKey { static let defaultValue = 1 }
struct WorkspaceWidgetHeight: LayoutValueKey { static let defaultValue: CGFloat = 190 }

/// A bounded grid lets a wide widget occupy two columns without arbitrary canvas coordinates.
struct WorkspaceWidgetGrid: Layout {
    var spacing: CGFloat = 16
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        #if os(iOS)
        let columns = width >= 310 ? 2 : 1
        #else
        let columns = max(1, min(4, Int((width + spacing) / 220)))
        #endif
        let unit = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        var result: [CGRect] = []
        var column = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let span = min(columns, view[WorkspaceWidgetSpan.self])
            if column + span > columns { column = 0; y += rowHeight + spacing; rowHeight = 0 }
            let height = view[WorkspaceWidgetHeight.self]
            result.append(
                CGRect(
                    x: CGFloat(column) * (unit + spacing), y: y,
                    width: unit * CGFloat(span) + spacing * CGFloat(span - 1), height: height))
            rowHeight = max(rowHeight, height)
            column += span
            if column == columns { column = 0; y += rowHeight + spacing; rowHeight = 0 }
        }
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, rect) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                anchor: .topLeading, proposal: ProposedViewSize(rect.size))
        }
    }
}
