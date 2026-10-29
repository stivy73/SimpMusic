# StivySimpMusic — fork indipendente di stivy73

Fork di [SimpMusic](https://github.com/maxrave-dev/SimpMusic), il client open source per YouTube Music creato da [maxrave-dev](https://github.com/maxrave-dev). Questo repository prosegue lo sviluppo **in modo autonomo** rispetto al progetto originale: funzionalità, correzioni, tempi e distribuzione di questo fork sono gestiti qui. Non è una versione ufficiale né è supportata dai manutentori upstream.

Il codice originale è stato modificato in questo fork nel 2026; le date e il contenuto delle singole modifiche sono documentati nella cronologia Git.

Lo sviluppo di questo fork usa anche **vibe coding**, cioè strumenti di IA per assistere la scrittura e la revisione del codice. Questa indicazione rende trasparente il processo di sviluppo; le modifiche vanno comunque verificate con test e prove d'uso prima di considerarle stabili.

## Migliorie introdotte nel fork

- **Album di YouTube Music nella Libreria:** lettura degli album salvati nell'account autenticato, con paginazione completa, aggiornamento al cambio account e apertura nella schermata album esistente. Gli album remoti restano distinti dai preferiti locali di SimpMusic.
- **Android Auto:** sezioni Home, Albums, Favorites e Downloads; album in griglia con copertine corrette, preferiti di YouTube Music e selezione alfabetica nelle raccolte supportate. Corretta anche l'apertura del brano scelto dai risultati di ricerca.
- **Significato della canzone:** analisi in italiano divisa in due parti — prima la storia raccontata dal testo, poi l'interpretazione — di circa 900 caratteri spazi inclusi, con tolleranza del 5% (855–945 caratteri), tramite OpenAI, Google Gemini 3.8 Flash o un endpoint compatibile configurato nelle impostazioni, con messaggi chiari per chiavi mancanti o non compatibili con il provider e possibilità di condividere il risultato.
- **Lettura vocale del significato:** TTS nativo di Android, OpenAI oppure Google Gemini 3.8 Flash TTS, disponibili nel player dell'app e in Android Auto. I servizi cloud riproducono l'audio in streaming; Gemini offre i toni DJ, Empatico e Professionale. In auto la spiegazione viene letta senza mostrarne il testo sul display.
- **Stabilità della riproduzione:** correzioni alla gestione del servizio multimediale e di alcuni problemi riscontrati in Android Auto.

Queste modifiche si aggiungono alle funzioni ereditate da SimpMusic; non implicano che tutte le funzioni del progetto originale siano state sviluppate in questo fork. Per la descrizione e i crediti del progetto di partenza, consulta il [README originale conservato qui](README.upstream.md).

La generazione del significato usa il provider IA selezionato e richiede la relativa chiave: una chiave OpenAI va associata a OpenAI, una chiave Google AI Studio a Gemini. La voce Gemini richiede una chiave API personale di Google AI Studio; se selezionata, il testo della spiegazione viene inviato a Google per produrre l'audio. Disponibilità e costi dipendono dai rispettivi account. La chiave TTS può essere diversa da quella usata per generare il significato della canzone.

## NoteNarrate per iOS

Il prototipo SwiftUI [NoteNarrate iOS](iosPrototype/README.md) prosegue separatamente
rispetto ad Android. La **0.13.0 (36)** aggiunge la navigazione tra pagine album
dentro le liste CarPlay, unifica i preferiti nei like YouTube Music (importando
anche tutte le tracce degli album preferiti precedenti), genera la radio del brano
con Gemini a ogni richiesta ed esclude proposte recenti verificate nel catalogo.
La narrazione, anche dalla cache o dalla voce di sistema, ha guadagno audio +30%.
La **0.12.4 (35)** sostituisce le schede verticali CarPlay
con copertine quadrate proporzionate, ripristina un unico orologio musicale dopo
la narrazione e limita la riproduzione alla durata della sorgente quando il
contenitore audio dichiara una coda aggiuntiva. Superati 236 test core e due
scenari UI; il risultato sul display e sull’audio dell’auto resta da collaudare.
La **0.12.3 (34)** apre le opzioni brano direttamente dai tre
puntini, include Mi piace YouTube Music nella scheda, rimuove Mostra video da iOS
e torna alla Home dopo il salvataggio delle impostazioni.
La **0.12.2 (33)** corregge le barre laterali native del Duo,
aggiunge Indietro nel player e lo swipe dal bordo per ridurlo mantenendo la musica.
La **0.12.1 (32)** aggiunge il karaoke animato sui timestamp
forniti dal testo, decodifica locale degli indirizzi audio WEB_REMIX, controlli
oltre il primo megabyte e recupero della riproduzione dalla stessa posizione.
La continuità sull’account Premium del telefono richiede ancora la prova reale.
La **0.12.0 (31)** aggiunge il menu player con le azioni
della versione Android e una pagina album con copertina grande, metadati,
Play/casuale/download, preferiti persistenti e tracce numerate con menu.
iPhone e CarPlay condividono il recupero completo delle tracce dell’album,
escludendo i suggerimenti. La **0.11.0 (30)** integra l’estensione Condividi per brani e
link YouTube Music/YouTube, una raccolta Ricevuti e lista/griglia, ordinamenti e
indice alfabetico persistenti per le raccolte. La **0.10.0 (29)** ha aggiunto
widget iOS Player/Playlist/Ascolti, sezioni
Classifiche/Podcast/Mix, artisti seguiti con avvisi facoltativi sulle nuove uscite
e consigli musicali Gemini verificati nel catalogo. Restano disponibili download/offline,
testi sincronizzati, timer, ripristino della coda, qualità audio, effetti, crossfade,
strumenti dei testi e statistiche/riepiloghi. Le prove fisiche Duo/CarPlay su voce e
continuità CDN restano separate. [Stato del porting](iosPrototype/PORTING_PROGRESS.md).

## Download e aggiornamenti

Le eventuali APK di **questo fork** devono essere pubblicate nelle [Releases di stivy73/SimpMusic](https://github.com/stivy73/SimpMusic/releases). Le release, i badge, F-Droid e il sito presenti nel README originale appartengono al **progetto upstream** e non identificano build di questo fork. Verifica sempre repository, versione e provenienza dell'APK prima di installarla.

Questo repository contiene anche il submodule [`core`](https://github.com/stivy73/core). Per ottenere i sorgenti completi dopo il clone:

```sh
git submodule update --init --recursive
```

## Licenza e attribuzione

Il codice di SimpMusic e del submodule `core` mantiene la licenza **GNU General Public License v3**: [LICENSE](LICENSE) e [core/LICENSE](core/LICENSE). Il progetto originale e i suoi autori restano accreditati; le modifiche di questo fork sono consultabili nella cronologia Git. Consulta le rispettive licenze e gli avvisi inclusi nei sorgenti prima di ridistribuire versioni modificate.

Sorgenti originali: [maxrave-dev/SimpMusic](https://github.com/maxrave-dev/SimpMusic) (`dev`) e [maxrave-dev/core](https://github.com/maxrave-dev/core) (`multiplatform`). Questo fork non dichiara affiliazione con Google, YouTube Music o il progetto upstream.


### NoteNarrate Android Auto — 2.3.11

- Search can be filtered to songs, artists or albums using the category selector above the results.
- Album results open the existing album browser and playback queue. Artist results open the artist catalog of albums and singles.
- The playback header includes album and artist icon actions when their identifiers are available, alongside song meaning and queue actions.
- Retains the 2.3.10 fix for empty-queue transitions when starting a radio station.

The Android APK source is maintained on this personal fork and its `stivy73/core` submodule; upstream SimpMusic attribution and GPL licensing are preserved.
