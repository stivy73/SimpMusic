import CarPlay
import UIKit
import Combine

@MainActor final class MusicAppState {
  static let shared = MusicAppState()
  let music = MusicLibraryModel()
  let narration = NarrationModel()
  lazy var playerPresentation=ApplePlayerAdapter(music:music,narration:narration)
  private var currentTrack:AnyCancellable?
  private var watch:MusicWatchBridge!
  private init() {
    watch=MusicWatchBridge(music:music,narration:narration)
    music.beforePlayback={ [weak narration] in narration?.stop() }
    narration.beforeReading={ [weak music] in music?.pause() }
    currentTrack=music.$nowPlaying.map { $0?.id }.removeDuplicates().sink { [weak narration] _ in
      narration?.clearInterpretation()
    }
  }
}
@MainActor final class MusicAppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application:UIApplication, configurationForConnecting session:UISceneSession, options:UIScene.ConnectionOptions)->UISceneConfiguration {
    if session.role == .carTemplateApplication {
      let config=UISceneConfiguration(name:"CarPlay",sessionRole:session.role);config.sceneClass=CPTemplateApplicationScene.self;config.delegateClass=MusicCarPlayScene.self;return config
    }
    return UISceneConfiguration(name:nil,sessionRole:session.role)
  }
}
@MainActor final class MusicCarPlayScene: UIResponder, CPTemplateApplicationSceneDelegate {
  private var controller: CPInterfaceController?
  private let songs=CPListTemplate(title:"Brani",sections:[])
  private let albums=CPListTemplate(title:"Album",sections:[])
  private let lists=CPListTemplate(title:"Playlist",sections:[])
  private var subscriptions=Set<AnyCancellable>()
  private var offsets: [ObjectIdentifier:Int]=[:]
  func templateApplicationScene(_ templateApplicationScene:CPTemplateApplicationScene,didConnect interfaceController:CPInterfaceController) {
    controller=interfaceController
    songs.tabImage=UIImage(systemName:"music.note");albums.tabImage=UIImage(systemName:"square.stack");lists.tabImage=UIImage(systemName:"list.bullet")
    let model=MusicAppState.shared.music
    Publishers.MergeMany([
      model.$songs.map { _ in () }.eraseToAnyPublisher(),
      model.$albums.map { _ in () }.eraseToAnyPublisher(),
      model.$playlists.map { _ in () }.eraseToAnyPublisher(),
      model.$authorization.map { _ in () }.eraseToAnyPublisher()
    ]).debounce(for:.milliseconds(100),scheduler:RunLoop.main).sink { [weak self] _ in self?.render() }.store(in:&subscriptions)
    render();interfaceController.setRootTemplate(CPTabBarTemplate(templates:[songs,albums,lists]),animated:false,completion:nil)
    Task { await model.refresh() }
  }
  func templateApplicationScene(_ templateApplicationScene:CPTemplateApplicationScene,didDisconnectInterfaceController interfaceController:CPInterfaceController) { subscriptions.removeAll();controller=nil }
  private func render() {
    let model=MusicAppState.shared.music
    guard model.authorization == .authorized else {
      let row=CPListItem(text:"Collega Apple Music su iPhone",detailText:"Consenti l'accesso alla libreria dall'app NoteNarrate");row.isEnabled=false
      for template in [songs,albums,lists] { template.updateSections([CPListSection(items:[row])]) };return
    }
    let trackRows=model.songs.map { song in
      let row=CPListItem(text:song.title,detailText:song.artistName)
      row.handler={ [weak self] _,done in done();Task { await model.play(song,in:model.songs);self?.showPlayer() } };return row
    }
    setRows(trackRows,in:songs)
    setRows(model.albums.map { album in
      let row=CPListItem(text:album.title,detailText:album.artistName)
      row.handler={ [weak self] _,done in done();Task { await model.play(album:album);self?.showPlayer() } };return row
    },in:albums)
    setRows(model.playlists.map { playlist in
      let row=CPListItem(text:playlist.name,detailText:playlist.curatorName)
      row.handler={ [weak self] _,done in done();Task { await model.play(playlist:playlist);self?.showPlayer() } };return row
    },in:lists)
  }
  private func setRows(_ rows:[CPListItem],in template:CPListTemplate) {
    let key=ObjectIdentifier(template)
    let offset=min(offsets[key] ?? 0,max(0,(rows.count-1)/20*20))
    offsets[key]=offset
    var page=Array(rows.dropFirst(offset).prefix(20))
    if offset>0 {
      let previous=CPListItem(text:"Pagina precedente",detailText:nil)
      previous.handler={ [weak self] _,done in done();DispatchQueue.main.async { self?.offsets[key]=max(0,offset-20);self?.render() } };page.append(previous)
    }
    if offset+20<rows.count {
      let next=CPListItem(text:"Altri elementi",detailText:"\(offset+21)–\(min(rows.count,offset+40)) di \(rows.count)")
      next.handler={ [weak self] _,done in done();DispatchQueue.main.async { self?.offsets[key]=offset+20;self?.render() } };page.append(next)
    }
    if page.isEmpty { let empty=CPListItem(text:"Nessun elemento nella libreria",detailText:nil);empty.isEnabled=false;page=[empty] }
    template.updateSections([CPListSection(items:page)])
  }
  private func showPlayer() { controller?.pushTemplate(CPNowPlayingTemplate.shared,animated:true,completion:nil) }
}
