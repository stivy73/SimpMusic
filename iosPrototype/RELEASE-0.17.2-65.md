# NoteNarrate 0.17.2 (65)

Il QR Passeggeri su CarPlay usa una riga grafica dedicata, senza titolo o
sottotitolo che sottraggano spazio. La griglia nativa offre lo spazio quadrato
più grande dei componenti immagine della lista: 220 × 220 punti nel runtime
iOS 27.2, rispetto ai 112 × 112 della miniatura nell’intestazione precedente.
La risoluzione segue `maximumImageSize` e la scala del display dell’auto.
Il QR resta quadrato, con margine bianco e moduli allineati ai pixel.
Anche la voce «Mostra QR» perde il sottotitolo «da fermi».

Misure lette nel runtime iOS 27.2 con le API pubbliche CarPlay: row 95 × 95,
grid 220 × 220, imageGrid 110 × 110, card 141 × 141, fullHeightCard 165 × 220,
header quadrato 112 × 112. Il layout effettivo rimane gestito dal sistema
CarPlay e va verificato sul display dell’auto.

Riferimenti Apple:
- [Griglia senza etichette](https://developer.apple.com/documentation/carplay/cplistimagerowitemgridelement/init(image:))
- [Dimensione prevista delle immagini](https://developer.apple.com/documentation/carplay/cplistimagerowitemelement/maximumimagesize)

Tre test QR superati, incluse le nuove dimensioni 220 e 440 pixel,
ridimensionamento e rotazione dell’invito. Archivio Release compilato e firmato
con Xcode 27.2 RC (27B48), SDK iPhoneOS 27.2. Build 65, versione 0.17.2 su
app, estensioni e Watch; minimi iOS 17 e watchOS 10 invariati.

IPA esportata e verificata: firma di distribuzione, CarPlay, Siri, Widget,
Share e companion Watch. Sorgenti aggiornati sul fork `stivy73/SimpMusic`,
branch `feature/youtube-library-albums`, commit
`f2c461ef6296daa9bc3f3936eedc82f3bb2e664a`.

IPA: `deliveries/NoteNarrate-iOS-0.17.2-build65.ipa`.
SHA-256: `8311b8b010c537efb187f42218d8bb2f432bef5a28e0bde47c31cad75b42b0a5`.
Archivio e simboli: `deliveries/archives/NoteNarrate-0.17.2-build65.xcarchive`.
Verifiche: `deliveries/NoteNarrate-iOS-0.17.2-build65-validation.json`.

Upload completato con il caricatore ufficiale Apple, senza errori.
Delivery/build UUID: `bd3e7311-759a-45fb-b564-b8c2e1d4011b`.
Elaborazione **VALID**, pubblico **INTERNAL_ONLY**, stato **IN_BETA_TESTING**.
Associazioni a **Team interno** e **Stivy73** rilette via API; appartenenza
al Team interno e accesso alla stessa app verificati per **Tommaso**
(`tommaso.stival@icloud.com`) e **Girbreda** (`girbreda@gmail.com`).
Note beta italiane salvate e rilette. Nessuna modifica degli altri tester,
dei ruoli, della distribuzione automatica o della pubblicazione App Store.

Ricevuta: `deliveries/NoteNarrate-iOS-0.17.2-build65-AppStore-status.json`,
verificata il 10 novembre 2026 alle 21:13:42 UTC.
Nessuna nuova prova sul display fisico dell’auto è stata eseguita:
dimensione visualizzata e scansione dal display restano da confermare sull’auto.
