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
