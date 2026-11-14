# NoteNarrate YouTube Music 0.17.8 (71)

Pausa dal blocco schermo durante Chromecast: i comandi PLAY/PAUSE/SEEK
vengono inviati e confermati con GET_STATUS sul ricevitore. Non si attende
una risposta diretta obbligatoria ai comandi che producono notifiche di
stato. La conferma deve corrispondere alla sessione media selezionata;
una sessione sostituita o una pausa ignorata non vengono dichiarate riuscite.
L'identificativo media del ricevitore permette il controllo anche quando
il suo stato non ripete i metadati personalizzati. Gli indirizzi IPv6 locali
sono riconosciuti anche con lettere maiuscole.

In Impostazioni > Diagnostica audio e voce compare la riga Comandi Chromecast,
con orario, comando e ultimo passaggio/esito. La diagnostica distingue la
pubblicazione della scheda dalla disponibilita del collegamento comandi.
La nuova riga fa parte del pannello esistente e non e un menu separato.
L'esito e condiviso tra app ed estensione in un gruppo Portachiavi dedicato;
non contiene cookie, chiavi API, URL audio, titoli o indirizzi del ricevitore.
Resta accessibile a telefono bloccato dopo il primo sblocco dal riavvio.
I gruppi privati del Portachiavi conservano il gruppo predefinito originale;
l'estensione non riceve accesso ai gruppi delle credenziali dell'app.

Rimossi gli avvisi informativi e i testi sui limiti tecnici da player,
sessione in auto, audio, testi, importazioni e impostazioni. Restano errori
operativi, comandi, caricamenti e conteggi effettivi; nelle importazioni
parziali si mostra N di M tracce senza banner. Licenze e informazioni sul
trattamento dei dati restano nelle rispettive schermate.

29 test Core superati: inclusi ricevitore con sola notifica di stato senza
risposta diretta a Pausa, metadati omessi, sessione sostituita, pausa ignorata,
certificato differente, Play/Seek, volume e gestione audio. Il test UI di
avvio e apertura ripetuta del player e passato. La scheda remota richiede
iOS 27; minimi app iOS 17 e Watch watchOS 10 invariati. Compilazione iPhone
e firme di sviluppo verificate; l'efficacia sul Chromecast reale va ancora
confermata nella beta. Il ponte audio corrente richiede ancora l'app aperta.

Destinazione: NoteNarrate YouTube Music, App Store Connect 6821630132,
com.stivy.simpmusic.prototype. La variante Apple Music resta separata.
Xcode 27.2 RC (27B48), SDK 27.2. Distribuzione interna ai gruppi esistenti
Team interno e Stivy73, con verifica di Tommaso e Girbreda dopo elaborazione.

Archivio Release completato. Verifica dell'archivio superata per dyld,
NowPlaying weak-linked, gruppo Portachiavi diagnostico condiviso e gruppi
privati preservati. Sulla versione 71 sono passati tre test UI senza errori:
avvio/apertura ripetuta del player, salvataggio impostazioni e riapertura
della sessione passeggeri con rotazione del codice.

IPA: deliveries/NoteNarrate-iOS-0.17.8-build71.ipa.
Archivio e simboli: deliveries/archives/NoteNarrate-0.17.8-build71.xcarchive.
SHA-256: `9d618f27a4338766afba56c611c0a3a254c99d3a838e7a9d38ae0c9019074509`.
Sorgenti: `f7ad43306ef9ce27109ca9cf074749790152cbdb`, pubblicati sul fork
stivy73/SimpMusic, branch feature/youtube-library-albums.

Upload ufficiale completato tramite modalita legacy altool dopo il timeout
del canale predefinito, riutilizzando la stessa consegna senza duplicati.
Delivery UUID: `bcc2c0be-1c7e-492d-9126-1ac5fc3b0c59`.
Verifica del 2026-11-14: VALID, INTERNAL_ONLY, IN_BETA_TESTING; assegnata a
Team interno e Stivy73. Confermati appartenenza e accesso app di Tommaso e
Girbreda; note italiane salvate e rilette. Nessun utente o ruolo modificato,
nessuna pubblicazione App Store.
Ricevuta: deliveries/NoteNarrate-iOS-0.17.8-build71-AppStore-status.json.
Validazione: deliveries/NoteNarrate-iOS-0.17.8-build71-validation.json.
