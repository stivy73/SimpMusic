# NoteNarrate 0.16.8 (61)

Il cuore dell’album salva ora l’album stesso nella raccolta YouTube Music,
oltre a mettere Mi piace alle sue tracce. Il salvataggio usa l’audioPlaylistID
OLAK fornito dal controllo Play dell’intestazione, mai il browse ID MPRE né
un identificativo di radio o album suggeriti.

Il cuore diventa pieno e rosso dopo la conferma del salvataggio album, senza
attendere che tutte le tracce abbiano Mi piace. La raccolta Album si aggiorna
con il dato confermato; un vecchio aggiornamento in corso non può cancellarlo.
Un errore successivo sui Mi piace mantiene l’album salvato e distingue i due
risultati. Tocchi ripetuti e cambi account sono gestiti senza duplicazioni o
risposte applicate all’account sbagliato. Il cuore dei brani usa il rosso quando
attivo. I dati di test sono isolati dal trasporto reale.

Verifica pubblica in sola lettura: Max Forever Vol. 2, Max Pezzali, 2026,
17 tracce, 4475 secondi; identificativo di salvataggio album presente.
Salvataggio autenticato e aspetto del cuore sul dispositivo ancora da collaudare.

86 test mirati superati: album, libreria, trasporto autenticato, parser,
paginazione, errori, tocchi ripetuti e cambi account. Archivio Release con
Xcode 27.2 RC (27B48), SDK iOS 27.2. Firma, esportazione, verifiche IPA
CarPlay/Siri/widget/share e firma Watch superate. Minimi iOS 17 e watchOS 10 invariati.

Sorgenti: `441d8956e334452f199c106eb2501bf8a299642f`, branch
`feature/youtube-library-albums` su `stivy73/SimpMusic`.
IPA esportata: `deliveries/NoteNarrate-iOS-0.16.8-build61.ipa`.
SHA-256: `21dba3be87e736573ae402e58280958f21f1f56054d33f7a9b0e1145d0967940`.

Upload Apple riuscito, elaborazione **VALID**, stato **IN_BETA_TESTING**.
Associazioni a **Team interno** e **Stivy73** rilette via API. Appartenenza di
**Tommaso** e **Girbreda** al Team interno verificata per questa consegna.
Nessuna modifica di utenti/ruoli o pubblicazione App Store.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.8-build61-AppStore-status.json`.
