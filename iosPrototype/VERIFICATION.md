# Verifica del prototipo — 11 ottobre 2026

Ambiente: macOS ARM64, Xcode 27.0, Swift 6.4, simulatore iPhone 18 Pro / iOS 27.

| Verifica | Esito osservato |
| --- | --- |
| swift test | 5 test, 0 fallimenti |
| swift-format lint --strict | Superato |
| git diff --check | Superato |
| NetworkProbe | 11 risultati reali; testo del primo brano disponibile, 938 caratteri; contenuto non stampato |
| Test UI live | 1 test, 0 fallimenti, 31.585 secondi |
| Build simulatore | Superata durante il test UI |
| Build generic iOS senza firma | BUILD SUCCEEDED |
| Chiamate IA e TTS Gemini con chiave reale | Non eseguite |
| Firma distribuzione TestFlight | EXPORT SUCCEEDED; Cloud Managed Apple Distribution, Team 63W2ZKR3Z7 |
| Verifica codesign IPA | valid on disk; satisfies its Designated Requirement |
| Archivio Release con icona e privacy manifest | ARCHIVE SUCCEEDED |
| Caricamento TestFlight | App upload complete; 0.1.0 (1) uploaded |
| Stato server Apple | Pronta per il test; scade fra 90 giorni; tester non ancora configurati |
| Installazione/verifica iPhone fisico | Non eseguita; nessun iPhone fisico rilevato |

## Percorso UI verificato

Home → ricerca “Old and Wise The Alan Parsons Project” → selezione del primo risultato →
player incorporato → avanzamento reale di almeno 3 secondi → seek all'80% → avanzamento di
altri 2 secondi → pausa confermata → Libreria → Impostazioni, con campo chiave presente.
La schermata Player.png mostra il brano a 1:24 su 1:40. Non è una schermata costruita con dati fittizi.

Il test non verifica l'intero catalogo, la sincronizzazione account, CarPlay, audio in background,
é generazione/lettura di un'interpretazione con una chiave Google reale.

## Comandi eseguiti

    swift test
    swift run NetworkProbe
    xcrun swift-format lint --strict --recursive Sources Tests Probe UITests Package.swift
    git diff --check

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'platform=iOS Simulator,id=B95C093E-E52D-49E9-AE45-EF8E54906F31' \
      -derivedDataPath /tmp/stivy-ios-build \
      -resultBundlePath /tmp/stivy-ios-ui-tests12.xcresult CODE_SIGNING_ALLOWED=NO test

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' -derivedDataPath /tmp/stivy-ios-device \
      CODE_SIGNING_ALLOWED=NO build

## Problemi trovati e decisioni

- Il primo tentativo nativo AVPlayer appariva avviato ma non avanzava: il controllo del solo
  rate non era sufficiente. Il test finale misura tempo effettivo e avanzamento dopo un seek.
- Il CDN AAC ha servito i primi due blocchi da 512 KiB, ma rifiutato con HTTP 403 il blocco
  successivo e il file completo. La consegna usa il player YouTube incorporato, non questo
  percorso di estrazione incompleto. Le sperimentazioni non sono incluse nel codice dell'app.
- L'embedded player inizialmente restituiva errore 152-4. L'identità del client è stata corretta
  usando come base URL e origin `https://com.stivy.simpmusic.prototype`, secondo la
  documentazione YouTube per app iOS. Il test successivo e il test finale sono riusciti.
- Il ritorno alla Libreria chiude esplicitamente il player; il mini player è collocato sopra
  la barra delle schede. Navigazione verificata nel test UI.
- Xcode segnala che non ci sono App Intents da estrarre; il simulatore segnala una classe
  di accessibilità WebKit duplicata. Non sono errori di compilazione o fallimenti del test.

Licenze incluse: GPL-3.0 del progetto, MIT di YouTubeSDK. Nessuna chiave personale nei sorgenti.

## Tentativo di firma Xcode

Team configurato: Archetipi Digitali srl, `63W2ZKR3Z7`. Il Portachiavi contiene un
certificato Apple Development valido per questo Team fino al 9 ottobre 2027.
Il controllo dei dispositivi ha restituito solo il simulatore.

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' -derivedDataPath /tmp/stivy-ios-signed \
      -allowProvisioningUpdates build

Esito: **BUILD FAILED**, codice 65 durante il provisioning. Xcode segnala
`No Accounts: Add a new account in Accounts settings` e l’assenza di un profilo
iOS App Development per `com.stivy.simpmusic.prototype`. Nessun IPA firmato prodotto.
Dopo lo sblocco del Mac, la pagina Apple Accounts di Xcode ha confermato che manca
un account con accesso attivo. È stata aperta la finestra Sign In; per proseguire
serve completare il login Apple direttamente in Xcode.

### Nuovo tentativo dopo accesso Apple

L’utente ha completato l’accesso Apple in Xcode. La pagina del Team conferma
**Archetipi Digitali srl**, ruolo Admin e **0 Provisioned Devices**.
Ripetuto lo stesso comando di build con `-allowProvisioningUpdates`.
Esito: **BUILD FAILED**, codice 65: `Your team has no devices from which to generate
a provisioning profile`. L’errore No Accounts è risolto; per una firma di sviluppo
installabile serve registrare un dispositivo reale. Nessun IPA firmato prodotto.

### Firma di distribuzione per TestFlight

L’utente non dispone di un dispositivo collegabile e ha scelto TestFlight.
Creato un archivio Release con icona AppIcon opaca 1024×1024, privacy manifest
per preferenze locali, orientamenti iPad completi e dSYM.

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' -derivedDataPath /tmp/stivy-ios-signed \
      -archivePath /tmp/StivySimpMusic-0.1-TestFlight.xcarchive \
      CODE_SIGNING_ALLOWED=NO archive
    xcodebuild -exportArchive -archivePath /tmp/StivySimpMusic-0.1-TestFlight.xcarchive \
      -exportPath /tmp/stivy-ios-testflight-final \
      -exportOptionsPlist /tmp/StivySimpMusic-ExportOptions.plist \
      -allowProvisioningUpdates

Esiti: **ARCHIVE SUCCEEDED**, **EXPORT SUCCEEDED**.
L’export locale usa `method=app-store-connect`, `destination=export`,
`signingStyle=automatic`, `teamID=63W2ZKR3Z7`, test interni.
Certificato: **Cloud Managed Apple Distribution**, valido fino all’11 ottobre 2027.
Profilo: **iOS Team Store Provisioning Profile: com.stivy.simpmusic.prototype**,
`get-task-allow=false`, `beta-reports-active=true`; non richiede dispositivi registrati.

Estratto l’IPA e verificato con:

    codesign --verify --deep --strict --verbose=2 Payload/StivySimpMusic.app

Esito: **valid on disk**, **satisfies its Designated Requirement**.
Autorità: **Apple Distribution: Archetipi Digitali srl (63W2ZKR3Z7)**.
UUID del binario e del dSYM coincidono: `C7F0FBF1-D19E-3803-A32C-09D84F7C493A`.

L’Organizer non riconosceva il Team dell’archivio non firmato. È stato quindi creato
un archivio di consegna copiando nell’archivio l’app firmata dall’export e registrando
Team e SigningIdentity nei metadati esterni. Firma nuovamente verificata, dSYM invariato.
Archivio salvato in `~/Library/Developer/Xcode/Archives/2026-10-11/`.

Il tentativo CLI di upload ha restituito `No Accounts with App Store Connect Access`.
Nell’Organizer l’accesso è riuscito, ma la creazione della prima scheda app non includeva
il campo `companyName`, richiesto da Apple. Aperto App Store Connect in Firefox:
la pagina richiede accettazione iniziale dei Termini di servizio. Caricamento non ancora
completato e nessun test su iPhone fisico effettuato.

Verificati anche tutti i plist con `plutil -lint`, il generatore di icona con
`swift-format lint --strict` e la presenza di Assets.car/PrivacyInfo.xcprivacy
nell’app firmata. I test del prototipo riportati sopra restano quelli della sessione
di implementazione; non sono stati rieseguiti per sole modifiche alla firma e alle risorse.

### Attivazione App Store Connect

L’utente ha scelto di leggere e accettare personalmente i Termini di servizio.
La successiva pagina App di App Store Connect è risultata accessibile, senza il
dialogo dei termini. Compilata la scheda con iOS, nome società Archetipi Digitali srl,
nome StivySimpMusic, lingua italiana, Bundle ID e SKU com.stivy.simpmusic.prototype.
La selezione Accesso limitato è stata bloccata dalla revisione automatica, che richiede
autorizzazione esplicita sul livello di accesso; scelta chiesta all’utente. Scheda
non ancora creata, upload non completato.

### Scheda app creata

L’utente ha autorizzato accesso a tutti gli utenti del Team. Scheda creata nel
Team Archetipi Digitali srl: StivySimpMusic, iOS, lingua italiana, SKU e Bundle ID
com.stivy.simpmusic.prototype, Apple ID `6821630132`.
URL TestFlight: https://appstoreconnect.apple.com/teams/fddd820e-15fa-4f15-a556-b56f300f3acf/apps/6821630132/testflight

Ripresa distribuzione dall’archivio firmato nell’Organizer, canale TestFlight Internal Only.
Stato osservato: Locating signing assets / Preparing. Upload ancora in corso.

### Upload completato

L’Organizer di Xcode conferma **App upload complete**,
**StivySimpMusic 0.1.0 (1) uploaded**.
La pagina TestFlight di App Store Connect mostra **Versione 0.1.0, Build (1)**,
**Elaborazione in corso**. Nessun invito inviato, nessun tester ancora configurato.
La disponibilità effettiva per l’installazione è distinta dall’upload completato.
Conferma visiva salvata in `Screenshots/TestFlight-upload.png`.

### Elaborazione completata

La pagina TestFlight conferma **Build 1 Interni**, **Pronta per il test**,
**Scade fra 90 giorni** per la versione **0.1.0**.
La build è pronta sul server Apple; l’assegnazione a un tester non è ancora stata
eseguita. L’utente è stato invitato a scegliere fra proprio account del Team,
un tester esterno o sola consegna della build caricata. Nessun invito inviato.
Schermata salvata in `Screenshots/TestFlight-ready.png`.

## Distribuzione TestFlight esterna

Su richiesta dell’utente, predisposta build **0.1.0 (2)** abilitata ai test esterni.
Versione aggiornata in Debug e Release; aggiunto TestFlightExternalExportOptions.plist
con `testFlightInternalTestingOnly=false`, esportazione locale e firma automatica.

    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' -derivedDataPath /tmp/stivy-ios-signed \
      -archivePath /tmp/StivySimpMusic-0.1-External.xcarchive \
      CODE_SIGNING_ALLOWED=NO archive
    xcodebuild -exportArchive -archivePath /tmp/StivySimpMusic-0.1-External.xcarchive \
      -exportPath /tmp/stivy-ios-external-export \
      -exportOptionsPlist TestFlightExternalExportOptions.plist -allowProvisioningUpdates

Esiti: **ARCHIVE SUCCEEDED**, **EXPORT SUCCEEDED**, firma valida su disco e
Designated Requirement soddisfatto; Team 63W2ZKR3Z7. UUID binario/dSYM coincidenti.
Il codice funzionale è invariato rispetto alla build già testata.
Salvata copia firmata negli archivi dell’Organizer e IPA in deliveries.
Il caricamento nell’Organizer usa **App Store Connect**, come previsto dalla
documentazione Apple per TestFlight esterno, e risulta in corso.

Descrizione beta, email feedback, contatto autorizzato e istruzioni di verifica
sono stati salvati in App Store Connect. Non è richiesto un account per ricerca
e riproduzione; le funzioni IA sono opzionali e richiedono la chiave Gemini dell’utente.
La chiave del proprietario non è stata condivisa con Apple o con i tester.
Dati personali del contatto e del destinatario dell’invito non salvati nel progetto.

### Upload esterno completato

L’Organizer conferma **App upload complete**, **StivySimpMusic 0.1.0 (2) uploaded**
tramite App Store Connect, senza il canale Internal Only. Conferma salvata in
`Screenshots/TestFlight-build2-upload.png`. Descrizione beta, email feedback,
contatto e note di revisione risultano salvati in App Store Connect.

Il destinatario dell’invito esterno è stato indicato dall’utente. Gruppo esterno,
invito e invio alla revisione beta ancora da completare: il Mac si è nuovamente
bloccato durante la navigazione TestFlight. Richiesto sblocco manuale.
Nessun invito inviato e nessuna revisione beta ancora avviata.


### Revisione beta esterna inviata — 11 ottobre 2026

Corretta la validazione dei contatti nella pagina TestFlight mediante digitazione
e salvataggio. Creato il prerequisito Apple: gruppo **Team interno**, 0 tester,
0 build, distribuzione automatica disattivata. Creato il gruppo esterno
**Beta privata**, aggiunta la build **0.1.0 (2)** e compilate le istruzioni italiane
per il test. Nessun login dell’app richiesto; notifica automatica ai tester selezionata.

Invio alla revisione beta completato: stato verificato **In attesa di verifica**.
Aggiunto il destinatario autorizzato: conferma UI **1 tester è stato aggiunto a
questo gruppo**, gruppo esterno con **1 tester e 1 build**. Lo stato del tester
è **Nessuna build disponibile**, in attesa dell’approvazione Apple. Non è stato
creato alcun link pubblico. Invio effettivo dell’email e installazione su iPhone
non ancora verificati. Nessuna pubblicazione App Store eseguita.

Nessuna modifica funzionale e nessuna nuova compilazione necessaria in questa fase.


### Beta interna predisposta — 11 ottobre 2026

Su richiesta dell’utente aggiunta la build **0.1.0 (2)** al gruppo **Team interno**.
Stato UI della build interna: **Pronta per il test**. Il primo destinatario, già
utente del Team, è stato aggiunto al gruppo; stato UI **Invitato**. Il gruppo
contiene ora **1 tester e 1 build**.

Il secondo destinatario non è ancora utente App Store Connect: predisposta una
bozza d’invito, non inviata, con ruolo Marketing. Richiesti nome e cognome e
conferma del ruolo limitato alla sola app prima di creare l’accesso persistente.
Non modificati i privilegi dell’utente già presente. Dati personali non inclusi
nel progetto. Nessuna nuova compilazione necessaria; installazione non verificata.


### Invito del secondo utente al Team inviato

Ricevuti nome, cognome e conferma del ruolo dall’utente. Invito App Store Connect
inviato con ruolo **Marketing**; nel selettore delle app è stata selezionata
StivySimpMusic, l’unica app presente nel Team. Certificati, profili e creazione
app non abilitati. Conferma UI: invito inviato.

Il destinatario risulta ancora in attesa di accettazione e non compare tra
i tester interni selezionabili. Dopo l’accettazione dell’invito al Team sarà
necessario aggiungerlo al gruppo **Team interno**, già dotato della build
**0.1.0 (2)**. Il primo tester continua a risultare **Invitato**. Nessuna
installazione fisica verificata e nessun dato personale inserito nei sorgenti.

### Test manuale della beta aperta sul Mac — 11 ottobre 2026

Testata la copia iOS in esecuzione sul Mac, selezionando il bundle Wrapper
effettivamente aperto. La ricerca di Old and Wise The Alan Parsons Project ha
restituito risultati reali; selezionato il brano Old and Wise, ID ZmzqqdVFw8g.
Il player incorporato ha caricato la copertina corretta e il tempo di riproduzione
è avanzato. Provati il comando avanti di 15 secondi e la pausa; lo stato finale
era In pausa a 132 secondi. Verificati ritorno alla Libreria e apertura Impostazioni.
Nessun crash osservato durante questi passaggi. Qualità audio non valutata.

La richiesta Significato mostra Inserisci la chiave Gemini nelle impostazioni:
questa copia non ha una chiave configurata. Generazione, lettura TTS e ripresa
automatica dopo TTS non verificabili in questo test. Nessuna credenziale inserita
o impostazione modificata. L'utente ha separatamente confermato che la beta funziona.

### Account YouTube Music e album — 0.2.0 (3), 11 ottobre 2026

Implementata Libreria con album remoti in griglia, refresh, apertura tracce con
SDK esistente e preferiti locali separati. Login WebKit effimero con conferma
esplicita dell'account selezionato sul sito; cookie YouTube e identità selezionata
nel Portachiavi. Versione WEB_REMIX rilevata dalla pagina. Nessuna scrittura nella
libreria remota, nessun nuovo OAuth, nessuna modifica al core Android o all'SDK.

Parser adattato perché quello SDK non accetta i renderer effettivi e non espone
inizializzatori pubblici riutilizzabili. FEmusic_liked_albums con SAPISIDHASH,
X-Goog-AuthUser, eventuale X-Goog-PageId. Continuation esaurite senza limiti di
album, deduplicazione per browseId e protezione da token ripetuti. Errori sulle
pagine successive non pubblicano liste incomplete. Al cambio account/logout
vengono annullate le richieste e invalidate anche le risposte tardive.

Verifiche eseguite:
- `swift test`: **19 test superati**, inclusi richieste Gemini con testo/stile,
  assenza chiave/testo, HTTP 429, WAV, parser, vuoto, più continuation, duplicati,
  token ripetuti, errori parziali, cambio account e logout.
- `xcrun swift-format lint --strict --recursive Sources Tests Probe UITests Package.swift`:
  superato.
- Build iOS generica: **BUILD SUCCEEDED**, senza firma.
- Test UI su iPhone 18 Pro / iOS 27: **3 test superati**, 75 secondi.
  Ricerca e player usano YouTube reale. Il test TTS usa un testo sintetico in DEBUG
  con voce iOS reale: completamento e ripresa, stop, conservazione dello stato
  iniziale in pausa. Terzo test: Libreria senza account, apertura login e annullamento.
- Primo tentativo del test TTS fallito per flag DEBUG mancante nel progetto; aggiunto
  soltanto alle configurazioni Debug e ripetuta l'intera suite con successo.
- WAV ricevuto controllato anche rispetto alla lunghezza dichiarata; errore di
  decodifica AVAudioPlayer gestito con ripresa della musica e messaggio esplicito.
- Durante la preparazione TTS il comando di nuova lettura resta disabilitato.

Log: /tmp/stivy-ios-core-tests.log, /tmp/stivy-ios-ui-build3-fixed.log.
Risultati UI: /tmp/stivy-ios-ui-build3-fixed.xcresult.

Limiti della verifica: nessuna chiave Gemini o sessione YouTube autenticata è stata
fornita durante questa fase. Quindi chiamata Gemini reale, qualità della voce,
confronto album con l'account dell'utente e login Google completato non sono ancora
collaudati. I test con fixture non costituiscono verifica del servizio autenticato.

Distribuzione 0.2.0 (3): archivio Release compilato senza firma e poi firmato con
Xcode Organizer → Custom → App Store Connect → Export → Archetipi Digitali srl →
firma automatica. L'esportazione CLI si è fermata in attesa; la procedura UI ha
completato la firma Cloud Managed Apple Distribution. IPA in
`deliveries/StivySimpMusic-iOS-0.2.0-build3.ipa`, SHA-256 accanto al file.
Verifica `codesign --verify --deep --strict --verbose=2`: valid on disk,
satisfies its Designated Requirement. Il test va eseguito fuori dalla sandbox
per consentire l'accesso alla verifica dei certificati.
L'hook `--test-meaning` è assente dal binario Release.


### TestFlight 0.2.0 (3) disponibile — 11 ottobre 2026

Xcode Organizer conferma `App upload complete: StivySimpMusic 0.2.0 (3) uploaded`.
App Store Connect ha completato l'elaborazione: `Pronta per il test`. Aggiunta la
build al gruppo esistente **Team interno**, con **3 tester**; stato successivo
**Test in corso**. Le note italiane di test sono state salvate (conferma UI Salvato).
Nessun nuovo accesso al Team, nessun link pubblico e nessuna pubblicazione App Store.
L'installazione della nuova build da parte dei tester non è ancora verificata.
Restano da collaudare login Google, album dell'account e Gemini con credenziali reali.


## Player adattivo e navigazione — 0.3.0 (4), 11 ottobre 2026

Player a schermo intero, disposizione verticale su iPhone e a due colonne quando
lo spazio lo consente; Dynamic Type accessibile conserva la disposizione verticale.
AnyLayout mantiene il WebView durante la rotazione. Libreria e chiusura verso la
schermata precedente sono comandi distinti; il mini player riapre il brano in pausa
alla posizione salvata. Uscire interrompe anche TTS, senza riavviare musica nascosta.
Il comando Riprova ricrea il player anche per lo stesso video. Gli eventi sono
accettati soltanto dal WebView attivo e dal frame principale.

Verifiche sul codice finale:
- Core: 19 test superati, 0 fallimenti (`/tmp/stivy-ios-core-build4.log`).
- iPhone 18 Pro: 4 test UI superati, 0 fallimenti, 100.201 secondi;
  ricerca/playback reale, seek, TTS nativo e ripresa, login annullato,
  rotazione e riapertura con posizione e pausa conservate.
  Risultati: `/tmp/stivy-ios-phone4-stable.xcresult`.
- iPad: 1 test UI superato, 0 fallimenti, 59.237 secondi;
  playback reale, seek, rotazione, ritorno e riapertura in pausa.
  Risultati: `/tmp/stivy-ios-ipad4-mobile.xcresult`.
- Screenshot landscape di iPhone e iPad ispezionati: video e controlli su due
  colonne, titolo leggibile; contenuto verticale scorrevole sui display bassi.
- `xcrun swift-format lint --strict --recursive Sources Tests Probe UITests Package.swift`
  e `git diff --check`: superati.
- Archivio Release: ARCHIVE SUCCEEDED, senza firma iniziale.
  `/tmp/StivySimpMusic-0.3.0-build4-mobile.xcarchive`.

Comandi UI: xcodebuild test con scheme StivySimpMusic, CODE_SIGNING_ALLOWED=NO,
-collect-test-diagnostics never; destinazioni iPhone
B95C093E-E52D-49E9-AE45-EF8E54906F31 e iPad 07BF9DF4-4A60-4A80-B0D4-4CC0812A51E6.
Per iPad: -only-testing:PrototypeUITests/PrototypeUITests/testRotationAndReopeningPreservePausedPosition.
Archivio: xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic
-configuration Release -destination 'generic/platform=iOS'
-archivePath /tmp/StivySimpMusic-0.3.0-build4-mobile.xcarchive
-derivedDataPath /tmp/stivy-ios-release CODE_SIGNING_ALLOWED=NO archive.

Problemi risolti nel collaudo: WebKit in modalita desktop su iPad restava in
buffering; impostato preferredContentMode mobile, poi superato il test completo.
La prima suite iPhone finale aveva due fallimenti del test: risultato fuori area
visibile con orientamento ereditato e tap in concorrenza con autoplay. Isolato
l'orientamento di ogni test, cercato il risultato scorrendo e atteso l'autoplay
prima dell'eventuale tap. Ripetuta l'intera suite con esito positivo.

Limiti: nessun nuovo test su iPhone/iPad fisici o wrapper Mac. Il test TTS usa
la voce iOS reale con testo sintetico DEBUG, non una chiamata Gemini reale.
Login autenticato e album dell'account richiedono ancora credenziali dell'utente.
Audio in background e CarPlay non implementati in questa build.


Firma e upload 0.3.0 (4): Xcode Organizer Custom → App Store Connect → Upload,
Team Archetipi Digitali srl, TestFlight internal testing only, firma automatica,
versione/build non gestite automaticamente. Conferma App upload complete.
Esportato lo stesso IPA dopo l'upload; codesign --verify --deep --strict conferma
valid on disk e satisfies its Designated Requirement. Versione 0.3.0, build 4;
flag DEBUG --test-meaning assente dal binario. IPA e SHA-256 in deliveries.


TestFlight 0.3.0 (4): elaborazione Apple completata; aggiunta al gruppo esistente
Team interno (3 tester), stato Test in corso. Note italiane salvate. Nessun nuovo
invito o privilegio, nessuna pubblicazione App Store. Installazione da parte dei
tester non ancora verificata.


## Prompt e accesso YouTube Music — 0.3.1 (5), 12 ottobre 2026

Il system prompt iOS era abbreviato rispetto ad Android. Ora coincide esattamente
con AiService.explainSong: italiano, prima storia/situazione (chi parla, eventi,
evoluzione), poi interpretazione, fatti distinti da possibili letture, niente versi
o retroscena inventati, incertezza esplicita, 855–945 caratteri inclusi gli spazi.
`python3 Scripts/CheckAndroidPrompt.py` confronta i due sorgenti: identici.
Restano differenze deliberate di comportamento: iOS richiede il testo e riprova
una volta se la lunghezza non rientra; non tronca il TTS a metà frase.

Rifiuto browser riprodotto con richieste pubbliche senza cookie: lo user agent
WebKit predefinito restituisce pagina unsupported (2.058 caratteri); Safari desktop
restituisce YouTube Music con ytmusic-app. Il WebView di login usa ora identità
Safari/WebKit desktop; il player video mantiene la propria configurazione mobile.
Aggiunti caricamento, ricarica in errore e conferma disabilitata finché la pagina
Music non è pronta. Nessun cambiamento al salvataggio cookie o all'account.

Verifiche: 19 test core superati; formatter e diff check superati; test live iPhone
login 1/1 passato (28.572 s), dopo rifiuto dei cookie facoltativi nella sessione
effimera. Primo test si era fermato sul consenso Google: non era più la pagina
browser unsupported. Screenshot finale ispezionato: home Music e pulsante Accedi.
Login Google completo e album autenticati NON verificati.
Release 0.3.1 (5): ARCHIVE SUCCEEDED, /tmp/StivySimpMusic-0.3.1-build5.xcarchive.
Risultati /tmp/stivy-login5-consent.xcresult, log /tmp/stivy-core5.log.

Test Gemini reale con chiave autorizzata letta solo in memoria: NetworkProbe usa
GeminiService dell'app e testi ottenuti dall'SDK. Con prompt allineato: 931 caratteri,
16 secondi; Gemini TTS Kore/Professionale: WAV decodificato di 66 secondi, generazione
26 secondi. Nessuna chiave o testo dei brani nei log/repository. Non è una prova
acustica della voce né della pausa/ripresa nell'app: quelle richiedono test UI.
Il precedente probe con prompt abbreviato aveva prodotto 899 caratteri e WAV 61 s.

Distribuzione: Xcode conferma upload completato 0.3.1 (5) su App Store Connect.
IPA esportata e firma Apple verificata con codesign --verify --deep --strict;
versione e build controllate dal plist, hook --test-meaning assente dal binario.
Copia in deliveries/StivySimpMusic-iOS-0.3.1-build5.ipa con SHA256.

App Store Connect conferma 0.3.1 (5) in Test in corso, associata a Team interno
(3 tester). Note italiane salvate con conferma Salvato. Nessuna modifica a utenti
o permessi; nessuna distribuzione esterna o pubblicazione App Store.

## Verifica account reale — 12 ottobre, 0.3.2 (8)

Sulla beta Mac 0.3.1 (5), dopo login Google completato dall'utente, riprodotto
"Formato della libreria non riconosciuto". La sessione persiste anche aggiornando
tramite TestFlight (build 6 e 7). La diagnostica della build 7 identifica
`section-contents:unknown`: sectionListRenderer senza contents. Il parser visitava
tutte le tab, incluse le schede inattive con contenuti caricati solo su richiesta.
Corretto il traversal: sceglie selected=true; in assenza di selected, prima tab con
content, come il parser Android. Nessun ripiego su un'altra tab se la selezionata
è malformata. Aggiunto conteggio album nella griglia. La conferma sulla sessione
reale della correzione è ancora pendente: non dichiarare la causa risolta finché
la build 8 non è stata provata sul Mac.

Diagnostica degli errori limitata ai nomi/contatori di renderer, senza valori dei
campi, cookie, token, nomi album o identità. Test dedicato conferma che valori
privati non compaiono nel messaggio. Test nuovi: scheda attiva prima/dopo placeholder;
scheda attiva malformata non deve leggere altre schede; nessuna richiesta da logout;
risposta tardiva dopo logout scartata. Login/switch/logout automatici usano account
fittizi; non è stato eseguito logout dalla sessione reale dell'utente.

Riferimento dell'utente da cercare dopo il caricamento: Bon Jovi Greatest Hits.
Archive release: /tmp/StivySimpMusic-0.3.2-build8-final.xcarchive, ARCHIVE SUCCEEDED.
Xcode ha richiesto nuovamente il login Apple durante la distribuzione della build 8.
La beta installata al momento di questa nota è 0.3.1 (7), solo diagnostica.

Aggiornamento dopo il nuovo login Apple: Xcode conferma upload completato di
0.3.2 (8). App Store Connect mostra Test in corso e gruppo Team interno (3 tester).
TestFlight Mac mostra Aggiorna per 0.3.2 (8); aggiornamento avviato, poi Mac bloccato.
Il controllo del plist dopo il blocco mostra ancora 0.3.1 (7): installazione e prova
reale della build 8 NON confermate. IPA firmata esportata in
../deliveries/StivySimpMusic-iOS-0.3.2-build8.ipa, con SHA256 affiancato.


### Esito sul Mac dopo lo sblocco

Installazione 0.3.2 (8) confermata dal plist dell'app e da TestFlight.
Sessione Google preservata. La griglia carica 155 album: percorrendo l'elenco
via UI sono stati raccolti 155 browseId distinti, fino a Wish You Were Here.
Bon Jovi Greatest Hits e The Ultimate Collection (Deluxe) entrambi presenti.
Refresh reale concluso con 155 album. Apertura di Bon Jovi Greatest Hits:
tracce visualizzate, incluse Livin' On A Prayer e You Give Love A Bad Name.
Il precedente errore section-contents non ricompare nella sessione verificata.
Non è stato misurato il numero di richieste continuation sul traffico reale;
il completamento e la protezione dai loop sono coperti dai test del parser.
Firma IPA verificata con codesign --verify --deep --strict fuori sandbox: OK.
Riproduzione avviata dalla traccia Livin' On A Prayer dell'album: il player
mostra Riproduzione attiva e il tempo avanza fino a 0:37. Messo in pausa e
riaperta la griglia (155 album) al termine della prova.


## Player con interfaccia Android — 0.4.0 (9), 12 ottobre 2026

Copertina predefinita e video opzionale, con una sola sessione WKWebView mantenuta
attiva passando fra copertina, testo e video. Icone per preferiti locali, significato,
menu, testo e coda; controlli precedente/successivo e selezione dalla coda. Le tracce
di un album ereditano la copertina dell'album. Testo recuperato dall'SDK e riusato
per l'interpretazione, con inserimento manuale, espansione, copia e condivisione.
Nessuna sincronizzazione delle righe: il provider restituisce testo senza timestamp.

Verifiche eseguite:
- 23 test Swift: superati.
- swift-format lint --strict e git diff --check: superati.
- CheckAndroidPrompt.py: prompt iOS/Android identici.
- Test UI copertina → video → copertina: posizione e pausa conservate; testo manuale
  visualizzato; cambio brano dalla coda e rimozione del vecchio testo: superato.
- Test UI rotazione/riapertura con posizione e pausa conservate: superato.
- Test UI TTS nativo con pausa e ripresa della musica: superato.
- Archivio Release generic iOS: ARCHIVE SUCCEEDED.

I primi test hanno rilevato overflow dello sfondo e identificazione inaffidabile
dell'editor del testo. Corrette dimensioni dello sfondo, aree di pressione delle
icone e identificatore accessibile; il test completo successivo è passato.
Risultati: /tmp/stivy-player9-ui2.xcresult (rotazione/TTS),
/tmp/stivy-player9-ui3.xcresult (percorso completo). Screenshot portrait e landscape
esaminati. Nessuna nuova chiamata Gemini a pagamento eseguita per questa modifica.
Il controllo del volume è inoltrato all'IFrame Player: l'effetto sul volume di un
 iPhone fisico resta da verificare. Riproduzione nativa in background non implementata.

Distribuzione: il tentativo CLI è fallito con No Accounts with App Store Connect Access.
La distribuzione tramite Organizer è riuscita: App upload complete, 0.4.0 (9).
App Store Connect conferma Test in corso, gruppo Team interno con 3 tester; note
salvate. Firma Cloud Managed Apple Distribution verificata con codesign --deep --strict.
IPA conservato in deliveries/StivySimpMusic-iOS-0.4.0-build9.ipa con SHA-256.
Build ID Apple: b59da12f-f8ce-4fc7-9265-5baa1ead92cb.
La nuova beta non è stata ancora installata e collaudata su un iPhone fisico.


## Avanzamento player e diagnosi latenza — 0.4.1 (10), 12 ottobre 2026

Il timer JavaScript setInterval è stato sostituito da un timer nativo a 500 ms
in modalità common del RunLoop. Interroga getCurrentTime/getDuration reali, senza
simulare il progresso. Il timer viene invalidato quando il WKWebView viene smontato;
una richiesta in corso impedisce l'accumulo di interrogazioni. Questa scelta evita
di dipendere dai timer di una pagina resa invisibile dalla copertina.

Test UI reale ricerca/play/avanzamento/seek/nuovo avanzamento/pausa: superato
(/tmp/stivy-progress-ui.xcresult). Sul Mac la build 0.4.0, dopo riapertura del player
Baby Can I Hold You, avanzava da 0:43 a 1:14 e 1:26: il blocco segnalato non è stato
riprodotto stabilmente. La causa esatta sul dispositivo dell'utente resta da confermare.

Misura NetworkProbe con API reale, una sola esecuzione su Old and Wise:
- recupero testo: 0,23 s;
- generateContent: 23,69 s, 869 caratteri, un solo tentativo;
- Interactions TTS: 23,84 s, audio WAV completo di 63 secondi.
Tempi indicativi di questa richiesta/rete, non benchmark comparativo simultaneo Android.
Nessuna chiave, contenuto del testo o audio salvati nei log del probe.

Confronto del codice: Android riproduce Gemini PCM da streamGenerateContent SSE e
conserva una cache audio; iOS attende Interactions/WAV completo e non ha tale cache.
iOS può inoltre fare una seconda richiesta di interpretazione per rispettare 855–945
caratteri; Android usa una sola richiesta. I testi iOS vengono caricati quando richiesti
o aprendo il pannello Testo, mentre il player Android passa il testo già disponibile.

Il popup ora distingue recupero testo, generazione interpretazione e preparazione
voce. Lo streaming TTS e la cache non sono stati modificati in questa patch: la diagnosi
individua questi interventi come principali opportunità di riduzione dell'attesa.

Build 0.4.1 (10): ARCHIVE SUCCEEDED. Test UI TTS nativo con pausa/ripresa: superato
(/tmp/stivy-progress-tts-ui.xcresult). Lint Swift e parità del prompt: superati.
Distribuzione bloccata prima dell'upload: Xcode riporta Unable to authenticate with
App Store Connect. Aperta la finestra di accesso; richiesto rinnovo manuale all'utente.
Archivio: /tmp/StivySimpMusic-0.4.1-build10.xcarchive. Nessuna build 10 caricata.

## 0.4.2 (11): streaming TTS e cache audio — 12 ottobre 2026

La 0.4.1 (10) è stata successivamente caricata con successo da Xcode dopo il
rinnovo del login Apple (Organizer: Uploaded to Apple).

GeminiService usa ora streamGenerateContent SSE per il player, con testo integrale,
voce scelta e speech_metadata.style. Il decoder valida PCM16 mono 24 kHz, errore
Google, finishReason e completamento; una risposta parziale non diventa cache.
PCMStreamPlayer usa AVAudioEngine/AVAudioPlayerNode, buffer da mezzo secondo e
non più di sei secondi accodati. La fine attende dataPlayedBack, non dataConsumed.
Stop e cambio brano cancellano la richiesta e l'audio; errori di riproduzione hanno
un limite di attesa. La ripresa riguarda solo il brano che era in play all'avvio.

Cache locale in Library/Caches/MeaningSpeech-v1, esclusa dal backup, massimo
100 MiB con espulsione LRU. Identità SHA256 su formato/modello/voce/stile/testo;
checksum dell'audio, scrittura atomica solo a stream completo. Nessuna chiave API
salvata nella cache. Un testo rigenerato differente richiede un nuovo audio.

Verifiche eseguite:
- swift-format lint --strict: superato; CheckAndroidPrompt.py: prompt identico.
- swift test: 32 test, zero errori (/tmp/stivy-stream-tests-final.log).
  Inclusi parser SSE, HTTP, dati mancanti/incompleti, formati, integrità e LRU cache,
  attesa dell'ultimo campione PCM e annullamento.
- 2 test UI iPhone 18 Pro iOS 27: superati (/tmp/stivy-stream-ui.xcresult).
  Trasporto PCM deterministico, rotazione durante la lettura, completamento,
  riascolto da cache, stop e ripresa; regressione TTS nativo con brano inizialmente
  in pausa. Non è una verifica soggettiva della qualità della voce.
- API Google reale con NetworkProbe --stream-key-file, testo diagnostico italiano
  di lunghezza comparabile all'interpretazione, senza nuovi versi inviati:
  primo PCM 0,88 s; avvio AVAudioEngine 0,92 s; 2.899.200 byte, durata 60,40 s;
  ultimo buffer riprodotto a 61,40 s. Recupero identico da cache: 0,003 s senza HTTP.
  Il tempo di fine rete (55,37 s) include backpressure del player, non misura
  la sola velocità di generazione del server. Nessuna credenziale nei log.
- Il vecchio probe WAV attendeva 23,84 s: confronto indicativo, testi/richieste
  differenti. Queste misure non includono generazione dell'interpretazione.
- Archivio Release: ARCHIVE SUCCEEDED (/tmp/stivy-stream-archive.log).
  Comando: xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic
  -configuration Release -destination 'generic/platform=iOS'
  -archivePath /tmp/StivySimpMusic-0.4.2-build11.xcarchive
  -derivedDataPath /tmp/stivy-ios-release CODE_SIGNING_ALLOWED=NO archive.

Build 11 firmata e caricata con successo (Organizer: Uploaded to Apple).
Superata dalla build 12 prima di assegnarla al gruppo interno.


## 0.4.3 (12): NoteNarrate e mini-player persistente — 12 ottobre 2026

Nome visibile NoteNarrate, icona fornita dall’utente e intestazione aggiornata.
Bundle ID, Keychain, target e signing team conservati per continuità degli aggiornamenti.

La riduzione del player chiamava pause e distruggeva la WKWebView alla chiusura
della fullScreenCover. Ora il player resta montato nella radice, nascosto e non
interattivo quando ridotto: Home, Cerca e Libreria non interrompono la sessione.
Il mini-player dispone di Pausa/Riprendi e conserva lo stato iniziale di pausa.

Verifiche: entrambi i test UI finali superati (/tmp/notenarrate-mini-ui.xcresult).
Il test reale YouTube verifica avanzamento del tempo dopo riduzione, cambio delle
tre schede, riapertura, ritorno alla Libreria e pausa esplicita dal mini-player.
Il secondo test verifica streaming TTS, rotazione, stop e ripresa della musica.
Lint Swift superato. I 32 test core precedenti restano superati (core invariato).
Archivio finale Release: ARCHIVE SUCCEEDED (/tmp/notenarrate-build12-final.log),
/tmp/NoteNarrate-0.4.3-build12-final.xcarchive. L’archivio precedente build12 senza
il fix mini-player non è stato caricato.

Archivio finale firmato e upload completato in Xcode il 12 ottobre. Organizer
riporta due avvisi non bloccanti: asset description generation e asset describer
task failed. Verifica dell’elaborazione Apple e assegnazione al gruppo interno
ancora da completare. IPA firmata: deliveries/NoteNarrate-iOS-0.4.3-build12.ipa
(con SHA256); pacchetto App Store, non installabile direttamente come APK.


Conferma App Store Connect, 12 ottobre 2026: NoteNarrate 0.4.3 (12),
build 8fc64cb9-6eff-4833-8e3d-3bf28399b81b, elaborata e assegnata a
Team interno (3 tester), stato Test in corso. Note della beta salvate
con conferma Salvato. Nome NoteNarrate visibile anche nella scheda Apple.
Gli avvisi Xcode non hanno impedito l’elaborazione e la disponibilità della beta.


## 0.4.4 (13): latenza prima della voce — 12 ottobre 2026

La catena precedente iniziava il recupero del testo al clic e rigenerava sempre
l’interpretazione. Gemini 3.8 Flash usava il ragionamento dinamico predefinito.
Ora il testo viene recuperato all’avvio del brano, riusando lo stesso task per il
pannello testi e l’interpretazione. Nessuna generazione IA a pagamento anticipata.
Solo il modello verificato gemini-3.8-flash usa thinkingLevel low: i modelli
personalizzati restano con la propria configurazione. Prompt e controllo della
lunghezza 855–945 caratteri invariati, inclusa la seconda richiesta se necessaria.

Cache locale dell’interpretazione: al massimo 50 testi, 7 giorni, esclusa dal
backup. Identità su prompt, modello, titolo, artista e contesto effettivo (anche
testo manuale). La riapertura riusa lo stesso testo e quindi la cache audio;
Rigenera interpretazione permette una nuova richiesta esplicita. Non si salvano
chiavi API o testi originali nella cache interpretazioni. Nessuna cache su errori.

Probe reale con testo diagnostico originale italiano, stessa richiesta/prompt:
- default: interpretazione 28,64 s, 919 caratteri; primo PCM 0,65 s; totale 29,29 s;
- low: interpretazione 3,04 s, 881 caratteri; primo PCM 0,63 s; totale 3,67 s.
Un confronto sequenziale indicativo, non una garanzia di latenza. Nessun recupero
YouTube incluso in questa misura. Probe interrotto dopo il primo PCM: verifica
rete, non durata riproduzione. /tmp/notenarrate-latency-probe.log.
Comando: swift run NetworkProbe --latency-key-file [file chiave autorizzato].

36 test core superati (/tmp/notenarrate-latency-tests.log), inclusi cache persistente,
scadenza, identità, limite, contenuti corrotti, configurazione Google e retry
lunghezza. Swift-format lint strict e CheckAndroidPrompt.py superati.
Archive Release 0.4.4 (13) riuscito: /tmp/NoteNarrate-0.4.4-build13.xcarchive.
Due test UI superati (75,69 s): continuità musicale minimizzando e cambiando tab;
streaming TTS con rotazione, completamento, stop e ripresa musica.
Risultati: /tmp/notenarrate-latency-ui.xcresult.

Distribuzione: dopo autorizzazione esplicita al percorso Custom, selezionato
Archetipi Digitali srl e attivato TestFlight internal testing only, disattivata
la gestione automatica versione/build. Xcode conferma App upload complete,
StivySimpMusic 0.4.4 (13) uploaded, senza avvisi.
ExportOptions conferma teamID 63W2ZKR3Z7, testFlightInternalTestingOnly=true.
Copia firmata: ../deliveries/NoteNarrate-iOS-0.4.4-build13.ipa.
SHA256: ebc27f32997845d78fb1eed4ad79ccad7d13f4f41dc445ab9566db7b0b2e43df.
Conferma App Store Connect, 12 ottobre 2026: 0.4.4 (13), build
16d3fc70-6ee0-4ae6-affe-4585c5fd1dcd, elaborata e assegnata a Team interno
(3 tester), stato Test in corso. Note italiane salvate con conferma Salvato.


## 0.4.5 (14): minimizzazione animata — 12 ottobre 2026

RootView conserva il PlayerScreen e la WKWebView, animando posizione, scala
e angoli verso il basso in 0,42 s con curva spring. La riapertura usa il
movimento inverso. Il player ridotto viene spostato fuori dall'area visibile,
con hit testing e accessibilità disabilitati. Il viewport segue la rotazione.
Con Riduci movimento attivo la transizione è una dissolvenza di 0,16 s.

Swift-format lint strict superato; CheckAndroidPrompt.py: prompt identico.
Archive Release 0.4.5 (14) riuscito: /tmp/NoteNarrate-0.4.5-build14.xcarchive.
Comando: xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic
-configuration Release -destination 'generic/platform=iOS'
-archivePath /tmp/NoteNarrate-0.4.5-build14.xcarchive
-derivedDataPath /tmp/stivy-ios-release CODE_SIGNING_ALLOWED=NO archive.

Due test UI superati, zero errori (73,245 s):
- testMinimizingKeepsMusicPlayingAcrossTabs: audio continuo, mini-player
  raggiungibile, controlli del player aperto nascosti, riapertura e pausa;
- testRotationAndReopeningPreservePausedPosition: rotazione, riapertura,
  posizione in pausa e ritorno alla Libreria.
Risultati: /tmp/notenarrate-animation-ui.xcresult.
Registrazione simulator /tmp/notenarrate-animation-test.mp4, sequenza
/tmp/notenarrate-animation-detail.png: movimento graduale verificato.

Xcode conferma App upload complete, StivySimpMusic 0.4.5 (14) uploaded,
senza avvisi. ExportOptions conferma Team 63W2ZKR3Z7,
testFlightInternalTestingOnly=true e manageAppVersionAndBuildNumber=false.
IPA firmata: ../deliveries/NoteNarrate-iOS-0.4.5-build14.ipa.
SHA256: c60a98ac51eda80efd5d31e4f241ab57464826f65bcae94d8a0048d57632e64f.
Assegnazione al gruppo interno ancora da completare: Firefox viene cambiato
durante le azioni, richiesta una finestra libera per due minuti.

## Home SimpMusic — 0.5.0 (15), 12 ottobre 2026

Implementazione iOS basata sul codice reale di HomeViewModel, HomeScreen,
HomeRepositoryImpl, HomeParser e MoodAndGenres del checkout SimpMusic/core.
Versione marketing 0.5.0, build 15; il Bundle ID resta quello della beta esistente.

### Verifiche completate

- `swift test`: **52 test, zero fallimenti**. Nuovi test coprono carousel misti,
  metadati/Altro, categorie/colore/params, pagina vuota, formato inatteso,
  continuations a catena, token ripetuti, deduplicazione, retry dopo HTTP error,
  cambio account/logout, rinnovo cookie e trasporto autenticato.
- `Scripts/CheckHomeFilters.py`: tutti i **10 params identici** a HomeViewModel Android.
- `Scripts/CheckAndroidPrompt.py`: prompt dell'interpretazione ancora identico ad Android.
- `swift-format lint --strict`: superato su Sources, Tests, Probe, UITests,
  Package.swift e sui tre file SDK adattati.
- Probe reale anonimo `swift run NetworkProbe --home`: Home con 3 sezioni iniziali,
  altra sezione via continuation, 12 mood/momenti e 25 generi. Categoria Allenamento:
  5 sezioni, 91 elementi. Playlist: 100 tracce iniziali + 10 da continuation.
  Filtro Relax: 3 sezioni. Le quantità/titoli della Home cambiano sul server.
- Test UI live **Home → Relax → Tutto → categoria → playlist → brano → playback
  in avanzamento → mini-player attivo → pausa**: superato, 37.280 secondi.
- Regressione UI **ricerca → playback → riduzione/riapertura animata → navigazione
  Home/Libreria/Cerca → avanzamento e pausa mantenuti**: superata, 41.492 secondi.
- Build simulatore e archivio Release generic iOS: **BUILD/ARCHIVE SUCCEEDED**.
  Archivio: `/tmp/NoteNarrate-0.5.0-build15-final.xcarchive`.
- Licenza MIT/copyright SDK: conservati nel vendor e inclusi nell'app Release
  in ThirdPartyNotices.txt, consultabile in Impostazioni → Licenze open source.

Screenshot reali del simulatore: Home-0.5.png, Home-categories-0.5.png,
Home-category-detail-0.5.png in Screenshots. Nessun dato fittizio nella Home.

### Decisioni e problemi risolti

- Il parser SDK precedente perdeva album/playlist/artisti annidati e pulsanti
  di categoria. Ora una copia locale conservata in Vendor/YouTubeSDK normalizza
  quei renderer e riusa gli inizializzatori originali; non si modifica .build.
- Trasporto WEB_REMIX condiviso con la libreria: cookie, SAPISIDHASH,
  X-Goog-AuthUser, X-Goog-PageId e versione client della sessione esistente.
- La continuation anonima richiede visitorData coerente: viene conservato dal
  trasporto della Home. Il caricamento parallelo delle categorie usa un trasporto
  distinto per non sostituirlo. Il primo probe aveva fallito prima di questa correzione.
- Le playlist a due colonne hanno tracce in secondaryContents, separate dal tab
  principale: entrambi vengono analizzati, scegliendo soltanto il tab attivo.
  Le continuation di una playlist vengono distinte da quelle dei carousel Home.
- La Home carica le altre sezioni durante lo scorrimento, prima della griglia dei
  generi, senza tetto di pagine.
  Errori nelle pagine successive sono visibili, con Riprova; token già consumati
  fermano il caricamento. Refresh e nuovo account sostituiscono i dati.
- Due tentativi UI iniziali hanno fallito: il primo test scorreva durante il cambio
  filtro, il secondo ha scoperto il problema secondaryContents. Il collaudo finale
  attende il caricamento e verifica anche la riproduzione dalla playlist.

### File interessati

App: StivyApp.swift, MusicModel.swift, YouTubeLibrary.swift, **HomeView.swift (nuovo)**.
Core: **YouTubeBrowse.swift, HomeDiscovery.swift, HomeModel.swift (nuovi)**.
Tests: **HomeDiscoveryTests.swift, YouTubeBrowseTests.swift (nuovi)**; UITests/PrototypeUITests.swift.
Probe: main.swift e **HomeProbe.swift (nuovo)**; **Scripts/CheckHomeFilters.py (nuovo)**.
Configurazione: Package.swift, StivySimpMusic.xcodeproj/project.pbxproj.
Documentazione/asset: README.md, VERIFICATION.md, **ThirdPartyNotices.txt (nuovo)**,
3 screenshot e **Vendor/YouTubeSDK (nuovo)** con 3 file parser/model adattati.
Non sono stati modificati Android o core Kotlin per questo porting Home.

### Limiti della verifica attuale

Il collaudo rete/simulatore è anonimo: autenticazione, cambio account e invalidazione
sono testati con fixture. “Ascolta di nuovo”, avatar, cronologia e consigli dell'account
sono renderizzati quando forniti da YouTube Music, ma la corrispondenza con la Home
personale richiede la prova sulla sessione Google della beta aggiornata.
La Home non aggiunge download, CarPlay o audio musicale nativo in background.

### Comandi

    swift test
    swift run NetworkProbe --home
    python3 Scripts/CheckHomeFilters.py
    python3 Scripts/CheckAndroidPrompt.py
    xcrun swift-format lint --strict --recursive Sources Tests Probe UITests Package.swift
    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'platform=iOS Simulator,id=B95C093E-E52D-49E9-AE45-EF8E54906F31' \
      -derivedDataPath /tmp/stivy-ios-tests \
      -resultBundlePath /tmp/notenarrate-home-ui-release.xcresult \
      -only-testing:PrototypeUITests/PrototypeUITests/testLiveHomeFiltersGenresAndCategoryNavigation \
      CODE_SIGNING_ALLOWED=NO test
    xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic \
      -destination 'generic/platform=iOS' -derivedDataPath /tmp/stivy-ios-release \
      -archivePath /tmp/NoteNarrate-0.5.0-build15-final.xcarchive CODE_SIGNING_ALLOWED=NO archive

Firma/caricamento TestFlight completati il 12 ottobre 2026 dopo lo sblocco del Mac:
Xcode conferma **StivySimpMusic 0.5.0 (15) uploaded**. Esportazione con firma
Cloud Managed Apple Distribution, Team Archetipi Digitali srl, versione automatica
disabilitata, simboli inclusi e **TestFlight internal testing only** abilitato.
IPA conservata in `deliveries/NoteNarrate-iOS-0.5.0-build15.ipa` del repository principale.
SHA256: `f442d7b2214f700fd132698b90caf8f4df3239600aedaa4b502b15341e6cb799`.
`codesign --verify --deep --strict` eseguito fuori sandbox: superato; catena
Apple Distribution → Apple Worldwide Developer Relations → Apple Root CA verificata.
L'esecuzione nel sandbox non poteva accedere al servizio di fiducia macOS.

App TestFlight sul Mac: la precedente 0.4.5 (14) risulta installata, quindi
l'assegnazione manuale della build 14 è stata completata dall'utente.
Elaborazione server e assegnazione della build 15 al gruppo Team interno non ancora
confermate: Firefox era utilizzato dall'utente durante il controllo della scheda
App Store Connect. Non è stata modificata l'assegnazione della build 14.

## Recupero automatico dei testi — 0.5.1 (16), 12 ottobre 2026

`LyricsResolver` riusa il parser YouTubeSDK e poi cerca sul catalogo online LRCLIB,
lo stesso fallback presente in `LyricsCanvasRepositoryImpl` Android. Richieste GET
`https://lrclib.net/api/search?track_name=...&artist_name=...`, senza chiavi IA o cookie
YouTube. User-Agent NoteNarrate con versione e URL del fork, timeout 10 secondi,
pausa fra ricerche e rispetto di Retry-After in caso di 429. Nessuno scraping generico
di pagine web o generazione del testo da parte dell'IA.

Titolo e artista devono corrispondere dopo normalizzazione; sono rimossi solo suffissi
tecnici (remaster, official audio/video, mono/stereo), non sottotitoli, Live o Acoustic.
Quando la durata è nota, tolleranza di 10 secondi e preferenza per il risultato più vicino.
Risultati strumentali, vuoti o privi di metadati validi sono scartati. LRC convertito
in testo senza timestamp, con tutte le righe conservate. Cache positiva in memoria
di 100 brani; risultati mancanti non memorizzati. Cambio brano e retry annullano il
recupero precedente con controllo di generazione prima di aggiornare la UI.

La risposta reale per Dreams conteneva due record con `duration: null`: ora il campo
è opzionale e i record non validi non fanno perdere gli altri risultati. La ricerca
con durata nota scarta record senza durata. MusicModel riusa la stessa task anticipata
sia nel pannello Testo sia nel Significato. Progresso “Cerco il testo online…” e fonte
visibili; solo dopo un esito negativo delle fonti resta l'inserimento manuale.
Prompt italiano 855–945 caratteri, interpretazione/cache audio/TTS invariati.

Verifiche eseguite:
- `swift test`: **68 test passati**, inclusi 16 nuovi test su fallback, cache, durata,
  normalizzazione, risultati omonimi, LRC, risposta vuota/malformata, HTTP, 429 e annullamento.
- `Scripts/CheckAndroidPrompt.py`: prompt identico ad Android.
- Probe reale `--lyrics-fallback 'November Rain' "Guns N' Roses"`: LRCLIB,
  **2030 caratteri, 0,31 secondi**, testo presente nel contesto IA; versi non stampati.
- Probe reale `--lyrics-fallback 'Dreams (2004 Remaster)' 'Fleetwood Mac'`: dopo
  la correzione del null, LRCLIB, **1218 caratteri, 0,18 secondi**, contesto IA verificato.
  Prima della correzione questo probe falliva; non era un problema della chiave IA.
- Build iOS Simulator: riuscita. Test UI `testNativeSpeechPausesThenResumesMusic`:
  riuscito, ripresa al termine e rispetto della pausa originaria allo stop manuale.
  Il testo IA nel test UI è una fixture; non è una prova end-to-end Gemini sul brano.
  Primo tentativo UI fallito per due pulsanti “Chiudi” nel sistema iOS corrente;
  introdotto identificatore univoco `close-meaning`, test finale superato.
- Formatter globale Sources/Tests/Probe/UITests/Package.swift: superato.
- Archivio Release finale riuscito dopo correzione parser LRCLIB:
  `/tmp/NoteNarrate-0.5.1-build16-final.xcarchive`.

File della funzione: nuovo `Sources/Core/LyricsResolver.swift`, nuovo
`Tests/LyricsResolverTests.swift`, nuovo `Probe/LyricsProbe.swift`; integrazioni in
MusicModel.swift, StivyApp.swift, Interpretation.swift, Probe/main.swift, UITests,
pbxproj (versione 0.5.1 / 16), README e questo report. Modifiche concorrenti per il
client Mac nei file condivisi preservate e incluse nella verifica di compilazione iOS.
Build 16 compilata, non caricata. La revisione automatica ha rifiutato il comando
di firma/esportazione/upload su TestFlight perché manca autorizzazione esplicita
per la nuova build 0.5.1 (16). Nessun tentativo alternativo di upload dopo il rifiuto.
L'utente ha poi autorizzato esplicitamente firma e caricamento della build16 su
TestFlight interno. Procedura CLI avviata il 12 ottobre 2026: export fallito con timeout App Store
Connect e No Accounts with App Store Connect Access. Nessun upload riuscito.
Il percorso GUI TestFlight Internal Only si ferma con No Team Found in Archive;
Team e SigningIdentity nel plist dell'archivio non firmato sono vuoti.
La selezione Custom e un tentativo di ripristino del solo metadato Team sono stati
rifiutati dalla revisione automatica; il metadato NON è stato modificato.
L'utente ha confermato: Sì, Custom solo TestFlight interno. Procedura GUI
riavviata con App Store Connect / Upload e Team Archetipi Digitali srl.
Prima errore helper, poi autenticazione ASC fallita. Riavviato Xcode dal menu: il
controllo accesso è passato e la GUI ha raggiunto Locating and creating signing assets.
Review IPA: Cloud Managed Apple Distribution, Team63W2ZKR3Z7, profilo Store
per com.stivy.simpmusic.prototype, versione0.5.1(16), get-task-allow=false.
Verificati i checkbox: Upload symbols=1, Manage version/build=0, TestFlight internal
testing only=1. Upload completato: Xcode mostra App upload complete — StivySimpMusic0.5.1(16)
uploaded; Organizer conferma Uploaded to Apple / Build Number16.
Esportazione in /tmp/NoteNarrate-0.5.1-build16-export: ExportOptions.plist conferma
method=app-store-connect, teamID=63W2ZKR3Z7, testFlightInternalTestingOnly=true,
manageAppVersionAndBuildNumber=false e uploadSymbols=true.
Copia conservata nel repository: deliveries/NoteNarrate-iOS-0.5.1-build16.ipa.
SHA256: f6cb0a2ff27db663accdb7c4316fe2b78298f76d40adf5900c73b8c1dc16a4fe.
codesign --verify --deep --strict eseguito fuori sandbox: superato. Catena Apple
Distribution: Archetipi Digitali srl (63W2ZKR3Z7) → WWDR → Apple Root CA.
Plist della IPA verificato: NoteNarrate0.5.1, build16, bundlecom.stivy.simpmusic.prototype.
Nessuna modifica manuale ai metadati Team dell'archivio originale o della copia.
Elaborazione Apple e assegnazione al gruppo Team interno non ancora confermate;
non sono stati aperti browser o modificati tester in questa task di caricamento.

## Verifica CarPlay — beta 0.5.1 (16)

Esito: **integrazione CarPlay non implementata**. Verifica del codice iOS/Mac condiviso,
del plist della IPA esportata e del suo profilo di provisioning, confrontati con la
documentazione Apple. Nessuna modifica a player, capacità dell'account o firma.

La IPA NoteNarrate 0.5.1 / 16, bundle com.stivy.simpmusic.prototype, dichiara
UIBackgroundModes=[audio], ma il suo UIApplicationSceneManifest contiene
UISceneConfigurations vuoto. Nel progetto non ci sono import CarPlay, scene
CPTemplateApplicationScene, delegate CarPlay, template o entitlement CarPlay.
Il profilo embedded.mobileprovision, decodificato con security cms, appartiene al
Team63W2ZKR3Z7 e NON include com.apple.developer.carplay-audio né
com.apple.developer.playable-content. Questo verifica il profilo della beta;
non stabilisce se il Team abbia già un'approvazione Apple per altre app/profili.

Il tentativo di lettura entitlements con codesign sul Mac non restituisce XML
utilizzabile per questo binario iOS: non è usato come prova dell'assenza di CarPlay.
La conclusione si basa invece su sorgenti, manifest e profilo incorporato.

| Funzione | Situazione verificata |
| --- | --- |
| Icona e interfaccia NoteNarrate nel launcher CarPlay | Mancano configurazione scena e capability nel profilo della beta. |
| Home, generi, Ascolta di nuovo | HomeModel/HomeDiscovery già riusabili; nessuna presentazione CarPlay. |
| Album YouTube salvati e continuation | LibraryModel/YouTubeLibrary già riusabili; nessun browser album CarPlay. |
| Preferiti | La UI iOS legge MusicModel.favorites locali. Il metodo SDK getLikedSongs esiste, ma non è integrato nella UI; non equiparare i due archivi. |
| Download | Non implementati nel prototipo iOS. |
| Play/pausa, precedente/successivo, posizione, copertina di sistema | Controlli dell'app presenti; manca integrazione MPRemoteCommandCenter/MPNowPlayingInfoCenter. |
| Riproduzione con telefono bloccato o app in background | Player effettivo = WKWebView + YouTube IFrame, non AVPlayer audio gestito dall'app. UIBackgroundModes da solo non dimostra supporto. |
| Interpretazione con lampadina, streaming TTS, cache, Stop e ripresa | Pipeline già presente in MusicModel/Core, nessun comando o popup CarPlay. |

PlaybackPlayer, usato da MusicModel, invia i comandi via evaluateJavaScript al player YouTube;
EmbeddedPlayer crea la WebView e l'IFrame. La AVAudioSession dell'app viene configurata
per la lettura TTS, non per una sessione musicale nativa persistente. Non risultano
handler dell'app per interruzioni/route change o comandi remoti. Lo SDK contiene un
YouTubeAVPlayer basato su AVPlayerItem, ma non è il player usato nell'app attuale;
la disponibilità effettiva degli stream va verificata prima di riutilizzarlo.

Percorso proposto, non ancora implementato:

1. Stabilizzare la riproduzione musicale in background e integrare metadati/controlli
   MediaPlayer, inclusi interruzioni, cambio brano e ripresa dopo TTS.
2. Verificare/richiedere l'entitlement audio CarPlay per l'App ID e aggiornare il
   profilo, senza considerare la firma TestFlight esistente come approvazione CarPlay.
3. Aggiungere una scena iOS CarPlay, con controller condivisi e template Apple per
   Home, Album e Preferiti. Non duplicare login, parser, continuation, IA o TTS.
   I Download richiedono una funzione dedicata prima di poter essere mostrati.
4. Aggiungere al Now Playing un CPNowPlayingImageButton con lampadina. Riutilizzare
   l'analisi dei testi e TTS, con presentazione CarPlay separata: solo titolo
   “Significato della canzone” e azione Stop, senza mostrare il testo interpretativo.
   Alla fine/Stop riprendere soltanto lo stesso brano se era in riproduzione.
5. Testare scena e controlli nel simulatore CarPlay, poi su iPhone con un sistema
   CarPlay reale: telefono bloccato, chiamata/Siri, scollegamento, rete assente,
   libreria oltre la prima pagina, cambio account e annullamento del TTS.

CarPlay supporta pulsanti immagine nel Now Playing e alert con azioni: la lampadina
e Stop sono tecnicamente rappresentabili. Questo non garantisce l'approvazione
Apple dell'esperienza finale. Il simulatore non mostra app senza gli entitlement
necessari: non è stato aperto né è stato dichiarato un test CarPlay riuscito.
Inventario simctl verificato: runtime iOS27 disponibile, simulatori spenti.
Nessuna build/test funzionale eseguita in questa verifica, poiché non c'è codice
CarPlay da provare; non sono state modificate le versioni o pubblicate nuove build.

Fonti Apple:
- [Entitlement CarPlay](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
- [Scene CarPlay](https://developer.apple.com/documentation/carplay/displaying-content-in-carplay)
- [App musicale CarPlay](https://developer.apple.com/documentation/carplay/integrating-carplay-with-your-music-app)
- [Now Playing](https://developer.apple.com/documentation/carplay/cpnowplayingtemplate)
- [Pulsante immagine](https://developer.apple.com/documentation/carplay/cpnowplayingimagebutton)
- [Alert e azioni](https://developer.apple.com/documentation/carplay/cpalerttemplate)
- [Simulatore CarPlay](https://developer.apple.com/documentation/carplay/using-the-carplay-simulator)
Nessuna modifica ad accessi del Team o alla beta 15.

## Background e integrazione CarPlay — 0.6.0 (17), 14 ottobre 2026

- `swift test`: 73 test, zero fallimenti. Selezione AAC/HLS, esclusione URL/codifiche
  non valide, range HTTP, intent di riproduzione e gestione delle interruzioni.
- `swift run NetworkProbe --audio ZmzqqdVFw8g`: metadati, AAC HTTP206 e decodifica
  AVPlayer reale con tempo avanzato oltre due secondi; audio probe silenziato.
- Simulatore iPhone18Pro/iOS27: `testNativeAudioStartupDiagnostic` riuscito.
- Tre test UI riusciti in `/tmp/notenarrate-background-verified.xcresult`:
  `testMinimizingKeepsMusicPlayingAcrossTabs`,
  `testNativeMusicContinuesWhenAppEntersBackground` (8s fuori dall'app e tempo
  effettivo avanzato oltre 6s), `testNativeSpeechPausesThenResumesMusic`.
  Il brano è fisso e reale; l'interpretazione di questa prova è un testo di fixture
  letto dalla sintesi nativa, non una richiesta IA/Gemini aggiuntiva.
- Ultima verifica dopo gli aggiustamenti dei callback: background e TTS entrambi
  riusciti in `/tmp/notenarrate-background-final-check.xcresult`. Linter rigoroso
  sui file modificati senza errori. Archivio finale 0.6.0 (17) salvato in
  `deliveries/archives/NoteNarrate-0.6.0-build17-unsigned.xcarchive`.
  Eliminati i risultati dei test falliti e le cache di compilazione di questa
  verifica; conservati i risultati funzionali, sorgenti e pacchetti distribuiti.
- I test iniziali falliti hanno individuato e corretto: ricorsione del delegate
  SwiftUI, callback artwork eseguito fuori dal MainActor, richieste complete CDN
  rifiutate e attesa di stime throughput indisponibili al resource loader.
  I test di lifecycle non dipendono più dall'ordinamento variabile della ricerca.
- `CheckAndroidPrompt.py` e `CheckHomeFilters.py`: invariati e identici ad Android.
- Archivio Release iOS senza firma riuscito con `xcodebuild -project
  StivySimpMusic.xcodeproj -scheme StivySimpMusic -destination
  'generic/platform=iOS' -derivedDataPath /tmp/notenarrate-ios17-release
  -archivePath /tmp/NoteNarrate-0.6.0-build17.xcarchive CODE_SIGNING_ALLOWED=NO archive`.
- Build Mac senza firma riuscita: `xcodebuild -project NoteNarrateMac.xcodeproj
  -scheme NoteNarrateMac -destination 'generic/platform=macOS'
  -derivedDataPath /tmp/notenarrate-mac-regression CODE_SIGNING_ALLOWED=NO build`.
- Il profilo attuale dell'App ID non contiene entitlement CarPlay. Manifest/delegate
  e template sono compilati. La GUI Simulator non è disponibile fra le app
  controllabili; nessun test visivo CarPlay è stato dichiarato riuscito.
- Restano prove reali su iPhone/auto, comandi Lock Screen/Control Center, avvio da
  CarPlay, cambio account nella scena auto, contenuti con restrizioni/URL scaduti,
  chiamate/Siri e lettura Gemini completa con ripresa. Nessuna nuova IPA firmata
  o nuova distribuzione TestFlight effettuata in questa implementazione.

## Richiesta entitlement Apple — 14 ottobre 2026

- In Chrome, con Team Archetipi Digitali srl (`63W2ZKR3Z7`) verificato, accettato
  il CarPlay Entitlement Addendum (rev. 06-08-2026), dopo l'autorizzazione specifica
  dell'utente, e inviata la richiesta di categoria Audio.
- Apple conferma “Thank you for your submission” e informa che la richiesta sarà
  esaminata. Ricevuta: `deliveries/carplay/request-submitted-2026-10-14.png`.
- Il modulo non prevede nome app, bundle ID o descrizione: la richiesta è per il
  Team; l'app destinataria prevista è NoteNarrate, `com.stivy.simpmusic.prototype`.
- App ID verificato nel portale, identificatore `3SYXQW6572`: CarPlay Audio non
  disponibile nelle capability abilitabili; scheda Capability Requests con
  “CarPlay Audio App” e “No Status”. Nessuna modifica a App ID o profili.
- Firma CarPlay, esportazione IPA e distribuzione restano in attesa della
  concessione Apple. Nessuna nuova compilazione o prova runtime in questa fase.

## CarPlay concesso e pacchetto verificato — 0.6.0 (17), 14 ottobre 2026

- L'utente ha comunicato la mail di concessione Apple. Nel portale, Team
  `63W2ZKR3Z7` e App ID `com.stivy.simpmusic.prototype` verificati, selezionata
  CarPlay Audio App (CarPlay framework), salvata e confermata dopo la riapertura
  dell'App ID. Prova: `deliveries/carplay/capability-enabled-2026-10-14.png`.
- Debug e Release includono ora `CARPLAY_ENTITLEMENTS_FILE=NoteNarrateCarPlay.entitlements`.
  Disabilitata `INFOPLIST_KEY_UIApplicationSceneManifest_Generation`: la generazione
  automatica sovrascriveva con un dizionario vuoto il ruolo CarPlay del plist sorgente.
  Il plist dell'archivio finale conserva `CPTemplateApplicationScene` e il delegate
  `StivySimpMusic.CarPlayScene`.
- Archivio Release riuscito con `xcodebuild -project StivySimpMusic.xcodeproj
  -scheme StivySimpMusic -destination 'generic/platform=iOS' -derivedDataPath
  /tmp/notenarrate-carplay-release -archivePath
  /tmp/NoteNarrate-0.6.0-build17-CarPlay-final.xcarchive CODE_SIGNING_ALLOWED=NO archive`.
- Il primo export da archivio senza firma ometteva l'entitlement nell'app. Una
  firma ad hoc preparatoria con il file di entitlement, sostituita dall'export
  Cloud Managed Apple Distribution, conserva CarPlay. Un tentativo di compilare
  direttamente l'archivio con firma ad hoc è stato rifiutato dall'SDK iOS perché
  richiede un profilo; nessun pacchetto intermedio è stato distribuito.
- Export finale Apple riuscito con `xcodebuild -exportArchive -archivePath
  /tmp/NoteNarrate-0.6.0-build17-CarPlay-final.xcarchive -exportPath
  /tmp/NoteNarrate-0.6.0-build17-CarPlay-verified-export -exportOptionsPlist
  /tmp/NoteNarrate-CarPlay-ExportOptions.plist -allowProvisioningUpdates`.
  Opzioni: app-store-connect, destination export, Team corretto, test interni,
  numero versione/build invariato. IPA conservata in
  `deliveries/NoteNarrate-iOS-0.6.0-build17-CarPlay.ipa`.
- Nuovo `Scripts/CheckCarPlayIPA.py`: verifica ZIP, firma e profilo con CarPlay,
  Team/bundle, get-task-allow=false, ruolo/delegate CarPlay e audio in background.
  Il controllo ha rifiutato un pacchetto con manifest vuoto e ha poi superato la
  verifica della IPA corretta. `codesign --verify --deep --strict`: superato.
  Report: `deliveries/carplay/build17-ipa-verification.json`.
  SHA256: `145cff1c4f195f907fb5382cb57ef31586636c7b0a4a941ac97801ce73eaedcd`.
- Due test UI sul simulatore iPhone18Pro/iOS27 riusciti, zero fallimenti:
  `testMinimizingKeepsMusicPlayingAcrossTabs` e
  `testNativeMusicContinuesWhenAppEntersBackground`. Risultati:
  `/tmp/notenarrate-carplay-signing-regression.xcresult`. Prompt e filtri Home
  ricontrollati: identici ad Android. Sintassi Python e plist verificati.
- L'upload della build17 su TestFlight è stato rifiutato dalla revisione automatica:
  richiede autorizzazione specifica per questa build, distinta dalla precedente
  build16 e dall'abilitazione CarPlay. Nessun upload o assegnazione ai tester
  effettuato in quel tentativo. L'utente ha poi autorizzato esplicitamente
  il caricamento della build17; upload CLI completato alle 21:16 (Europe/Rome),
  con “Upload succeeded” e pacchetto in elaborazione Apple. I log della firma
  di upload confermano CarPlay Audio negli entitlement effettivi. La IPA locale
  verificata è un'esportazione separata dello stesso archivio; destination upload
  non conserva una seconda IPA nella cartella di export.
- Elaborazione Apple conclusa: versione0.6.0/build17 “Pronta per il test”.
  Assegnata al gruppo esistente Team interno, senza aggiungere tester o cambiare
  accessi; stato finale confermato “Test in corso”, gruppo Team interno.
  Prova: `deliveries/carplay/testflight-build17-testing-2026-10-14.png`.
  Build Apple ID: `e71d12de-4198-40f3-b840-ed1caa596d3f`. Distribuzione solo interna.
  Resta il collaudo della scena CarPlay su iPhone/auto reali: la firma verificata
  e i test del player telefonico non sostituiscono una prova sul display dell'auto.

## Correzioni CarPlay — 0.6.1 (18), 17 ottobre 2026

Segnalazioni reali con foto: popup interpretazione senza voce, Now Playing senza
cover e navigazione album testuale. Le foto non consentono di attribuire con
certezza il silenzio a un singolo errore runtime; non è disponibile il log dell'iPhone.

- Eliminata la presentazione contemporanea sul telefono quando la richiesta viene
  da CarPlay. La chiusura del foglio telefonico non annulla una richiesta auto.
- Protezione della preparazione IA/TTS con background task limitato e scadenza
  gestita; sessione media unica per musica, AVSpeechSynthesizer e PCM, senza cambio
  di modalità a spokenAudio. La voce nativa usa la sessione dell'app. Cancellazioni
  di sistema ed errori sono visibili in CarPlay con Riprova, senza testo del significato.
- Le notifiche di configurazione iniziale di AVAudioEngine non vengono trattate
  come errori quando il motore funziona; se si ferma durante la lettura viene
  segnalata l'interruzione. Ripresa limitata allo stesso brano con intento attivo.
- Il percorso album conserva artwork e artista dell'album quando assenti nei
  renderer dei brani, evitando anche ricerche LRCLIB prive dell'artista. Nessun
  cambiamento al prompt italiano, ai requisiti sui testi o alla scelta del provider.
- Home, Album, Preferiti e contenuti usano CPGridTemplate con cover originali a
  colori, pagine sullo stesso template e limite Apple letto a runtime. Nessun
  taglio arbitrario della libreria. Artwork condiviso con Now Playing, cache
  limitata, quattro richieste concorrenti e controlli contro aggiornamenti obsoleti.
- Nuovi file: `Sources/App/AppleArtwork.swift`, `Sources/Core/CarPlayContent.swift`,
  `Tests/CarPlayContentTests.swift`. Aggiunti test UI di preparazione in background
  e lettura completa per sintesi nativa e PCM, con verifica del provider artwork.
  I test UI usano un testo di fixture e PCM sintetico; non sono una prova in auto.
- `swift test --scratch-path /tmp/notenarrate-carplay18-core-tests`: 78 test,
  zero fallimenti. Include traversata di 513 album senza perdite/duplicati,
  libreria vuota/ridotta, copertina preferita, ID non validi e metadati artista.
- Formatter/linter rigoroso sui file modificati: superato. CheckAndroidPrompt.py
  e CheckHomeFilters.py: identici ad Android.
- Test reale Google: `swift run --scratch-path /tmp/notenarrate-carplay18-core-tests
  NetworkProbe --stream-key-file <file-locale-protetto>`. Chiave mai stampata o
  salvata nei log. Primo PCM 1,45s, primo buffer 1,50s; 60,28s di audio PCM,
  ultimo buffer completato a 61,83s; cache identica, riascolto senza HTTP 0,001s.
  Eseguito su Mac: conferma il servizio/decoder, non il routing dell'auto.
- Archivio iOS Release riuscito con `xcodebuild -project StivySimpMusic.xcodeproj
  -scheme StivySimpMusic -destination 'generic/platform=iOS' -derivedDataPath
  /tmp/notenarrate-carplay18-build -archivePath
  /tmp/NoteNarrate-0.6.1-build18-CarPlay-ready.xcarchive CODE_SIGNING_ALLOWED=NO archive`.
  Manifest CarPlay e versione/build verificati. Build Mac condivisa riuscita.
- I test UI non sono stati eseguiti: Xcode aggiornato a 27.1 richiede CoreSimulator
  1174.9.2, mentre il componente installato è 1171.7.0. Riavvio del solo servizio
  utente insufficiente; Xcode chiede Install Required per i componenti ufficiali.
  Il Mac è bloccato e il tool richiede sblocco manuale. Nessun simulatore cancellato.
  La compilazione dei test con `build-for-testing` e destinazione generica
  iOS Simulator è invece riuscita; log `/tmp/notenarrate-carplay18-build-for-testing.log`.
- Export locale tentato, non riuscito: Xcode segnala No Accounts e credenziali
  Portachiavi incomplete (Xcode-Username mancante). Nessuna IPA18 firmata o nuova
  distribuzione TestFlight. Prima di pubblicare: completare componenti/login Xcode,
  eseguire i test UI, esportare e verificare con CheckCarPlayIPA.py; poi ottenere
  autorizzazione specifica per il caricamento della build18 ai tester interni.

### Ripresa verifiche — 18 ottobre 2026

- Dopo lo sblocco manuale, i componenti di Xcode 27.1 risultano disponibili.
  Riutilizzato il runtime iOS 27.0 già installato, senza scaricare i 15,9 GB del
  runtime 27.1 e senza cancellare dispositivi o dati del simulatore.
- Eseguiti quattro test UI sul simulatore iPhone 18 Pro/iOS 27.0: tutti superati,
  zero fallimenti, 127 secondi di esecuzione. Coprono preparazione e lettura nativa
  in background, preparazione e streaming PCM in background, provider artwork di
  sistema, ripresa musica, minimizzazione/cambio scheda e lettura dal player interno.
  Le fixture vocali/PCM non richiedono chiavi API e non dimostrano il routing audio
  su un'auto reale. Comando concluso con `TEST SUCCEEDED`; `xcresulttool` conferma
  Passed, 4 superati, 0 falliti e 0 saltati. Risultati:
  `/tmp/notenarrate-carplay18-ui-verified.xcresult`; log:
  `/tmp/notenarrate-carplay18-ui-verified.log`. La raccolta diagnostica finale del
  simulatore è scaduta dopo 600 secondi, senza fallire i test o il risultato.
  Segnalati warning di runtime sull'attivazione sincrona della sessione audio e
  sull'inversione di priorità; non sono crash. Il test non misura la latenza
  dell'hardware CarPlay.
- Comando: `xcodebuild -project StivySimpMusic.xcodeproj -scheme StivySimpMusic
  -destination 'platform=iOS Simulator,id=B95C093E-E52D-49E9-AE45-EF8E54906F31'
  -derivedDataPath /tmp/notenarrate-background-carplay-build
  -resultBundlePath /tmp/notenarrate-carplay18-ui-verified.xcresult
  -only-testing:PrototypeUITests/PrototypeUITests/testCarPlayNativeNarrationStartsInBackgroundAndResumesMusic
  -only-testing:PrototypeUITests/PrototypeUITests/testCarPlayStreamingNarrationStartsInBackgroundAndResumesMusic
  -only-testing:PrototypeUITests/PrototypeUITests/testNativeSpeechPausesThenResumesMusic
  -only-testing:PrototypeUITests/PrototypeUITests/testMinimizingKeepsMusicPlayingAcrossTabs
  CODE_SIGNING_ALLOWED=NO test`.
- Xcode conferma ancora nessun account Apple configurato. Aperta la finestra di
  accesso del Team; richiesta all'utente l'immissione privata di password/2FA.
  Firma Apple, verifica IPA18 e distribuzione TestFlight restano da completare.
- L'utente ha successivamente completato il login. Account Michele Stival visibile
  in Xcode; avviata una nuova esportazione Apple locale della build18, senza upload.
- Esportazione conclusa con `EXPORT SUCCEEDED`: `xcodebuild -exportArchive
  -archivePath /tmp/NoteNarrate-0.6.1-build18-CarPlay-ready.xcarchive
  -exportPath /tmp/NoteNarrate-0.6.1-build18-CarPlay-signed-export
  -exportOptionsPlist /tmp/NoteNarrate-CarPlay18-ExportOptions.plist
  -allowProvisioningUpdates`. Opzioni destination export, distribuzione solo interna,
  Team 63W2ZKR3Z7, versione e numero build invariati.
- `Scripts/CheckCarPlayIPA.py` superato fuori sandbox: CarPlay presente nella firma
  e nel profilo Apple, firma valida, bundle/Team e scene corretti, audio background.
  IPA: `deliveries/NoteNarrate-iOS-0.6.1-build18-CarPlay.ipa`.
  Report: `deliveries/carplay/build18-ipa-verification.json`.
  SHA256: `b7777c03a15b8a97da499420f1c8d8d6e4193067f95b79822d1a65adfe9ccafc`.
  Pacchetto App Store Connect solo TestFlight interno, non installabile direttamente.
  Nessun upload18 o assegnazione ai tester effettuati; rimane l'autorizzazione per
  questa nuova distribuzione e il collaudo nell'auto reale.
- L'utente ha autorizzato caricamento e assegnazione ai tester interni con
  “Procedi”. Upload `xcodebuild -exportArchive` dallo stesso archivio e
  `TestFlightExportOptions.plist` concluso il 18 ottobre 2026 alle 07:17 Europe/Rome:
  “Upload succeeded”, “Uploaded package is processing”, `EXPORT SUCCEEDED`.
  Log: `/tmp/notenarrate-carplay18-upload.log`. Elaborazione e assegnazione al
  gruppo non ancora confermate; non dichiarate disponibili dal solo upload.
- I log della firma di upload confermano `com.apple.developer.carplay-audio = 1`.
  App Store Connect aperto in Chrome con il profilo archetipi-digitali.it; pagina
  ferma sullo spinner anche dopo un ricaricamento, senza campi di accesso utilizzabili.
  Chiesto all'utente di verificare la scheda lasciata aperta. Nessuna modifica ai
  tester, ai gruppi o alle impostazioni di distribuzione attraverso il browser.
  Prova: `deliveries/carplay/testflight-build18-web-loading-2026-10-18.jpg`.
