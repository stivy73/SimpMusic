# NoteNarrate iOS 0.15.1 (51)

Ripristino del mini player nativo CarPlay seguendo la configurazione di Vocalia:
mini player esplicitamente abilitato su iOS 27+, template Now Playing configurato
prima del template principale e controllo per evitare aperture duplicate del
player completo. Trasporto, coda e comandi musicali rimangono gestiti da CarPlay.

Implementazione: `7c80db4ec97e62ee131f2720c85c57d8a98ca3bc`.
App, estensione Condividi, widget ed estensione Siri: versione 0.15.1, build 51.
Minimo iOS 17 conservato. Toolchain Xcode 27.2 RC (27B48), SDK iOS 27.2.

Verifiche già completate sull'implementazione: 14 test core mirati, tre test UI
di regressione CarPlay (pagine Home/Album e ripristino dell'orologio musicale
dopo la narrazione), compilazioni Debug e Release. Il tocco sul mini player
nel display dell'auto resta da verificare. Dettagli in [CARPLAY.md](CARPLAY.md).

## Consegna TestFlight — 3 novembre 2026

Preflight API: ultima build Apple 50, elaborata; conservati i sette membri del
gruppo Team interno e la distribuzione interna manuale.

Archivio ed esportazione firmata API riusciti. App e tre estensioni riportano
0.15.1 (51), SDK 27.2. Verificati firma di distribuzione, CarPlay nella firma e
nel profilo, Siri/frasi italiane, widget, Condividi e App Group.

Sorgenti/versione/build dell'archivio: `727413baa768a9f40a2d5d9be199fcea7d0877ac`,
pubblicati e verificati sul fork personale `stivy73/SimpMusic`, branch
`feature/youtube-library-albums`.

IPA: `deliveries/NoteNarrate-iOS-0.15.1-build51-CarPlayMiniPlayer.ipa`.
SHA256: `2be01038b5309c0a4523630564a08a9f5d390ec82279b53c71ce9aefa879db87`.
Verifica firma: `deliveries/NoteNarrate-iOS-0.15.1-build51-CarPlayMiniPlayer-validation.json`.
Archivio: `/tmp/NoteNarrate-0.15.1-build51.xcarchive`.

Caricamento API riuscito (`Upload succeeded`, `EXPORT SUCCEEDED`). App Store
Connect conferma **VALID** e **IN_BETA_TESTING** per la build
`a94839c0-7bf0-476d-b385-cfadec758e3f`.
Gruppi assegnati e riletti: **Team interno** e **Stivy73**.
Verifica API indipendente completata il 3 novembre 2026 alle 11:21 Europe/Rome;
sette membri Team interno confermati.
Note beta italiane (`it`) salvate e rilette. Nessuna modifica a membri, ruoli o
distribuzione automatica; nessuna pubblicazione App Store.
Stato Apple: `deliveries/NoteNarrate-iOS-0.15.1-build51-CarPlayMiniPlayer-AppStore-status.json`.

La disponibilità della beta non dimostra l'installazione sui dispositivi né il
funzionamento del tocco sul mini player nel display dell'auto; il collaudo fisico
rimane da eseguire.
