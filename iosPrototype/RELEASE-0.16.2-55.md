# NoteNarrate 0.16.2 (55)

Messaggi espliciti per credito API Gemini esaurito, fatturazione non attiva,
quota gratuita e limiti di utilizzo. I codici 402 e i messaggi noti di credito
prepagato esaurito producono indicazioni per saldo e fatturazione; un generico
429 non viene presentato come certezza di credito esaurito. I messaggi del provider
non sono memorizzati o mostrati integralmente. Verifiche: 21 test Gemini superati.

Riferimenti: https://ai.google.dev/gemini-api/docs/api-errors e
https://ai.google.dev/gemini-api/docs/billing/ .

Distribuzione verificata: upload Apple riuscito, elaborazione **VALID** e stato
**IN_BETA_TESTING**. Associazione riletta via API per **Team interno** (Tommaso incluso)
e **Stivy73**, con note italiane confermate. Non è una pubblicazione App Store.

Sorgente della build: `95048bd971ec60b031ba922da330d1d21b2a2350` su
`stivy73/SimpMusic`, branch `feature/youtube-library-albums`.
IPA: `deliveries/NoteNarrate-iOS-0.16.2-build55.ipa`.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.2-build55-AppStore-status.json`.
SHA-256: `5677f3902c8ba3499745ec40b96e2cbf0ebde0f9c1be192c8949b9578428c6cc`.
Firma iPhone/Watch, entitlement CarPlay e controlli IPA superati. Build con
Xcode 27.2 RC (27B48), SDK iOS 27.2. Nessuna conferma di installazione della 55
sui due telefoni o di collegamento nel veicolo reale.

Inclusa ulteriore correzione scoperta Passeggero: riconosciuti gli annunci Bonjour
con suffisso numerico di collisione, senza invalidare l’identità TLS del QR.
Riprodotto il fallimento prima della modifica e il collegamento dopo la correzione.
Ridotte le riaperture inutili del listener e rimossa l’associazione rigida a una
sola interfaccia di rete nella risoluzione Bonjour. Aggiunta diagnostica condivisibile
della fase di scoperta/connessione, senza segreti, indirizzi o contenuti musicali.
Totale test mirati: 36 superati; CarPlay wireless reale ancora da collaudare.
