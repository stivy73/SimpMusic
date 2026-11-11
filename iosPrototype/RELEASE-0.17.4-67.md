# NoteNarrate 0.17.4 (67)

Corregge il crash immediato all'avvio della build 66. Il report TestFlight del
Duo riporta `DYLD 1 Library missing`, `@rpath/GoogleCast.framework/GoogleCast`:
il framework era presente nell'IPA ma l'eseguibile non cercava nella cartella
Frameworks dell'app. Debug e Release ora includono
`LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks`.

Il nuovo CheckRuntimeFrameworks.py controlla LC_RPATH e la presenza delle
dipendenze incorporate anche per il dylib di Debug. CheckCarPlayIPA.py esegue
automaticamente il controllo su ogni pacchetto. Il controllo rifiuta l'IPA 66
e accetta il pacchetto corretto. Il crash originale è stato riprodotto nel
simulatore; due avvii con apertura player sono superati con la correzione.

Archivio firmato con Xcode 27.2 RC (27B48), SDK 27.2. Versione/build 0.17.4 (67)
su app, tre estensioni e Watch; minimi iOS 17 e watchOS 10 invariati.
Due avvii reali anche in Release, senza fixture Debug, superati con Home
raggiungibile. L'IPA esportata supera firma di distribuzione, controlli dei
framework dinamici, CarPlay, Siri, Widget, Share e Watch.

Sorgenti: `e2c9d5fc97eef8dd0c4a94561f71921e0c9d7895`, branch
`feature/youtube-library-albums` sul fork `stivy73/SimpMusic`.
IPA: `deliveries/NoteNarrate-iOS-0.17.4-build67.ipa`.
SHA-256: `5cd159c16cd9b91d772ce1be5da2a6b2f58b873fb12de176fcf10ed04f3bf9de`.
Archivio e simboli: `deliveries/archives/NoteNarrate-0.17.4-build67.xcarchive`.
Validazione: `deliveries/NoteNarrate-iOS-0.17.4-build67-validation.json`.

Upload Apple senza errori. Delivery/build UUID
`b88053ab-2043-4159-bb09-772f90334a57`, stato **VALID / IN_BETA_TESTING**,
**INTERNAL_ONLY**. Associazioni a **Team interno** e **Stivy73** rilette,
appartenenza al gruppo e accesso all'app di **Tommaso** e **Girbreda** verificati.
Note beta italiane salvate e rilette. Nessuna modifica di utenti, ruoli,
distribuzione automatica o pubblicazione App Store.
Ricevuta: `deliveries/NoteNarrate-iOS-0.17.4-build67-AppStore-status.json`,
verificata l'11 novembre 2026 alle 07:45:20 UTC.

Il crash originale proviene dal Duo. La correzione è stata avviata nel
simulatore in Debug e Release; installazione/avvio della nuova beta sul Duo
restano da confermare con l'aggiornamento TestFlight.
