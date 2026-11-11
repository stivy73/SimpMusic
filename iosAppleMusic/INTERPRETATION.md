# Interpretazione da ShareNarrate

Su richiesta dell'utente, il primo flusso Apple Music riutilizza la routine
ShareNarrate invece dell'adapter di testi con licenza predisposto in precedenza.

## Provenienza

Sorgenti letti dal checkout locale `ShareNarrate/ios/Shared` e confrontati con
`stivy73/ShareNarrate` nel checkout `work/ShareNarrate-github`, HEAD `a495df1`.
`SongWebMeaning.swift` coincide nei due checkout; il file è stato introdotto
nel commit `de2aaea`. Consultata anche la chat ShareNarrate
`01a14fe5-706c-78b1-b27b-23f819a9057e`, che descrive lo stesso flusso.

Componenti ripresi:

- `Content/SongWebMeaning.swift`: prompt, Google Search, parsing grounding e
  rifiuto dei risultati senza evidenza.
- `Content/ContentHTTP.swift`: trasporto con limite durante la ricezione,
  timeout totale, niente cookie/cache/credenziali persistenti e niente redirect
  per le richieste Google con API key.
- `AppViews.swift`: fonti e Search Suggestions originali di Google in WebView
  effimera, JavaScript disabilitato e link aperti dal sistema.
- `SongWebMeaningTests.swift`: fixture con fonti, completamento e URL sicuri.

Adattamenti: metadati direttamente da MusicKit invece di SongMetadata, modello
configurabile con validazione del nome, namespace HTTP separato e UI NoteNarrate.
Non sono stati importati cookie, credenziali o libreria ShareNarrate.
L'approvazione di un'altra app non equivale all'approvazione di questa variante.

## Flusso attivo

1. Su Significato l'utente conferma l'invio a Google di titolo e artista.
2. Gemini cerca spiegazioni, interviste e dichiarazioni con `google_search`.
   Il prompt esclude ricerca, recupero e citazione dei testi musicali.
3. La risposta deve essere completa (`STOP`), con fonti HTTPS associate a
   passaggi del testo e Search Suggestions. Le parti `thought` sono escluse.
4. Se mancano fonti utilizzabili o arriva `FONTI_INSUFFICIENTI`, l'app mostra
   l'avviso esplicito di fonti insufficienti; non narra un significato inventato
   dal solo titolo. Un errore HTTP/rete viene mostrato come errore.
5. L'interpretazione e le fonti sono visibili insieme ai suggerimenti Google.
   La lettura usa il motore voce già presente, dopo pressione di Leggi.

Nessun recupero di lyrics da MusicKit, scraping o chiamata a LicensedLyricsService.
Le fonti, il risultato e l'audio generato non vengono scritti su disco né inseriti
in cache. Il risultato viene cancellato al cambio brano o con Cancella.
Il contesto persistente Watch contiene solo stato/trasporto, non il testo del
risultato Google; la richiesta d'interpretazione rimanda alla conferma su iPhone.

## Attivazione e verifica

Serve la chiave Gemini dell'utente con accesso al modello e a Google Search.
Le richieste partono dal dispositivo verso Google, senza backend Archetipi.
Non sono stati eseguiti test Google live né utilizzate chiavi locali in questo
porting. La ricerca può dipendere da quote e disponibilità del progetto Google.

Riferimenti di implementazione:
[Grounding con Google Search](https://ai.google.dev/gemini-api/docs/google-search),
[requisiti di visualizzazione](https://ai.google.dev/gemini-api/docs/grounding/search-suggestions).
La UI mantiene l'HTML `renderedContent` senza modifiche.
