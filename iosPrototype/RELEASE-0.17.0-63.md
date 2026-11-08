# NoteNarrate 0.17.0 (63)

Corregge la chiusura anticipata della sessione delle richieste audio, compatibile
con i due crash segnalati sulla build 62 nel caricamento dei blocchi. Le richieste
vengono cancellate e attese prima dell’invalidazione della sessione. I controlli
CDN, i limiti del buffer e la preparazione anticipata restano attivi.

Aggiunge Libreria → Caricamenti → Brani/Album e CarPlay → Preferiti → Caricamenti
personali, usando la sessione YouTube Music già selezionata. Carica tutte le pagine
e conserva metadati e vincolo dell’account proprietario in coda, ripristino,
preparazione e download. I brani personali non usano sorgenti anonime e non vengono
inviati a un diverso account tramite sessione passeggeri.

374 test core e la regressione UI Brani/Album superati. Compilazioni Debug per
simulatore e Release per iPhone riuscite con Xcode 27.2 RC (27B48), SDK 27.2.
Minimi iOS 17 / watchOS 10 invariati. Il test UI usa dati fittizi: resta da
collaudare la libreria privata reale e verificare l’assenza del crash sul Duo e
in CarPlay. [Analisi, verifiche e limiti](CRASH_AND_UPLOADS.md).

Consegna TestFlight in preparazione; il caricamento e le associazioni ai gruppi
verranno registrati dopo la conferma Apple.
