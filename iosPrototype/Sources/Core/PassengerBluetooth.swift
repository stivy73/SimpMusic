@preconcurrency import CoreBluetooth
import Foundation

@MainActor protocol PassengerBluetoothTransport: AnyObject {
  var onReady: ((UUID) -> Bool)? { get set }
  var onData: ((UUID, Data) -> Void)? { get set }
  var onClose: ((UUID) -> Void)? { get set }
  var onDiagnostic: ((String) -> Void)? { get set }
  func host(_ invite: PassengerInvitation)
  func join(_ invite: PassengerInvitation)
  func stop()
  func send(_ data: Data, to id: UUID) -> Bool
  func close(_ id: UUID)
}

/// Small catalog/control messages only. Core Bluetooth is independent of Bonjour and the
/// car's Wi-Fi route. The invitation authenticates/encrypts this transport before approval.
@MainActor final class PassengerBluetooth: NSObject, PassengerBluetoothTransport {
  var onReady: ((UUID) -> Bool)?
  var onData: ((UUID, Data) -> Void)?
  var onClose: ((UUID) -> Void)?
  var onDiagnostic: ((String) -> Void)?

  private static let upstream = CBUUID(string: "F467BB32-09A5-47BA-B87C-BE94044613A1")
  private static let downstream = CBUUID(string: "F467BB32-09A5-47BA-B87C-BE94044613A2")
  private var invitation: PassengerInvitation?
  private var hosting = false
  private var peripheralManager: CBPeripheralManager?
  private var centralManager: CBCentralManager?
  private var downstream: CBMutableCharacteristic?
  private var peers: [UUID: Peer] = [:]
  private var pendingPeripheral: CBPeripheral?
  private var rejectedCentrals = Set<UUID>()

  private final class Peer {
    let id: UUID
    let channel: PassengerBluetoothChannel
    let central: CBCentral?
    let peripheral: CBPeripheral?
    var upstream: CBCharacteristic?
    var downstream: CBCharacteristic?
    var input = PassengerFrameBuffer()
    var output = PassengerBluetoothQueue()
    var writing = false
    var ready = false
    var closing = false
    var deadline: Task<Void, Never>?
    init(
      invitation: PassengerInvitation, central: CBCentral? = nil, peripheral: CBPeripheral? = nil
    ) {
      self.id = central?.identifier ?? peripheral!.identifier
      self.central = central
      self.peripheral = peripheral
      channel = PassengerBluetoothChannel(
        invitation: invitation, role: central != nil ? .host : .guest)
    }
  }

  func host(_ invite: PassengerInvitation) {
    stop()
    invitation = invite
    hosting = true
    onDiagnostic?("Bluetooth: attivazione annuncio alternativo")
    peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
  }

  func join(_ invite: PassengerInvitation) {
    stop()
    invitation = invite
    onDiagnostic?("Bluetooth: ricerca diretta della sessione QR")
    centralManager = CBCentralManager(delegate: self, queue: .main)
  }

  func stop() {
    invitation = nil
    peripheralManager?.delegate = nil
    peripheralManager?.stopAdvertising()
    peripheralManager?.removeAllServices()
    centralManager?.delegate = nil
    centralManager?.stopScan()
    if let pendingPeripheral { centralManager?.cancelPeripheralConnection(pendingPeripheral) }
    for peer in peers.values {
      peer.deadline?.cancel()
      peer.peripheral?.delegate = nil
      if let peripheral = peer.peripheral { centralManager?.cancelPeripheralConnection(peripheral) }
    }
    peers = [:]
    rejectedCentrals = []
    pendingPeripheral = nil
    downstream = nil
    peripheralManager = nil
    centralManager = nil
    hosting = false
  }

  /// Queue bounds apply before handing anything to the OS; backpressure never drops chunks.
  func send(_ data: Data, to id: UUID) -> Bool {
    guard let peer = peers[id], peer.ready, !peer.closing else { return false }
    do {
      try enqueue(peer.channel.seal(data), to: peer)
      return true
    } catch {
      drop(id)
      return false
    }
  }

  func close(_ id: UUID) {
    guard let peer = peers[id], !peer.closing else { return }
    // A peripheral cannot cancel a central's connection. Deliver an authenticated goodbye
    // first, then discard its state; no further commands from this central are accepted.
    if peer.ready {
      _ = send((try? PassengerMessage(.goodbye).encoded()) ?? Data(), to: id)
    }
    guard peers[id] != nil else { return }
    peer.closing = true
    peer.deadline?.cancel()
    peer.deadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      self?.drop(id)
    }
    drain(peer)
  }

  private func state(_ state: CBManagerState) {
    let value: String
    switch state {
    case .poweredOn: value = "pronto"
    case .poweredOff: value = "spento; attivalo in Impostazioni"
    case .unauthorized: value = "permesso negato; abilitalo per NoteNarrate in Impostazioni"
    case .unsupported: value = "non supportato"
    case .resetting: value = "ripristino in corso"
    default: value = "inizializzazione"
    }
    onDiagnostic?("Bluetooth: " + value)
  }

  private func enqueue(_ packet: Data, to peer: Peer) throws {
    try peer.output.append(PassengerFrameBuffer.encode(packet))
    drain(peer)
  }

  private func drain(_ peer: Peer) {
    guard peers[peer.id] === peer else { return }
    if let central = peer.central, let manager = peripheralManager, let downstream {
      while let chunk = peer.output.next(maximum: central.maximumUpdateValueLength) {
        guard manager.updateValue(chunk, for: downstream, onSubscribedCentrals: [central]) else {
          return
        }
        peer.output.consume(chunk.count)
      }
      if peer.closing { drop(peer.id) }
    } else if let peripheral = peer.peripheral, let characteristic = peer.upstream,
      !peer.writing
    {
      if let chunk = peer.output.next(
        maximum: peripheral.maximumWriteValueLength(for: .withResponse))
      {
        peer.writing = true
        peer.output.consume(chunk.count)
        peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
      } else if peer.closing {
        drop(peer.id)
      }
    }
  }

  private func receive(_ data: Data, from peer: Peer) throws {
    for packet in try peer.input.append(data) {
      let event = try peer.channel.receive(packet)
      if let response = event.response { try enqueue(response, to: peer) }
      if event.ready {
        peer.ready = true
        peer.deadline?.cancel()
        onDiagnostic?("Bluetooth: canale QR autenticato e cifrato")
        guard onReady?(peer.id) == true else {
          close(peer.id)
          return
        }
      }
      if let payload = event.payload, !peer.closing {
        onData?(peer.id, payload)
      }
      guard peers[peer.id] === peer else { return }
    }
  }

  private func armDeadline(_ peer: Peer) {
    peer.deadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(12))
      guard !Task.isCancelled else { return }
      self?.onDiagnostic?("Bluetooth: tempo di collegamento/autenticazione scaduto")
      self?.drop(peer.id)
    }
  }

  private func drop(_ id: UUID) {
    guard let peer = peers.removeValue(forKey: id) else { return }
    peer.deadline?.cancel()
    if let central = peer.central {
      // Bound this temporary list as well; a new session clears it.
      if rejectedCentrals.count < 64 { rejectedCentrals.insert(central.identifier) }
    }
    if let peripheral = peer.peripheral {
      peripheral.delegate = nil
      centralManager?.cancelPeripheralConnection(peripheral)
      pendingPeripheral = nil
    }
    if peer.ready { onClose?(id) }
  }
}

extension PassengerBluetooth: @preconcurrency CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard peripheral === peripheralManager else { return }
    state(peripheral.state)
    guard peripheral.state == .poweredOn else {
      for id in Array(peers.keys) { drop(id) }
      return
    }
    guard hosting, let invitation else { return }
    rejectedCentrals = []
    peripheral.removeAllServices()
    let up = CBMutableCharacteristic(
      type: Self.upstream, properties: [.write], value: nil, permissions: [.writeable])
    let down = CBMutableCharacteristic(
      type: Self.downstream, properties: [.notify], value: nil, permissions: [])
    downstream = down
    let service = CBMutableService(type: CBUUID(nsuuid: invitation.sessionID), primary: true)
    service.characteristics = [up, down]
    peripheral.add(service)
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?
  ) {
    guard peripheral === peripheralManager, error == nil, let invitation else {
      onDiagnostic?("Bluetooth: pubblicazione servizio non riuscita")
      return
    }
    peripheral.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [CBUUID(nsuuid: invitation.sessionID)]
    ])
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    guard peripheral === peripheralManager else { return }
    onDiagnostic?(
      error == nil ? "Bluetooth: annuncio QR pubblicato" : "Bluetooth: annuncio non disponibile")
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    guard peripheral === peripheralManager, characteristic.uuid == Self.downstream,
      let invitation, peers[central.identifier] == nil, peers.count < 4,
      !rejectedCentrals.contains(central.identifier)
    else { return }
    let peer = Peer(invitation: invitation, central: central)
    peers[peer.id] = peer
    armDeadline(peer)
    onDiagnostic?("Bluetooth: dispositivo vicino; verifico invito QR")
    do {
      if let packet = try peer.channel.start() { try enqueue(packet, to: peer) }
    } catch { drop(peer.id) }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    guard peripheral === peripheralManager else { return }
    drop(central.identifier)
    rejectedCentrals.remove(central.identifier)
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
  ) {
    guard peripheral === peripheralManager, let first = requests.first else { return }
    guard
      requests.allSatisfy({
        $0.characteristic.uuid == Self.upstream && $0.offset == 0 && $0.value != nil
          && $0.value!.count <= 65_536 && peers[$0.central.identifier]?.closing == false
      })
    else {
      peripheral.respond(to: first, withResult: .unlikelyError)
      return
    }
    do {
      for request in requests {
        if let peer = peers[request.central.identifier], let data = request.value {
          try receive(data, from: peer)
        }
      }
      peripheral.respond(to: first, withResult: .success)
    } catch {
      onDiagnostic?("Bluetooth: invito o pacchetto non valido")
      peripheral.respond(to: first, withResult: .unlikelyError)
      for request in requests { drop(request.central.identifier) }
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    guard peripheral === peripheralManager else { return }
    for peer in Array(peers.values) { drain(peer) }
  }
}

extension PassengerBluetooth: @preconcurrency CBCentralManagerDelegate,
  @preconcurrency CBPeripheralDelegate
{
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central === centralManager else { return }
    state(central.state)
    guard central.state == .poweredOn else {
      for id in Array(peers.keys) { drop(id) }
      return
    }
    guard let invitation else { return }
    central.scanForPeripherals(withServices: [CBUUID(nsuuid: invitation.sessionID)], options: nil)
    onDiagnostic?("Bluetooth: scansione QR pronta")
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard central === centralManager, pendingPeripheral == nil, let invitation else { return }
    pendingPeripheral = peripheral
    let peer = Peer(invitation: invitation, peripheral: peripheral)
    peers[peer.id] = peer
    central.stopScan()
    onDiagnostic?("Bluetooth: auto individuata; avvio collegamento")
    armDeadline(peer)
    central.connect(peripheral, options: nil)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard central === centralManager, peers[peripheral.identifier] != nil, let invitation else {
      return
    }
    peripheral.delegate = self
    peripheral.discoverServices([CBUUID(nsuuid: invitation.sessionID)])
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    guard central === centralManager else { return }
    onDiagnostic?("Bluetooth: collegamento non riuscito")
    drop(peripheral.identifier)
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    guard central === centralManager else { return }
    onDiagnostic?("Bluetooth: dispositivo disconnesso")
    drop(peripheral.identifier)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard peers[peripheral.identifier] != nil, error == nil,
      let invitation,
      let service = peripheral.services?.first(where: {
        $0.uuid == CBUUID(nsuuid: invitation.sessionID)
      })
    else {
      drop(peripheral.identifier)
      return
    }
    peripheral.discoverCharacteristics([Self.upstream, Self.downstream], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    guard let invitation,
      invalidatedServices.contains(where: { $0.uuid == CBUUID(nsuuid: invitation.sessionID) })
    else { return }
    onDiagnostic?("Bluetooth: sessione del principale chiusa o riaperta")
    drop(peripheral.identifier)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard let peer = peers[peripheral.identifier], error == nil,
      let up = service.characteristics?.first(where: { $0.uuid == Self.upstream }),
      let down = service.characteristics?.first(where: { $0.uuid == Self.downstream }),
      up.properties.contains(.write), down.properties.contains(.notify)
    else {
      drop(peripheral.identifier)
      return
    }
    peer.upstream = up
    peer.downstream = down
    do {
      _ = try peer.channel.start()
      peripheral.setNotifyValue(true, for: down)
    } catch { drop(peer.id) }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard peers[peripheral.identifier] != nil else { return }
    if error != nil || !characteristic.isNotifying { drop(peripheral.identifier) }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard let peer = peers[peripheral.identifier], characteristic.uuid == Self.downstream else {
      return
    }
    guard error == nil, let value = characteristic.value else {
      drop(peer.id)
      return
    }
    do { try receive(value, from: peer) } catch {
      onDiagnostic?("Bluetooth: invito o pacchetto non valido")
      drop(peer.id)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard let peer = peers[peripheral.identifier], characteristic.uuid == Self.upstream else {
      return
    }
    guard error == nil else {
      drop(peer.id)
      return
    }
    peer.writing = false
    drain(peer)
  }
}

/// A retry of a full BLE transmit buffer must use the exact same chunk, without consuming it.
struct PassengerBluetoothQueue {
  static let maximum = PassengerFrameBuffer.maximum * 2
  private var packets: [Data] = []
  private var index = 0
  private var offset = 0
  private(set) var count = 0
  mutating func append(_ data: Data) throws {
    guard !data.isEmpty, data.count <= Self.maximum - count else { throw PassengerError.busy }
    packets.append(data)
    count += data.count
  }
  func next(maximum: Int) -> Data? {
    guard maximum > 0, index < packets.count else { return nil }
    return Data(packets[index].dropFirst(offset).prefix(maximum))
  }
  mutating func consume(_ amount: Int) {
    precondition(index < packets.count && amount > 0 && amount <= packets[index].count - offset)
    offset += amount
    count -= amount
    if offset == packets[index].count {
      index += 1
      offset = 0
      if index == packets.count || index >= 32 {
        packets.removeFirst(index)
        index = 0
      }
    }
  }
}
