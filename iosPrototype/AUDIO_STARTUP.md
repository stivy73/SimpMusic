# Preparazione anticipata — candidata successiva alla build 61

La preparazione viene spostata prima della selezione, invece di nascondere lo
stato di caricamento. Mentre il brano corrente suona viene preparato il successivo
nella coda effettiva, anche con crossfade disattivato. Aprendo un album a player
fermo viene preparata la prima traccia; un ascolto già attivo mantiene priorità
sul successore della coda. È conservato un solo player anticipato, silenzioso.

Il player anticipato conserva la sorgente già verificata, lo stesso range loader,
il buffer e l’AVPlayerItem. Il preroll AVFoundation prepara i primi campioni senza
avviare l’audio. Avanti e fine brano promuovono quel player, senza una seconda
risoluzione o ricostruzione. Una preparazione ancora in corso viene condivisa.
Pausa e narrazione mantengono il successore silenzioso; modifica della coda,
recupero o cambio del contesto lo invalidano.

Il riuso richiede sessione completa, revisione account, qualità e revisione di
rete identiche. Scadenza massima 120 secondi, con almeno 30 secondi residui per
un indirizzo firmato. Account, cookie, indirizzi e audio anticipato restano solo
in memoria. Non si anticipa l’intero catalogo. Il loader conserva al massimo
32 blocchi da 128 KiB; AVFoundation decide quali intervalli leggere per l’indice
e il preroll. Nessun limite sul traffico è dedotto dal solo limite di memoria.
I controlli iniziale/oltre 1 MiB/finale o HLS restano invariati; anche un player
promosso mantiene diagnostica e recupero 403, isolati con un token per loader.

Un brano mai preparato richiede comunque la rete: questa modifica non garantisce
un avvio istantaneo per una selezione arbitraria a freddo o con rete assente.

Misura pubblica, una singola osservazione sul Mac con uscita muta, usando
**Ma perché (114 BPM Mix) / 883**, durata 252 secondi. Stessa soglia di avanzamento
(0,02 s) e osservazione ogni 10 ms: **1,92 s a freddo**, includendo risoluzione e
controlli, contro **0,110 s dal comando di avvio a player già preparato**. Il lavoro
precedente all’avvio caldo è escluso e resta necessario: non è una riduzione a
zero del tempo di rete. Avanzamento di 101,28 s durante un’attesa di almeno 95 s,
senza blocchi oltre il primo minuto. Sono misure AVFoundation, non latenza acustica
sul Duo o nell’auto, e non medie né tempi garantiti su rete cellulare.

Riproduzione della prova:
`swift run --package-path iosPrototype NetworkProbe --audio-startup-warm 'Ma perché 114 BPM Mix 883'`.
Log finale: `/tmp/nn-warm-live-final.log`.

Verifiche candidate: 72 test core superati, compilazioni Debug/simulatore e
Release/iPhone riuscite con Xcode 27.2 RC / SDK 27.2. Tre nuove regressioni UI
superate: Avanti a player pronto con crossfade disattivato, Avanti durante la
preparazione condivisa, pausa che conserva il successore silenzioso fino al
comando esplicito. Il conteggio delle attese condivise distingue il riuso da un
nuovo caricamento. Log `/tmp/nn-warm-ui4.log`, risultato
`/tmp/NoteNarrate-Warm-UI4.xcresult`; core `/tmp/nn-warm-core.log`, Release
`/tmp/nn-warm-release.log`. Candidata non ancora distribuita su TestFlight;
comportamento fisico sul Duo e in CarPlay ancora da collaudare.

---

# Avvio audio e ripresa dei brani lunghi — 4 novembre 2026

Ottimizzazione distribuita nella beta interna **0.15.2 (52)**, il 4 novembre 2026,
per **Team interno** e **Stivy73**. [Consegna e sorgenti](RELEASE-0.15.2-52.md).

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
senza attesa della coda silenziosa. Caricamento TestFlight, elaborazione e gruppi
verificati per la build 52. Nessuna nuova installazione fisica dichiarata;
i tempi sul Duo e sul display dell'auto restano da provare.

Log core: `/tmp/notenarrate-startup-core.log`.
Log UI: `/tmp/notenarrate-startup-ui.log`.
Risultati UI: `/tmp/NoteNarrate-Startup-UI.xcresult`.
Log Release: `/tmp/notenarrate-startup-release.log`.
