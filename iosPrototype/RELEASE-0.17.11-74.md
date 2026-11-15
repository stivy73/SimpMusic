# NoteNarrate YouTube Music 0.17.11 (74)

Correzione dei percorsi audio delle Station: le sorgenti senza durata provano
prima HLS; una playlist live puo essere validata senza EXT-X-ENDLIST se il
contenuto ha durata sconosciuta e un target duration valido. Il segmento
corrente viene verificato; le playlist finite incomplete restano rifiutate.
I frammenti AAC di 1024 byte o meno non vengono dichiarati brani completi.
Lo stato live viene conservato nei fallback e nella diagnostica del player.

Diagnostica Chromecast: cronologia limitata a 24 eventi con ora, stato app,
richieste LOAD, cambi di stato ricevitore, fine brano e richiesta di avanzamento.
Non contiene titoli, indirizzi, URL audio o credenziali. La coda Chromecast
non e stata resa autonoma: la continuita a iPhone sospeso resta irrisolta.

33 test audio superati, comprese dirette HLS, playlist finite incomplete,
frammenti di inizializzazione AAC e fallback HLS fallito. Compilazione Debug
superata. Le Station effettive e il comportamento su Chromecast reale restano
 da verificare sui dispositivi. Nessun nuovo banner informativo.

Xcode 27.2 RC (27B48), SDK 27.2; minimi invariati. App YouTube Music 6821630132,
com.stivy.simpmusic.prototype, separata dalla variante Apple Music.
Distribuzione interna a Team interno e Stivy73 con verifica di Tommaso e Girbreda.
