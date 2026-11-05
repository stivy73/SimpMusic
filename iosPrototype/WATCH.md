# NoteNarrate per Apple Watch

Prima versione **companion iPhone**, scelta dall'utente il 5 novembre 2026.
Modifica successiva alla beta 0.15.2 (52), non ancora distribuita. La build locale
mantiene quel numero; una nuova consegna dovrà incrementare app ed estensioni,
compreso il nuovo target Watch.

## Funzioni

- Player con copertina, titolo, artista e avanzamento ricevuto da iPhone.
- Pausa/ripresa, brano precedente e successivo.
- Coda: finestra fino a 40 elementi attorno al brano corrente, con totale indicato;
  selezione tramite identificatore della singola occorrenza, anche con duplicati.
- Significato: avvio della narrazione, testo fino a 6000 caratteri, progresso,
  interruzione con ripresa della musica.
- Radio Gemini dal brano corrente, riutilizzando il servizio iPhone.
- Stato di collegamento, aggiornamento manuale, conferma/errore e timeout dei comandi.

Musica e voce escono dall'iPhone o dalla sua destinazione audio corrente, inclusi
cuffie e CarPlay. L'orologio non ha un player indipendente, login YouTube o chiave
Gemini. Si usano le impostazioni già configurate su iPhone.

## Struttura e collegamento

Target moderno SwiftUI `NoteNarrateWatch`, bundle
`com.stivy.simpmusic.prototype.watchapp`, incorporato nella directory `Watch`
dell'app iPhone. Companion `com.stivy.simpmusic.prototype`, `WKApplication=true`,
`WKRunsIndependentlyOfCompanionApp=false`. Minimo watchOS 10; iPhone resta iOS 17.
Toolchain Xcode 27.2 RC (27B48), SDK iOS/watchOS 27.2.

`WatchPhoneBridge` vive in `AppleAppSession`, condivisa con Siri e CarPlay.
`WatchSessionLink` usa [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity):
`updateApplicationContext` per lo stato recente e `sendMessage` con risposta per
le azioni. I comandi non sono accodati per un'esecuzione differita quando iPhone
non è raggiungibile. Si chiede di avvicinare/sbloccare il telefono e aprire l'app.
Gli aggiornamenti di contesto in background sono best effort, non un orologio
continuamente sincronizzato al millisecondo.

Il protocollo Foundation condiviso limita il JSON a 60.000 byte, la coda a 40
righe e la copertina JPEG a 16.000 byte. In caso di dati Unicode molto lunghi,
si omettono prima copertina e poi righe eccedenti, mantenendo il totale. Nessun
cookie, chiave o URL audio firmato viene trasferito. Le immagini si preparano
solo se il companion risulta installato su un Watch abbinato.

Ogni azione è vincolata all'occorrenza corrente e a un intervallo di due minuti;
un comando vecchio o diretto a un'altra occorrenza è rifiutato. Le ultime 32
risposte sono memorizzate per non rieseguire richieste duplicate con lo stesso
UUID. Timeout Watch 12 secondi: una risposta tardiva non sostituisce una richiesta
successiva. Gli snapshot più vecchi non sovrascrivono quelli recenti. Gli errori
Gemini/brano mancante/preparazione passano dalle protezioni Siri esistenti.

## Compilazione e verifica

Schemi: `NoteNarrateWatch` per l'app Watch, `StivySimpMusic` per iPhone con Watch
incorporato. Compilare con `DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer`.

```sh
xcodebuild -project StivySimpMusic.xcodeproj -scheme NoteNarrateWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
python3 Scripts/CheckWatchCompanion.py <percorso/StivySimpMusic.app>
swift test --filter 'WatchCompanionTests|SiriPlaybackActionTests|AudioRecoveryTests'
```

Il controllo del pacchetto verifica incorporamento, bundle associati, versione e
build allineate, piattaforma Watch, eseguibile e icona. Non certifica una firma di
distribuzione né l'approvazione Apple del nuovo identificatore Watch.

I test core coprono messaggi, payload Unicode/copertina, finestre della coda,
selezione di occorrenze, comandi scaduti, cambio brano, schema ignoto e stato vuoto.
Le regressioni UI iPhone coprono ripresa sessione, opzioni player e voce CarPlay.

Esito: **25 test core superati** (otto Watch, sei comandi Siri, undici timing/
recupero audio) e **tre regressioni UI iPhone superate**. Compilazioni per
Watch Simulator e per iPhone Simulator con companion incorporato riuscite;
compilazione Release per iPhone e watchOS reali riuscita senza firma.
Verificati metadati di associazione, versione e icone nei due pacchetti.
Log: `/tmp/notenarrate-watch-core.log`, `/tmp/notenarrate-watch-phone-ui.log`,
`/tmp/notenarrate-watch-phone-build.log`, `/tmp/notenarrate-watch-release.log`.
Risultati UI: `/tmp/NoteNarrate-Watch-Phone-UI.xcresult`.

Sul Mac non è installato un runtime watchOS e non esistono coppie di simulatori
Watch/iPhone. Compilazione per watchOS e controllo dell'embedded bundle sono
verifiche distinte dal rendering sul quadrante e dal trasporto WatchConnectivity.
Aggiornamento beta 0.16.0 (53): firma/provisioning di distribuzione del nuovo
bundle, inclusione nell’IPA ed elaborazione TestFlight verificati. Non è stata
verificata l’installazione su Watch fisico. Resta la prova su Watch abbinato: app aperta
su entrambi i dispositivi, cambio brano, coda con duplicati, narrazione, radio,
iPhone bloccato, allontanamento/riconnessione, risposta tardiva e passaggio CarPlay.
