# NoteNarrate 0.16.4 (57)

Aggiunto **Mostra QR** nella schermata Passeggeri di CarPlay, raggiungibile dalla
Coda del player. Invito della sessione corrente, richieste e autorizzazioni sul
display dell’auto. Mostrare il QR mantiene la sessione corrente.
QR condiviso con iPhone, ad alto contrasto e con quiet zone; rimosso quando termina
la sessione. Header nativo su iOS 26.4+, riga immagine sui sistemi precedenti.

28 test Passeggero superati, inclusi 3 test Vision con lettura completa del QR a
128/160/180/240/360/720 pixel, riduzione interpolata e rotazione dell’invito.
Compilazione iOS e archivio Release riusciti con Xcode 27.2 RC (27B48), SDK 27.2.
Firma iPhone/Watch e controlli CarPlay/Siri/widget/share dell’IPA superati.

Caricamento Apple riuscito, elaborazione **VALID** e stato **IN_BETA_TESTING**.
Associazione a **Team interno** e **Stivy73** riletta via API; Tommaso verificato
nel Team interno. Nessuna pubblicazione App Store o modifica dei ruoli.

Sorgente: `f919bdfc3fffdbeeb752d9668639713706d0246f` su `stivy73/SimpMusic`,
branch `feature/youtube-library-albums`. Archivio finale: `NoteNarrate57-final.xcarchive`.
IPA: `deliveries/NoteNarrate-iOS-0.16.4-build57.ipa`.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.4-build57-AppStore-status.json`.
SHA-256 dell’IPA esportata:
`bb6434c7774f8269a759bd89bab4362e89dbf831edbcae1ce1ba6019428ac22d`.

La leggibilità del QR fotografando il display fisico dell’auto è ancora da
confermare. L’utente ha già confermato il collegamento Bluetooth della 56.
