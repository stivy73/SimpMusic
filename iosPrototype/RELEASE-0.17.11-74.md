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

Archivio Release ed esportazione interna completati. Firme e profili dei sei
bundle verificati, controllo dyld e framework superato.
IPA: deliveries/NoteNarrate-iOS-0.17.11-build74.ipa.
Archivio e simboli: deliveries/archives/NoteNarrate-0.17.11-build74.xcarchive.
SHA-256: `854c316752810beedad9bc327178b2ea3e8a80e8f41951a62d11a86fd67d67ee`.
Sorgenti: `99d30e2b7aee76059ba87e7df5b94e6ac5a6a981`, pubblicati su stivy73/SimpMusic,
branch feature/youtube-library-albums.
Validazione: deliveries/NoteNarrate-iOS-0.17.11-build74-validation.json.

Upload ufficiale completato al secondo tentativo dopo timeout del servizio
Apple; riutilizzata la stessa consegna 449d83c6-dae5-47bd-9c34-40ce3862ae1b.
Verifica Apple del 2026-11-15: VALID, INTERNAL_ONLY, IN_BETA_TESTING.
Assegnata a Team interno e Stivy73; appartenenza al gruppo e accesso app
confermati per Tommaso e Girbreda, note italiane salvate e rilette.
Ricevuta: deliveries/NoteNarrate-iOS-0.17.11-build74-AppStore-status.json.
