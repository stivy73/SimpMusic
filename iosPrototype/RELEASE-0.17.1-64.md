# NoteNarrate 0.17.1 (64)

Corregge il filtro che scartava gli indirizzi del CDN c.youtube.com utilizzato
anche dai caricamenti personali. Decodifica, selezione, nonce e validazione
condividono la policy dei CDN Google; i parametri firmati e i controlli di inizio,
oltre 1 MiB e fine restano attivi. Nessun fallback anonimo per i file personali.

Corregge la riga Shuffle/Play-all nella raccolta e conserva endpoint, account,
visitor e token nelle continuazioni. Le righe sconosciute continuano a fallire
senza salvare una raccolta parziale; viene riportata una diagnosi di struttura.
La diagnostica audio distingue i formati e la famiglia CDN senza esporre URL,
firme o cookie. Il player non attribuisce più ogni errore generico all’account.

382 test core superati, inclusi 8 nuovi casi. Compilazione Release iPhone riuscita
con Xcode 27.2 RC (27B48), SDK 27.2. Minimi iOS 17 / watchOS 10 invariati.
La segnalazione della build 63 mostra player OK e due AAC con zero candidati,
ma non il dominio effettivo: la correzione riproduce un difetto coerente con il
log, ancora da verificare sul file privato originale. Nessuna nuova prova fisica
Duo/CarPlay è stata eseguita. [Analisi e verifiche](CRASH_AND_UPLOADS.md).

Archivio firmato, esportazione e upload Apple riusciti. L’IPA verificata è stata
caricata direttamente con il caricatore ufficiale Apple altool.
Controlli di firma e versione app/estensioni/Watch, CarPlay, Siri, Widget e Share
superati. Sorgenti: `1f717366d030eac0ccb17897b447fd31d136b914`, branch
`feature/youtube-library-albums` su `stivy73/SimpMusic`.
IPA: `deliveries/NoteNarrate-iOS-0.17.1-build64.ipa`.
SHA-256: `3f469b828b6cbe272396c327e722b715955bbbcc5afbeb48ef9cabb9b79bd14d`.
Archivio e simboli conservati in
`deliveries/archives/NoteNarrate-0.17.1-build64.xcarchive`.

Elaborazione Apple **VALID**, stato **IN_BETA_TESTING**. Associazioni a
**Team interno** e **Stivy73** rilette via API; appartenenza al Team interno e
accesso alla stessa app di **Tommaso** e **Girbreda** verificati. Note beta
italiane salvate. Nessuna modifica di utenti, ruoli, distribuzione automatica o
pubblicazione App Store.
Ricevuta: `deliveries/NoteNarrate-iOS-0.17.1-build64-AppStore-status.json`.
Verifiche IPA: `deliveries/NoteNarrate-iOS-0.17.1-build64-validation.json`.
Disponibilità ai tester verificata tramite API; resta da provare il file privato
originale sul dispositivo del proprietario.
