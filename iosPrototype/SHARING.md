# Ricezione da Apple Music e Spotify

In Condividi scegliere **NoteNarrate**, poi **Aggiungi a NoteNarrate**. Aprendo
NoteNarrate compare l’anteprima; il contenuto resta disponibile anche in
**Libreria → Ricevuti** fino alla riproduzione, al salvataggio o all’eliminazione.

Sono riconosciuti i collegamenti di **brani, album e playlist** di entrambi i
servizi, inclusi i link Apple di album con `?i=` per un singolo brano, le varianti
Spotify `intl-xx` e i link brevi dei domini consentiti. Si conservano soltanto
identificatori, tipo, servizio e paese; parametri di tracciamento eliminati.
I vecchi link YouTube/YouTube Music e le ricerche testuali restano compatibili.

L’anteprima recupera titolo, autore, copertina e tracce dal catalogo pubblico.
**Trova i brani su YouTube Music** converte le tracce con tre ricerche simultanee,
mostra l’avanzamento e mantiene l’ordine originale, comprese eventuali ripetizioni
volute. Titolo, artisti e durata devono concordare: cover, remix e registrazioni
live non sono sostituzioni automatiche. **Scegli versione** permette di cambiare
la ricerca e confermare un risultato per ciascuna traccia dubbia o assente.

Si può riprodurre, aggiungere alla coda o creare una **playlist privata YouTube
Music**, con un conteggio esplicito delle tracce trovate. Solo quest’ultima
azione richiede l’accesso YouTube Music. Le raccolte, i Mi piace e gli abbonamenti
Apple Music/Spotify non vengono modificati; la riproduzione usa YouTube Music.
La pagina contiene un collegamento alla raccolta originale per ogni servizio.

## Limiti visibili nell’interfaccia

- Una playlist privata deve prima diventare accessibile con un link pubblico
  nell’app di origine. Non si richiedono password o cookie Apple/Spotify.
- I servizi possono limitare le tracce pubbliche. Il totale viene confrontato
  quando disponibile; altrimenti compare un avviso che la completezza non è
  confermata. Non viene dichiarata completa un’anteprima limitata.
- Sono accettate fino a 500 tracce per raccolta, con risposte fino a 8 MiB e
  timeout di rete. Le raccolte più grandi ricevono un errore esplicito.
- I metadati pubblici e la presenza di una versione YouTube Music non garantiscono
  l’identità del master o la disponibilità audio in ogni paese/account.
- La conversione si può interrompere senza perdere il link ricevuto. Il cambio
  account annulla le ricerche pendenti e invalida le corrispondenze. Nessuna
  scrittura remota è automatica; un esito di creazione non confermato richiede
  di controllare le playlist prima di riprovare, per evitare duplicati.

## Implementazione e verifica

`SharedMusic.swift` valida i link e definisce il formato dell’inbox App Group.
`SharedCatalog.swift` recupera solo metadati pubblici, blocca redirect verso
host non consentiti e implementa conversione, scelta manuale e annullamento.
`SharedCatalogScreen.swift` offre anteprima, coda e creazione della playlist.
L’estensione non compie richieste di rete durante la condivisione.

Test mirati in `SharedCatalogTests.swift` e `SharingAndCollectionTests.swift`;
scenari UI reali dell’estensione in `PrototypeUITests.swift`. I test UI usano
metadati e scritture remoti simulati; i probe di rete leggono invece i metadati
reali senza modificare gli account. Probe ripetibile:

```sh
DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer \
  swift run --package-path iosPrototype --scratch-path /tmp/NoteNarrate-Sharing \
  NetworkProbe --shared-catalog 'https://music.apple.com/us/album/594061854' --match-first
```

L’implementazione non implica un caricamento TestFlight: la beta pubblicata e
la distribuzione ai tester vanno verificate separatamente.

Verifiche del 1 novembre 2026 con Xcode 27.2 RC (27B48), SDK 27.2:

- 297 test core superati, inclusi 26 test di condivisione/importazione.
- Compilazioni Debug per simulatore e Release per iPhone riuscite.
- Cinque scenari UI distinti superati: ricezione Apple Music (tre tipi), Spotify
  (tre tipi), ricerca da testo, YouTube diretto e corrispondenza manuale. Le
  scritture private YouTube Music nei test UI sono simulate.
- Sei link reali verificati dal resolver Swift: brano/album/playlist di entrambi
  i servizi. Album Apple da 11 tracce e playlist editoriali da 50 tracce lette;
  verificato anche un link di playlist personale Apple con 20 tracce visibili.
- Il primo brano di cinque raccolte ha avuto una corrispondenza automatica su
  YouTube Music; la registrazione Spotify Singles di esempio richiede una scelta
  manuale. Non viene promesso il trasferimento esatto di ogni versione.

Prove locali in `deliveries/sharing/` e nei result bundle
`/tmp/NoteNarrate-SharedCatalog-UI-{signed,final,manual}.xcresult`.
Nessun nuovo collaudo sui telefoni dei tester. La funzionalità è stata poi
distribuita in TestFlight interno con **0.15.0 (50)**; stato e gruppi verificati
separatamente nella [consegna](RELEASE-0.15.0-50.md).
