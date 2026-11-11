# NoteNarrate YouTube Music 0.17.5 (68)

Corregge le copertine strette nel player CarPlay dei brani avviati dal passeggero.
Il messaggio precedente perdeva la copertina dell'album e il principale la
sostituiva con `hqdefault.jpg`, miniatura del video con bande incorporate.
PassengerTrack ora trasporta il riferimento alla copertina pubblica originale;
PassengerBridge lo conserva sia in invio sia nella ricostruzione della coda.
Il normale percorso ArtworkSource/AppleArtworkStore usa cosi la stessa immagine
scelta sul telefono del passeggero.

Campo opzionale compatibile con il protocollo v1: i vecchi messaggi continuano
a decodificarsi, i vecchi client ignorano il nuovo campo. Per la correzione
completa aggiornare entrambi gli iPhone alla 68. Copertine limitate ai CDN
pubblici dei servizi supportati, HTTPS e massimo 512 byte per riferimento;
credenziali e indirizzi audio restano esclusi. Validazione anche dopo decoding.

28 test mirati Core superati: immagine originale attraverso JSON, compatibilita
con client precedenti, riferimenti non consentiti e selezioni da 500 brani.
Test UI sul bridge reale TLS passeggero-principale superato: copertina conservata
in coda e Play Now, selezioni atomiche, idempotenza e silenzio del passeggero.
Prova sul display fisico dell'auto ancora da confermare.

Archivio Release firmato con Xcode 27.2 RC (27B48), SDK 27.2. Versione/build
0.17.5 (68) su app, tre estensioni e Watch; minimi iOS17/watchOS10 invariati.
App di destinazione: NoteNarrate YouTube Music, App Store Connect 6821630132,
bundle com.stivy.simpmusic.prototype. La variante Apple Music resta separata.
Consegna TestFlight in preparazione.
