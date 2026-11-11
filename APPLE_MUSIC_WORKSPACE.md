# NoteNarrate Apple Music — ambiente di sviluppo

Questo worktree contiene la variante Apple Music in `iosAppleMusic/`, con
progetto autonomo MusicKit, player, libreria, ricerca, CarPlay, comandi Siri e
companion Watch. Stato e limiti sono documentati in `iosAppleMusic/README.md`.

## Identità e collegamenti

- Chat: NoteNarrate Apple Music (`01a1c982-22b6-7343-a9f6-28c81ae9280b`).
- Chat madre YouTube Music: `01a12ae3-7139-7732-9d1b-46a43784e02a`.
- Repository sorgente: `/Users/stivy/Documents/ChatGPT/iOS/SimpMusic`.
- Worktree: `/Users/stivy/.codex/worktrees/notenarrate-apple-music/SimpMusic`.
- Branch: `codex/apple-music`.
- Commit iniziale: `e2c9d5fc97eef8dd0c4a94561f71921e0c9d7895`.
- Il commit iniziale comprende la correzione del caricamento Google Cast e
  versione 0.17.4 (67). La consegna TestFlight resta gestita dalla chat madre.

Non usare come sorgente il repository contenitore
`/Users/stivy/Documents/ChatGPT/iOS`: il tentativo precedente falliva copiando
repository annidati non tracciati, con errore EISDIR su AmbientMusicMod.
Questo worktree parte dai file tracciati del commit indicato. Non sono stati
copiati deliveries/, macPrototype/, chiavi API, api.txt o credenziali locali.

## Decisione architetturale

Un unico repository con codice condiviso e due target/eseguibili:

- YouTube Music: mantenimento nella chat madre e nel checkout originale.
- Apple Music: MusicKit ufficiale, con componenti YouTube non ufficiali esclusi
  dal target App Store durante la compilazione.

Condividere, dove possibile, UI, narrazione Gemini, CarPlay, Watch e gestione
coda. Separare accesso ai cataloghi, librerie, identità dei brani e riproduzione
tramite interfacce comuni, evitando di confondere gli identificatori dei provider.
Le correzioni comuni vanno trasferite come modifiche verificabili tramite commit;
le cronologie delle chat e i branch non si sincronizzano automaticamente.

Il ponte Chromecast attuale non può essere riutilizzato per estrarre audio
MusicKit. Testi, interpretazioni e invio dati a Gemini richiedono verifiche
separate di licenza e consenso. MusicKit non garantisce l'approvazione App Store.

## Regole operative

- Operare esplicitamente nel percorso di questo worktree.
- Usare `DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer`.
- Toolchain richiesta: Xcode 27.2 RC (27B48), SDK iOS 27.2.
- Conservare i minimi iOS 17 / watchOS 10 salvo nuova decisione esplicita.
- Remote personale `stivy`: https://github.com/stivy73/SimpMusic.git.
- `origin` è upstream maxrave-dev: non inviare push lì.
- Non modificare il checkout originale o la consegna urgente della build 67.
- Nessun upload, pubblicazione, modifica tester o App Store Connect da questo
  fork senza un nuovo incarico specifico.
- Prima di implementare MusicKit, consultare AGENTS.md, sorgenti e commit della
  chat madre per verificare eventuali aggiornamenti successivi al commit iniziale.
