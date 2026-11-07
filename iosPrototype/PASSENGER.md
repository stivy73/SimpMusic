# Avvio automatico CarPlay — 0.16.5 (58)

Ogni collegamento CarPlay attiva il telefono principale: apre una sessione se
necessario oppure riprende quella già aperta mantenendo QR e passeggeri.
Dopo un riavvio viene creato un nuovo invito, disponibile direttamente su CarPlay.
L’invito non viene salvato su disco. L’accesso del passeggero richiede conferma.

**Coda → Passeggeri** è sempre presente. Se la sessione era stata terminata,
toccare la voce la riapre. La chiusura esplicita viene rispettata fino a una
nuova apertura dal menu o al successivo collegamento CarPlay. La vista QR si
aggiorna al nuovo invito, evitando di mostrare un codice scaduto.

# Invito QR su CarPlay — 0.16.4 (57)

Da **player CarPlay → Coda → Passeggeri → Mostra QR**, il principale mostra
l’invito della sessione già aperta. Il QR si espande nello stesso pannello, senza aggiungere livelli alla navigazione;
**Nascondi QR** ripristina l’elenco. Visualizzarlo o tornare indietro non riapre
la sessione e non interrompe musica o collegamenti Bluetooth. Le richieste di
accesso e i passeggeri autorizzati sono gestibili anche nella schermata QR.

Su iOS 26.4 e successivi il codice occupa la miniatura quadrata del nuovo header
nativo del template lista; sui sistemi precedenti usa una singola immagine di
lista. CarPlay determina la dimensione finale. QR nero su bianco, bordo libero,
moduli allineati ai pixel. Lo stesso generatore è usato su iPhone. L’immagine
resta solo in memoria, viene aggiornata se cambia invito e rimossa a sessione
terminata. Non è salvata nella diagnostica o sul disco.

Verifica automatica con Vision: lettura del contenuto completo a 128, 160, 180,
240, 360 e 720 pixel e dopo riduzione con interpolazione a 160/200/240 pixel.
Rotazione dell’invito verificata. Leggibilità con la fotocamera sul display
fisico dell’auto ancora da confermare; usare l’invito da fermi.

# Collegamento alternativo Bluetooth — 0.16.3 (56)

Distribuita in TestFlight per Team interno e Stivy73; Tommaso incluso nel Team interno.

I report della 55 mostrano il listener principale pronto e l’annuncio Bonjour
pubblicato, ma nessun risultato sul passeggero. L’utente conferma che, scollegando
CarPlay e usando una rete Wi-Fi comune, gli stessi telefoni si abbinano: il difetto
osservato dipende quindi dal contesto di rete con CarPlay wireless attivo.

La 56 aggiunge un canale **Core Bluetooth**, indipendente da Bonjour e dalla rete
IP dell’auto. Il principale lo pubblica quando viene aperta la sessione. Dopo un QR
valido, il passeggero preferisce Wi-Fi e avvia la ricerca Bluetooth dopo 4 secondi
se non ha trovato l’auto. Entrambi devono aggiornare alla 56, attivare Bluetooth e
consentire il permesso a NoteNarrate. Tenere le due app aperte per l’abbinamento.
La ricerca manuale per numero continua a usare Bonjour: in auto usare il QR.

Il QR rimane invariato: autenticazione reciproca HMAC-SHA256 con due nonce casuali,
chiavi direzionali nuove per ogni connessione tramite HKDF-SHA256 e AES-GCM con
contatori contro replay/riordino. Nessuna selezione viene eseguita prima della
conferma del principale. Continuano a viaggiare solo identificatori catalogo,
metadati e comandi; account, audio e chiavi dei servizi restano separati. La chiave
del QR non viene trasmessa né memorizzata. Coda Bluetooth con limiti di memoria,
frammentazione e controllo di flusso; le raccolte fino a 500 brani restano atomiche.

Diagnostica con stato del permesso/radio Bluetooth, scoperta, autenticazione e
conteggio dei collegamenti attivi per trasporto. Nessun identificativo dei
periferici, indirizzo o contenuto musicale nei report. I tempi ripartono dalla
nuova sessione/ricerca, evitando valori accumulati di ore.

Verifiche automatiche: crypto, QR errato, replay, manomissione, contatori,
frammentazione BLE da 20 byte di una selezione di 500 brani, limiti di coda;
integrazione PassengerLink con adattatore radio di test e vera crittografia,
senza risultato Bonjour, approvazione e due riabbinamenti con lo stesso QR.
I test dell’adattatore non sono una prova della radio fisica Core Bluetooth:
**abbinamento Bluetooth con CarPlay wireless confermato funzionante dall’utente dopo la beta 56**.
La lettura del nuovo QR sul display CarPlay della 57 resta invece da collaudare.

Riferimento Apple: https://developer.apple.com/documentation/corebluetooth/transferring-data-between-bluetooth-low-energy-devices .

## Correzione Bonjour e diagnostica — build 55

Il filtro ora riconosce lo stesso identificatore anche quando Bonjour rinomina
l’annuncio con un suffisso numerico, ad esempio `(2)`. Un test con annuncio
rinominato riproduce il mancato abbinamento del vecchio codice e passa con la
correzione, usando vere connessioni Bonjour/TLS. Non è ancora confermato che il
veicolo dell’utente presenti questa specifica rinomina.

Il ritorno in primo piano conserva il listener se è già pronto, evitando riaperture
superflue. Ripristino manuale e collegamento CarPlay possono ancora forzarlo.
La risoluzione del servizio non viene vincolata all’interfaccia osservata dal browser.

In **Sessione in auto → Diagnostica connessione in auto** sono disponibili stato
listener, pubblicazione Bonjour, conteggio annunci, attesa/errori DNS/TLS/POSIX,
scoperta, richiesta e autorizzazione. Il report non include invito, QR, nomi dei
passeggeri, indirizzi, chiavi o contenuti musicali. Se il problema continua con
CarPlay wireless, raccogliere il report da entrambi i telefoni subito dopo il
fallimento; il QR da solo non garantisce un percorso Wi-Fi tra i dispositivi.

# Correzione riconnessione successiva alla beta 53

Ripristino del listener mantenendo invito, collegamenti attivi, stato musicale e
registro delle richieste già eseguite. I callback del listener sostituito sono
ignorati tramite una generazione dedicata, senza invalidare le connessioni TCP
ancora attive. Un errore del listener non cancella più il QR: vengono tentati
fino a tre ripristini e resta disponibile il comando manuale.

Il ripristino viene richiesto anche quando l’app torna attiva e quando si collega
la scena CarPlay. Nella schermata del telefono principale è presente **Ripristina
collegamento**. La ricerca dell’auto dopo una scansione QR ha un limite di 25 secondi,
con istruzioni di recupero se Bonjour non ritrova la sessione. Chiudere esplicitamente
la sessione continua a invalidare il vecchio invito.

Verifiche: 12 test protocollo/trasporto superati, inclusi due abbinamenti consecutivi
con lo stesso QR via Bonjour dopo disconnessione e ripristino listener, nuova
approvazione obbligatoria e conservazione di un collegamento TLS già attivo durante
il ripristino. Build Release iPhone/Watch riuscita. Il cambio di rete del veicolo
su due telefoni fisici resta da collaudare. Correzione distribuita in TestFlight 0.16.1 (54).

Per la beta 53: chiudere la sessione su entrambi i telefoni, aprirne una nuova sul
telefono principale e scansionare il nuovo QR con entrambe le app in primo piano.

---

# Sessione in auto — modalità Passeggero

Distribuita nella beta interna 0.16.0 (53) su TestFlight. Entrambi gli iPhone devono installare una versione con questa funzione.

## Uso

1. Da fermo, sul telefono collegato a CarPlay, aprire **Sessione in auto** dalla
   Home o dalle Impostazioni e scegliere **Apri una sessione nell’auto**.
2. Sul telefono del passeggero aprire la stessa schermata, inserire il proprio
   nome e scegliere **Scansiona QR**. In alternativa cercare l’auto con lo stesso
   numero e inserire il codice mostrato dal telefono principale, oppure incollare
   l’invito condiviso.
3. Il telefono principale deve autorizzare il passeggero. Prima dell’autorizzazione
   non vengono condivisi lo stato del player o i comandi musicali.
4. Il passeggero chiude il pannello e usa normalmente Cerca e Libreria: Play invia
   la selezione all’auto; **Invia all’auto** nei menu permette di aggiungere alla
   coda o riprodurre subito. I comandi di un album operano sulla sua raccolta;
   le playlist vengono caricate integralmente sul telefono del passeggero.
5. Il telefono principale può autorizzare/scollegare persone dalla schermata della
   sessione. Con sessione aperta, **Coda → Passeggeri** offre questi comandi anche
   in CarPlay, insieme alla chiusura della sessione per tutti.

**Aggiungi alla coda** conserva la coda del telefono principale. Se non c’è ancora
un brano, avvia la raccolta. **Riproduci subito** sostituisce la coda con la selezione
inviata. Se si seleziona una traccia in una lista, vengono inviate quella traccia
e le successive. La conferma indica l’accettazione da parte del player; un eventuale
errore della sorgente audio resta visibile sul telefono principale.

Il telefono del passeggero interrompe la propria riproduzione entrando nella
sessione e non riproduce contemporaneamente le selezioni inviate. Alla disconnessione
non riprende automaticamente. Una fascia visibile distingue il collegamento
all’auto, l’attesa di conferma, l’esito dell’invio e gli errori di connessione.

## Collegamento e limiti

- Trasporto locale Network.framework, Bonjour `_nnpassenger._tcp`, TCP con TLS
  e chiave precondivisa derivata da un codice casuale di 24 caratteri (120 bit).
  `includePeerToPeer` abilita i collegamenti Wi-Fi tra dispositivi; il trasporto
  dei comandi esclude l’interfaccia cellulare. La musica sul telefono principale
  continua a usare normalmente la sua rete Internet.
- Wi-Fi attivo su entrambi i telefoni e permesso iOS **Rete locale**. Per la
  scansione serve il permesso Fotocamera; invito e codice funzionano senza camera.
  Non è richiesto un server, un nuovo login o un abbonamento Apple Music/SharePlay.
- Fino a quattro collegamenti simultanei, ciascuno approvato esplicitamente.
  Scollegare un passeggero revoca quel collegamento: per rientrare deve essere
  nuovamente approvato. Chiudere e riaprire la sessione cambia anche il codice.
- Comandi atomici da 1 a 500 brani, coda massima 5.000. Raccolte troppo grandi
  vengono rifiutate con messaggio, senza essere troncate o inviate parzialmente.
- Si trasferiscono soltanto ID YouTube Music, titolo e artista. La playlist privata
  viene letta dall’account del passeggero; l’audio viene risolto dal telefono
  principale con il proprio account e i controlli CDN già presenti. Non si trasferiscono
  cookie, API key, URL firmati, audio, download locali o credenziali.
- Il codice di invito resta in memoria e non viene pubblicato in Bonjour o salvato
  nell’app. Il QR è mostrato soltanto nel pannello di invito. Un URL ricevuto apre
  un’anteprima e richiede un’azione esplicita prima di cambiare la sessione corrente.
- Schema e lunghezza dei messaggi verificati, massimo 1 MiB prima del decoding,
  soli ID catalogo validi, controllo dell’ID sessione e scadenza delle richieste.
  Le conferme sono memorizzate per evitare la riesecuzione di richieste duplicate;
  gli ID ancora validi non vengono scartati per fare spazio a nuove richieste.
- Timeout distinti per collegamento, approvazione e conferma. Nessuna ripetizione
  automatica dei comandi se manca la conferma: il player potrebbe averli già ricevuti.

L’app usa il background audio già esistente, senza aggiungere audio fittizio o
nuovi privilegi in background. Network.framework evita la disconnessione automatica
di Multipeer Connectivity quando l’app passa in background, ma non impedisce a iOS
di sospenderla. Se il telefono principale viene sospeso quando non sta riproducendo,
occorre riaprire NoteNarrate e riconnettersi. La coesistenza con il Wi-Fi di CarPlay
wireless e il comportamento con schermo spento richiedono una prova nell’auto reale.

Riferimenti Apple:
[scelta dell’API di rete](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework),
[Bonjour e TLS tra dispositivi](https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol),
[privacy della rete locale](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Verifiche

- Xcode 27.2 RC (27B48), SDK iOS 27.2, deployment target iOS 17 mantenuto.
- 35 test core mirati: protocollo, framing TCP frammentato/coalescente, limiti,
  identificatori/sessioni/scadenza, registro delle conferme, connessioni TLS reali
  su loopback con approvazione, rifiuto di codice errato, revoca e duplicati;
  regressioni Watch, Siri e recupero audio incluse.
- Quattro test UI iPhone: apertura sessione e rotazione codice con screenshot
  verificato, menu player, vista album e salvataggio impostazioni.
- Due ulteriori test UI di integrazione: il bridge reale su iPhone riceve via TLS
  un’intera raccolta, preserva/sostituisce la coda, ignora il duplicato e inoltra
  i normali comandi Play/Add quando il telefono diventa passeggero, mantenendolo
  silenzioso; regressione del ripristino dell’orologio CarPlay dopo la narrazione.
- Build Debug iPhone/Watch e Release iPhone/Watch compilate.

I test locali non dimostrano la scoperta Bonjour fra due iPhone reali, la lettura
con fotocamera, il comportamento sul Wi-Fi dell’auto o l’esecuzione con schermo
spento. Firma, upload, elaborazione e assegnazioni della beta 53 verificate separatamente
in RELEASE-0.16.0-53.md. Le prove sono elencate in `deliveries/passenger`.
