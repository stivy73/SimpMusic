# NoteNarrate iOS 0.15.2 (52)

Avvio audio e ripresa dei brani lunghi più rapidi: preferenza HLS per la
riproduzione oltre dieci minuti, playlist accettate fino a 4 MiB, durata remota
senza scansione iniziale e collegamento degli effetti quando il player è pronto.
La diagnostica distingue i tempi di sorgente, buffer, player e ripristino della
posizione. Il fallback AAC conserva i controlli su inizio, oltre 1 MiB e fine;
i download conservano la preferenza AAC.

Implementazione: `faa171350a3a5ffd639dfeff25dad3e6766ba401`.
App, estensione Condividi, widget ed estensione Siri: versione 0.15.2, build 52.
Minimo iOS 17 conservato. Toolchain Xcode 27.2 RC (27B48), SDK iOS 27.2.

Verifiche dell'implementazione: 52 test core, sei regressioni UI su iPhone 18 Pro
/ iOS 27.2, compilazioni Debug e Release. Su Oceanic Delta Waves la prova Mac
passa da 7,98 a 3,65 secondi per l'avvio; ripresa HLS a 22:08 in 8,18 secondi.
Le prove di streaming proseguono per 95 secondi; tempi su rete cellulare e Duo
ancora da verificare. [Misure e limiti](AUDIO_STARTUP.md).

## Consegna TestFlight — 4 novembre 2026

Preflight API: ultima build 51 valida, sette membri Team interno conservati.
La build è distribuita ai gruppi interni esistenti Team interno e Stivy73.
Caricamento API riuscito il 4 novembre 2026 alle 13:55 Europe/Rome
(`Upload succeeded`, `EXPORT SUCCEEDED`). App Store Connect conferma **VALID**
e **IN_BETA_TESTING** per la build `eac33705-6992-4fb3-839e-70c615e93fa1`.
Gruppi assegnati e riletti: **Team interno** e **Stivy73**. Note beta italiane
(`it`) salvate e rilette. Nessuna modifica a membri, ruoli o distribuzione
automatica; nessuna pubblicazione App Store.
Verifica API indipendente completata il 4 novembre 2026 alle 14:04 Europe/Rome;
sette membri Team interno confermati.

Archivio ed esportazione API riusciti. Verificati firma di distribuzione,
CarPlay nella firma e nel profilo, Siri/frasi, widget, Condividi e App Group.
App e tre estensioni riportano tutte 0.15.2 (52), SDK 27.2.

Sorgenti/versione/build dell'archivio: `cfb7dfbccba342de7cd0caaa5a8a1875e4cbb00a`,
pubblicati e verificati su `stivy73/SimpMusic`, branch
`feature/youtube-library-albums`.

IPA: `deliveries/NoteNarrate-iOS-0.15.2-build52-AudioStartup.ipa`.
SHA256: `ce9e467431b48227bf280a41943103df4200b9a7ee0fa4ce620162c56e56e249`.
Verifica firma: `deliveries/NoteNarrate-iOS-0.15.2-build52-AudioStartup-validation.json`.
Archivio: `/tmp/NoteNarrate-0.15.2-build52.xcarchive`.

Stato Apple: `deliveries/NoteNarrate-iOS-0.15.2-build52-AudioStartup-AppStore-status.json`.
La disponibilità della beta non dimostra l'installazione sui dispositivi dei
tester o i tempi effettivi sul Duo e in auto; il collaudo fisico resta da eseguire.
