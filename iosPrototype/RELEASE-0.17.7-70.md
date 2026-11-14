# NoteNarrate YouTube Music 0.17.7 (70)

Chromecast: sessione Now Playing remota su iOS 27, con titolo, artista,
copertina, avanzamento e comandi Play/Pausa, posizione e volume al ricevitore.
La nuova estensione ExtensionKit controlla esclusivamente il dispositivo e
la sessione Cast gia selezionati; verifica il certificato fissato dall'app,
la sessione del ricevitore e l'identificativo del brano prima di inviare comandi.
Non riceve cookie, chiavi API o URL audio firmati. Il framework NowPlaying e
collegato debolmente: app iOS 17 e Watch watchOS 10 restano supportati; la nuova
estensione richiede iOS 27. L'interfaccia Now Playing locale resta attiva per
ascolto sul telefono, AirPlay e narrazione.

I tasti fisici volume dell'iPhone regolano relativamente il volume Chromecast
con app attiva, senza riportarlo bruscamente al livello del telefono. I vecchi
riscontri del ricevitore non annullano pressioni rapide. Al limite 0/100 del
volume iPhone usare il cursore Chromecast nell'app. Il volume locale viene
ripristinato quando si scollega Cast.

Il ponte audio corrente continua a richiedere NoteNarrate aperta. La scheda
Now Playing non e un meccanismo per impedire la sospensione o terminazione
dell'app. Nessun nuovo server o backend APNs fa parte di questa beta.

Destinazione: app YouTube Music 6821630132, com.stivy.simpmusic.prototype.
La variante Apple Music resta separata. Xcode 27.2 RC (27B48), SDK 27.2.

Verifica del servizio remoto: due tentativi su simulatore iOS 27.2 hanno
restituito internalFailure. Il log di mediaremoted documenta
`MRXPCServiceNowPlayingSessions ... server is not available` e
`RemoteSessionEligibilityMonitor ... notEligible`. Il test di registrazione
resta disponibile per iPhone fisico ed esplicitamente saltato sul simulatore.
L'iPhone associato al Mac risulta offline. La scheda e i comandi verso un
Chromecast reale richiedono verifica fisica nella beta; non sono dichiarati
collaudati sulla base della sola compilazione.

Artefatti previsti: deliveries/NoteNarrate-iOS-0.17.7-build70.ipa e
deliveries/archives/NoteNarrate-0.17.7-build70.xcarchive, con ricevute
separate per validazione, upload, elaborazione Apple e accesso tester.

Archivio Release compilato e firmato. Verifica dyld superata: NowPlaying
e weak-linked nell'app e l'estensione non carica GoogleCast.framework.
23 test Core superati senza errori; due test UI superati (avvio e apertura
del player ripetuta, QR artwork e ripristino della copertina). Un test UI
di registrazione del servizio remoto saltato per il limite del simulatore
documentato sopra. Nessuna prova fisica Chromecast dichiarata.
