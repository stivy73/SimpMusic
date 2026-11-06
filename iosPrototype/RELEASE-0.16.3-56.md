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

Candidata compilata con Xcode 27.2 RC (27B48), SDK iOS 27.2; deployment minimo
invariato iOS 17 / watchOS 10. Test, firma, upload, elaborazione e associazione
ai gruppi da verificare prima di chiamare disponibile la beta.

La radio Bluetooth e il caso reale dei due telefoni con CarPlay wireless non
sono verificati dai test automatici: collaudo nel veicolo ancora necessario.
