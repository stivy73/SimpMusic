# Avvio audio e ripresa dei brani lunghi — 4 novembre 2026

Ottimizzazione successiva alla beta 0.15.1 (51), ancora da distribuire.

La prova pubblica su **Oceanic Delta Waves / Jason Stephenson**, durata 3839 s,
ha riprodotto due attese: scansione del file AAC frammentato da 62.132.786 byte
per leggere durata/tracce e rifiuto della playlist HLS, che occupa circa 724 KB
e superava il vecchio limite di 512 KiB. Il ritorno all'AAC causava altre letture
prima dell'avvio, soprattutto riprendendo da una posizione avanzata.

## Modifica

La riproduzione e la preparazione della transizione preferiscono HLS per i brani
di almeno dieci minuti, quando disponibile e validato. Le playlist restano
limitate a 4 MiB; i segmenti iniziale, successivo al minuto e finale sono
verificati prima dell'uso. Se HLS fallisce, l'AAC conserva tutti i controlli su
inizio, confine 1 MiB e fine. La risoluzione per i download mantiene l'ordine AAC.

Per lo streaming con durata della sorgente valida si imposta subito il termine
della riproduzione di quel video. Non si attendono `.duration`, `.timeRange` e
`.segments` dell'asset remoto. L'item omette anche il caricamento automatico della
durata; gli effetti si collegano alle tracce disponibili quando il player è pronto.
File locali e sorgenti senza durata mantengono la verifica della timeline reale,
inclusa la protezione dai contenitori con silenzio finale.

Il comportamento del caricamento automatico è documentato nell'
[API Apple di AVPlayerItem](https://developer.apple.com/documentation/avfoundation/avplayeritem/1588088-playeritemwithasset)
e nell'header `AVPlayerItem.h` dell'SDK 27.2: l'inizializzatore predefinito include
`duration` tra le chiavi da caricare prima di `readyToPlay`.

La diagnostica aggiunge tempi monotoni per sorgente verificata, primo buffer,
durata, player pronto, posizione ripristinata e riproduzione avviata. Il report
resta limitato a 96 righe e non contiene indirizzi firmati, cookie o chiavi.

## Misure reali sul Mac

Prove pubbliche senza account, con AVFoundation e uscita muta, sulla stessa
connessione. Sono singole osservazioni, non medie o tempi garantiti su cellulare.

| Percorso | Attesa prima dell'avanzamento audio | Avanzamento in 95 s |
| --- | ---: | ---: |
| Codice precedente, avvio AAC | 7,98 s | 97,54 s |
| Nuovo avvio HLS | 3,65 s | 95,45 s |
| Candidata AAC, ripresa a 22:08 | 20,32 s | 91,08 s |
| Nuova ripresa HLS a 22:08 | 8,18 s | 97,25 s |

La candidata AAC della terza riga aveva già rimosso le letture esplicite della
timeline; il confronto di ripresa isola il beneficio del percorso HLS e non è
una misura della beta 51. Le prove attraversano il primo minuto senza lo stop
a 0:59. L'orologio AVFoundation e quello reale possono divergere leggermente.

Log: `/tmp/notenarrate-startup-baseline.log`,
`/tmp/notenarrate-startup-hls-final.log`, `/tmp/notenarrate-startup-resume.log`,
`/tmp/notenarrate-startup-resume-final.log`.

Riproduzione delle misure:

```sh
swift run --scratch-path /tmp/NoteNarrate-Startup-Core NetworkProbe --audio-startup 'Oceanic Delta Waves Jason Stephenson'
swift run --scratch-path /tmp/NoteNarrate-Startup-Core NetworkProbe --audio-startup-resume 1328 'Oceanic Delta Waves Jason Stephenson'
```

`--audio-layout` legge solo le intestazioni degli atomi MP4 e stampa tipo,
offset e dimensione; `--audio-timing` conserva l'ispezione approfondita esplicita.

## Verifiche

Superati 52 test core mirati: preferenza HLS, playlist oltre il vecchio limite,
limite massimo, fallback AAC con controllo completo, ordine dei download,
durata locale/remota, buffer, recupero e sessione. Compilazioni Debug/simulatore
e Release/iPhone con Xcode 27.2 RC (27B48), SDK 27.2 e minimo iOS 17.

Superate sei regressioni UI su iPhone 18 Pro / iOS 27.2: narrazione CarPlay,
crossfade con pausa, continuità oltre il minuto con conteggio PCM degli effetti,
sessione ripristinata in pausa, recupero alla posizione corrente e fine brano
senza attesa della coda silenziosa. Nessuna nuova installazione fisica o beta
TestFlight dichiarata; i tempi sul Duo e sul display dell'auto restano da provare.

Log core: `/tmp/notenarrate-startup-core.log`.
Log UI: `/tmp/notenarrate-startup-ui.log`.
Risultati UI: `/tmp/NoteNarrate-Startup-UI.xcresult`.
Log Release: `/tmp/notenarrate-startup-release.log`.
