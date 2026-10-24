# NoteNarrate iOS — prototipo 0.6

Client SwiftUI per iPhone e iPad, separato dalla build Android. Sviluppato con assistenza
IA/vibecoding: è un prototipo, non un porting completo di SimpMusic.

La **0.4.3 (12)** introduce il nome NoteNarrate, la nuova icona e il mini-player persistente.
Disponibile in TestFlight per il gruppo **Team interno** (stato Apple: Test in corso).

La **0.4.4 (13)** disponibile in TestFlight per il Team interno riduce l’attesa dell’interpretazione: recupero anticipato del testo,
ragionamento rapido sul modello predefinito e cache locale del risultato. “Rigenera interpretazione”
richiede una nuova analisi; riaprendo la stessa canzone viene riusata anche la voce già in cache.

La **0.4.5 (14)** aggiunge un'animazione di riduzione e riapertura del player:
scorre verso il mini-player mantenendo la sessione audio. Con “Riduci movimento”
attivo usa una breve dissolvenza.

La **0.5.0 (15)** porta la Home di SimpMusic: sezioni personalizzate di YouTube Music
(inclusa “Ascolta di nuovo” quando restituita dall'account), filtri Tutto, Relax, Riposo,
Energetico, Triste, Romantico, Buonumore, Allenamento, Festa, In viaggio e Concentrazione.
I generi e gli stati d'animo arrivano dal catalogo reale, con navigazione a playlist,
album e artisti, pulsante Altro, cronologia autenticata e refresh. Lo scorrimento carica
le continuation; le playlist possono proseguire oltre le prime 100 tracce.
Caricamento Apple completato per i test interni; elaborazione e assegnazione della build 15
al gruppo Team interno non ancora confermate. I risultati sono in VERIFICATION.md.

La **0.5.1 (16)** cerca automaticamente il testo su LRCLIB quando YouTube Music
non lo fornisce o dà errore. La ricerca confronta titolo, artista e, se nota, durata;
riconosce i suffissi tecnici dei titoli rimasterizzati. Il testo recuperato alimenta
sia il pannello Testo sia l'interpretazione e la lettura automatica. Non occorre
un'altra API key; la fonte viene mostrata nell'app. Build e collaudi locali completati; firma Apple verificata e caricamento per
TestFlight interno completato. Elaborazione e assegnazione al gruppo non ancora
confermate; dettagli in VERIFICATION.md.

La **0.6.0 (17)** introduce il player AVPlayer per l'audio in background e i comandi
di Lock Screen/Control Center, con la stessa sessione del mini-player. CarPlay usa
Home, Album e Preferiti, e la lampadina avvia l'interpretazione parlata con Stop
e ripresa della musica, senza testo o video sul display dell'auto. Apple ha concesso
l'entitlement CarPlay Audio e la capability è abilitata sull'App ID. Firma e profilo
CarPlay verificati; build disponibile in TestFlight per Team interno, stato
**Test in corso**. Resta la prova su CarPlay reale. Dettagli di firma,
distribuzione e prove: [CARPLAY.md](CARPLAY.md) e [VERIFICATION.md](VERIFICATION.md).

La **0.6.1 (18)** corregge il percorso di lettura CarPlay in background, mantiene
artista e copertina dell'album nelle tracce e introduce griglie di copertine con
paginazione per Home, Album e Preferiti. Condivide sessione audio e caricamento
delle immagini con Now Playing. Firma Apple e profilo CarPlay verificati, 78 test
core e quattro test UI superati. Caricata su Apple il 18 ottobre 2026 per TestFlight
interno; elaborazione e assegnazione al gruppo non ancora confermate perché
App Store Connect web resta sul caricamento. L'ultima beta con distribuzione
confermata resta la 0.6.0 (17). Prova nell'auto reale ancora necessaria.

La candidata **0.6.2 (19)** avvia l'interpretazione indipendentemente dal callback
del popup CarPlay e mantiene attiva la sessione Now Playing durante la voce.
Le tracce degli album sono liste numerate; il catalogo usa card con copertine
grandi, due per riga. Recupero testi con fallback più rapido, errori espliciti e
diagnostica locale condivisibile. Il player prova ora anche l'account YouTube
confermato, con lo stesso trasporto autenticato della Libreria. Il flusso IOS
anonimo ha riprodotto un 403 oltre 1 MiB: prelettura e buffer non rimuovono tale
restrizione. Il percorso autenticato necessita del collaudo con l'account reale
e in auto; non è dichiarato risolto dal solo test dei primi secondi.

## Cosa contiene

- Home personalizzata e ricerca reale su YouTube Music, riusando YouTubeSDK (MIT).
- Player con copertina predefinita, sfondo sfumato e icone ispirate alla versione Android. Il video è accessibile dal pulsante dedicato o dal menu.
- Pausa, seek, brano precedente/successivo, coda selezionabile e controllo volume del player.
- Pannello testo con caricamento, riprova, espansione, copia, condivisione e inserimento manuale. I testi sono statici: il provider attuale non restituisce timestamp per la sincronizzazione.
- Layout del player verticale su schermi stretti e a due colonne su quelli ampi; ritorno alla libreria o alla schermata precedente.
- La musica continua riducendo il player e navigando fra Home, Cerca e Libreria. Il mini-player ha Pausa/Riprendi; riaprendo il player si conservano posizione e stato. Controlli accessibili con tempo trascorso e rimanente.
- Login YouTube Music in una finestra Google isolata, sessione nel Portachiavi, cambio account e logout.
- Album salvati remoti in griglia, refresh, apertura tracce e continuation complete senza duplicati.
- Preferiti **locali** persistenti, distinti dalla libreria remota dell'account YouTube Music.
- Interpretazione in italiano: storia raccontata dal testo, poi significato, circa 900 caratteri
  (855–945). Recupero anticipato del testo attraverso l'SDK; se manca, ricerca online
  su [LRCLIB](https://lrclib.net/docs), già usato da Android. I risultati omonimi di
  artisti diversi e quelli strumentali sono scartati. Cache dei testi nella sola sessione.
  Inserimento manuale quando anche la ricerca online non trova una corrispondenza.
  Senza testo non viene generata un'interpretazione basata solo sul titolo.
- Lettura automatica con voce iOS oppure Google Gemini 3.8 Flash TTS;
  stili DJ, Empatico e Professionale per Gemini. Dalla 0.4.2 la voce Gemini viene
  riprodotta in streaming PCM appena arrivano i primi blocchi; il riascolto dello
  stesso testo, voce e stile usa la cache audio locale (100 MiB, esclusa dal backup).
  Gli audio incompleti non vengono salvati; la musica riprende dopo l'ultimo buffer.
- Pausa prima dell'interpretazione e ripresa dello stesso brano alla fine o allo stop della lettura.
- Copia e condivisione dell'interpretazione.
- Chiave Gemini nel Portachiavi iOS. Nessuna chiave personale incorporata nel progetto.
- Nessun popup promozionale.

## Provarlo

1. Apri **StivySimpMusic.xcodeproj** in Xcode.
2. Seleziona lo scheme **StivySimpMusic** e un simulatore iPhone, quindi Run.
3. In Libreria scegli **Accedi a YouTube Music**, completa il login, seleziona il profilo
   desiderato sul sito e premi **Usa questo account**. Poi apri un album o cerca un brano e aprilo. I contenuti che YouTube non consente di incorporare mostrano un errore.
4. Per l'IA: **Impostazioni → Chiave API Google Gemini → Salva impostazioni**.
   Il link **Non hai le API?** apre Google AI Studio. La chiave non è condivisa con YouTube.
5. Dal player premi **Significato della canzone**. Se YouTube non fornisce il testo,
   l'app lo cerca online e poi avvia l'interpretazione e la lettura. Se nessuna fonte
   trova una corrispondenza, apri **Aggiungi il testo manualmente** e riprova.
   L'opzione Gemini TTS usa la stessa chiave.

Richiede iOS 17+ e Xcode con Swift 6. Il modello testuale è configurabile; il valore iniziale
è quello del fork Android, **gemini-3.8-flash**. L'accesso ai modelli dipende dalla chiave e dalla quota.

La firma automatica è configurata sul Team **Archetipi Digitali srl** (`63W2ZKR3Z7`),
per app e test UI, in Debug e Release. Il Bundle ID è `com.stivy.simpmusic.prototype`.
Per un iPhone fisico occorrono un account Apple Developer attivo in Xcode e un profilo
iOS che includa il dispositivo. Collega l’iPhone, selezionalo come destinazione e premi Run.
Chi riusa il progetto con un altro account deve selezionare il proprio Team.

La firma di distribuzione **Apple Distribution: Archetipi Digitali srl** è stata
completata tramite Cloud Managed Signing di Xcode. L’IPA `0.1.0 (1)` usa un profilo
App Store per il Bundle ID del prototipo e ha superato `codesign --verify --deep --strict`.
È un pacchetto per TestFlight/App Store Connect: non si installa direttamente come un APK.
La scheda StivySimpMusic è stata creata in App Store Connect (Apple ID `6821630132`),
con lingua italiana e accesso per tutti gli utenti del Team, come autorizzato dall’utente.
Il caricamento TestFlight della build `0.1.0 (1)` è riuscito dall’Organizer di Xcode.
App Store Connect conferma **Pronta per il test**, con scadenza fra 90 giorni.
La build è riservata ai tester interni; l’assegnazione ai tester resta da configurare.

[TestFlight in App Store Connect](https://appstoreconnect.apple.com/teams/fddd820e-15fa-4f15-a556-b56f300f3acf/apps/6821630132/testflight)

Per preparare l’archivio e caricarlo su TestFlight interno:

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' -archivePath /tmp/StivySimpMusic.xcarchive \
      CODE_SIGNING_ALLOWED=NO archive
    xcodebuild -exportArchive -archivePath /tmp/StivySimpMusic.xcarchive \
      -exportPath /tmp/StivySimpMusic-TestFlight \
      -exportOptionsPlist TestFlightExportOptions.plist -allowProvisioningUpdates

L’esportazione con `signingStyle=automatic` firma l’archivio per distribuzione usando
il Team configurato. `TestFlightExportOptions.plist` carica la build per **test interni**.
Per un’esportazione locale impostare `destination=export`. I test esterni richiedono
una build esportata senza il vincolo `testFlightInternalTestingOnly` e la procedura beta Apple.

Inclusi asset AppIcon 1024×1024 opaco, orientamenti iPad completi, simboli dSYM e
privacy manifest per l’uso delle preferenze locali (`UserDefaults`, motivo `CA92.1`).
La dichiarazione crittografia riguarda le sole funzioni di sistema (HTTPS e Portachiavi);
non viene implementata crittografia proprietaria.

## Decisioni architetturali

Sources/App contiene UI, coordinamento del player e lettura. Sources/Core contiene prompt,
client Gemini, trasporto browse e stato Home/libreria, testabili come package Swift.
YouTubeSDK è incluso in **Vendor/YouTubeSDK**, a partire dal commit
**fa9bd98bafe98cd8d0918d22382001d10cdbe375**, con licenza MIT e copyright conservati.
La copia locale estende il parser esistente: normalizza album/playlist/artisti nei renderer
annidati, espone la decodifica browse e conserva ordine, metadati, Altro e categorie.
Dettagli: [LOCAL_CHANGES.md](Vendor/YouTubeSDK/LOCAL_CHANGES.md).
Il core Kotlin Android non è stato modificato per questa Home.

`YouTubeBrowse` riusa WEB_REMIX e l'autenticazione della libreria esistente
(SAPISIDHASH, indice account e identità delegata). `FEmusic_home` fornisce le sezioni;
`FEmusic_moods_and_genres` i pulsanti con browseId, params e colore. Le loro destinazioni
e quelle di Altro vengono aperte con gli endpoint restituiti dal server; `FEmusic_history`
fornisce la cronologia. I dieci params dei filtri provengono da HomeViewModel Android,
controllati da `Scripts/CheckHomeFilters.py`. Non si simulano consigli o cronologia con dati locali.

La Home e i generi vengono caricati in parallelo, con identità visitatore separate
per evitare di invalidare la continuation anonima della Home. Le pagine successive mantengono
visitorData, ordine e deduplicazione per tipo/ID; token ripetuti fermano la paginazione
con un avviso. Un errore di continuation lascia visibili le sezioni ricevute ma segnala
che il caricamento è incompleto e offre Riprova. Il refresh sostituisce i risultati.
Cambio account, cookie, indice o identità delegata invalida le richieste in corso e
rimuove i dati precedenti. Al logout viene caricata una Home anonima; Ascolta di nuovo
è una sezione personalizzata del server, disponibile con login. Lo stato Home rimane
in memoria durante la navigazione; non è una cache offline persistente.

Fino alla 0.5.1, il player iOS usa l'IFrame Player API in un WKWebView persistente:
le richieste AVPlayer dirette al CDN fallivano anche con ricerca e metadati validi.
Dalla 0.6.0 iOS usa AVPlayer con un resource loader per intervalli limitati di byte,
validazione del range e cancellazione delle richieste. Il player appartiene al modello
e continua fuori dall'app. Su Mac rimane il player WebKit. Dettagli in [CARPLAY.md](CARPLAY.md).

La selezione di un altro brano invalida gli eventi del precedente; la lettura e le risposte IA
sono protette da cancellazione e identità della richiesta. La ripresa riguarda solo il brano
che era in ascolto all'inizio. Riducendo il player, la sessione audio viene conservata e la musica mantiene posizione e stato;
il mini-player consente di interrompere o riprendere la riproduzione.

L'interpretazione usa **generateContent**. Gemini TTS usa l'API REST **Interactions**,
**speech_metadata** per lo stile e audio PCM in streaming, con cache locale WAV per il riascolto. Se il modello ignora la lunghezza,
effettua un secondo tentativo; poi conserva il testo completo con un avviso, senza troncare la lettura.

## Verifica

    swift test
    swift run NetworkProbe
    swift run NetworkProbe --home
    python3 Scripts/CheckHomeFilters.py
    xcrun swift-format lint --strict --recursive Sources Tests Probe UITests Package.swift
    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' \
      -derivedDataPath /tmp/stivy-ios-device CODE_SIGNING_ALLOWED=NO build

Per i test UI usa un simulatore installato, per esempio:

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
      -derivedDataPath /tmp/stivy-ios-build CODE_SIGNING_ALLOWED=NO test

NetworkProbe verifica ricerca e disponibilità del testo, senza stamparne il contenuto.
Con `--home` verifica la Home anonima, categorie, filtri, playlist e continuation reali.
I test unitari controllano testo mancante, limite del contesto, lunghezza e risposta WAV,
inclusa una risposta malformata. Il test UI usa la rete reale per ricerca, riproduzione,
avanzamento, seek, pausa e navigazione alle impostazioni.
I risultati della sessione sono in **VERIFICATION.md**; le schermate sono in **Screenshots/**.

## Limiti del prototipo

Non ancora portati: download, CarPlay,
sincronizzazione Android, OpenAI TTS e gestione completa della schermata di blocco.
Il player è incorporato e richiede la schermata visibile: non è ancora un player audio
nativo in background. Può mostrare pubblicità e restrizioni stabilite da YouTube.

Ricerca e testi dipendono da API interne che possono cambiare. Non tutti i brani hanno testi.
Le chiamate IA/TTS richiedono la chiave inserita dall'utente; i risultati delle prove
con chiave reale sono registrati nella cronologia di VERIFICATION.md. La ripresa dopo TTS nativo è verificata sul simulatore con testo di prova.
La voce Gemini e il comportamento su iPhone fisico restano da collaudare: build e test
del simulatore non sostituiscono questa prova.

## Licenze e fonti

Il prototipo resta nel progetto GPL-3.0; vedi LICENSE. La dipendenza YouTubeSDK conserva la
propria licenza MIT, inclusa in ThirdParty-YouTubeSDK-LICENSE.txt.

- SimpMusic originale: https://github.com/maxrave-dev/SimpMusic
- SDK riusato: https://github.com/atpugvaraa/YouTubeSDK
- Gemini TTS: https://ai.google.dev/gemini-api/docs/speech-generation
- Player YouTube: https://developers.google.com/youtube/iframe_api_reference
- Identità del client iOS: https://developers.google.com/youtube/terms/required-minimum-functionality

## TestFlight esterno — build 0.1.0 (2)

Preparata una nuova build con `CURRENT_PROJECT_VERSION=2` e
`testFlightInternalTestingOnly=false` in **TestFlightExternalExportOptions.plist**.
La versione esterna è distinta dalla build 1 riservata ai test interni.
Archivio Release ed export firmato sono riusciti; firma Apple Distribution verificata.
L’upload della build 2 è riuscito: Xcode conferma `StivySimpMusic 0.1.0 (2) uploaded`.
La build 2 è stata inviata alla revisione beta Apple: lo stato osservato in
TestFlight è **In attesa di verifica**. Creato il gruppo esterno **Beta privata**
con 1 tester e 1 build, con notifica automatica ai tester abilitata all’invio.
Il tester autorizzato è stato aggiunto; lo stato attuale è **Nessuna build disponibile**
fino all’approvazione Apple. L’invio effettivo dell’email non è ancora verificato.
Come prerequisito Apple è stato creato anche un gruppo interno vuoto, senza
build, tester o distribuzione automatica. Le informazioni beta e i contatti sono
stati salvati in App Store Connect; i dati personali non sono incorporati nei sorgenti.

    xcodebuild -exportArchive -archivePath /tmp/StivySimpMusic-0.1-External.xcarchive \
      -exportPath /tmp/stivy-ios-external-export \
      -exportOptionsPlist TestFlightExternalExportOptions.plist -allowProvisioningUpdates

Questo file usa `destination=export` per conservare l’IPA locale. Il caricamento
per test esterni avviene nell’Organizer con **App Store Connect**, quindi configurando
la build nella sezione **TestFlight**. La pubblicazione App Store è una procedura separata.


## Account e album — 0.2.0 (3)

`YouTubeLibrary` riusa l'identità WEB_REMIX dell'SDK e aggiunge la firma SAPISIDHASH,
X-Goog-AuthUser e l'eventuale identità del canale selezionato. La versione del client
proviene dalla pagina YouTube Music autenticata. Login tramite WebKit effimero:
solo i cookie destinati a YouTube vengono salvati nel Portachiavi; nessuna password
viene letta dall'app e non si usa un nuovo flusso OAuth.

Endpoint: `FEmusic_liked_albums`. Il parser SDK degli album non è riutilizzabile:
il suo inizializzatore è interno e accetta un dizionario appiattito, mentre il parser
sezioni gli passa il renderer grezzo. `LibraryAlbumsPage` adatta pertanto gli involucri
grid/section già supportati dal core Android. Le tracce usano `YouTubeMusicClient.getAlbum`.
Nessuna modifica alla dipendenza, al submodule core o a .gitmodules.

La lista viene pubblicata solo dopo l'esaurimento delle continuation; errori di rete,
renderer inattesi o token ripetuti producono un errore, senza successo parziale.
Cancellazione e revisione della richiesta impediscono risultati del vecchio account.
I preferiti locali mantengono il proprio archivio indipendente.

Il test UI TTS usa `--test-meaning` solo in DEBUG: testo sintetico, voce iOS reale,
player YouTube reale. Non sostituisce il collaudo Gemini con chiave personale.
Il login Google e gli album dell'account richiedono ancora una sessione reale per
la verifica completa; Google può limitare l'accesso nei browser incorporati.


La build **0.2.0 (3)** è caricata ed elaborata su TestFlight, assegnata al gruppo
**Team interno** (3 tester), con stato **Test in corso**. Aggiornare tramite TestFlight.
Le precedenti sezioni di distribuzione descrivono la cronologia delle build 0.1.0.


## Player e navigazione — 0.3.0 (4)

Il player usa tutto lo spazio disponibile. `AnyLayout` mantiene la stessa gerarchia
durante il passaggio fra colonna singola e doppia: il WebView non viene ricreato
solo per una rotazione o un cambio di larghezza. Il layout torna verticale con
caratteri accessibili. Home ha una larghezza massima sui display grandi.

Due comandi distinti consentono di tornare alla Libreria oppure alla schermata
precedente; il mini player permette di riaprire il brano. Uscire dal player mette
in pausa e interrompe l'eventuale lettura, senza riprendere musica nascosta. La
riapertura conserva posizione e pausa. Un errore del video offre Riprova riproduzione.

I controlli leggono lo stato pubblicato dal player senza un secondo timer UI.
Gli eventi WebKit sono accettati soltanto dal WebView attivo; un nuovo caricamento
ha identità distinta anche quando si riprova lo stesso video.

La riproduzione musicale in background e CarPlay restano il punto successivo
della roadmap; non sono stati implementati in questa versione.


Verifica 0.3: 19 test core, 4 test UI iPhone e 1 test UI iPad superati.
Rotazione, seek, riapertura in pausa e lettura nativa con ripresa verificati.
WebKit usa la presentazione mobile anche su iPad, dove il caricamento in modalita
predefinita desktop restava in buffering. Dettagli e limiti in VERIFICATION.md.


La precedente beta **0.3.2 (8)** è disponibile su TestFlight per **Team interno**
(3 tester), stato **Test in corso**. Aggiornare dall'app TestFlight.


## Correzioni 0.3.1 (5)

Prompt principale identico ad Android, verificabile con
`python3 Scripts/CheckAndroidPrompt.py` dal checkout completo. Corretto il rifiuto
del browser nella pagina di login YouTube Music mediante configurazione Safari
WebKit desktop. Login Google e libreria personale verificati nella successiva build 0.3.2 (8).

`NetworkProbe --gemini-key-file <file>` permette il test delle API reali senza
ricompilare l'app: legge la chiave sulla riga successiva all'etichetta Gemini key,
non stampa segreti/testi e verifica interpretazione e decodifica WAV usando
GeminiService dell'app. Richiede una chiave dell'utente e consuma la relativa quota.


## Correzioni 0.3.2 (8)

Il parser della libreria legge soltanto la scheda attiva, ignorando i placeholder
delle schede inattive. Rimangono il recupero completo delle continuation,
la deduplicazione per browseId e l'errore esplicito se una pagina non è valida.
La griglia mostra anche il numero totale degli album.

Verificata sul Mac la beta TestFlight con una sessione Google reale: 155 album
con identificativi distinti, conteggio invariato dopo refresh, entrambe le edizioni
di Bon Jovi Greatest Hits presenti e apertura delle tracce funzionante.
La sessione Google è rimasta attiva dopo l'aggiornamento. I 23 test automatici
coprono anche cambio account, logout e scarto delle risposte obsolete; questi
ultimi passaggi non sono stati ripetuti sull'account reale per conservarne la sessione.


## Streaming e cache: prova diagnostica

`swift run NetworkProbe --stream-key-file <file>` verifica lo streaming reale e
la riproduzione PCM fino alla fine, poi integrità e tempi della cache. Legge la
chiave nello stesso formato del probe precedente e consuma la quota Google.
I tempi di avvio riguardano solo la sintesi vocale, dopo la generazione del testo.


## Rebranding NoteNarrate (0.4.3)

Nome nella schermata Home, nelle Impostazioni e sotto l'icona iOS aggiornato a
NoteNarrate. Icona fornita dall'utente, adattata ai formati Apple senza ridisegno.
Bundle ID, servizio Portachiavi, target e scheme Xcode mantengono gli identificativi
esistenti per preservare sessioni, chiave Gemini e percorso di aggiornamento.
Le attribuzioni e la storia della derivazione da SimpMusic restano documentate.

## Audio in background e CarPlay — 0.6.0 (17)

Su iOS la musica usa ora AVPlayer, indipendente dalla presentazione del player,
con controlli e copertina di sistema. Il loader AAC legge intervalli di byte del
CDN per evitare i 403 delle richieste complete. Video opzionale su YouTube.
La pausa/ripresa per l'interpretazione riusa il TTS e la cache esistenti.

CarPlay aggiunge Home, Album, Preferiti e lampadina/Stop nel Now Playing.
L'interfaccia in auto non mostra lyrics o testo interpretativo. Per attivarlo
su dispositivi e TestFlight manca ancora l'entitlement audio approvato da Apple.
Procedura, decisioni tecniche e limiti: [CARPLAY.md](CARPLAY.md).

Verificati 73 test del core, avvio AAC nativo e tre test UI iOS: minimizzazione,
background e pausa/ripresa dopo TTS nativo con testo di prova. Compilate Release iOS
e versione Mac. Non costituisce una verifica fisica CarPlay o iPhone bloccato.

## Build 20 e bozza App Store — 21 ottobre 2026

La **0.6.2 (20)** conserva il codice funzionale della build19, con nuovo numero
build e distribuzione App Store Connect abilitata anche alla scheda Store. La
19 era solo TestFlight interno e non poteva essere associata. `AppStoreExportOptions.plist`
prepara upload senza invio alla revisione; le build ordinarie interne continuano
a usare `TestFlightExportOptions.plist`.

Scheda italiana in bozza: NoteNarrate, sottotitolo “Musica, storie e significati”,
categoria Musica, descrizione e parole chiave, assistenza sul fork GitHub. Rilascio
manuale; nessun invio ad App Review. Privacy, classificazione per età, diritti sui
contenuti e risorse Store devono essere completati prima di richiedere la pubblicazione.
Restano aperti i collaudi CarPlay e continuità sul conto Premium riportati sopra.

A ogni nuova build per TestFlight il sorgente corrispondente e la documentazione
vengono sincronizzati sul fork GitHub `stivy73/SimpMusic`. Nessuna chiave personale,
cookie, archivio firmato o screenshot locale viene incluso nel commit.


## iPhone Duo — 0.7.0 (21)

Interfaccia adattiva secondo le indicazioni Apple e SDK iOS 27.1: navigazione e
mini-player nativi, player e testo affiancati nelle finestre ampie, controlli che
si riordinano negli spazi ridotti, copertina intera e griglia album flessibile.
Il minimo resta iOS 17; account, coda e servizi audio/IA sono condivisi.
Dettagli e limiti di collaudo: [IPHONE_DUO.md](IPHONE_DUO.md).


## CarPlay — 0.7.1 (22)

Scheda Cerca con filtri Canzoni, Artisti e Album sulla ricerca inviata dal telefono;
icone Album e Artista nel player, con riferimenti reali conservati. Il template
Apple con tastiera resta riservato alle app di navigazione. La lettura automatica
non attende più una seconda generazione per correggere la lunghezza: prompt
italiano invariato e risposta letta integralmente. Test core, narrazione in
background e richiesta reale Google superati; l'udibilità in auto resta da provare.
Il 403 CDN della musica è distinto e non è risolto da questa modifica.


## CarPlay — 0.7.2 (23)

La canzone continua durante la preparazione della narrazione e si ferma quando
la voce è pronta. Il player PCM attende l'uscita audio e registra gli errori di
avvio/interruzione. Novanta test core e due prove UI in background superati,
compresa una preparazione rallentata. L'udibilità nell'auto resta da confermare.
Il blocco CDN oltre il primo MiB non è risolto: Condividi diagnostica include ora
versione/build e la causa dello scarto del flusso account prima del fallback.
