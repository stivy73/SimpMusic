# NoteNarrate YouTube Music 0.17.10 (73)

Gestione esplicita dell'esito di sei operazioni CarPlay di apertura e chiusura
schermate. Un rifiuto viene consegnato al callback anziche provocare
l'eccezione di CPInterfaceController quando il callback e assente.

Il rapporto StivySimpMusic del 2026-11-14 17:13 riguarda la build 71 e mostra
un SIGABRT in CPInterfaceController._handleCompletion. Il tester segnala il
blocco prima dell'avvio del brano successivo. Il rapporto non identifica
l'operazione rifiutata: la correzione elimina le chiamate senza callback,
ma il passaggio automatico va confermato su CarPlay reale.

Compilazione Debug superata. Xcode 27.2 RC (27B48), SDK 27.2; minimi invariati.
Destinazione: NoteNarrate YouTube Music, app 6821630132. La variante Apple Music
resta separata. Distribuzione ai gruppi esistenti Team interno e Stivy73,
con verifica accesso di Tommaso e Girbreda dopo elaborazione Apple.

Archivio Release ed esportazione interna completati; firme e profili dei sei
bundle verificati, controllo framework/dyld superato.
IPA: deliveries/NoteNarrate-iOS-0.17.10-build73.ipa.
Archivio e simboli: deliveries/archives/NoteNarrate-0.17.10-build73.xcarchive.
SHA-256: `bf5e2d3f1f0c761365a573edbd37f2bd5730b6d2ef59b219102de30605a49e77`.
Sorgenti: `d7a24bba5925a122749b286bda809c77cb8d13c7`, pubblicati su stivy73/SimpMusic,
branch feature/youtube-library-albums.
Validazione: deliveries/NoteNarrate-iOS-0.17.10-build73-validation.json.

Upload ufficiale completato, delivery fe1d5878-7642-42ac-8ed9-af869d991675.
Verifica Apple del 2026-11-14: VALID, INTERNAL_ONLY, IN_BETA_TESTING.
Assegnata a Team interno e Stivy73; accesso app e appartenenza al gruppo
confermati per Tommaso e Girbreda, note italiane rilette.
Ricevuta: deliveries/NoteNarrate-iOS-0.17.10-build73-AppStore-status.json.
