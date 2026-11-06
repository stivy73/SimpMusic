# NoteNarrate 0.16.2 (55)

Messaggi espliciti per credito API Gemini esaurito, fatturazione non attiva,
quota gratuita e limiti di utilizzo. I codici 402 e i messaggi noti di credito
prepagato esaurito producono indicazioni per saldo e fatturazione; un generico
429 non viene presentato come certezza di credito esaurito. I messaggi del provider
non sono memorizzati o mostrati integralmente. Verifiche: 21 test Gemini superati.

Riferimenti: https://ai.google.dev/gemini-api/docs/api-errors e
https://ai.google.dev/gemini-api/docs/billing/ .

Distribuzione interna prevista: Team interno (Tommaso incluso), preservando Stivy73.
Upload, elaborazione e associazioni da verificare separatamente in deliveries.

Inclusa ulteriore correzione scoperta Passeggero: riconosciuti gli annunci Bonjour
con suffisso numerico di collisione, senza invalidare l’identità TLS del QR.
Riprodotto il fallimento prima della modifica e il collegamento dopo la correzione.
Ridotte le riaperture inutili del listener e rimossa l’associazione rigida a una
sola interfaccia di rete nella risoluzione Bonjour. Aggiunta diagnostica condivisibile
della fase di scoperta/connessione, senza segreti, indirizzi o contenuti musicali.
Totale test mirati: 36 superati; CarPlay wireless reale ancora da collaudare.
