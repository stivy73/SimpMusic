# Sessione in auto — modalità Passeggero

Implementata nel sorgente successivo alla beta 0.15.2 (52). Non ancora distribuita
su TestFlight. Entrambi gli iPhone devono installare una versione con questa funzione.

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
spento. Firma di distribuzione, nuova beta e assegnazione ai gruppi non eseguite
per questa implementazione. Le prove sono elencate in `deliveries/passenger`.
