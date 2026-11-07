# NoteNarrate 0.16.5 (58)

La sessione Passeggero viene avviata quando si collega CarPlay, anche dopo un
riavvio dell’app o dell’iPhone. Una sessione esistente conserva invito QR,
passeggeri autorizzati e collegamenti attivi. Se il telefono era un passeggero,
il collegamento CarPlay lo rende principale della propria sessione.

La voce **Passeggeri** è sempre nella Coda. Dopo la chiusura manuale permette
di riaprire la sessione dal display; la schermata Passeggeri offre anche
**Apri una nuova sessione**. Le richieste richiedono sempre autorizzazione.
Diagnostica con avvio/ripresa della sessione al collegamento CarPlay.

30 test Passeggero superati: avvio da stato iniziale, chiusura/riapertura,
nuova istanza dopo riavvio, passaggio da passeggero a principale e conservazione
dei collegamenti TCP e Bluetooth già autorizzati. Test QR/Vision inclusi.
Archivio Release con Xcode 27.2 RC (27B48), SDK iOS 27.2; firme iPhone/Watch e
controlli CarPlay/Siri/widget/share dell’IPA superati. Deployment minimo invariato.

Upload Apple riuscito, elaborazione **VALID**, stato **IN_BETA_TESTING**.
Associazione a **Team interno** e **Stivy73** riletta via API; Tommaso verificato
nel Team interno. Nessuna modifica dei ruoli o pubblicazione App Store.

Sorgenti: `ba7099490f381e05541c70625bff5e786306e7c8`, branch
`feature/youtube-library-albums` su `stivy73/SimpMusic`.
IPA: `deliveries/NoteNarrate-iOS-0.16.5-build58.ipa`.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.5-build58-AppStore-status.json`.
SHA-256 dell’IPA esportata:
`af0c711ed84138ecf5802bfe13fe56ddb4aa7d1015843cee318c0bb2da3b3e1a`.
Avvio automatico tramite evento CarPlay sul veicolo reale da collaudare.
