# Crash audio e caricamenti personali — 8 novembre 2026

## Segnalazione e correzione

Le caselle collegate non hanno restituito la notifica cercata. È stato recuperato
il rapporto di crash originale tramite l’API App Store Connect, relativo a
NoteNarrate 0.16.9 (62), iPhone Duo, iOS 27.2, 8 novembre alle 12:06:43 CET.
Eccezione `EXC_CRASH (SIGABRT)`, thread 7; frame applicativo della richiesta
`AudioRangeBuffer.fetch`, `AudioRangeLoader.swift:240` nella build consegnata.
Il rapporto privato resta fuori dal repository.

Un secondo controllo richiesto dall’utente ha recuperato un nuovo crash della
stessa build e dello stesso Duo alle **14:39:23 CET** (ricevuto da Apple alle
13:39:42 UTC). Firma identica: SIGABRT, thread 7, `AudioRangeBuffer.fetch`,
riga 240; stesso offset nel binario. La build 62 installata non contiene ancora
la correzione locale descritta qui. Anche il secondo rapporto privato resta
fuori dal repository.

Il rapporto non include il motivo testuale dell’eccezione; alcune etichette dei
frame di sistema sono incoerenti e non sono usate per attribuire il crash alla
sessione passeggeri. La chiusura anticipata di URLSession è una causa plausibile
coerente con il frame applicativo: la cancellazione Swift è cooperativa e prima
la sessione veniva invalidata anche se una richiesta stava ancora per nascere.

Ora il buffer rifiuta nuove letture, cancella quelle esistenti e ne attende la
conclusione prima di invalidare la sessione. Chiusure concorrenti condividono
la stessa attesa. Un lettore tardivo può rimuovere solo la propria richiesta,
senza perdere il tracciamento di un eventuale nuovo tentativo sullo stesso blocco.
Il test di regressione sospende intenzionalmente una richiesta durante la
cancellazione e verifica l’ordine reale tra completamento e invalidazione.

Riferimento del contratto URLSession:
https://developer.apple.com/documentation/foundation/urlsession/invalidateandcancel()

## Caricamenti YouTube Music

In Libreria, **Caricamenti → Brani / Album**, con ricerca e ordinamento della
raccolta esistenti. In CarPlay, **Preferiti → Caricamenti personali → Brani
caricati / Album caricati**. Si usa l’account YouTube Music già selezionato;
non occorrono nuove chiavi API o credenziali.

Endpoint autenticati `FEmusic_library_privately_owned_tracks` e
`FEmusic_library_privately_owned_releases`, con tutte le pagine, deduplicazione
e pubblicazione atomica. Il parser riconosce anche il video ID presente solo
nel menu della coda, e i riferimenti privati ad artista/album senza pageType.
Gli album caricati sono già posseduti e non inviano operazioni di salvataggio
destinate agli album commerciali.

L’indicatore di caricamento personale si conserva in coda, ripristino,
preparazione anticipata e download. Il player usa solo l’account proprietario;
nessun tentativo anonimo o sostituzione con una registrazione pubblica. Un
errore di riproduzione personale invita a verificare l’account selezionato.
L’invio di queste tracce a un altro account tramite sessione passeggero viene
rifiutato con un messaggio specifico. Nessuna operazione di upload o eliminazione
di file personali è stata aggiunta.

Riferimenti per il formato del servizio:
https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/uploads.py
https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/parsers/uploads.py

## Verifiche e limiti

- Xcode 27.2 RC (27B48), SDK iOS 27.2; minimi iOS 17 / watchOS 10 invariati.
- 374 test core superati, incluse le regressioni di chiusura concorrente,
  menu privati, album, paginazione e assenza di fallback pubblico.
- Test UI `testPersonalUploadsHaveSeparateSongsAndAlbums` sul simulatore
  iPhone 18 Pro: apertura Caricamenti, alternanza Brani/Album e ritorno ai brani.
- Compilazione Release per iPhone riuscita, senza firma/distribuzione.
- Log locali: `/tmp/nn-crash-uploads-tests.log`,
  `/tmp/nn-crash-uploads-device-final.log`, `/tmp/nn-uploads-ui-final.log`.

Il test UI usa dati fittizi. Restano da collaudare la raccolta reale del
proprietario, la riproduzione dei suoi file e l’assenza del crash sul Duo/CarPlay.
Distribuita su TestFlight come **0.17.0 (63)**: Apple `VALID` /
`IN_BETA_TESTING`, gruppi Team interno e Stivy73 assegnati; Tommaso e Girbreda
verificati. [Ricevuta della consegna](RELEASE-0.17.0-63.md).

## Compatibilità caricamenti dopo la build 63

La diagnostica inviata dal dispositivo mostra account riconosciuto, player HTTP
200 / playability OK, dettagli e streaming presenti, due formati AAC ma zero
candidati. Non mostra il dominio effettivo né un errore di autenticazione.

Il codice accettava soltanto googlevideo.com, anche nella decodifica degli
indirizzi. I caricamenti personali documentati da ytmusicapi possono usare
host Google sotto c.youtube.com con percorso /videoplayback: prima questi URL
venivano cancellati dal decoder e poi esclusi dal selettore. È un difetto
riprodotto nei test coerente con la segnalazione; manca la prova sul file
personale originale del dispositivo.

Ora decodifica, selezione, nonce e validazione condividono la stessa policy
per i due CDN. Restano i controlli HTTPS e del percorso per c.youtube.com,
la conservazione dei parametri firmati e le prove di inizio, oltre 1 MiB e fine.
I caricamenti continuano a usare soltanto la sessione del proprietario.
La diagnostica riporta per formato presenza di URL/cipher e famiglia CDN;
non riporta indirizzi, firme, cookie, identificativi o valori delle query.

La lettura della raccolta riconosce il controllo Shuffle/Play-all rivolto a una
playlist, senza scartare il primo brano per posizione. Le continuazioni dei
caricamenti conservano browseId, query continuation/ctoken, account e visitor.
Una riga realmente illeggibile continua a impedire un salvataggio parziale e
produce una diagnosi di struttura anziché il generico NSURLErrorDomain -1017.
Il messaggio di riproduzione non attribuisce più all’account ogni errore generico.

Riferimenti primari:

- [Player di un caricamento personale, esempio di URL c.youtube.com](https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/browsing.py)
- [Controllo iniziale della raccolta](https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/parsers/library.py)
- [Continuazioni dei caricamenti](https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/uploads.py)

382 test core superati, inclusi 8 nuovi casi su CDN, parametri firmati, validazione
completa, controlli di raccolta, paginazione autenticata e diagnostica senza dati
privati. Compilazione Release iPhone riuscita con Xcode 27.2 RC (27B48), SDK 27.2.
Log locali: /tmp/nn64-core-tests.log e /tmp/nn64-device-build.log.
Queste ulteriori correzioni non sono ancora incluse in una nuova build TestFlight.
La verifica opzionale della disponibilità della sessione sul Mac è stata interrotta
senza risultato; nessuna credenziale è stata mostrata o salvata.
