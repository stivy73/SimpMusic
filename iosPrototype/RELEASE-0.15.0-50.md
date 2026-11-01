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

Stato della consegna: preparazione di archivio firmato, upload API ed elaborazione
Apple in corso. Assegnazione prevista ai gruppi esistenti Team interno e Stivy73.
Nessuna pubblicazione App Store.
