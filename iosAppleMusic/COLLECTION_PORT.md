# Album, raccolte, playlist e ricezione

Il port parte dai sorgenti YouTube Music del commit `5a277798`, senza importare
il suo player audio, la sessione YouTube o endpoint di scrittura non Apple.

`Scripts/import_youtube_collections.py` genera e verifica:

- `YouTubeCollectionPresentation.swift` da `AlbumScreen.swift`: stessa geometria
  compatta/ampia, copertina, gradiente, intestazione, controlli, riepilogo,
  numerazione, durata e pulsante opzioni per traccia. Usa album e playlist MusicKit.
- `SharedMusic.swift`: stesso parser e stessa inbox atomica per link e ricerche.
  Gruppo separato `group.com.stivy.notenarrate.applemusic`.
- `SharedCatalog.swift`: stesso recupero metadati pubblici e riconoscimento
  conservativo di titolo/artisti/durata; nessuna sostituzione automatica con
  live, remix o cover. Il catalogo di destinazione è Apple Music.
- `ShareExtension/ShareViewController.swift`: stesso compositore, con nomi e
  istruzioni della variante Apple Music.
- `Tests/SharedCatalogTests.swift`: stessi casi del flusso originale, adattati
  al candidato neutro e al catalogo Apple.

`PlaylistPresentation.swift` adatta i flussi di `RemotePlaylistView.swift`:
creazione, aggiunta, scelta playlist, rinomina, spostamento delle occorrenze e
rimozione della singola occorrenza. Le modifiche sono delegate a MusicKit.
Non viene mostrata un'azione di eliminazione che il servizio non espone: il
collegamento Apri in Musica permette le altre operazioni nell'app Apple.

## Adattamenti al servizio

La riproduzione conserva `Queue(album:startingAt:)` e
`Queue(playlist:startingAt:)`, comprese le occorrenze duplicate. Le azioni su
intere raccolte inseriscono il contenitore MusicKit nella coda. La navigazione
non riscrive le playlist per ottenere shuffle o ordinamenti di presentazione.

La creazione e l'aggiunta usano `MusicLibrary.createPlaylist` e `add(_:to:)`.
Rinomina e riscrittura di tracce sono abilitate per le playlist create da questa
app; MusicKit applica il vincolo anche sul server. Prima della riscrittura si
rilegge la playlist e si confronta la sequenza delle occorrenze. Elementi non
riproducibili bloccano la riscrittura completa, così non vengono persi.
Le scritture non vengono ritentate automaticamente: timeout e inserimenti
parziali sono dichiarati, con il numero di aggiunte confermate.

Fonti ufficiali:
https://developer.apple.com/documentation/musickit/musiclibrary
https://developer.apple.com/documentation/musickit/musiclibrary/edit(_:name:description:authorDisplayName:items:)

I link Apple Music vengono aperti per ID, cercando prima l'eventuale playlist
personale con lo stesso URL. Spotify mantiene tutte le posizioni sorgente,
anche duplicate, e mostra corrispondenze mancanti e copertura parziale.
L'utente può scegliere la versione Apple Music prima di riprodurre, accodare
o creare una nuova playlist con i brani trovati. I servizi di origine non
vengono modificati. Il limite originale è 500 tracce dai metadati pubblici.

## Verifiche

- 88 test superati, inclusi i 16 test importati sulle condivisioni e 4 nuovi
  casi su spostamenti, duplicati, nome, permessi e snapshot modificati.
- Compilazione Debug di app, Watch ed estensione riuscita.
- Archivio Release per iPhone riuscito, con app, Watch ed estensione 0.1.0 (11).
  Firma verificata; profili rigenerati dopo l'autorizzazione del titolare.
  App ed estensione contengono esclusivamente il gruppo Apple Music dedicato.
  Ricevuta: `verification/collections-signing.json`.
- Simulatore iPhone 18 Pro / iOS 27.2, dati sintetici: schermata album con
  anno, descrizione, durata totale e per traccia, Play e shuffle; menu con
  azioni di raccolta; foglio Condividi con NoteNarrate Music; riconoscimento
  Album Apple Music; salvataggio Contenuto ricevuto; elemento presente in
  Libreria > Ricevuti. La prima build senza entitlement simulati non poteva
  aprire il gruppo; ripetuto con build firmata ad hoc, con esito positivo.
- La fixture richiede DEBUG, PLAYER_LAYOUT_FIXTURE e BROWSE_LAYOUT_FIXTURE.
  È esclusa dal Release. Nessuna scrittura alla libreria musicale reale nel test.

Restano verifiche con account reale: avvio audio, scritture sulle playlist,
playlist private, confronto tra versioni Spotify/Apple e comportamento sui
display fisici. Un successo dei test sintetici non certifica queste prove.

L'archivio di verifica è `/tmp/NoteNarrateMusic-CollectionsReview.xcarchive`.
Non è una nuova beta: nessun export o upload TestFlight eseguito in questo lotto.
