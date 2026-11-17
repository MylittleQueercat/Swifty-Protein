# Swifty Protein

An Android Flutter app for exploring ligands from the RCSB Protein Data Bank.

The app reads `ligands.txt`, searches ligand IDs, downloads and parses CIF files, and displays an interactive ball-and-stick preview. It also includes local account login, biometric unlock, and image sharing.

## Run

```bash
flutter pub get
flutter run
```

An Android device with internet access is required to load ligands.

## Progress

- Flutter project and the full ligand list from `ligands.txt` are in place.
- Search filters ligand IDs as the user types. Selecting one downloads its CIF file from RCSB and parses atoms and bonds outside the UI isolate.
- The current ball-and-stick preview supports rotation, zoom, atom selection, and PNG sharing through the Android share sheet.
- Android local accounts use salted password hashes and Android KeyStore encrypted storage. The login screen returns whenever the app leaves the foreground; biometric unlock is available on supported Android devices.
- Flutter static analysis found no compile errors, but the Android APK has not been built: the current environment lacks a working `javac` installation. Native authentication and sharing still need device verification.

## Next steps

1. Install or select a full JDK, build the Android APK, and fix any Kotlin or manifest errors.
2. Replace the software projection in `lib/main.dart` with a hardware accelerated 3D renderer, including a camera, lighting, and sphere and cylinder geometry.
3. Add a themed app icon and a branded launch screen that remains visible for the required duration.
4. Check account creation, password login, biometric failures, background locking, CIF loading errors, atom selection, gestures, and sharing on a real Android device.
5. Profile large ligands and improve rendering, memory use, and responsiveness where needed.

Android is the supported target. The generated iOS scaffold has no native authentication or sharing implementation.
