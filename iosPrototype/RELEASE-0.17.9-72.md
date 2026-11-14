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
