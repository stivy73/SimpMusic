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

Consegna TestFlight in preparazione; caricamento, stato e gruppi verranno
registrati dopo conferma Apple.
