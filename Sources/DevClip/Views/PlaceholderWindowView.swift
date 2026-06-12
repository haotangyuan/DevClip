import SwiftUI

struct PlaceholderWindowView: View {
    var title: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(minWidth: 520, minHeight: 320)
    }
}
