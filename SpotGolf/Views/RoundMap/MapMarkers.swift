import SwiftUI

/// A thin dark pole with a small flag at the top, on the hole's pin: green for a real pin,
/// red for the center of the green until a real pin is known. Larger as the map zooms in.
struct PinFlag: View {
    static let size = CGSize(width: 12, height: 24)
    static let poleWidth: CGFloat = 1.5
    /// The flag's base, where the pole meets the ground: the map anchors and scales it there.
    static let base = UnitPoint(x: poleWidth / 2 / size.width, y: 1)
    /// Darker than the map's greens, so the flag stands out on them.
    private static let realPinGreen = Color(red: 0.0, green: 0.55, blue: 0.15)

    let source: PinSource
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(white: 0.15))
                .frame(width: Self.poleWidth, height: Self.size.height)
            FlagShape()
                .fill(source == .center ? Color.red : Self.realPinGreen)
                .frame(width: Self.size.width - Self.poleWidth, height: 8)
                .offset(x: Self.poleWidth)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: Self.base)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source == .center ? "Green center" : "Pin")
        .accessibilityIdentifier("Pin")
    }
}

/// A bullseye on the tapped point: one thin ring with four spokes pointing in and a small dot
/// in the middle, open so the map shows through. Its yards are in the boxes on the left.
struct TargetMarker: View {
    /// The ring's diameter, in points.
    static let ring: CGFloat = 40
    /// How far the lines to and from the target stop from its center: the ring's radius and a gap.
    static let lineGap: CGFloat = ring / 2 + 6

    var body: some View {
        let ring = Self.ring
        let line: CGFloat = 1.5
        let spoke: CGFloat = 9
        ZStack {
            Circle().stroke(.white, lineWidth: line).frame(width: ring, height: ring)
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(.white)
                    .frame(width: line, height: spoke)
                    .offset(y: -(ring - spoke) / 2)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Circle().fill(.white).frame(width: 4, height: 4)
        }
        .frame(width: ring + line, height: ring + line)
        // See-through, so the player still sees the spot they tapped
        .opacity(0.75)
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target")
        .accessibilityIdentifier("Target")
    }
}

/// A small white bubble whose arrow tip sits on the start of the hazard.
struct HazardBubble: View {
    let yards: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(yards)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
            BubbleArrow()
                .fill(.white)
                .frame(width: 8, height: 5)
        }
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hazard in \(yards) yards")
    }
}

/// A pin with a plus sign, or a flag for a putt the watch heard. Tapping turns the suggestion
/// into a real stroke.
struct SuggestionPin: View {
    let isContact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: isContact ? "flag.fill" : "plus")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                BubbleArrow()
                    .fill(Color.green)
                    .frame(width: 10, height: 7)
            }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isContact ? "Add suggested putt" : "Add suggested stroke")
    }
}

/// A triangle pointing down.
struct BubbleArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A triangle pointing right, for the pin's flag.
struct FlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
