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

## Preparazione TestFlight — 11 novembre 2026

Archivio Release firmato ed esportazione App Store Connect per soli interni
riusciti. IPA 0.1.0 (1), iPhone e Watch con versioni/companion ID allineati,
team 63W2ZKR3Z7, `get-task-allow=false` e `beta-reports-active=true` nei profili.
SHA256 IPA: `ec43076b9c8696269fa1ad5b89e510bdef85a2ead629c54c23c9bf0aafdaa85a`.
Artefatto: `iosAppleMusic/deliveries/0.1.0-1/NoteNarrateMusic.ipa` (escluso da Git).

L'utente ha richiesto espressamente solo Stivy73 per questa app: la richiesta
sostituisce l'assegnazione abituale a Team interno per questa consegna.
Gli altri gruppi dell'app YouTube Music non vengono modificati.
Scheda separata App Store Connect e attivazione MusicKit richiedono ancora
accesso Apple nel browser. Nessuna beta dichiarata disponibile prima della
verifica di upload, processing, assegnazione e tester effettivi.
