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

Consegna TestFlight in preparazione; nessuna nuova prova sul display fisico
dell’auto è stata eseguita.
