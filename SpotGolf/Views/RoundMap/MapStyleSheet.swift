import MapKit
import SwiftUI

/// Picks the map's style, as Apple Maps' Map Modes sheet does: a row of previews of the shown
/// hole in each style, the picked one outlined, with its name under each. Picking one applies
/// it and closes the sheet.
struct MapStyleSheet: View {
    let selected: MapStyleChoice
    /// Where the previews look: the shown hole's green, or the player.
    let center: CLLocationCoordinate2D
    let select: (MapStyleChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text("Map Style")
                    .font(.title3)
                    .fontWeight(.bold)
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .padding(8)
                            .background(.quaternary)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("CloseMapStyles")
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(MapStyleChoice.allCases) { choice in
                    Button {
                        select(choice)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            MapStylePreview(choice: choice, center: center, isSelected: choice == selected)
                            Text(choice.title)
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(choice.title))
                    .accessibilityAddTraits(choice == selected ? .isSelected : [])
                    .accessibilityIdentifier("MapStyle-\(choice.rawValue)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .presentationDetents([.height(196)])
        .presentationDragIndicator(.hidden)
    }
}

/// A snapshot of the hole in one style, outlined in blue when it is the picked one. A snapshot
/// rather than a live map, so the tap goes to the button instead of the map.
private struct MapStylePreview: View {
    let choice: MapStyleChoice
    let center: CLLocationCoordinate2D
    let isSelected: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private static let size: CGFloat = 88
    /// About 300 m across, enough to show a hole's shape.
    private static let span = MKCoordinateSpan(latitudeDelta: 0.0027, longitudeDelta: 0.0027)

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        }
        .task(id: choice) {
            image = await Self.snapshot(choice, center: center, scale: displayScale)
        }
    }

    /// The hole in the style, or nothing when the snapshot fails, which leaves the plain tile.
    private static func snapshot(_ choice: MapStyleChoice, center: CLLocationCoordinate2D, scale: CGFloat) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: size, height: size)
        options.scale = scale
        options.preferredConfiguration = choice.mapConfiguration
        return try? await MKMapSnapshotter(options: options).start().image
    }
}
