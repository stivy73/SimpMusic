# NoteNarrate YouTube Music 0.17.17 (80)

Il player avvia i brani lunghi con indice AAC completo dal frammento richiesto.
La percentuale di download è visibile nel player, nel menu del brano e in
Libreria → Download e offline. Se la dimensione è sconosciuta, viene mostrato
il numero di byte ricevuti. La spunta conferma che il file è disponibile offline.

Per i download AAC frammentati, NoteNarrate verifica la durata dei campioni
audio e ignora i marcatori vuoti che possono far apparire doppia la durata del file.
Conserva la durata verificata per la riproduzione locale, il passaggio al brano
successivo e Chromecast.

Prova su Mac con *Oceanic Delta Waves* di Jason Stephenson. Il download ha
restituito tutti i 62.132.786 byte. Dopo la riapertura della libreria, AVPlayer
ha riprodotto il file da disco all’inizio, a 22:08 e negli ultimi tre secondi,
segnalando la fine a 1:03:59,07. Nel confronto di streaming su Mac e Wi-Fi
la mediana di tre avvii a freddo è scesa da 17,78 a 1,08 secondi.

Superati 437 test automatici e quattro prove d’interfaccia su simulatore iOS
27.2 per avanzamento del download, verifica finale, fine brano e ripresa.

Il 21 novembre 2026 App Store Connect ha confermato `VALID` e
`IN_BETA_TESTING` per la build `b547ada1-4b9c-4a97-8ee7-2d97aef3e3c3`.
Assegnata a Team interno e Stivy73. Verificati l’accesso di Tommaso e Girbreda
e le note di prova in italiano.

Commit dei sorgenti `f3a8a9bee7191208507b2ef888b7db7bd31a3113`.
L’IPA è in `deliveries/NoteNarrate-iOS-0.17.17-build80.ipa` e l’archivio
con i simboli in `deliveries/archives/NoteNarrate-0.17.17-build80.xcarchive`.
SHA-256 dell’IPA `585b2180fdc5302ad3f585cd09502330149f53b95bb9b78a034a94ca5f00f36f`.
