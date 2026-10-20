# Verifica Mac — 12 ottobre 2026

## Distribuzione 0.1.0 (1)

- Xcode 27.0 (27A266a), macOS minimo 14.0; archive Release riuscito.
- Binario universal `x86_64 arm64`, bundle `com.stivy.notenarrate.mac`.
- Firma cloud-managed `Developer ID Application: Archetipi Digitali srl (63W2ZKR3Z7)`.
- Invio notarizzazione riuscito: distribuzione Xcode `CB27A0E2-D067-4C13-8B5E-854507D0CE0B`.
- `xcodebuild -exportNotarizedApp` riuscito; ticket allegato, `stapler validate` riuscito.
- `codesign --verify --deep --strict --all-architectures` riuscito.
- Timestamp e hardened runtime verificati per arm64 e x86_64; sandbox e rete in uscita,
  nessun entitlement get-task-allow.
- Gatekeeper: `accepted`, `source=Notarized Developer ID`.
- ZIP integro; tutti i controlli ripetuti con successo sulla copia estratta.
- Nessuna chiave API o sessione personale inclusa nella distribuzione.

Archive:

```sh
xcodebuild -project NoteNarrateMac.xcodeproj -scheme NoteNarrateMac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/notenarrate-mac-notarized-build \
  -archivePath /tmp/notenarrate-mac-0.1.0.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Development: Michele Stival (64A9DQLN43)' archive
xcodebuild -exportArchive -archivePath /tmp/notenarrate-mac-0.1.0.xcarchive \
  -exportPath /tmp/notenarrate-mac-notarization-upload \
  -exportOptionsPlist NotarizeOptions.plist -allowProvisioningUpdates
sh Scripts/FinishNotarization.sh /tmp/notenarrate-mac-0.1.0.xcarchive
```

L'azione Archive produce entrambe le architetture anche con destination arm64.
Log effettivi: `/tmp/notenarrate-mac-archive.log`,
`/tmp/notenarrate-mac-notarization-upload.log`, `/tmp/notenarrate-mac-finalization.log`.

## Funzionalità

- `swift test --scratch-path /tmp/notenarrate-mac-core-tests`: 68 test, zero errori,
  ricontrollati prima della notarizzazione. Log `/tmp/notenarrate-mac-core-release-check.log`.
- Formatter Swift, confronto prompt Android e confronto filtri Home passati nel porting.
- Build iOS generica passata dopo gli adattatori macOS e le preferenze iniziali Mac.
- Recupero LRCLIB reale Dreams/Fleetwood Mac: 1233 caratteri, 0.52 s dopo risposta YouTube
  senza testo; non sono stampati contenuto o credenziali.
- Gemini TTS reale su Mac con il probe: primo PCM 1.10 s, primo buffer audio 1.13 s,
  durata audio 56.80 s, ultimo buffer completato a 58.00 s; cache su disco 0.002 s,
  checksum verificato senza nuova richiesta HTTP. Log `/tmp/notenarrate-mac-gemini-stream-live.log`.
- UI test Mac isolati: lettura nativa con pausa/ripresa riuscita; streaming PCM di prova
  e replay della cache riusciti. Il terzo test ha verificato avanzamento reale e riproduzione
  dopo minimizzazione, ma è fallito cercando il pulsante Testo fuori dalla gerarchia visibile:
  non si dichiara la suite UI interamente riuscita. Risultato:
  `/tmp/notenarrate-mac-isolated-tests.xcresult` (3 test, 1 fallimento).

## Limiti del collaudo

La notarizzazione non costituisce verifica completa delle funzioni dell'app. Il runtime è
stato provato su Apple silicon; la firma Intel è verificata ma non il runtime su un Mac Intel.
Non è stata collaudata qui la Libreria autenticata sulla sessione Google personale del Mac.
Non è stata eseguita una distribuzione sul Mac App Store né una pubblicazione GitHub/Drive.
