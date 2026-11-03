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

## Preparazione TestFlight — 3 novembre 2026

Preflight API: ultima build Apple 50, elaborata; conservati i sette membri del
gruppo Team interno. Build 51 destinata ai gruppi esistenti Team interno e
Stivy73, con distribuzione interna manuale. Archivio, firma, caricamento,
elaborazione Apple e assegnazione saranno registrati dopo verifica.
