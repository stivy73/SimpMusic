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

Archivio firmato, IPA, caricamento e gruppi TestFlight da verificare.
Collaudo fisico sul Duo e in CarPlay ancora necessario.
