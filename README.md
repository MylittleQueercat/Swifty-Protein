# Swifty Protein

An Android Flutter app for exploring ligands from the RCSB Protein Data Bank.

The app reads `ligands.txt`, searches ligand IDs, downloads and parses CIF files, and displays an interactive ball-and-stick preview. It also includes local account login, biometric unlock, and image sharing.

## Run

```bash
flutter pub get
flutter run
```

An Android device with internet access is required to load ligands. The app is still in development: the molecule preview uses software projection, and the native Android build has not yet been verified in this environment.
