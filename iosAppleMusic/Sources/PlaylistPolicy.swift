import Foundation
import CoreFoundation

enum PlaylistPolicy {
  enum Failure:LocalizedError {
    case readOnly,notCreatedHere,incomplete,changed,invalidName,invalidMove
    var errorDescription:String? {switch self {
    case .readOnly:"Questa playlist non è modificabile. Scegli una tua playlist o creane una nuova."
    case .notCreatedHere:"Puoi rinominare e riordinare qui le playlist create con NoteNarrate Music. Per questa playlist usa Musica."
    case .incomplete:"La playlist contiene elementi non disponibili. Non posso riscriverla senza rischiare di perderli. Aprila in Musica."
    case .changed:"La playlist è cambiata. Aggiornala prima di modificarla."
    case .invalidName:"Inserisci un nome playlist da 1 a 200 caratteri."
    case .invalidMove:"Spostamento non valido. Aggiorna la playlist e riprova."
    }}
  }
  static func name(_ input:String) throws -> String {
    let clean=input.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !clean.isEmpty,clean.count<=200,!clean.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else {throw Failure.invalidName}
    return clean
  }
  static func canAdd(data:Data,status:Int,id:String) throws -> Bool {
    guard status==200,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let values=root["data"] as? [[String:Any]],values.count==1,values[0]["id"] as? String==id,
      let attrs=values[0]["attributes"] as? [String:Any],let flag=attrs["canEdit"] as? NSNumber,
      CFGetTypeID(flag)==CFBooleanGetTypeID() else {throw Failure.readOnly}
    return flag.boolValue
  }
  // Same occurrence-based move as RemotePlaylist.moveAction. Duplicated songs stay distinct.
  static func moved<T>(_ entries:[T],from:Int,to:Int) throws -> [T] {
    guard entries.indices.contains(from),(0...entries.count).contains(to) else {throw Failure.invalidMove}
    var values=entries;let row=values.remove(at:from);values.insert(row,at:to>from ? to-1:to);return values
  }
  static func requireSnapshot(_ expected:[String],current:[String]) throws {
    guard expected==current else {throw Failure.changed}
  }
}
