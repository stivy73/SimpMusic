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

IPA esportata e verificata: firma di distribuzione, framework Google Cast
incorporato, CarPlay, Siri, Widget, Share e companion Watch.
Sorgenti sul fork `stivy73/SimpMusic`, branch `feature/youtube-library-albums`,
commit `9f1032e05a18256d245baed5a3af815427c6aa81`.

IPA: `deliveries/NoteNarrate-iOS-0.17.3-build66.ipa`.
SHA-256: `1be38a5ce2fa08d993d2ad9aeea62b31f6086695c006bbd75168a54db5b2bf6f`.
Archivio e simboli: `deliveries/archives/NoteNarrate-0.17.3-build66.xcarchive`.
Verifiche: `deliveries/NoteNarrate-iOS-0.17.3-build66-validation.json`.

Upload Apple completato senza errori, delivery/build UUID
`9d903840-b60c-418c-9d27-5ae74109bc16`. Build resa disponibile agli interni.

L'11 novembre il report del Duo ha identificato un crash immediato all'avvio:
`DYLD 1 Library missing`, `@rpath/GoogleCast.framework/GoogleCast`.
Il framework era incorporato e firmato, ma mancava il percorso
`@executable_path/Frameworks` nell'eseguibile. La firma non rilevava questo difetto.
La build 67 corregge il percorso e aggiunge verifiche di caricamento e avvio reale.
