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

Archivio Release ed esportazione interna completati; firme e profili dei sei
bundle verificati e controllo framework/dyld superato.
IPA: deliveries/NoteNarrate-iOS-0.17.12-build75.ipa.
Archivio e simboli: deliveries/archives/NoteNarrate-0.17.12-build75.xcarchive.
SHA-256: `f58d03cc3d2ccf9a94e4acdf22dfd2626ae2f1a5d02c4476e5ee75d0e0bdbb73`.
Sorgenti: `8a112d96f0565805e2510918f341e1241e0f002f`, pubblicati su stivy73/SimpMusic,
branch feature/youtube-library-albums.
Validazione: deliveries/NoteNarrate-iOS-0.17.12-build75-validation.json.

Upload ufficiale completato, delivery 998e6ff8-caa2-45bf-8ab0-a50f7b550619.
Verifica Apple del 2026-11-15: VALID, INTERNAL_ONLY, IN_BETA_TESTING.
Assegnata a Team interno e Stivy73; appartenenza al gruppo e accesso app
confermati per Tommaso e Girbreda. Note italiane salvate e rilette.
I timeout di lettura Apple sono stati risolti ripetendo le sole verifiche
mancanti, senza ripetere l'upload.
Ricevuta: deliveries/NoteNarrate-iOS-0.17.12-build75-AppStore-status.json.
