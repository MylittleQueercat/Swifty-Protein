# Swifty Protein

An Android Flutter app for exploring ligands from the RCSB Protein Data Bank.

The app reads `ligands.txt`, searches ligand IDs, downloads and parses CIF files, and displays an interactive ball-and-stick preview. It also includes local account login, biometric unlock, and image sharing.

## Run

```bash
flutter pub get
flutter run
```

An Android device with internet access is required to load ligands.

Use a full JDK for Android builds. Android Studio's bundled JDK works when
`JAVA_HOME` points to its `jbr` directory. Build a debug APK with
`flutter build apk --debug`. The output is
`build/app/outputs/flutter-apk/app-debug.apk`.

## Progress

- Flutter project and the full ligand list from `ligands.txt` are in place.
- Search filters ligand IDs as the user types. Selecting one downloads its CIF file from RCSB and parses atoms and bonds outside the UI isolate.
- The current ball-and-stick preview supports rotation, zoom, atom selection, and PNG sharing through the Android share sheet.
- Android local accounts use salted password hashes and Android KeyStore encrypted storage. The login screen returns whenever the app leaves the foreground; biometric unlock is available on supported Android devices.
- Flutter static analysis previously found no compile errors. The Android debug APK builds successfully with Android Studio's bundled JDK. Native authentication and sharing still need device verification.

## Android runtime verification

On the workstation used for testing, both the Pixel 10 and Medium Phone
emulators failed during startup. The Pixel 10 also failed to restore its
`default_boot` snapshot. A minimal QEMU virtual machine with no Android image
reproduced `KVM: entry failed, hardware error 0x0`, including outside the
Android emulator. The cause of the host KVM failure is still unconfirmed.
A separate Android emulator attempt with software CPU emulation went offline
during APK installation.

The app has yet to complete an on-device launch test. Use an Android phone
with USB debugging enabled or a workstation with a working emulator. Once
`adb devices` lists the target as online, install and launch the debug build:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n com.example.swifty_protein/.MainActivity
```

## Next steps

1. Install and launch the debug APK on an Android device or emulator.
2. Replace the software projection in `lib/main.dart` with a hardware accelerated 3D renderer, including a camera, lighting, and sphere and cylinder geometry.
3. Add a themed app icon and a branded launch screen that remains visible for the required duration.
4. Check account creation, password login, biometric failures, background locking, CIF loading errors, atom selection, gestures, and sharing on a real Android device.
5. Profile large ligands and improve rendering, memory use, and responsiveness where needed.

Android is the supported target. The generated iOS scaffold has no native authentication or sharing implementation.
