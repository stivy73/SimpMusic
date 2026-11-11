# NoteNarrate Apple Music

Variante nativa MusicKit separata dal target YouTube Music. Versione iniziale
0.1.0 (1), bundle `com.stivy.notenarrate.applemusic`, iOS 17 e watchOS 10.

## Implementato

- Autorizzazione Apple Music esplicita, ricerca brani nel catalogo, libreria
  brani/album/playlist con paginazione anche delle tracce delle raccolte.
- Riproduzione con ApplicationMusicPlayer, coda, seek, aggiunta alla libreria,
  condivisione link e selettore AirPlay di sistema.
- CarPlay con liste paginate e Now Playing; per il nuovo App ID resta necessario
  l'accesso CarPlay audio nel profilo di provisioning. Nessun entitlement
  CarPlay viene dichiarato finché non è concesso.
- Siri: riprendi, pausa, brano successivo tramite App Intents.
- Companion Watch: stato, trasporto, coda; interpretazione avviata da iPhone
  dopo conferma. Non riproduce musica in autonomia e non espone la radio YT.
- Interpretazione Gemini e voce Gemini/di sistema condivise con il progetto
  originale. Chiave Gemini nel Portachiavi dedicato a questa variante.
- Interpretazione recuperata da ShareNarrate: Gemini con Google Search usa
  solo titolo e artista; conserva fonti collegate ai passaggi e suggerimenti
  Google. Nessun recupero di testi musicali. Vedi [INTERPRETATION.md](INTERPRETATION.md).
- Adapter testi con licenza predisposto per un eventuale uso futuro, escluso
  dal flusso corrente: [LICENSED_LYRICS.md](LICENSED_LYRICS.md).

Il target usa una lista esplicita di sorgenti: non collega gli estrattori
YouTube, login/cookie YouTube, Google Cast SDK o server audio del vecchio target.
La condivisione di codice riguarda Gemini, audio voce e protocollo Watch.
La modifica Watch `#if !APPLE_MUSIC` conserva la radio nel target originale.

## Compilare

Aprire `NoteNarrateMusic.xcodeproj`, schema `NoteNarrateMusic`.

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer
xcodebuild -project iosAppleMusic/NoteNarrateMusic.xcodeproj \
  -scheme NoteNarrateMusic -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/NoteNarrateMusic-Build CODE_SIGNING_ALLOWED=NO build
swift test --package-path iosAppleMusic --scratch-path /tmp/NoteNarrateMusic-Contracts
```

Da root repository, `python3 iosAppleMusic/Scripts/generate_project.py`
rigenera progetto, schema e Info.plist. Le modifiche strutturali vanno mantenute
anche nel generatore. Endpoint testi: build setting `LICENSED_LYRICS_ENDPOINT`,
vuoto per default e non usato dalla ricerca del significato; nessuna chiave
fornitore deve essere incorporata nell'app.

## Prima della distribuzione

Non è ancora una release pronta per App Store. MusicKit è attivo sul nuovo App ID
e la beta firmata 0.1.0 (1) è stata distribuita al solo Stivy73. Mancano verifica live della ricerca Google,
privacy/support URL e metadati pubblici. Occorrono prove reali con account Apple
Music, gestione abbonamenti/accesso negato, AirPlay, Siri, Watch e CarPlay.
Non sono state migrate radio AI, ricezione share di raccolte da altri servizi,
connessione passeggeri o Chromecast; non vengono presentate come disponibili.

MusicKit è un App Service da attivare sull'App ID, non un entitlement inventato.
Riferimenti: [MusicKit](https://developer.apple.com/musickit/),
[configurazione App ID](https://developer.apple.com/help/account/services/musickit/),
[App Review](https://developer.apple.com/app-store/review/guidelines/).

Nessun upload TestFlight o invio pubblico viene eseguito dal generatore.
