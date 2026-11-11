# NoteNarrate 0.17.3 (66)

Aggiunge al player i selettori AirPlay e Chromecast. AirPlay usa l’uscita audio
nativa di sistema; Chromecast integra GoogleCastDynamic 4.8.6 con Default Media
Receiver, controlli remoti e avanzamento automatico della coda.

Il ponte locale serve il brano corrente senza inviare cookie o indirizzi CDN
firmati al ricevitore. Per Chromecast occorrono la stessa rete Wi-Fi e l’app
aperta. La narrazione usa l’uscita dell’iPhone, anche AirPlay, e non il Chromecast.
Gli stream privi di alternativa AAC non sono supportati dal ponte. Disconnessione,
cambio uscita e fine brano conservano posizione e limite della durata sorgente.
[Dettagli e limitazioni](AIRPLAY_CAST.md).

Cinque test mirati superati: richieste HTTP reali, GET/HEAD, range attraverso
più blocchi, intervalli non validi, token errato e regressione QR CarPlay.
Compilazioni Debug e Release riuscite; archivio firmato con Xcode 27.2 RC (27B48),
SDK 27.2. Versione/build verificati su app, tre estensioni e Watch.
Minimi iOS 17 e watchOS 10 invariati. Ricevitori Chromecast e AirPlay fisici
ancora da verificare.

Consegna TestFlight in preparazione.
