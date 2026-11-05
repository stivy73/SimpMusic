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
