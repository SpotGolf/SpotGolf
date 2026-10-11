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

/// A small white label with the yards between two strokes, centered on their line.
struct DistanceLabel: View {
    let yards: Int
    /// The line's number in the hole, from 1, for its accessibility identifier.
    let number: Int

    var body: some View {
        Text("\(yards)")
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(yards) yards")
            .accessibilityIdentifier("StrokeDistance_\(number)")
    }
}

/// A pin on a point of the map: a round head on a short arrow, and a small dot on the point
/// under the arrow's tip. Suggestion pins and spot pins are both drawn with it. Anchor the
/// annotation at `.bottom`: the view's bottom edge runs through the dot's center. A lifted pin
/// rises off the dot on a line, for a spot being dragged.
struct MapPin<Content: View>: View {
    let color: Color
    /// The dot's color, when it differs from the head's.
    var dotColor: Color? = nil
    /// An edge on the head and the dot, for a white pin on light ground.
    var outline: Color? = nil
    var lift: CGFloat = 0
    var headScale: CGFloat = 1
    var shadow: Color = .black.opacity(0.25)
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Circle()
                    .fill(color)
                    .frame(width: PinMetrics.head, height: PinMetrics.head)
                    .overlay { content }
                    .overlay {
                        if let outline {
                            Circle().stroke(outline, lineWidth: 1.5)
                        }
                    }
                BubbleArrow()
                    .fill(color)
                    .frame(width: PinMetrics.arrow.width, height: PinMetrics.arrow.height)
            }
            .scaleEffect(headScale, anchor: .bottom)
            .shadow(color: shadow, radius: headScale > 1 ? 8 : 2, y: headScale > 1 ? 2 : 1)
            if lift > 0 {
                Rectangle()
                    .fill(color.opacity(0.6))
                    .frame(width: 2, height: lift)
            }
            Color.clear.frame(width: PinMetrics.dot, height: PinMetrics.gap)
            Circle()
                .fill(dotColor ?? color)
                .overlay { Circle().stroke(outline ?? .white, lineWidth: 1) }
                .frame(width: PinMetrics.dot, height: PinMetrics.dot)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        // Puts the dot's center, not its bottom, on the coordinate
        .offset(y: PinMetrics.dot / 2)
    }
}

enum PinMetrics {
    /// The head's diameter.
    static let head: CGFloat = 28
    static let arrow = CGSize(width: 10, height: 7)
    /// The dot's diameter.
    static let dot: CGFloat = 8
    /// Between the arrow's tip and the dot.
    static let gap: CGFloat = 2
    /// From the dot's center up to the head's center.
    static let headCenter: CGFloat = head / 2 + arrow.height + gap + dot / 2
}

/// A green pin with a plus sign, or a flag for a putt the watch heard, its dot on the spot
/// the watch found. Tapping turns the suggestion into a real stroke.
struct SuggestionPin: View {
    let isContact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MapPin(color: .green) {
                Image(systemName: isContact ? "flag.fill" : "plus")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isContact ? "Add suggested putt" : "Add suggested stroke")
    }
}

/// A spot's pin, red for a stroke with penalty strokes and blue otherwise, with the club it was hit
/// with in the head, or its number before clubs were recorded, and its dot on the GPS
/// location. Tapping the head opens the spot. While the spot is dragged, the pin turns orange
/// and lifts off the dot, and a bullseye around the dot shows where it would land.
struct SpotPin: View {
    /// How far the pin lifts while dragged.
    private static let lift: CGFloat = 30

    let number: Int
    let stroke: Stroke
    let isDragging: Bool
    let action: () -> Void

    var body: some View {
        // A tap gesture, not a button: a button would take the long press that lifts the pin
        MapPin(color: isDragging ? .orange : color, dotColor: color,
               lift: isDragging ? Self.lift : 0, headScale: isDragging ? 1.5 : 1,
               shadow: isDragging ? .orange.opacity(0.4) : .black.opacity(0.25)) {
            Text(stroke.club?.shortName ?? "\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottom) {
            if isDragging {
                // Centered on the dot, which sits at the bottom of the pin: a zero-height frame
                // puts the marker's center on the bottom edge
                TargetMarker()
                    .frame(height: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, action)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("Stroke_\(number)")
    }

    private var color: Color {
        stroke.penaltyStrokes > 0 ? .red : .blue
    }

    private var accessibilityLabel: String {
        if let club = stroke.club {
            String(localized: "Spot \(number), \(club.name)")
        } else {
            String(localized: "Spot \(number)")
        }
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
