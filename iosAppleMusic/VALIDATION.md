# Verifica iniziale — 11 novembre 2026

- Debug iPhone Simulator, incluso companion Watch: BUILD SUCCEEDED.
- Release generico iPhone + Watch, firma disattivata: BUILD SUCCEEDED.
- Test SwiftPM contratto testi e routine ShareNarrate: 12 eseguiti, 0 fallimenti.
- Installazione/avvio nel simulatore iPhone 17 iOS 27.2: processo avviato
  ancora attivo al controllo successivo, senza crash immediato.
- Dipendenze binario Release: MusicKit, CarPlay e WatchConnectivity presenti;
  Google Cast assente. Nessun pacchetto estrazione/login YouTube nel progetto.
- Orientamenti iPad e localizzazione App Intents corretti nella verifica finale.

Artefatti locali non versionati:

- `/tmp/NoteNarrateMusic-Build/Build/Products/Debug-iphonesimulator/NoteNarrateMusic.app`
- `/tmp/NoteNarrateMusic-Release/Build/Products/Release-iphoneos/NoteNarrateMusic.app`
- `/tmp/NoteNarrateMusic-build.log`, `/tmp/NoteNarrateMusic-release.log`,
  `/tmp/NoteNarrateMusic-tests.log`.

Il test di avvio non verifica l'interfaccia completa né la riproduzione protetta.
Restano da verificare su dispositivi reali MusicKit con account autorizzato,
CarPlay, AirPlay, Watch e Siri. Nessun servizio testi live né richiesta Google live è stato contattato.
- Routine ShareNarrate: prompt, fonti associate al testo, suggerimenti Google,
  fallback in assenza di grounding, URL HTTPS e parti thought verificati con fixture.
Nessun archivio firmato, upload TestFlight o invio App Store eseguito.
