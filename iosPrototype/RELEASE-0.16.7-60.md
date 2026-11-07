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

Test, archivio Release, firma, upload e assegnazione TestFlight da verificare.
