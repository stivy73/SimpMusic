# NoteNarrate 0.16.9 (62)

Preparazione audio anticipata: il successore della coda viene preparato durante
l’ascolto, anche senza crossfade. A player fermo l’apertura di un album prepara
la prima traccia. È conservato un solo player anticipato e silenzioso.
Avanti e fine brano riusano sorgente validata, buffer, AVPlayerItem e player;
una preparazione già in corso viene condivisa senza ricominciare il lavoro.
Pausa e narrazione mantengono silenzioso il successore. I controlli CDN contro
403/stop a un minuto restano invariati, così come diagnostica e recupero.

Il riuso richiede la stessa sessione completa, revisione account, rete e qualità.
TTL massimo 120 s, con margine di 30 s sulla scadenza della sorgente. Il contesto
della preparazione, gli indirizzi e l’audio anticipato restano solo in memoria;
nessuna nuova persistenza, senza modifiche alla sessione già nel Portachiavi.
La prima selezione non anticipata richiede ancora la rete: non è garantita
l’assenza di attesa per ogni brano arbitrario.

Prova pubblica AVFoundation sul Mac, uscita muta, Ma perché (114 BPM Mix)/883:
1,92 s a freddo e 0,110 s al comando sul player già preparato, stessa soglia
0,02 s e osservazione ogni 10 ms. Avanzamento oltre il minuto senza blocchi.
Sono osservazioni singole, non tempi garantiti sul Duo o in auto.

72 test core e 3 nuove regressioni UI superati: Avanti caldo, riuso della
preparazione in corso e pausa silenziosa. Compilazioni Debug/simulatore e
Release/iPhone riuscite con Xcode 27.2 RC (27B48), SDK 27.2.
[Misure, limiti e log](AUDIO_STARTUP.md).

Archivio firmato ed esportazione riusciti. Verifiche IPA CarPlay/Siri/widget/share
e firma Watch superate; minimi iOS 17 e watchOS 10 invariati.
Sorgenti: `26569af358fe10e4282c83943d729dd4c54aafc3`, branch
`feature/youtube-library-albums` su `stivy73/SimpMusic`.
IPA esportata: `deliveries/NoteNarrate-iOS-0.16.9-build62.ipa`.
SHA-256: `1f21a533b7eb45f5b68c12d10cea38c2fddb2046bb065708eb9efa5412c612ae`.

Upload Apple riuscito, elaborazione **VALID**, stato **IN_BETA_TESTING**.
Associazioni a **Team interno** e **Stivy73** rilette via API. Appartenenza di
**Tommaso** e **Girbreda** al Team interno verificata per questa consegna.
Nessuna modifica di utenti/ruoli o pubblicazione App Store.
Ricevuta: `deliveries/NoteNarrate-iOS-0.16.9-build62-AppStore-status.json`.
Collaudo fisico sul Duo e in CarPlay ancora necessario.
