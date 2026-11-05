# NoteNarrate 0.16.1 (54)

Correzione del crash Watch alla prima risposta dell’iPhone: callback di
WatchConnectivity esplicitamente Sendable e gestione del ciclo di avvio/background.
Verificati il crash precedente, tre riaperture senza crash e il brano sincronizzato
su Watch/iPhone simulati; otto test core Watch superati.

Riconnessione Passeggero dopo cambio rete CarPlay: ripristino listener con QR
invariato, recupero su foreground e collegamento CarPlay, comando manuale e timeout
Bonjour. Dodici test di protocollo/trasporto superati, comprese due scansioni
consecutive dello stesso invito dopo disconnessione e conservazione dei collegamenti
attivi durante il ripristino.

Build Release iPhone/Watch riuscita. Collaudo su Watch fisico e due iPhone nel
veicolo ancora necessario. Prove e stato distribuzione in deliveries.

Consegna: upload Apple riuscito. Build `5931dac6-b381-4e7c-ab62-19da4626555a`,
VALID e Test in corso, assegnazione a Team interno e Stivy73 verificata nella
pagina TestFlight dopo timeout dell’API di scrittura. Nessun utente/ruolo o
automatismo modificato. Sorgenti archivio: `a59453596d70ed14c56704e5c9c95eb24d690693`.
IPA e prove: `deliveries/NoteNarrate-iOS-0.16.1-build54.ipa` e JSON adiacenti.
