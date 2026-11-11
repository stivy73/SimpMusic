# Uscite audio AirPlay e Chromecast

Il player iPhone/iPad espone due pulsanti accanto al volume: AirPlay (selettore
AVRoutePickerView di sistema) e Chromecast (selettore dell’SDK Google Cast).
AirPlay usa la sessione audio longFormAudio già condivisa da musica e voce.

Chromecast usa GoogleCastDynamic 4.8.6, fissato tramite Swift Package Manager,
e il Default Media Receiver CC1AD845. Non richiede un ricevitore personalizzato.
I comandi esistenti di play/pausa, seek, volume e cambio brano passano al
ricevitore; posizione e stato tornano al player. Il completamento remoto
avanza la coda. Crossfade ed equalizzazione locali non vengono applicati al Cast.
Il limite di durata sorgente evita le code silenziose dei contenitori errati.

Il ricevitore legge un endpoint HTTP temporaneo sulla rete locale, protetto da
un token casuale che cambia ad ogni caricamento. Gli indirizzi CDN firmati,
i cookie e la sessione account rimangono sul telefono. Il ponte serve il solo
brano corrente con richieste CDN limitate a blocchi di 128 KiB, oppure un file
scaricato, senza cache persistente aggiuntiva. Gestisce GET, HEAD, Content-Range,
HTTP 206/416, massimo quattro connessioni e timeout di lettura delle intestazioni.
L’SDK richiede il permesso Rete locale per trovare i dispositivi.

Per Chromecast entrambi i dispositivi devono trovarsi sulla stessa rete Wi-Fi;
NoteNarrate deve rimanere aperta perché ospita il ponte audio. Questa limitazione
è mostrata nel player. La narrazione resta sull’uscita audio dell’iPhone (anche
AirPlay), non viene inviata al Chromecast. Gli stream HLS senza alternativa AAC
non sono supportati dal ponte e mostrano un errore. La disconnessione Cast
conserva la posizione senza avviare automaticamente l’altoparlante del telefono;
la selezione esplicita di AirPlay trasferisce il controllo all’uscita Apple.

Verifica: build iPhone Debug e Release riuscite con SDK 27.2; test HTTP end-to-end e parsing
range con file sintetico superati. Prova su ricevitori Chromecast e AirPlay fisici
ancora necessaria. Questa modifica non costituisce una consegna TestFlight.

Riferimenti:
- https://developers.google.com/cast/docs/ios_sender/
- https://developers.google.com/cast/docs/ios_sender/integrate
- https://developer.apple.com/documentation/avkit/avroutepickerview
