# StivySimpMusic — fork indipendente di stivy73

Fork di [SimpMusic](https://github.com/maxrave-dev/SimpMusic), il client open source per YouTube Music creato da [maxrave-dev](https://github.com/maxrave-dev). Questo repository prosegue lo sviluppo **in modo autonomo** rispetto al progetto originale: funzionalità, correzioni, tempi e distribuzione di questo fork sono gestiti qui. Non è una versione ufficiale né è supportata dai manutentori upstream.

Il codice originale è stato modificato in questo fork nel 2026; le date e il contenuto delle singole modifiche sono documentati nella cronologia Git.

Lo sviluppo di questo fork usa anche **vibe coding**, cioè strumenti di IA per assistere la scrittura e la revisione del codice. Questa indicazione rende trasparente il processo di sviluppo; le modifiche vanno comunque verificate con test e prove d'uso prima di considerarle stabili.

## Migliorie introdotte nel fork

- **Album di YouTube Music nella Libreria:** lettura degli album salvati nell'account autenticato, con paginazione completa, aggiornamento al cambio account e apertura nella schermata album esistente. Gli album remoti restano distinti dai preferiti locali di SimpMusic.
- **Android Auto:** sezioni Home, Albums, Favorites e Downloads; album in griglia con copertine corrette, preferiti di YouTube Music e selezione alfabetica nelle raccolte supportate. Corretta anche l'apertura del brano scelto dai risultati di ricerca.
- **Significato della canzone:** spiegazione in italiano tramite OpenAI, Google Gemini 3.8 Flash o un endpoint compatibile configurato nelle impostazioni, con messaggi chiari per chiavi mancanti o non compatibili con il provider e possibilità di condividere il risultato.
- **Lettura vocale del significato:** TTS nativo di Android, OpenAI oppure Google Gemini 3.8 Flash TTS, disponibili nel player dell'app e in Android Auto. I servizi cloud riproducono l'audio in streaming; Gemini offre i toni DJ, Empatico e Professionale. In auto la spiegazione viene letta senza mostrarne il testo sul display.
- **Stabilità della riproduzione:** correzioni alla gestione del servizio multimediale e di alcuni problemi riscontrati in Android Auto.

Queste modifiche si aggiungono alle funzioni ereditate da SimpMusic; non implicano che tutte le funzioni del progetto originale siano state sviluppate in questo fork. Per la descrizione e i crediti del progetto di partenza, consulta il [README originale conservato qui](README.upstream.md).

La generazione del significato usa il provider IA selezionato e richiede la relativa chiave: una chiave OpenAI va associata a OpenAI, una chiave Google AI Studio a Gemini. La voce Gemini richiede una chiave API personale di Google AI Studio; se selezionata, il testo della spiegazione viene inviato a Google per produrre l'audio. Disponibilità e costi dipendono dai rispettivi account. La chiave TTS può essere diversa da quella usata per generare il significato della canzone.

## Download e aggiornamenti

Le eventuali APK di **questo fork** devono essere pubblicate nelle [Releases di stivy73/SimpMusic](https://github.com/stivy73/SimpMusic/releases). Le release, i badge, F-Droid e il sito presenti nel README originale appartengono al **progetto upstream** e non identificano build di questo fork. Verifica sempre repository, versione e provenienza dell'APK prima di installarla.

Questo repository contiene anche il submodule [`core`](https://github.com/stivy73/core). Per ottenere i sorgenti completi dopo il clone:

```sh
git submodule update --init --recursive
```

## Licenza e attribuzione

Il codice di SimpMusic e del submodule `core` mantiene la licenza **GNU General Public License v3**: [LICENSE](LICENSE) e [core/LICENSE](core/LICENSE). Il progetto originale e i suoi autori restano accreditati; le modifiche di questo fork sono consultabili nella cronologia Git. Consulta le rispettive licenze e gli avvisi inclusi nei sorgenti prima di ridistribuire versioni modificate.

Sorgenti originali: [maxrave-dev/SimpMusic](https://github.com/maxrave-dev/SimpMusic) (`dev`) e [maxrave-dev/core](https://github.com/maxrave-dev/core) (`multiplatform`). Questo fork non dichiara affiliazione con Google, YouTube Music o il progetto upstream.
