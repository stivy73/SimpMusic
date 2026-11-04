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

## Preparazione TestFlight — 4 novembre 2026

Preflight API: ultima build 51 valida, sette membri Team interno conservati.
La build è destinata ai gruppi interni esistenti Team interno e Stivy73.
Archivio, firma, caricamento, elaborazione Apple e assegnazione saranno
registrati dopo verifica.
