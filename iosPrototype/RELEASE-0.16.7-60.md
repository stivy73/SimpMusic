# NoteNarrate 0.16.7 (60)

Correzioni alla sincronizzazione dei Mi piace YouTube Music:
- Gestione delle intestazioni playlist, anche modificabili, nelle pagine a una
  o due colonne; lettura delle tracce in secondaryContents e paginazione completa.
- Il caricamento condiviso della raccolta non viene annullato quando una
  schermata scompare. Il cambio account continua a invalidare le richieste.
- Gli errori sul cuore mostrano la causa originale della sincronizzazione.
  Per formati sconosciuti sono riportati solo i nomi delle strutture, senza
  valori, cookie, identificativi o contenuto della risposta autenticata.
- Risposte sconosciute, incomplete o con la sola intestazione continuano a
  essere rifiutate; non sono salvate come raccolte vuote o parziali.

La precedente foto conferma il rifiuto del formato, ma non identifica il nome
della struttura sconosciuta. I formati corretti riproducevano lo stesso errore;
la sincronizzazione sullo specifico account è ancora da collaudare dopo l’update.

62 test mirati superati (Mi piace, libreria, album, playlist e discovery),
inclusi i formati playlist corretti e la paginazione e deduplicazione.
Archivio Release con Xcode 27.2 RC (27B48), SDK iOS 27.2.
Firma ed esportazione riuscite; controlli IPA CarPlay/Siri/widget/share e firma
Watch superati. Minimi iOS 17 e watchOS 10 invariati.

Sorgenti: `23f17b2aae5dcc83f0551ab4dd852bac3cd2edb0`, branch
`feature/youtube-library-albums` su `stivy73/SimpMusic`.
IPA esportata: `deliveries/NoteNarrate-iOS-0.16.7-build60.ipa`.
SHA-256: `db246095968186fa94dd43092e461cddc7ad344dfe24c4854cc9e1ef4e554741`.

Upload Apple riuscito, elaborazione **VALID**, stato **IN_BETA_TESTING**.
Associazioni a **Team interno** e **Stivy73** rilette via API; Tommaso verificato
nel Team interno. Nessuna modifica di utenti/ruoli o pubblicazione App Store.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.7-build60-AppStore-status.json`.
