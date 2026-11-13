# Verifica iniziale — 11 novembre 2026

- Debug iPhone Simulator, incluso companion Watch: BUILD SUCCEEDED.
- Release generico iPhone + Watch, firma disattivata: BUILD SUCCEEDED.
- Test SwiftPM contratto testi e routine ShareNarrate: 12 eseguiti, 0 fallimenti.
- Installazione/avvio nel simulatore iPhone 17 iOS 27.2: processo avviato
  ancora attivo al controllo successivo, senza crash immediato.
- Dipendenze binario Release: MusicKit, CarPlay e WatchConnectivity presenti;
  Google Cast assente. Nessun pacchetto estrazione/login YouTube nel progetto.
- Orientamenti iPad e localizzazione App Intents corretti nella verifica finale.

Artefatti locali non versionati:

- `/tmp/NoteNarrateMusic-Build/Build/Products/Debug-iphonesimulator/NoteNarrateMusic.app`
- `/tmp/NoteNarrateMusic-Release/Build/Products/Release-iphoneos/NoteNarrateMusic.app`
- `/tmp/NoteNarrateMusic-build.log`, `/tmp/NoteNarrateMusic-release.log`,
  `/tmp/NoteNarrateMusic-tests.log`.

Il test di avvio non verifica l'interfaccia completa né la riproduzione protetta.
Restano da verificare su dispositivi reali MusicKit con account autorizzato,
CarPlay, AirPlay, Watch e Siri. Nessun servizio testi live né richiesta Google live è stato contattato.
- Routine ShareNarrate: prompt, fonti associate al testo, suggerimenti Google,
  fallback in assenza di grounding, URL HTTPS e parti thought verificati con fixture.
Nessun archivio firmato, upload TestFlight o invio App Store eseguito.

## Preparazione TestFlight — 11 novembre 2026

Archivio Release firmato ed esportazione App Store Connect per soli interni
riusciti. IPA 0.1.0 (1), iPhone e Watch con versioni/companion ID allineati,
team 63W2ZKR3Z7, `get-task-allow=false` e `beta-reports-active=true` nei profili.
SHA256 IPA: `ec43076b9c8696269fa1ad5b89e510bdef85a2ead629c54c23c9bf0aafdaa85a`.
Artefatto: `iosAppleMusic/deliveries/0.1.0-1/NoteNarrateMusic.ipa` (escluso da Git).

L'utente ha richiesto espressamente solo Stivy73 per questa app: la richiesta
sostituisce l'assegnazione abituale a Team interno per questa consegna.
Gli altri gruppi dell'app YouTube Music non vengono modificati.
Scheda separata App Store Connect e attivazione MusicKit richiedono ancora
accesso Apple nel browser. Nessuna beta dichiarata disponibile prima della
verifica di upload, processing, assegnazione e tester effettivi.

## Distribuzione completata — 11 novembre 2026

Nuova app **NoteNarrate Music**, Apple ID `6833455204`, bundle
`com.stivy.notenarrate.applemusic`. Separata da NoteNarrate YouTube Music,
Apple ID `6821630132`, i cui tester/gruppi non sono stati modificati.

Upload API riuscito; build ID `f5516708-491d-46cf-b360-379246197a90`:
`VALID` / `IN_BETA_TESTING`, versione 0.1.0 (1), audience solo interni.
Assegnato soltanto il gruppo **Stivy73**, distribuzione manuale
(`hasAccessToAllBuilds=false`), un tester interno, stato UI **Invitato**.
La ricevuta email e l'installazione effettiva restano verifiche del tester.
Note italiane beta caricate. Nessun gruppo Team interno associato per questa
consegna, secondo la richiesta esplicita di test personale.

MusicKit attivato e riletto selezionato in App Services per l'App ID nuovo.
La bozza App Store 0.1.0 resta `PREPARE_FOR_SUBMISSION`, rilascio `MANUAL`:
nessun invio alla review pubblica e nessuna pubblicazione.

Sorgenti e configurazione beta sincronizzati su `stivy73/SimpMusic`, branch
`codex/apple-music`, commit sorgente di consegna `b91ea6b5`.
Il timeout della prima assegnazione API è stato risolto rileggendo lo stato e
usando la relazione build→gruppo; l'API e la UI hanno confermato il risultato.

## Correzione accesso MusicKit — build 0.1.0 (2)

Segnalazione reale: ricerca «Seal» con `developerTokenRequestFailed` e libreria
vuota. Verificato in Apple Developer il bundle `com.stivy.notenarrate.applemusic`
e MusicKit selezionato in App Services. Il messaggio identifica un fallimento
nel recupero del token sviluppatore; non dimostra assenza di abbonamento.
La causa remota del rifiuto Apple non è ancora confermata da un test fisico.

Individuato un difetto locale: `refresh()` verificava prima MusicSubscription e
saltava tutte le richieste libreria quando questa verifica falliva. Ora brani,
album e playlist vengono letti prima e con errori indipendenti; un errore token
non viene presentato come abbonamento assente.

Ricerca e verifica abbonamento tentano un solo rinnovo sviluppatore con l'opzione
MusicKit ufficiale `.ignoreCache`, poi ripetono la richiesta una volta. Gli errori
consenso non attivano questo recupero. Il comando manuale Ripristina collegamento
è disponibile in Impostazioni con report condivisibile di fasi/domain/code e
conteggi, senza token, chiavi, risposte HTTP o titoli della libreria.

Verifiche: 16 test passati, build Debug riuscita, app persistente nel simulatore,
archivio Release iPhone/Watch firmato riuscito. MusicKit con account reale non
verificabile nel simulatore: attendere il test iPhone e il report prima di
considerare risolto il rifiuto remoto del token.

Riferimenti Apple:
https://developer.apple.com/documentation/musickit/musictokenrequesterror/developertokenrequestfailed
https://developer.apple.com/documentation/musickit/musictokenrequestoptions/ignorecache

Build 2 distribuita su TestFlight: `VALID` / `IN_BETA_TESTING`, build ID
`92398806-dd46-4b20-bd19-16f72a957767`. Confermati soltanto il gruppo interno
Stivy73 (manuale), un tester e note italiane. Lo stato INSTALLED del tester si
riferisce all'app e non prova che abbia già installato e verificato la build 2.
Il test reale del recupero token rimane da confermare dal dispositivo.

IPA: `iosAppleMusic/deliveries/0.1.0-2/NoteNarrateMusic.ipa` (esclusa da Git).
SHA256: `a853e999aa9a1f0cb768e2e2f6e94656d3c81fd20a739a76e63e0fa8c25dc722`.
Commit sorgente: `8a086e0b`, sincronizzato sul branch personale `codex/apple-music`.
Nessuna modifica all'app NoteNarrate YouTube Music o ai suoi gruppi.

## Playlist e preparazione audio — build 0.1.0 (3)

Dati reali build 2: catalogo e rinnovo token funzionanti, libreria nativa con
0 brani/0 album/6 playlist; errore `MPMusicPlayerControllerErrorDomain 6` durante
un tentativo di riproduzione. Il codice 6 riguarda la preparazione audio e non
prova un fallimento token. Il report precedente non registrava le fasi playback.

Modifica: album e playlist sono passati al player come contenitori MusicKit
originali (`Queue(for:[playlist])` / `[album]`), eliminando lettura completa e
conversione di tutte le tracce in Song prima di avviare. Preparazione e avvio
espliciti, log separati per sessione/preparazione/play, conteggi e presenza dei
parametri, prevenzione degli avvii sovrapposti. I comandi successivo/precedente
e ripresa registrano anch'essi gli errori. Nessun ID, titolo o token nel report.

Lettura libreria con includeOnlyDownloadedContent=false esplicito. Aggiunta
Verifica libreria cloud: tre GET MusicDataRequest ufficiali, limit=1, in sola
lettura; nessun download/import/modifica. I conteggi campione vengono marcati
come prima pagina, non come totali. Status di autenticazione, errori e risposte
non valide non vengono trasformati in librerie vuote.

Verifiche locali: 20 test passati, Debug riuscita, avvio persistente simulatore,
archivio Release iPhone/Watch firmato riuscito. La riproduzione reale e l'origine
dei conteggi libreria restano da confermare sul dispositivo; non dichiarare
risolto definitivamente il codice 6 sulla sola base della compilazione.

Riferimenti Apple: https://developer.apple.com/videos/play/wwdc2026/254/
https://developer.apple.com/documentation/applemusicapi/get-all-library-songs
https://developer.apple.com/documentation/applemusicapi/get-all-library-playlists

Build 3 distribuita: `VALID` / `IN_BETA_TESTING`, ID
`73f2ce57-41cc-4dff-a02d-d21c31d719db`, app separata `6833455204`. Riletti
solo gruppo Stivy73, distribuzione manuale, un tester. Note italiane caricate.
Lo stato INSTALLED è dell'app e non verifica il test della build 3.

IPA: `iosAppleMusic/deliveries/0.1.0-3/NoteNarrateMusic.ipa`.
SHA256: `9c680f223b6e2b812892f4adbed3642dde886cbf1757926791f7ce94a2710973`.
Commit sorgente `d864eefd`, sincronizzato nel fork personale. Resta da provare
la stessa playlist sul dispositivo e condividere il report dopo il tentativo
se l'errore persiste; per la libreria eseguire la verifica cloud in sola lettura.

## Libreria cloud completa — build 0.1.0 (4)

Report reale build 3: richieste native 0 brani, 0 album, 6 playlist. Probe cloud
HTTP 200: songs prima pagina 0 senza next; albums prima pagina 1 senza next;
playlists prima pagina 1 con next. Dimostrata una differenza tra la risposta
MusicLibraryRequest locale e la risorsa album disponibile nell'account cloud.

Implementata lettura di `/v1/me/library/songs`, `/albums`, `/playlists` con
MusicDataRequest e token gestiti da MusicKit. Limite 100 per pagina e lettura di
ogni next; URL successivi ammessi solo sullo stesso endpoint HTTPS Apple, senza
credenziali nel codice, cambio host/risorsa, frammenti o cicli. La raccolta viene
applicata solo a caricamento completo; errori HTTP/malformati non equivalgono a
una libreria vuota. Contenuti cloud decodificati nelle strutture MusicKit native,
senza ricostruire ID o parametri opachi di riproduzione. Si preferisce il valore
cloud per gli ID condivisi e si conservano gli elementi presenti solo sul device.
La lettura locale resta disponibile se il caricamento cloud fallisce.

Verifiche: 30 test passati, inclusi pagine multiple, duplicati, pagina successiva
fallita, URL esterni/risorsa diversa, ciclo, annullamento, risposta vuota valida,
merge con playlist locali e decoder reale MusicKit per album, brani e playlist
fittizi con playParameters. Debug compilato; archivio finale Release firmato.
Il risultato sulla libreria reale richiede verifica iPhone dopo l'aggiornamento.

Build 4 distribuita: `VALID` / `IN_BETA_TESTING`, ID
`c5440a8e-9d05-4924-857a-ab04bd65ce8e`, app separata `6833455204`.
Riletti gruppo assegnato Stivy73 soltanto, distribuzione manuale e appartenenza
dell'unico tester autorizzato. Note italiane caricate. Nessuna modifica all'app
YouTube Music. INSTALLED riguarda l'app, non dimostra l'installazione della build 4.

IPA: `iosAppleMusic/deliveries/0.1.0-4/NoteNarrateMusic.ipa`.
SHA256: `571373710cded80c3574a201e0232562130051890885077eac951c80f3021d67`.
Commit sorgente `d128d239`, sincronizzato nel fork personale. Visualizzazione
della libreria reale e riproduzione restano da verificare sul dispositivo.

## Confronto libreria dispositivo — build 0.1.0 (5)

Report reale build 4 ripetibile dopo rinnovo token: MusicKit locale 0 brani,
0 album, 6 playlist; cloud 0 brani, 1 album, 6 playlist, una pagina completa.
La paginazione da sola non ha risolto gli album mancanti. Non attribuire la causa
al token (rinnovo riuscito) o alla sincronizzazione senza ulteriore evidenza.

Aggiunto confronto indipendente in sola lettura con MPMediaQuery songs/albums/
playlists, solo se MPMediaLibrary risulta autorizzata. Il confronto avviene fuori
MainActor e trasferisce soltanto conteggi, senza ID, titoli o URL. Report finale
con conteggi effettivamente pubblicati e intestazioni Album/Playlist con totali.
Il refresh cloud usa reloadIgnoringLocalCacheData e Cache-Control no-cache.
30 test passati, incluso controllo che ogni pagina richieda dati aggiornati.
Debug compilata. Necessario report fisico per determinare perché Musica mostri
una raccolta diversa dalle API MusicKit; non dichiarare il problema risolto.

Utente conferma Sincronizza libreria attivo; caso: Heaven on Earth (Deluxe Edition)
di Belinda Carlisle, visibile in Musica ma assente nell'app. Aggiunta ricerca
album dalla schermata Libreria con debounce e gestione richieste superate:
MusicLibrarySearchRequest e /v1/me/library/search?types=library-albums, più
conteggio MPMediaQuery filtrato per titolo. Nessuna ricerca nel catalogo pubblico,
nessuna aggiunta alla libreria, risultati nativi riproducibili separati dall'elenco
completo; limite esplicito 25 per sorgente e presenza di altre pagine nel report.
33 test passati (inclusi input esatto codificato, risposte library-albums,
vuoto valido e rifiuto payload catalogo/malformato/errore HTTP); Debug riuscita.
Primo tentativo export/upload: timeout recuperando elenco app; API buildUploads
conferma soltanto AWAITING_UPLOAD con uploadedDate=null per build 5. La build finale
include la ricerca mirata; non è stata consegnata la variante diagnostica iniziale.

Build finale 5 consegnata: VALID / IN_BETA_TESTING,
ID 3d8a1323-4a3c-42a6-bb26-cf032785bf22, app separata 6833455204.
Upload confermato da Xcode e buildUploads COMPLETE; gruppo Stivy73 soltanto,
manuale, un solo tester e appartenenza riletta. Note italiane caricate.
IPA: iosAppleMusic/deliveries/0.1.0-5/NoteNarrateMusic.ipa.
SHA256 e404e9c6f421687cfdbfe83d5bb4afc2c5f4bac4de8ef70d4a2836958fdbcd03.
Sorgenti 495a505f sincronizzati sul fork personale. Archivio Release firmato
riuscito, iPhone/Watch entrambi versione 0.1.0 build 5 con identità separate YT.
Resta da provare Heaven on Earth nella ricerca Libreria e condividere il report;
la build è diagnostica, non prova la soluzione del problema sul dispositivo.

## Recupero brani iOS — build 0.1.0 (6)

Report reale build 5: MPMediaQuery 14 brani cloud, 1 album, 6 playlist;
MusicKit locale 0 brani / 0 album / 6 playlist; cloud 0 brani / 1 album /
6 playlist. Pubblicati 0 brani, 1 album, 6 playlist. Nessun tentativo di
ricerca album nel report: Heaven on Earth resta da verificare separatamente.

Il lettore MPMediaQuery restituisce ora anche gli ID playbackStoreID (solo in
memoria) osservati sul dispositivo. Solo se l’elenco brani MusicKit è vuoto,
risolve gli ID catalogo validi con MusicCatalogResourceRequest<Song> (100 per
batch). Nessuna ricerca per titolo, nessuna mutazione MusicLibrary. Risultati
non richiesti rifiutati, ID duplicati eliminati e ordine iOS ricostruito anche
se Apple risponde in ordine diverso. Pubblicazione solo a batch completati.
Risposte parziali valide riportano conteggi non disponibili; errori di batch
non pubblicano risultati parziali. Nessun tentativo per ID zero/vuoti/privati.
Controlli, Siri, Watch, CarPlay e narrazione conservano il player MusicKit.

40 test superati; nuovi casi 14 brani, batch successivo fallito, ID estranei,
risposte duplicate, mancanti, ID non utilizzabili e annullamento. Debug riuscita.
La libreria fisica deve confermare la presenza degli ID catalogo e la riproduzione.
Questa modifica risolve il percorso di lettura mancante, non dimostra che Apple
restituisca tutti i brani dell’account o che l’album segnalato sia stato trovato.
Riferimento: developer.apple.com/documentation/mediaplayer/mpmediaitem/playbackstoreid

Build 6 consegnata su TestFlight: VALID / IN_BETA_TESTING,
ID ad026131-de80-4739-a15b-895679edd06d, app separata 6833455204.
Gruppo Stivy73 soltanto, manuale, un tester e appartenenza verificati.
Note italiane caricate. Stato INSTALLED relativo all'app, non prova build 6.
Archivio Release finale ed esportazione firmata riusciti; iPhone/Watch entrambi
0.1.0 (6), bundle distinti dalla variante YouTube. Sorgenti 6546c71b sincronizzati.
IPA: iosAppleMusic/deliveries/0.1.0-6/NoteNarrateMusic.ipa.
SHA256: 44c4f06c641f6917637c98fbf6406e68b18423fed62b0fd79245ea812a2cedb5.
Da verificare su iPhone: conteggi Identificativi brani iOS / Recupero brani iOS,
comparsa e riproduzione dei brani; ricerca Heaven on Earth nella scheda Libreria.

## Unificazione elenco e ricerca album — build 0.1.0 (7)

L’utente conferma che Heaven on Earth compare nella ricerca personale. Il modello
precedente pubblicava i risultati soltanto in libraryAlbumMatches, senza integrarli
in albums. Corretto: stessa funzione per ricerca manuale e recupero automatico,
merge per ID con l’elenco principale e conservazione dei tipi Album MusicKit.

Persistono soltanto ID l.* restituiti dalla ricerca personale, in UserDefaults.
Al successivo refresh gli ID sono verificati con GET /v1/me/library/albums?ids=...
(100 per batch), senza mostrare metadata salvati e senza copiare album dal catalogo.
ID non validi, non richiesti e risposte non autorizzate sono rifiutati. Risorse
non restituite dall’account non diventano righe. Fallimento di batch non pubblica
una raccolta parziale. Nessuna mutazione della libreria musicale dell’utente.

MPMediaQuery fornisce anche i titoli album (solo memoria), deduplicati. I titoli
assenti vengono cercati nella libreria personale, massimo 25 per aggiornamento;
conteggio residuo mostrato per proseguire. Nessun titolo è incorporato nel codice
dell’app o nei nuovi log. Ricerca cloud su tutte le pagine, vincolando host,
endpoint, term e types=library-albums; la ricerca nativa legge i batch da 25.

48 test passati; inclusi caso Heaven on Earth integrato nell’elenco e deduplica,
ricerca multipagina e fallimento successivo, rifiuto next di host/term/tipo diversi,
ripristino ID con account attuale, ID invalidi, risorse inattese ed errori HTTP.
Debug riuscita. Resta necessaria la prova fisica: album nell’elenco dopo pulizia
della ricerca, aggiornamento e riavvio, e riproduzione dello stesso Album.

Build 7 consegnata: VALID / IN_BETA_TESTING,
ID fc611521-7717-47d0-b338-319c77ae41db, app separata 6833455204.
Gruppo assegnato Stivy73 soltanto, manuale; un tester e appartenenza verificati.
Note italiane caricate. INSTALLED riguarda l’app, non conferma il test di build 7.
Archivio Release firmato ed export riusciti; iPhone/Watch versione 0.1.0 (7).
Sorgenti 78885edc sincronizzati nel fork personale.
IPA: iosAppleMusic/deliveries/0.1.0-7/NoteNarrateMusic.ipa.
SHA256: b6eac5eb137981b134197f2822dd1ca840b19b8ccc04b7fb0108a79ef6fee7e1.
Resta da confermare sul dispositivo Heaven on Earth nell’elenco principale,
senza testo di ricerca, dopo aggiornamento e dopo riavvio. Se non rilevato
automaticamente da iOS, una ricerca sulla nuova build conserva l’ID per la
verifica Apple successiva; i risultati della vecchia build non erano persistiti.

## Album nella Home — build 0.1.0 (8)

L’utente conferma che Heaven on Earth è presente in ricerca e in Libreria/Album
ma manca nella Home. Verificato il percorso UI: la Home mostrava esclusivamente
SongRows; non era un ulteriore errore di caricamento o sincronizzazione album.

Aggiunta sezione Album della libreria in Home, sopra i brani, con conteggio e
stesso music.albums della Libreria. Estratto AlbumRows comune per Home, elenco
Album e risultati della ricerca: stessa copertina/titolo/artista e stesso comando
MusicLibraryModel.play(album:). Nessun elenco o caricamento autonomo della Home.
Modifica di presentazione: verifica con compilazione Debug e archivio Release;
nessun test aggiunto che duplichi il semplice binding SwiftUI. Il motore di
recupero della build 7 resta invariato e già coperto dai 48 test precedenti.
Resta da confermare resa e riproduzione da Home sul dispositivo.

Build 8 consegnata: VALID / IN_BETA_TESTING,
ID 00c7a350-b1be-4ab3-a86d-edd3b93fe49d, app separata 6833455204.
Solo gruppo Stivy73 assegnato, manuale, un tester e appartenenza verificati.
Note italiane caricate. INSTALLED riguarda l’app, non prova l’installazione di 8.
Compilazione Debug, archivio Release e export firmato riusciti; iPhone e Watch
entrambi 0.1.0 (8). Sorgenti f4511d20 sincronizzati nel fork personale.
IPA: iosAppleMusic/deliveries/0.1.0-8/NoteNarrateMusic.ipa.
SHA256: e6f3f46c292c1079d7f45179b35f5853c4cb768dbde5860c69ecaa7a0e944203.
Conferma fisica richiesta: Heaven on Earth in Home nella sezione Album della
libreria e avvio della riproduzione dallo stesso elemento già visibile in Libreria.

## Allineamento punto 1 — build 0.1.0 (9)

Dettaglio album/playlist e artista, ricerca catalogo su quattro tipi, Home con
recenti e consigli. Raccolte caricate con MusicKit, paginazione tracce/entries e
selezione nativa Queue(album:startingAt:) / Queue(playlist:startingAt:).
Occorrenze playlist conservate, elementi indisponibili visibili; nessuna coda
ricostruita per titolo o primo ID duplicato. Ricerca invalida risposte superate;
limite 25 per categoria esplicito. Discovery carica indipendentemente dalla libreria.

Aggiunta Favoriti via POST /v1/me/favorites?ids[type]=...; ID di libreria risolti
tramite relazione catalog ufficiale, senza matching testuale. 202 trattato come
accettazione. GET personale/catalogo verifica inFavorites: solo booleano esplicito
può riempire la stella. Stato omesso/errore non equivale a falso né a successo.
Elenco Preferiti legge le collezioni personali paginate e filtra solo attributi
espliciti; pagina non verificabile genera errore, non una raccolta vuota fittizia.
Rimozione soltanto in Musica: Apple Support 111118 documenta il limite per terzi.
Nessuna API privata, nessuna scrittura reale durante i test, nessun preferito locale.

53 test contratti passati, inclusi risorse ammesse, ID privati/URL injection,
booleani, 202 senza verifica, mapping assente/ambiguo/403 e paginazione del filtro.
Debug riuscita. Necessari collaudo iPhone con account e verifica manuale di scritture,
playlist con duplicati, raccolte grandi, discovery vuota/rete e artista.
Riferimenti: https://support.apple.com/111118
https://developer.apple.com/documentation/applemusicapi/add-resource-to-favorites

Build 9 consegnata: VALID / IN_BETA_TESTING,
ID 5736d232-a6de-4d29-b210-a1b2afb78971, app separata 6833455204.
Solo Stivy73 assegnato, manuale; un tester e appartenenza verificati.
Note italiane caricate. Stato INSTALLED riferito all’app, non alla prova di 9.
Archivio ed export firmati riusciti; iPhone e Watch entrambi 0.1.0 (9).
Sorgenti 8cfec9a9 sincronizzati sul fork personale. Nessuna modifica YT.
IPA: iosAppleMusic/deliveries/0.1.0-9/NoteNarrateMusic.ipa.
SHA256: 7c1a14044293398a679302d708d5de14d3a470d130165d37688bf0afb6eae6ec.
Collaudo richiesto: Heaven on Earth/traccia intermedia, playlist con duplicati,
ricerca quattro categorie, recenti e consigli, Preferiti confrontati con Musica.
Risorse personali senza equivalente catalogo possono non consentire aggiunta
ai Preferiti dall’app: l’errore resta esplicito e si usa Musica, senza API private.

## Player originale YouTube adattato a MusicKit — build 0.1.0 (10)

Il report utente di build 9 mostra prepareToPlay riuscito e play ritornato con
stato paused, oltre a 14 ID iOS risolti in zero Song. Il player semplificato della
variante Apple Music è stato rimosso. La presentazione proviene direttamente da
StivyApp.swift del commit YT 5a277798: copertina, mini player nativo, overlay
conservato, gesto dal bordo, layout compatto/esteso, toolbar verticali, scrubber,
controlli e animazioni. Provenienza e differenze verificabili con lo script di
importazione e documentate in PLAYER_PORT.md.

L’adapter usa esclusivamente ApplicationMusicPlayer per la musica. Coda con ID
di occorrenza nativi, preferiti/libreria Apple, MPVolumeView e AirPlay. Il pannello
Fonti e significato mantiene il percorso Google Search già presente e il consenso;
nessuna importazione del motore audio YT, recupero testi o relay Chromecast.

Controllo del vero stato playing dopo il comando, fino a circa 3 s, messaggio
Riprova se non confermato. Una pausa da iPhone/Siri/Watch invalida l’intento;
non può essere annullata da un comando play ancora in attesa. Se il player parte
successivamente, l’avviso si elimina. Nessuna prova di riproduzione reale nel test.

Il fallback dei brani iOS usa GET ufficiale /v1/catalog/{storefront}/songs?ids=,
con MusicDataRequest, validazione HTTP/schema e conteggi diagnostici. "Non
restituiti" sostituisce "non disponibili": zero risultati non ne prova il motivo.
Il recupero dei 14 Song deve essere verificato con l’account del dispositivo.

59 test superati, inclusi avvio ritardato, play senza playing, pausa esplicita,
richiesta dei 14 ID/storefront e rifiuto di risposte invalide/HTTP 403. Verifica
del port fissato riuscita. Compilazione Debug e archivio Release firmato riusciti.
Il test visivo con dati sintetici è separato dal Release tramite
DEBUG && PLAYER_LAYOUT_FIXTURE. Il Mac bloccato impedisce per ora il controllo
visivo in Device Hub; lo sblocco è stato richiesto. La compilazione non equivale
al collaudo sul dispositivo, né risolve da sola il report paused di build 9.

Build 10 consegnata: VALID / IN_BETA_TESTING,
ID 2b7b9877-6d88-4322-af21-955e3986e274, app separata 6833455204.
Solo Stivy73 assegnato, manuale; un tester e appartenenza al gruppo verificati.
Note italiane aggiornate e verificate per lettura: la localizzazione it creata
da Apple esisteva già con whatsNew nullo e richiedeva PATCH, non una nuova POST.
Stato INSTALLED riferito all’app, non all’installazione/prova della build 10.
Archivio ed export firmati, firme archivio e IPA verificate; iPhone e Watch
entrambi 0.1.0 (10). Dati sintetici del test assenti dal binario Release.
Sorgenti 50c91bd147db4561b9e5ca5afa9b867357d903c3 sincronizzati nel fork personale.
IPA: iosAppleMusic/deliveries/0.1.0-10/NoteNarrateMusic.ipa.
SHA256: 7e6485f14c29cec8a6c0fb221a7ab8833a9e82546898aac3034578e2c72fbe34.
Il sorgente StivyApp.swift nel checkout YouTube coincide con l’hash importato.
Il controllo visivo resta sospeso per Mac bloccato; non viene dichiarato un
collaudo di interfaccia o una riproduzione MusicKit sul dispositivo.

Ripresa del collaudo UI il 13 novembre 2026 dopo sblocco del Mac. Installata solo
nel simulatore iPhone 18 Pro / iOS 27.2 la build DEBUG PLAYER_LAYOUT_FIXTURE.
Player completo osservato con copertina, trasporto, tempi e badge Apple Music.
Verificati: play/pausa della fixture, seek con tempo da 0:42 a 2:10, chiusura
tramite Indietro, mini player con pausa, riapertura e gesto dal bordo per tornare.
Osservato il layout orizzontale a due colonne; la coda (0 elementi sintetici)
si apre tramite azione di accessibilità. Restano da verificare lo scorrimento
dei comandi inferiori in orizzontale e il pannello Fonti: nuovo blocco del Mac
durante il test. Non si deduce un difetto dell’app dai drag senza esito nella
superficie simulata. Nessun account o servizio musicale usato per queste prove.
Audio MusicKit, libreria reale, coda con duplicati, narrazione, AirPlay e schermo
fisico Duo rimangono prove distinte e non eseguite da questo collaudo sintetico.
