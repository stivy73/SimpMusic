import Foundation

/// Service-neutral input for the original conservative cross-catalog matcher.
public struct SharedMatchCandidate:Identifiable,Equatable,Sendable {
  public enum Kind:Sendable {case song}
  public struct ArtistCredit:Equatable,Sendable {public let name:String}
  public let kind:Kind
  public let mediaId:String
  public let title:String
  public let subtitle:String
  public let artwork:URL?
  public let durationSeconds:Double?
  public var artistReferences:[ArtistCredit]? {nil}
  public var id:String {mediaId}
  public init(kind:Kind = .song,mediaId:String,title:String,subtitle:String,artwork:URL?,durationSeconds:Double?=nil) {
    self.kind=kind;self.mediaId=mediaId;self.title=title;self.subtitle=subtitle;self.artwork=artwork;self.durationSeconds=durationSeconds
  }
}
enum SharedMatchKey {
  static func normalize(_ text:String)->String {
    text.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX"))
      .components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.joined(separator:" ")
  }
}
