// Adapted from iosPrototype/Sources/App/HomeView.swift at 5a277798. SHA256 c7b7463a5de94f84e0ae47a6fa5ec5e22ed1e015ff16f89dde11eca96ff901b4
// Reproduce with Scripts/import_youtube_discovery.py.
import SwiftUI

struct AppleDiscoveryShelves: View {
  let shelves: [AppleShelf]
  var songsAsList = false
  var body: some View {
    ForEach(shelves) { shelf in
      VStack(alignment: .leading, spacing: 14) {
        if !shelf.title.isEmpty {
          HStack(spacing: 12) {
            if let avatar = shelf.avatar {
              YTPlayerArtwork(url: avatar).frame(width: 46, height: 46).clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
              if !shelf.subtitle.isEmpty {
                Text(shelf.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              Text(shelf.title).font(.title2.bold()).accessibilityIdentifier("home-shelf-title")
            }
            Spacer(minLength: 8)
            NavigationLink("Altro") { AppleShelfScreen(shelf:shelf) }
              .font(.subheadline).accessibilityLabel("Altro: \(shelf.title)")
          }.padding(.horizontal, 20)
        }
        if songsAsList && shelf.items.allSatisfy({ $0.kind == .song }) {
          ForEach(shelf.items) { item in
            AppleDiscoveryItemLink(item: item, queue: shelf.items) {
              HStack(spacing: 14) {
                BrowseCover(item: item).frame(width: 58, height: 58)
                  .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                  Text(item.title).foregroundStyle(.primary).fontWeight(.semibold).lineLimit(2)
                  Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.circle.fill").font(.title2)
              }.padding(.horizontal, 20).padding(.vertical, 5).contentShape(Rectangle())
            }
          }
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
              ForEach(shelf.items) { item in
                AppleDiscoveryItemLink(item: item, queue: shelf.items.filter { $0.kind == .song }) {
                  AppleDiscoveryCard(item: item)
                }
              }
            }
          }
          .contentMargins(.horizontal, 20, for: .scrollContent)
          // Clip the row's foreground at its safe-area viewport. Native Duo
          // controls belong to the navigation container and must stay unclipped.
          .clipped()
          .accessibilityIdentifier("home-shelf-\(shelf.id)")
        }
      }
    }
  }
}

private struct AppleDiscoveryCard: View {
  let item: MusicBrowseItem
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      BrowseCover(item: item).frame(width: 164, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: item.kind == .artist ? 82 : 14))
      Text(item.title).font(.subheadline.weight(.semibold))
        .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("home-card-title-\(item.id)")
      Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
        .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
    }.frame(width: 164, alignment: .leading).foregroundStyle(.primary)
      .accessibilityElement(children: .combine)
  }
}

struct AppleDiscoveryCategories: View {
  let sections: [AppleCategorySection]
  var body: some View {
    ForEach(sections) { section in
      VStack(alignment: .leading, spacing: 14) {
        Text(section.title).font(.title2.bold()).accessibilityIdentifier("home-category-title")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
          ForEach(section.items) { item in
            NavigationLink {
              AppleExploreDestinationScreen(destination:item.target)
            } label: {
              HStack(spacing: 12) {
                Rectangle().fill(color(item.stripeColor)).frame(width: 7)
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
              }.frame(minHeight: 60).padding(.trailing, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("home-category-\(item.title)")
          }
        }
      }.padding(.horizontal, 20)
    }
  }
  private func color(_ argb: UInt32) -> Color {
    Color(
      red: Double((argb >> 16) & 255) / 255,
      green: Double((argb >> 8) & 255) / 255, blue: Double(argb & 255) / 255)
  }
}
