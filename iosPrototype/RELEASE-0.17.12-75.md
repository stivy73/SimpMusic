# NoteNarrate YouTube Music 0.17.12 (75)

La preparazione delle sorgenti HLS live non carica durata, tracce e fine
prima di collegare AVPlayer. Il player conserva durata indefinita e non
ripristina una posizione iniziale che puo essere fuori dalla finestra live.
Lo stesso percorso si applica alla preparazione anticipata del brano.

Impostazioni > Diagnostica riunisce le voci Chromecast e audio/voce.
Il report audio condiviso include il dettaglio Chromecast e la cronologia
coda. Nessuna nuova richiesta di autorizzazione o avviso informativo.

45 test audio superati, incluso il caso live che non accede a durata o
tracce di un asset non leggibile; il caso di durata sconosciuta non live
continua a richiedere la verifica. Un test UI verifica accesso e vicinanza
delle diagnostiche e report Chromecast. La Station reale resta da provare.
La continuita Chromecast a iPhone sospeso non e stata risolta.

App YouTube Music 6821630132, com.stivy.simpmusic.prototype; Apple Music
resta separata. Xcode 27.2 RC (27B48), SDK 27.2; minimi invariati.
Distribuzione interna a Team interno e Stivy73 con verifica di Tommaso e Girbreda.
