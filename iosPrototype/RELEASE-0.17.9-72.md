# NoteNarrate YouTube Music 0.17.9 (72)

La scheda Chromecast nel blocco schermo e in Dynamic Island non viene piu
considerata attiva per il solo successo della registrazione. Il passaggio
da Now Playing locale alla sessione remota protegge i metadati esistenti,
li rimuove prima della promozione e li ripristina se il controllo principale
non viene ottenuto. Una sessione gia registrata viene recuperata dopo il
riavvio; il ritorno in primo piano e la fine della narrazione provocano una
nuova richiesta di controllo senza attendere la deduplicazione dei metadati.
La narrazione conserva la registrazione remota senza promuoverla.

Nuovo menu sempre presente: Impostazioni > Chromecast > Diagnostica Chromecast.
Mostra collegamento, registrazione e controllo principale della scheda,
ultimo comando, stato SDK/ricevitore, rete e narrazione. Comprende Copia
diagnostica, condivisione e Ripristina controlli; il ripristino interroga il
ricevitore e ripubblica la scheda senza ricaricare il brano. Nessuna chiave,
cookie o URL audio viene aggiunta al report. Nessun banner informativo.

37 test Core mirati superati, inclusi otto regressioni della sessione di
sistema: registrazione in background, promozione al ritorno, ordine del
passaggio, ripristino dopo errore o mancato controllo, adozione della sessione
corretta, perdita del controllo e recupero di un riferimento scaduto.
Due test UI superati: avvio e apertura ripetuta del player, accesso alla
diagnostica dedicata con report e ripristino disabilitato senza ricevitore.
La presentazione effettiva di Dynamic Island e blocco schermo e i comandi
richiedono conferma su iPhone e Chromecast reali: il simulatore non offre
il servizio remoto Now Playing. Il ponte audio non e stato sostituito.

App YouTube Music 6821630132, com.stivy.simpmusic.prototype; Apple Music
resta separata. Xcode 27.2 RC (27B48), SDK 27.2; minimi iOS 17 e Watch 10
invariati, estensione remota iOS 27. Distribuzione ai gruppi interni esistenti
Team interno e Stivy73 con verifica di Tommaso e Girbreda dopo elaborazione.

Archivio Release ed esportazione interna completati; firme e profili dei
sei bundle verificati, controllo dyld e framework superato, gruppi privati
del Portachiavi preservati e diagnostica condivisa isolata dalle credenziali.
IPA: deliveries/NoteNarrate-iOS-0.17.9-build72.ipa.
Archivio e simboli: deliveries/archives/NoteNarrate-0.17.9-build72.xcarchive.
SHA-256: `aeeec58e73dae6cf9c75c5af7d740a54fbd0d84df3a123a8e9bedd09fcc33ed6`.
Sorgenti: `d104a94804db5643d68af980b65939577790b96d`, pubblicati sul fork
stivy73/SimpMusic, branch feature/youtube-library-albums.
Upload ufficiale completato, delivery `f66c141f-1ead-408c-9810-789e0159ffe4`.
Validazione: deliveries/NoteNarrate-iOS-0.17.9-build72-validation.json.

Verifica Apple del 2026-11-14: VALID, INTERNAL_ONLY, IN_BETA_TESTING;
assegnata a Team interno e Stivy73. Confermati appartenenza al gruppo e
accesso app di Tommaso e Girbreda, note italiane salvate e rilette.
Ricevuta: deliveries/NoteNarrate-iOS-0.17.9-build72-AppStore-status.json.
