//
//  YouTubeMusicHomePage.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 29/03/26.
//

import Foundation

public struct YouTubeMusicHomePage: Sendable {
  public let sections: [YouTubeMusicSection]
  public let continuationToken: String?
  public let categories: [YouTubeMusicCategorySection]

  public init(
    sections: [YouTubeMusicSection], continuationToken: String?,
    categories: [YouTubeMusicCategorySection] = []
  ) {
    self.sections = sections
    self.continuationToken = continuationToken
    self.categories = categories
  }

  public var items: [YouTubeMusicItem] {
    sections.flatMap(\.items)
  }
}
