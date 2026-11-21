# NoteNarrate YouTube Music 0.17.17 (80)

Il player avvia i brani lunghi con indice AAC completo dal frammento richiesto.
La percentuale di download è visibile nel player, nel menu del brano e in
Libreria → Download e offline. Se la dimensione è sconosciuta, viene mostrato
il numero di byte ricevuti. La spunta conferma che il file è disponibile offline.

Per i download AAC frammentati, NoteNarrate verifica la durata dei campioni
audio e ignora i marcatori vuoti che possono far apparire doppia la durata del file.
Conserva la durata verificata per la riproduzione locale, il passaggio al brano
successivo e Chromecast.

Prova su Mac con *Oceanic Delta Waves* di Jason Stephenson. Il download ha
restituito tutti i 62.132.786 byte. Dopo la riapertura della libreria, AVPlayer
ha riprodotto il file da disco all’inizio, a 22:08 e negli ultimi tre secondi,
segnalando la fine a 1:03:59,07. Nel confronto di streaming su Mac e Wi-Fi
la mediana di tre avvii a freddo è scesa da 17,78 a 1,08 secondi.
