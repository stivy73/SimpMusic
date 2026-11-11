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
raggiungibile. Consegna TestFlight in corso.
