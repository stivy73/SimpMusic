# NoteNarrate 0.16.3 (56)

Aggiunto un percorso Bluetooth per la sessione Passeggero quando CarPlay wireless
impedisce ai due iPhone di scoprirsi tramite Bonjour. Dopo la scansione QR,
la ricerca alternativa parte dopo 4 secondi senza risultati Wi-Fi. Servono
Bluetooth attivo, permesso per NoteNarrate ed entrambe le app aggiornate.

Autenticazione e cifratura applicativa legate al QR; conferma obbligatoria del
principale. Nessun audio trasferito: il principale continua a riprodurre la musica.
Diagnostica estesa e tempi relativi alla sessione. Dettagli e limiti: [PASSENGER.md](PASSENGER.md).

25 test Passeggero superati (10 nuovi Bluetooth/crypto e 15 esistenti).
Compilazione Release e archivio firmato iPhone/Watch riusciti.

Compilata con Xcode 27.2 RC (27B48), SDK iOS 27.2; deployment minimo
invariato iOS 17 / watchOS 10. IPA firmata ed esportata; caricamento Apple riuscito. Elaborazione **VALID**,
stato **IN_BETA_TESTING**, associazioni a **Team interno** e **Stivy73** rilette
con successo. Tommaso verificato come membro del Team interno tramite la
relazione del tester. Nessuna pubblicazione App Store o modifica dei ruoli.

Sorgente: `5c46d106d7468f9a0ae9aa7c8ddba192526d6a08`, su
`stivy73/SimpMusic`, branch `feature/youtube-library-albums`.
IPA: `deliveries/NoteNarrate-iOS-0.16.3-build56.ipa`.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.3-build56-AppStore-status.json`.
SHA-256 dell’IPA esportata:
`abf233ccc7df0c1695af08097f5c287af6b298f87b33a6e11aae38e8cebe76f3`.
Firme iPhone/Watch, CarPlay, permesso Bluetooth e modalità background verificati.
Il primo tentativo di caricamento è stato interrotto in analisi prima dell’upload
per includere anche l’adeguamento dei pacchetti ATT; distribuito l’archivio finale
`NoteNarrate56-ready.xcarchive`.

La radio Bluetooth e il caso reale dei due telefoni con CarPlay wireless non
sono verificati dai test automatici: collaudo nel veicolo ancora necessario.
