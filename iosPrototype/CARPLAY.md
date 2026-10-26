# NoteNarrate iOS — audio in background e CarPlay

## Audio e karaoke del 26 ottobre 2026 — 0.12.1 (32)

La diagnostica del telefono con build 31 conferma `HTTP 403` esattamente all’offset
1048576 e nessuna sorgente account completa validata. Non è un limite temporale del
player: il flusso pubblico era accettato dopo il solo controllo dei primi byte.
Mancava inoltre la decodifica WEB_REMIX s/n presente nel codice Android.

La candidata integra il decoder locale, conserva byte e ordine della query firmata,
valida anche confine/fine per entrambe le sorgenti e ripristina la stessa posizione
quando un flusso in corso fallisce (massimo due tentativi). HLS mantiene l’effettiva
traccia audio della master playlist. In caso di errore iniziale, le voci Account audio
e Musica vengono aggiornate con lo stadio fallito senza credenziali o URL firmati.

Cinque scenari UI superati: evidenziazione/scorrimento karaoke con navigazione
manuale, recupero reale dell’AVPlayerItem e posizione, testo/timer, minimizzazione
e TTS streaming/rotazione/interruzione/ripresa. Le prove di stato usano audio locale
controllato; non vengono presentate come prove della rete Premium o dell’auto.
I testi karaoke rimangono nell’interfaccia del telefono, non sul display CarPlay.

**Evidenze finali:** 231 test core superati, inclusi decoder WebKit reale su script
locale, timeout, firme con padding, conservazione degli URL, richieste player
allineate ad Android, controlli AAC/HLS e budget di recupero. Decoder verificato
anche sullo script pubblico YouTube corrente senza credenziali. Prova AVPlayer
pubblica `dQw4w9WgXcQ`: 98,0 secondi avanzati, zero campioni in stallo e tutti i
3.449.447 byte scaricabili. La sorgente pubblica `ZmzqqdVFw8g` continua invece a
rifiutare il blocco oltre 1 MiB e la coda: viene esclusa prima della riproduzione.
Questo non dimostra ancora la continuità dell’account Premium del telefono.

**Da verificare sul dispositivo:** account Premium del telefono oltre 0:59,
audibilità e corretta uscita CarPlay. Nessuna nuova richiesta di entitlement,
nessuna modifica al prompt o alle chiavi IA. L’account viene usato solo tramite
il normale percorso dell’app: nessuna estrazione di sessione in probe esterne.

## Controllo del 26 ottobre 2026 — 0.12.0 (31)

- Configurazione firmata della precedente IPA 0.11.0 (30) verificata: entitlement
  CarPlay Audio nella firma e nel profilo, scena CarPlay conservata, audio in
  background, Siri e frasi d’esempio in Base/italiano/inglese; nessuna incongruenza.
- Nel sorgente: Home personalizzata, generi/stati d’animo, album remoti, preferiti
  locali/YouTube Music e offline; catalogo con due copertine grandi per riga,
  tracce album a lista numerata, paginazione e caricamento immagini limitato.
- Ricerca Siri direttamente in auto con risultati filtrabili per canzone,
  artista e album; icone album/artista nel player, coda modificabile, radio,
  autoplay, casuale/ripetizione e comandi multimediali sul modello condiviso.
- Bug trovato e corretto: il comando Radio dell’artista veniva sovrascritto
  da `setTiles` dopo la risposta. Ora resta nella barra e durante la paginazione.
- Album iPhone e CarPlay passano per `AlbumDetail`: tutte le pagine, ordine e
  occorrenze delle tracce, metadati/copertina e riferimenti artista; nessuna
  raccomandazione inserita in Play o Download dell’album.

**Prove eseguite:** 199 test core superati. Prima delle modifiche, otto test UI
superati su narrazione nativa/streaming, Now Playing durante la voce, rifiuto
presentazione, background, ricerca album/artista/playlist, coda e casuale/ripetizione.
Sulla candidata: quattro scenari UI nuovi superati; regressioni TTS streaming e
minimizzazione superate; conferma di testo manuale e rifiuto del popup superata.
Il primo tentativo di quest’ultima si era fermato nel caricamento YouTube prima
che la richiesta CarPlay iniziasse: la conferma usa un file audio locale verificato.
Una vecchia asserzione sui testi assumeva che ogni registrazione successiva avesse
lyrics: corretta per verificare l’assenza del testo manuale del brano precedente
anche quando il nuovo testo non è disponibile.

**Limite della verifica:** XCTest ha usato il simulatore iPhone e il percorso
condiviso della richiesta CarPlay. La UI esterna CarPlay non è stata pilotata:
Simulator.app non risulta disponibile nell’installazione Xcode corrente. La revisione
dei template/limiti/paginazione è quindi sul sorgente, separata dalle prove UI.
Restano da provare sul dispositivo l’udibilità della voce nell’auto e la continuità
YouTube Premium oltre un minuto/CDN 403. Questi risultati non certificano quei due punti.

Log locali: `/tmp/notenarrate-carplay-audit-core.log`,
`/tmp/notenarrate-carplay-audit-ui.xcresult`, `/tmp/notenarrate31-core-final.log`,
`/tmp/notenarrate31-player-album-ui.xcresult`, `/tmp/notenarrate31-final-ui.xcresult`.

**Consegna:** IPA finale 0.12.0 (31) verificata da `CheckCarPlayIPA.py`, inclusi
CarPlay/Siri nella firma e nel profilo, manifest, versioni ed estensioni.
Caricamento TestFlight interno riuscito il 26 ottobre alle 10:09 Europe/Rome,
Apple in elaborazione; comando terminato con esito 0. Sorgenti `ac7fe9ff`
pubblicati sui due branch personali. Assegnazione ai tester manuale.

## Riferimenti e cronologia delle implementazioni precedenti

Le sezioni seguenti conservano il contesto storico delle build indicate; gli
stati e i limiti superati successivamente non descrivono la candidata corrente.


Implementazione candidata 0.6.2 (19); upload19 confermato il 20 ottobre 2026,
elaborazione Apple in corso al termine dell'upload. Assegnazione ai tester
affidata all'utente; disponibilità e collaudo in auto non ancora confermati.
Apple ha concesso CarPlay Audio al Team e la capability
è stata abilitata sull'App ID `com.stivy.simpmusic.prototype` il 14 ottobre 2026.
La configurazione Xcode include ora `com.apple.developer.carplay-audio` per default.
Firma del pacchetto, distribuzione e collaudo in auto sono verifiche distinte;
il risultato corrente è riportato in `VERIFICATION.md`.

## Architettura

- Su iOS `NativePlayback.swift` mantiene AVPlayer nel modello, indipendente da
  player espanso/minimizzato e dalla vista. La risposta `/youtubei/v1/player`
  prova la sessione WEB_REMIX della Libreria e poi il client IOS pubblico,
  riusando il parser `YouTubeVideo` dell'SDK esistente.
  Selezione AAC MP4, poi HLS. Gli URL firmati non sono salvati né registrati.
- `AudioRangeLoader` adatta le richieste AVPlayer a intervalli di byte del CDN
  tramite URLSession. Richieste limitate a 512 KiB, senza server locale o download
  completo obbligatorio. L'avvio immediato usa un primo blocco precaricato;
  il recupero automatico dagli stalli rimane abilitato. Il video si apre su YouTube
  solo su richiesta, mettendo in pausa l'audio dell'app.
- `AppleMediaSession` pubblica copertina, titolo, artista, durata, tempo e stato
  per Lock Screen/Control Center/CarPlay. Play, pausa, precedente, successivo e
  seek agiscono sullo stesso modello. Interruzioni e disconnessione cuffie non
  fanno ripartire un brano già messo in pausa o sostituito.
- Un task di background limitato copre il recupero del prossimo stream quando
  il telefono è già bloccato. Il sistema conserva i propri limiti di esecuzione.
- `AppleAppSession` mantiene gli stessi modelli anche se l'avvio avviene dalla
  scena CarPlay. Nessun nuovo login, parser Home, parser album, prompt o TTS.
- `CarPlayScene` usa `CPListTemplate`: Home, Album e Preferiti. Le raccolte usano
  card `CPListImageRowItemCardElement` a immagine piena su iOS26+, due per riga,
  con fallback `CPListImageRowItem` sulle versioni precedenti. Le tracce degli
  album e i brani preferiti sono liste numerate. Home riusa le
  sezioni personalizzate; album salvati remoti e continuation riusano la libreria.
  Preferiti distingue NoteNarrate locale e YouTube Music (`VLLM`). Le raccolte grandi
  hanno pagine precedenti/successive rispettando `CPListTemplate.maximumItemCount`, senza
  nascondere definitivamente gli elementi o accumulare template di paginazione.
- `AppleArtworkStore` carica solo le copertine della pagina visibile, con quattro
  richieste simultanee, deduplicazione e cache RAM limitata a 32 MiB/128 immagini.
  Le copertine sono a colori; richieste cancellate o pagine precedenti non possono
  sostituire le immagini correnti. La stessa cache alimenta `MPMediaItemArtwork`.
  I brani aperti da un album conservano la copertina dell'album e l'artista se
  mancano nei renderer delle singole tracce. Il fallback video viene usato solo
  quando la copertina non è disponibile e l'ID video è valido.
- La lampadina apre solo “Significato della canzone” con azione Interrompi.
  Testi reali, IA, streaming TTS Gemini/cache o sintesi nativa sono quelli del
  player interno. Alla fine/Stop riparte solo il brano precedentemente attivo.
  Nel display CarPlay non compaiono testo interpretativo, lyrics o video.
  Il tasto Now Playing diventa Stop durante la lettura, anche se iniziata dal telefono.
- Musica, voce nativa e streaming usano la medesima sessione `.playback`, modalità
  `.default` e policy `.longFormAudio`; la sintesi nativa usa esplicitamente la
  sessione dell'app. La preparazione IA/TTS è coperta da un background task limitato,
  concluso all'inizio effettivo della voce, al fallimento, allo Stop o alla scadenza.
  La richiesta CarPlay non apre il foglio sul telefono. Fallimenti mostrano un
  breve errore con Riprova/Chiudi, senza testo interpretativo. Il pulsante Stop è
  denominato “Interrompi” per evitare il troncamento nel display dell'auto.
- L'azione di lettura parte prima della presentazione del popup: il callback del
  veicolo non è più un prerequisito. Un rifiuto esplicito cancella la richiesta e
  riprende solo il brano precedentemente attivo. Durante la voce Now Playing
  dichiara la riproduzione attiva, con il breve titolo “Significato della canzone”.
  Non pubblica il testo interpretativo. Avvio della voce nativa e preparazione
  hanno timeout gestiti; l'ultima fase è condivisibile dalle impostazioni del telefono.
- Il resolver media prova prima `YouTubeBrowse.player` con WEB_REMIX, cookie e
  identità già confermati per la Libreria, riusando il parser `YouTubeVideo`.
  I candidati autenticati vengono controllati anche verso la fine del file.
  I cookie vengono inviati soltanto a music.youtube.com e non al CDN. Il percorso
  IOS pubblico precedente resta un fallback. La risoluzione completa su account
  reale è una verifica ancora aperta: il test anonimo ha fallito a 1 MiB con 403.
- Il loader conserva fino a otto blocchi da 512 KiB in RAM, deduplica le richieste,
  anticipa un blocco e ritenta errori transitori con limiti. Nessun audio o URL
  firmato è persistito. Una riserva di 30 s e il recupero automatico AVPlayer aiutano
  gli underrun di rete, ma non aggirano il rifiuto del CDN.
- Su Mac resta il player WebKit esistente. Compilazione Mac verificata dopo le
  modifiche condivise. Preferenze, Portachiavi e ID applicazione restano compatibili.

## Abilitazione Apple

Il 14 ottobre 2026 è stato accettato, con autorizzazione esplicita dell'utente,
il CarPlay Entitlement Addendum Apple (rev. 06-08-2026) ed è stata inviata la
richiesta **Audio** per Archetipi Digitali srl, Team `63W2ZKR3Z7`. Apple ha
confermato “Thank you for your submission” e comunica che esaminerà la richiesta.
Il modulo riguarda il Team e non offre campi per nome app, bundle ID o descrizione;
NoteNarrate e `com.stivy.simpmusic.prototype` restano la destinazione prevista.

La prima verifica mostrava “No Status” e nessuna capability abilitabile. Dopo
la mail di concessione Apple, il portale ha reso disponibile CarPlay Audio.
È stata selezionata, salvata e verificata dopo la riapertura dell'App ID:
`deliveries/carplay/capability-enabled-2026-10-14.png`. La ricevuta iniziale resta
in `deliveries/carplay/request-submitted-2026-10-14.png`.

1. La concessione e l'abilitazione sull'App ID sono completate. Per le nuove firme
   usare un profilo rigenerato che contenga `com.apple.developer.carplay-audio = true`.
2. `CARPLAY_ENTITLEMENTS_FILE=NoteNarrateCarPlay.entitlements` è ora la configurazione
   ordinaria di Debug e Release. La generazione automatica del manifest delle scene
   è disabilitata per conservare il ruolo CarPlay dichiarato in `Info.plist`.
3. Con Cloud Managed Signing e archivio compilato usando `CODE_SIGNING_ALLOWED=NO`,
   la prima esportazione non conserva gli entitlement. Prima dell'export Apple,
   dichiararli con una firma ad hoc locale dell'app nell'archivio:

       codesign --force --sign - --entitlements NoteNarrateCarPlay.entitlements \
         --generate-entitlement-der <archive>/Products/Applications/StivySimpMusic.app

   Questa firma serve solo alla preparazione e viene sostituita da Apple Distribution.
   Non distribuire l'archivio ad hoc o un'IPA priva del profilo Apple approvato.
4. Verificare l'IPA esportata con `python3 Scripts/CheckCarPlayIPA.py <exported.ipa>`.
   Il controllo richiede CarPlay nella firma e nel profilo, Team/bundle corretti,
   firma valida, audio in background e ruolo/delegate CarPlay nel plist finale.
   Caricare su TestFlight solo il pacchetto che supera questi controlli.
5. Provare con CarPlay Simulator e poi con iPhone/auto reali: telefono bloccato,
   avvio a freddo, cambio account, liste grandi, seek, chiamata/Siri, assenza rete,
   lettura TTS completa, Stop, scollegamento e cambio brano durante l'IA.

Descrizione preparata per eventuali richieste di chiarimento Apple, non inviata
dal modulo attuale: “NoteNarrate is an audio music client with
personalized browsing, saved albums and favorites. CarPlay will use Apple's audio
templates and Now Playing controls. A custom action offers a short spoken song
interpretation, with stop and music resume. The car interface displays no lyrics,
interpretation text or video. No custom driving UI is used.”

Alla build 19 i Download non erano implementati. Dalla build 28 sono disponibili
in Libreria e nei Preferiti CarPlay; non richiedono una nuova risoluzione CDN quando
il file completo è già stato verificato e salvato.
La ricerca, il playback di tutti i contenuti del catalogo, i comandi di sistema su
hardware reale e la scena CarPlay non sono certificati dal solo test del core.

Fonti: [entitlement](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements),
[scene](https://developer.apple.com/documentation/carplay/cptemplateapplicationscenedelegate),
[app musicali](https://developer.apple.com/documentation/carplay/integrating-carplay-with-your-music-app).


## Build 22: ricerca e navigazione contestuale

La scheda Cerca espone tre filtri server-side, riusando i parametri della versione
Android. La query è l'ultima ricerca inviata sul telefono, non il testo ancora
in digitazione. Le risposte cancellate o appartenenti al precedente account non
aggiornano l'interfaccia. Artisti/album mantengono i browse ID, incluse le righe
responsive che il decoder precedentemente scartava. Le icone del player usano i
riferimenti del brano e conservano il contesto dell'album nel passaggio alla coda.
Se il riferimento manca in un vecchio preferito, si apre una ricerca tipizzata.

Apple documenta CPSearchTemplate tra i template di navigazione, non quelli audio:
non viene usata una tastiera non autorizzata dall'entitlement CarPlay Audio.
Riferimenti: https://developer.apple.com/documentation/carplay e
https://developer.apple.com/documentation/carplay/cpnowplayingtemplate .

La generazione automatica usa un singolo tentativo (timeout rete 25 secondi),
compatibile con il watchdog generale di preparazione da 45 secondi. Il retry per
sola lunghezza resta disponibile nel servizio per chiamanti che lo richiedono;
non ritarda più la voce nel player mobile e CarPlay. I test di voce in background
sono fixture reali del player, mentre la prova server Google usa testo recuperato
online. Nessuno dei due dimostra l'uscita fisica CarPlay del veicolo.


## Build 23: passaggio dalla musica alla voce

La preparazione CarPlay non mette più subito in pausa AVPlayer. La pausa avviene
all'arrivo del primo blocco PCM o appena prima dell'avvio AVSpeechSynthesizer.
La revisione/token continua a impedire l'avvio tardivo dopo stop/cambio canzone.
Il watchdog e il task UIKit restano limitati; non viene riprodotto audio fittizio
per mantenere viva l'app. Il player PCM aspetta un clock di rendering valido,
usa playAudio() su iOS/macOS27 e termina con errore se l'uscita non parte.

La documentazione Apple distingue l'esecuzione audio dal tempo limitato concesso
ai task di preparazione: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app .
API player: https://developer.apple.com/documentation/avfaudio/avaudioplayernode/playaudio() .

Il CDN403 è riprodotto separatamente e non corretto. La diagnostica deve essere
letta dalla build corrente nel veicolo: una prova Google sul Mac non dimostra né
l'audio fisico CarPlay né che la sessione Premium del telefono sia riutilizzata.


## Build 24: ricerca vocale autonoma, shuffle e ripetizione
La scheda Cerca include la cella Siri per la categoria audio e un'estensione
INPlayMediaIntent. L'app gestisce gli intenti in background, cerca canzoni,
artisti e album e aggiorna i risultati sul display del veicolo. La query non
proviene più dall'ultima ricerca sul telefono. È possibile cambiare filtro dalla
lista CarPlay. La tastiera CPSearchTemplate è riservata da Apple all'entitlement
Navigation: NoteNarrate mantiene Audio, senza forzature della categoria.
Shuffle e ripetizione sono collegati allo stesso ordine della coda del telefono
e a MPRemoteCommandCenter. Il collaudo Siri e dei comandi su auto reale resta
necessario; i difetti audio della build23 sono fuori da questo intervento.
