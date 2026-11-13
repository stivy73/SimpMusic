# Player condiviso con NoteNarrate YouTube Music

La presentazione di build 10 deriva dal vero player in
`iosPrototype/Sources/App/StivyApp.swift`, commit `5a277798`.
SHA256 del sorgente originale:
`23ab00e6eee9a94887e951f85345708d25a7e80413d96519f00cf0701afbedb2`.

`Sources/YouTubePlayerPresentation.swift` contiene i blocchi originali Artwork,
DuoNavigationBars, SystemMiniPlayerAccessory, LegacyMiniPlayerInset, MiniPlayer,
MiniPlaybackButton, PlayerScreen e PlayerControls, con gli adattamenti espliciti
nello script. Anche l’overlay conservato, le animazioni e il gesto dal bordo di
RootView sono riportati in MusicRoot. Non è una ricostruzione grafica indipendente.

Dal repository:

```sh
python3 iosAppleMusic/Scripts/import_youtube_player.py
python3 iosAppleMusic/Scripts/import_youtube_player.py --check
```

Il primo comando rigenera il file a partire dal commit fissato; il secondo
verifica identità del risultato e provenienza. La versione YouTube resta intatta.

## Adattamenti del servizio

- ApplePlayerAdapter collega la stessa presentazione a ApplicationMusicPlayer:
  riproduzione, pausa, seek, salti, shuffle, repeat, stato e durata nativi.
- Le identità delle voci della coda MusicKit vengono conservate, anche quando
  una playlist contiene lo stesso brano più volte.
- Copertina, sfondo sfocato, dimensioni, barra temporale, mini player, animazioni,
  gesto di ritorno e disposizione delle barre verticali derivano dal sorgente YT.
- Il badge indica Apple Music. Il volume usa MPVolumeView e l’uscita usa AirPlay;
  MusicKit non espone il volume privato del precedente motore YouTube.
- Le opzioni usano Preferiti e libreria Apple, accodamento e condivisione nativi.
  Non vengono introdotti preferiti locali né API private.
- Il pannello Fonti e significato usa l’interpretazione con Google Search già
  presente nella variante Apple Music e conserva il consenso prima dell’invio.
  Non viene importato il recupero di testi YouTube, né il motore di streaming,
  il relay Chromecast, l’autenticazione YouTube o il vecchio harness DEBUG.

## Diagnostica collegata al report di build 9

L’app osserva lo stato nativo dopo play(): il ritorno del comando non conferma
che sia iniziata la riproduzione. Dopo circa tre secondi senza stato playing
mostra un errore con Riprova; una pausa esplicita annulla l’intento in attesa.
Un avvio nativo successivo elimina l’avviso. Non è una prova che il problema
audio del dispositivo sia risolto.

Il recupero dei 14 ID iOS passa per la richiesta ufficiale esplicita
`GET /v1/catalog/{storefront}/songs?ids=...`, validata prima di decodificare.
Il report include storefront, stato HTTP e conteggi richiesti/restituiti;
non include ID, token, chiavi o titoli. Zero risultati viene descritto come
"non restituiti", senza dedurne l’indisponibilità dei brani. Anche questo
recupero deve essere confermato con l’account reale.

## Collaudo

59 test di contratto superati, inclusi ID/storefront, risposte catalogo invalide,
avvio ritardato, play senza stato playing e pausa che annulla l’attesa.
Compilazione Debug e archivio Release firmato riusciti.

La build per controllare il layout usa `DEBUG PLAYER_LAYOUT_FIXTURE` e un solo
brano sintetico, senza account, rete o audio; il flag e i dati sintetici sono
esclusi dalla configurazione Release. Il test di layout non dimostra la
riproduzione MusicKit, il caricamento di una libreria reale o il comportamento
fisico dell’iPhone Duo.

Prova visiva in Device Hub ancora da completare: il controllo del computer
segnala il Mac bloccato. Prova fisica richiesta: avvio da traccia/album/playlist,
mini player e ritorno, seek, trasporto, coda con duplicati, significato e AirPlay.
