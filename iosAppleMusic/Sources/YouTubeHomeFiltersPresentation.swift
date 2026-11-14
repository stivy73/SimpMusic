// Adapted from iosPrototype/Sources/App/HomeView.swift at 5a277798. SHA256 c7b7463a5de94f84e0ae47a6fa5ec5e22ed1e015ff16f89dde11eca96ff901b4
// Reproduce with Scripts/import_youtube_discovery.py.
import SwiftUI

struct AppleHomeQuickFilters:View {
  @ObservedObject var home:HomeQuickFilterStore<MusicBrowseItem>
  var body:some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(AppleHomeFilter.values) { filter in
          Button {
            Task { await home.select(filter) }
          } label: {
            Text(filter.title).font(.subheadline.weight(.semibold))
              .padding(.horizontal, 18).padding(.vertical, 10)
              .foregroundStyle(home.selectedFilter == filter ? Color.black : Color.primary)
              .background(
                home.selectedFilter == filter ? Color.cyan : Color.clear, in: Capsule()
              )
              .overlay(
                Capsule().stroke(home.selectedFilter == filter ? .clear : .gray.opacity(0.55)))
          }.buttonStyle(.plain).accessibilityIdentifier("home-filter-\(filter.id)")
            .accessibilityAddTraits(home.selectedFilter == filter ? .isSelected : [])
            .accessibilityValue(
              home.selectedFilter == filter ? "Selezionato" : "Non selezionato")
        }
      }
    }
    .contentMargins(.horizontal, 20, for: .scrollContent)
    .clipped()
  }
}
