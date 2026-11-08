# NoteNarrate 0.17.0 (63)

Corregge la chiusura anticipata della sessione delle richieste audio, compatibile
con i due crash segnalati sulla build 62 nel caricamento dei blocchi. Le richieste
vengono cancellate e attese prima dell’invalidazione della sessione. I controlli
CDN, i limiti del buffer e la preparazione anticipata restano attivi.

Aggiunge Libreria → Caricamenti → Brani/Album e CarPlay → Preferiti → Caricamenti
personali, usando la sessione YouTube Music già selezionata. Carica tutte le pagine
e conserva metadati e vincolo dell’account proprietario in coda, ripristino,
preparazione e download. I brani personali non usano sorgenti anonime e non vengono
inviati a un diverso account tramite sessione passeggeri.

374 test core e la regressione UI Brani/Album superati. Compilazioni Debug per
simulatore e Release per iPhone riuscite con Xcode 27.2 RC (27B48), SDK 27.2.
Minimi iOS 17 / watchOS 10 invariati. Il test UI usa dati fittizi: resta da
collaudare la libreria privata reale e verificare l’assenza del crash sul Duo e
in CarPlay. [Analisi, verifiche e limiti](CRASH_AND_UPLOADS.md).

Archivio firmato, esportazione e upload Apple riusciti. Verifiche IPA CarPlay,
Siri, Widget, Share e firma Watch superate; versioni app/estensioni/Watch allineate.
Sorgenti: `b277e15d29026b39dc40ec61a8a4ffe8b3ea3482`, branch
`feature/youtube-library-albums` su `stivy73/SimpMusic`.
IPA: `deliveries/NoteNarrate-iOS-0.17.0-build63.ipa`.
SHA-256: `25f5bec371f20d1b1a1e393069578dd6d2b7e3b88a261dddbfd9b6648ac28fa8`.
Archivio e simboli conservati in
`deliveries/archives/NoteNarrate-0.17.0-build63.xcarchive`.

Elaborazione Apple **VALID**, stato interno **IN_BETA_TESTING**.
Associazioni a **Team interno** e **Stivy73** rilette via API. Appartenenza di
**Tommaso** e **Girbreda** al Team interno e accesso alla stessa app verificati.
Note beta italiane salvate. Nessuna modifica di utenti, ruoli, distribuzione
automatica o pubblicazione App Store.
Ricevuta: `deliveries/NoteNarrate-iOS-0.17.0-build63-AppStore-status.json`.
Verifiche del pacchetto: `deliveries/NoteNarrate-iOS-0.17.0-build63-validation.json`.
La disponibilità su TestFlight non costituisce prova del collaudo fisico ancora
necessario sui caricamenti privati e sul Duo/CarPlay.
