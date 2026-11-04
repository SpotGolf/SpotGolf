import SwiftUI

/// The credit the course data's license (ODbL) requires wherever the data is shown, visible
/// without a tap. It sits in the map's bottom right corner, level with Apple's own credit at the
/// bottom left, under the map buttons. Taps open OpenStreetMap's copyright page.
struct MapCredit: View {
    static let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    var body: some View {
        Link(destination: Self.copyrightURL) {
            // A legal notice, the same in every language, so it is not in the string catalog
            Text(verbatim: "© OpenStreetMap")
                .font(.caption2)
                // Not the link tint, which is hard to read on the greens
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityIdentifier("MapCredit")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        // The map ignores the bottom safe area; this centers it in the strip under the buttons,
        // where Apple's credit is
        .padding(.trailing, 12)
        .padding(.bottom, 8)
    }
}
