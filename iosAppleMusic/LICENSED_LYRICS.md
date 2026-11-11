# Contratto del servizio testi

Stato: client pronto, nessun contratto/provider/backend attivo. Questo documento
non concede diritti sui testi. Il controllo `permittedUses` verifica quanto
asserito dal nostro backend fidato; non prova da solo l'esistenza di una licenza.

## Architettura

App → backend HTTPS controllato → API del fornitore con licenza.
Le credenziali del fornitore restano sul backend. Non usare l'endpoint del
fornitore direttamente nell'app e non configurare server di terzi non fidati.
Il backend dovrà applicare autenticazione dell'app/utente, limiti richieste e
le condizioni reali del contratto prima di rendere disponibile il servizio.
Nessun backend di produzione o credenziale è stato creato in questo porting.

L'app richiede conferma prima di inviare il riferimento del brano al servizio
e il testo a Gemini. Non salva i testi sorgente su disco. L'interpretazione
rimane in memoria nella sessione e viene cancellata al cambio di brano.
I redirect HTTP vengono rifiutati per evitare l'inoltro dei metadati altrove.

## Richiesta

Impostare in Xcode il build setting `LICENSED_LYRICS_ENDPOINT` all'URL completo
HTTPS del backend. Info.plist lo espande; non configurato produce un errore
esplicito prima di effettuare richieste.

`POST /lyrics/resolve`, `Content-Type: application/json`:

```json
{"appleMusicID":"123456789","title":"Titolo","artist":"Artista"}
```

Il backend deve risolvere l'ID del catalogo Apple Music, verificare la
corrispondenza e i diritti territoriali/contrattuali. Gli ID della libreria
locale potrebbero richiedere risoluzione nel catalogo: non inventare una
corrispondenza basandosi sul solo titolo. In caso di dubbio rispondere 404/403.

## Risposta autorizzata

`200 application/json`, massimo 200 kB, date ISO8601 UTC:

```json
{
  "appleMusicID": "123456789",
  "text": "Testo autorizzato dal fornitore",
  "provider": "Nome del fornitore",
  "copyright": "Attribuzione richiesta dal titolare",
  "sourceURL": "https://provider.example/attribution/123456789",
  "expiresAt": "2030-01-01T00:00:00Z",
  "permittedUses": ["aiInterpretation"]
}
```

L'esempio è un fixture di schema, non un'autorizzazione. Il backend può emettere
`aiInterpretation` solo quando il contratto consente esplicitamente l'invio del
testo a Google, l'analisi/trasformazione AI e l'uso delle interpretazioni previsto
dall'app (inclusa la lettura). La sola licenza per mostrare i testi non deve
abilitare questo campo. Non chiedere permessi inesistenti come fallback.

Il client rifiuta ID differente, testo vuoto/oltre 100 kB, assenza di attribuzione,
fonte non HTTPS, scadenza passata o assenza di `aiInterpretation`. Timeout 25 s,
sessione effimera senza cookie e senza cache persistente. Risposte non 200 o
malformate non vengono inviate a Gemini. Non vengono mostrati testi integrali
nella UI; si mostra l'attribuzione con link e l'interpretazione generata.

## Attivazione successiva

1. Selezionare un fornitore e ottenere accordo scritto per gli usi sopra.
2. Implementare sul backend l'adapter dell'API reale, autenticazione e limiti;
   usare segreti del server e log privi di testi/chiavi.
3. Configurare l'endpoint e verificare casi consentiti, negati, scaduti, titoli
   ambigui, account diversi e mercati diversi, con fixture autorizzati.
4. Allineare privacy policy, informative Gemini, dati dichiarati in App Store
   Connect e attribuzione alle condizioni effettivamente concordate.

Test locali del contratto: `swift test --package-path iosAppleMusic`.
