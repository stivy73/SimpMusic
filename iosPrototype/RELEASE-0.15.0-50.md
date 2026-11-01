# NoteNarrate iOS 0.15.0 (50)

Ricezione da Apple Music e Spotify per brani, album e playlist pubbliche:
anteprima con copertina e tracce nell’ordine originale, ricerca parallela delle
versioni YouTube Music, scelta manuale, riproduzione, coda e creazione di playlist
private YouTube Music. Link privati o elenchi pubblici incompleti hanno messaggi
espliciti. Parametri di tracciamento non salvati; nessun login Apple/Spotify.

Implementazione: `aee73b2cbf9775abd43afe1d48256730edd7060c`.
App, estensione Condividi, widget ed estensione Siri: versione 0.15.0, build 50.
Minimo iOS 17 conservato. Toolchain Xcode 27.2 RC (27B48), SDK iOS 27.2.

Verifiche funzionali già completate sull’implementazione: 297 test core,
5 scenari UI distinti (9 percorsi di condivisione), 6 link reali dei due servizi
più una playlist personale Apple. Compilazioni Debug e Release riuscite.
Scritture remote nei test UI simulate; nessun nuovo collaudo sul telefono dei tester.
I dettagli sono in [SHARING.md](SHARING.md).

## Consegna verificata il 1 novembre 2026

Archivio firmato ed esportazione API riusciti. Verificati firma di distribuzione,
profili CarPlay, Siri, widget, estensione Condividi e App Group. Upload API riuscito;
App Store Connect conferma **VALID** e **IN_BETA_TESTING**.

Build Apple: `93a8e803-9ccb-46fd-a639-1defa29b030b`.
Gruppi assegnati e riletti dall’API: **Team interno** e **Stivy73**.
Note beta italiane (`it`) salvate e rilette. Nessuna modifica a membri, ruoli o
distribuzione automatica dei gruppi. Nessuna pubblicazione App Store.

Sorgenti/versione/build dell’archivio: `01cf8a2ab682bad930ba7c625074aec233232675`,
pubblicati sul fork personale `stivy73/SimpMusic`, branch `feature/youtube-library-albums`.

IPA: `deliveries/NoteNarrate-iOS-0.15.0-build50-Sharing.ipa`.
SHA256: `fb293ccc19ba3f8dfa8c9b19b977b8e40c0703bd1d4ea02b1617a0d7c3f595eb`.
Verifica firma: `deliveries/NoteNarrate-iOS-0.15.0-build50-Sharing-validation.json`.
Stato Apple: `deliveries/NoteNarrate-iOS-0.15.0-build50-Sharing-AppStore-status.json`.
Archivio: `/tmp/NoteNarrate-0.15.0-build50.xcarchive`.

Disponibilità della beta e installazione sul telefono sono verifiche distinte:
nessun nuovo collaudo fisico sui dispositivi dei tester viene dichiarato qui.
