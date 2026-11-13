# Home, Esplora, Artisti e Preferiti

Lotto successivo ad album/playlist e ricezione, nella sola variante Apple Music.
Verifica preliminare su versione di sviluppo 0.1.0 (11). Dopo la successiva
richiesta del titolare, consegnato su TestFlight nella 0.1.0 (12), al solo Stivy73.
Ricevuta: `verification/testflight-0.1.0-12.json`.

## Codice riutilizzato

`Scripts/import_youtube_discovery.py` estrae dal commit YouTube Music `5a277798`
le sezioni `DiscoveryShelves`, `DiscoveryCard` e `DiscoveryCategories` di
`iosPrototype/Sources/App/HomeView.swift`. Il file generato conserva spaziature,
caroselli orizzontali LazyHStack, schede 164 pt con due righe riservate,
contentMargins, clipping al viewport, griglia categorie e collegamenti Altro.
L'hash della sorgente e `--check` rendono verificabile il port.

## Comportamento

- Home: Ascolta di nuovo, consigli personali Apple, album e brani della
  libreria in caroselli. Altro apre l'elenco completo della sezione con le
  preferenze di visualizzazione; le pagine native aggiuntive hanno cursore,
  caricamento ed errore/riprova indipendenti. Le raccomandazioni mantengono
  l'ordine album/playlist fornito da Apple. Le stazioni non sono elencate in
  questi caroselli, come nel precedente adattamento della Home.
- Cronologia dedicata dalla barra Home: `MusicRecentlyPlayedRequest<Song>`
  e paginazione MusicKit. È la cronologia recente disponibile tramite Apple,
  senza date o ascolti ricostruiti localmente; non dichiara uno storico illimitato.
- Esplora dalla Home: generi del catalogo (`MusicCatalogResourceRequest<Genre>`),
  classifiche native per paese dell'account e per genere, playlist ricercate per
  stato d'animo, nuove uscite degli artisti personali. Gli stati d'animo sono
  ricerche esplicite di playlist, non una tassonomia editoriale Apple inventata.
- Nuove uscite: ultimo album/singolo restituito da Apple per ciascun artista
  in libreria o preferito, pubblicato negli ultimi 90 giorni. Dodici riferimenti
  per volta, quattro letture simultanee, comando per gli altri artisti, errori e
  riprova; niente limite silenzioso. Deduplicazione album e ordine per data di
  pubblicazione, esclusione di date sconosciute e future. Le date di aggiunta
  alla libreria non diventano date di pubblicazione.
- Artista: immagine, generi, note editoriali quando fornite, preferito verificato,
  condivisione, apertura in Musica, radio nativa e sezioni Ultima uscita, Brani più
  ascoltati, Album, Singoli/EP, Raccolte, Compare anche in, Playlist e Artisti simili.
  Ogni sezione dispone di Altro. Gli ID personali vengono collegati al catalogo
  tramite la relazione ufficiale, senza ricerca per somiglianza del nome.
- Preferiti: categorie Brani/Album/Playlist/Artisti, griglia/elenco, ordinamento e
  indice, impostazioni separate per categoria, aggiornamento e scelta persistente.
  Gli artisti sono verificati con `inFavorites` sui catalog ID collegati agli
  artisti personali. Pagine, relazioni e batch incompleti non diventano un falso
  elenco vuoto o completo; gli errori vengono mostrati.
- Ricerca: rimozione di una sola voce di cronologia con X o swipe; le altre voci
  restano nello stesso ordine. Menu categorie alternativo in Libreria, Cerca e
  Preferiti. Ordine inverso disponibile anche con Ordine originale; cambia la
  presentazione, senza riscrivere album o playlist sul servizio.

## Verifiche e limiti del collaudo

94 test superati, zero errori (6 nuovi): finestra nuove uscite/deduplicazione/
date, ordine originale inverso, cancellazione selettiva ricerca, relazioni degli
artisti e conservazione del cursore, relazioni non riconosciute e batch preferiti
incompleti. Controllati i tre script di importazione fissata.

Debug iOS Simulator e archivio Release firmato app/Watch/estensione riusciti.
Archivio: `/tmp/NoteNarrateMusic-DiscoveryReview.xcarchive`.
Ricevuta in `verification/discovery-build.json`. Le fixture non sono presenti
nel Release. Nessuna modifica a utenti, ruoli, gruppi tester o servizi esterni.

Device Hub, solo simulatore iPhone 18 Pro / iOS 27.2, dati sintetici:
avvio, carosello spostato dalla prima scheda agli ascolti 4/5; Altro Album con
sette elementi; Ordine originale inverso da Album Beta iniziale ad Album 7;
Cronologia con sei brani; Esplora, Generi > Rock > classifiche, Stati d'animo >
Relax > playlist; menu Libreria > Preferiti; Artisti preferiti e griglia;
pagina artista e proporzioni dell'immagine corretta; eliminata la sola ricerca
Rock, conservando Seal e Jazz; pagina Nuove uscite con contatore e stato iniziale.
Il vecchio link sintetico in Ricevuti è stato chiuso dopo Permission denied
nel simulatore non autorizzato, senza trattarlo come un risultato dell'account.

Non verificati con account reale: disponibilità dei generi/classifiche per il
paese, pagine di cronologia e raccomandazioni, relazioni artista, preferiti e
ultime uscite, radio/riproduzione. Nessuna scrittura musicale reale nel collaudo.
Restano distinti i test sui display fisici, CarPlay e iPhone Duo.

## Riferimenti Apple

- https://developer.apple.com/documentation/musickit/musicrecentlyplayedrequest
- https://developer.apple.com/documentation/musickit/musiccatalogchartsrequest
- https://developer.apple.com/documentation/applemusicapi/get-all-genres
- https://developer.apple.com/documentation/musickit/artist
- https://developer.apple.com/documentation/applemusicapi/artists/attributes-data.dictionary
