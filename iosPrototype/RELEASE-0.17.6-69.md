# NoteNarrate YouTube Music 0.17.6 (69)

Il comando Coda > Passeggeri > Mostra QR apre il player nativo CarPlay e
sostituisce temporaneamente la copertina con il QR della sessione corrente.
Il QR occupa la stessa area dell'album e appare anche sul blocco schermo iPhone.
Il pulsante X, il ritorno dalla vista player, la fine della sessione o la
sconnessione CarPlay ripristinano la copertina. Titolo, posizione, stato e
controlli di riproduzione restano quelli del brano reale. Se nessun brano e
selezionato resta disponibile il QR nella griglia nativa Passeggeri.
Il sottotitolo precedente non viene mostrato. L'app non salva inviti o QR reali su disco. La navigazione riutilizza il player se gia nello stack.

Include la correzione delle copertine dei passeggeri preparata nella beta 68:
si trasmette il riferimento HTTPS alla copertina pubblica originale, evitando
la miniatura video con bande. Campo opzionale compatibile con messaggi v1;
entrambi gli iPhone devono essere aggiornati alla 69 per il risultato completo.
La 68 era stata caricata prima della richiesta aggiuntiva e non distribuita
ai gruppi.

Destinazione: NoteNarrate YouTube Music, App Store Connect 6821630132,
com.stivy.simpmusic.prototype. La variante Apple Music resta separata.
Toolchain Xcode 27.2 RC (27B48), SDK 27.2; minimi iOS17/watchOS10 invariati.
Archivio Release ed IPA firmata esportati. Verificate firme, percorso dyld
Google Cast, CarPlay, Siri (5 azioni, 8 frasi it/en), Widget, Share e Watch.
Versione/build 0.17.6 (69) coerenti su tutti i cinque bundle.
31 test Core e 2 test UI superati: lettura del QR pubblicato in
MPMediaItemArtwork, immagine quadrata, titolo e riproduzione invariati,
ripristino della copertina originale; bridge TLS reale passeggero-principale
con conservazione della copertina in coda e Play Now.
La verifica fisica sul display auto resta da confermare.

IPA: `deliveries/NoteNarrate-iOS-0.17.6-build69.ipa`.
Archivio e simboli: `deliveries/archives/NoteNarrate-0.17.6-build69.xcarchive`.
SHA-256: `3c3280028abcc8433f53529d12772ab4db4bdafa4a28f8c4bcac420319584757`.
Consegna TestFlight: in corso; stati Apple e gruppi da rileggere dopo upload.
