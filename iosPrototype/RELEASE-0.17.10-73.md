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
