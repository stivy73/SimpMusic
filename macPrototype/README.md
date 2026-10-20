# NoteNarrate per macOS

Porting nativo SwiftUI di NoteNarrate iOS. Target `NoteNarrateMac`, macOS 14 o successivo.
La distribuzione 0.1.0 è universal (Apple silicon e Intel), firmata Developer ID e notarizzata.

## Funzioni

- Home YouTube Music con generi, stati d'animo, sezioni personali dopo login e continuation.
- Ricerca, album remoti e preferiti locali distinti, usando la stessa pipeline iOS.
- Player con copertina, video opzionale, seek, volume, coda, testi, copia e condivisione.
- Barra laterale Home/Cerca/Libreria/Impostazioni e mini-player persistente.
- Interpretazione italiana: storia raccontata dal testo e significato, circa 900 caratteri ±5%.
- Lettura automatica: voce italiana macOS oppure Gemini TTS espressivo, streaming PCM e cache.
- La musica viene messa in pausa durante l'interpretazione e riprende alla fine o allo stop.
- Fallback LRCLIB se YouTube Music non restituisce testo o la richiesta fallisce. La fonte è
  indicata nella vista Testo; niente interpretazioni basate soltanto sul titolo.

## Architettura condivisa

Il progetto `NoteNarrateMac.xcodeproj` referenzia direttamente `../iosPrototype/Sources/Core`
e `../iosPrototype/Sources/App`. Non contiene copie di parser, prompt, client IA, cache o
resolver testi. `Sources/MacApp.swift` aggiunge soltanto finestra, navigazione desktop e menu.
I bridge condizionali `os(macOS)` nei sorgenti condivisi adattano NSViewRepresentable,
Portachiavi, clipboard e toolbar. AVAudioSession rimane limitata a iOS; macOS usa
AVSpeechSynthesizer e AVAudioEngine della stessa pipeline di lettura.

LRCLIB è interrogato con titolo e artista; i risultati sono verificati per entrambi. Se la
durata è nota viene applicata la tolleranza Android di 10 secondi. Titoli con suffissi tecnici
come Remaster/Official Audio vengono normalizzati, preservando Live/Acoustic e sottotitoli
significativi. Record strumentali, vuoti o non pertinenti vengono scartati. Il testo plain è
preferito; quando è disponibile soltanto LRC vengono rimossi timestamp e metadati per
l'interpretazione. Non si simula la sincronizzazione dei versi nella UI. Cancellazione,
errori HTTP, risposte malformate, Retry-After e cambio brano sono gestiti dal resolver condiviso.

Il WKWebView del player resta montato quando si torna al mini-player o si cambia sezione.
`inactiveSchedulingPolicy = .none` evita la sospensione delle attività del player inattivo;
la posizione è letta dal media reale, non stimata. I limiti di incorporamento restano quelli
di YouTube; questo porting non aggiunge estrazione di stream audio o download.

Il Bundle ID macOS è `com.stivy.notenarrate.mac`. Preferenze, cache e Portachiavi Mac sono
separati dall'installazione iOS; non vengono copiati automaticamente account o chiavi.
La sessione Google e la chiave Gemini vanno inserite nelle Impostazioni della versione Mac.
Al primo avvio Gemini TTS è attivo con stile Empatico e voce Aoede; le preferenze già
salvate hanno precedenza su questi valori iniziali.

## Comandi

Apri `NoteNarrateMac.xcodeproj`, seleziona `NoteNarrateMac` e `My Mac` in Xcode.

```sh
xcodebuild -project NoteNarrateMac.xcodeproj -scheme NoteNarrateMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/notenarrate-mac-build CODE_SIGNING_ALLOWED=NO build
cd ../iosPrototype
swift test
```

Scorciatoie: ⌘1 Home, ⌘2 Cerca, ⌘3 Libreria, ⌘4 Player, ⌘0 Mostra finestra,
⌘Spazio Pausa/Riprendi, ⌘←/⌘→ precedente/successivo, ⇧⌘I Significato, ⌘, Impostazioni.

## Consegna e licenze

Il pacchetto `../deliveries/NoteNarrate-macOS-0.1.0-universal-notarized.zip` usa la firma
Developer ID Application di Archetipi Digitali srl. Il ticket Apple è allegato all'app;
firma, hardened runtime, timestamp, sandbox e Gatekeeper sono verificati su entrambe le
architetture e sulla copia estratta dallo ZIP. Non è una pubblicazione sul Mac App Store.

Per riprodurre l'invio, crea un archive Release con la firma Apple Development aziendale,
poi esegui `xcodebuild -exportArchive -archivePath <archive> -exportPath <staging>
-exportOptionsPlist NotarizeOptions.plist -allowProvisioningUpdates`. L'account Xcode deve
avere accesso al Developer ID cloud-managed del Team. Una volta accettato da Apple,
`sh Scripts/FinishNotarization.sh <archive>` esporta e verifica il pacchetto senza reinviarlo.
Lo script rifiuta di sovrascrivere lo ZIP finale. `BuildMac.sh` resta una build locale di sviluppo.
I risultati effettivi e i limiti del collaudo sono in VERIFICATION.md.

Il porting resta GPL-3.0, come il progetto originale: vedi `../LICENSE`.
YouTubeSDK mantiene licenza MIT, inclusa nei sorgenti e nella schermata Licenze dell'app.
Sviluppo realizzato con assistenza IA/vibecoding.
