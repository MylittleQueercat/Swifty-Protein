# Swifty Protein

Swifty Protein is an Android Flutter app for exploring ligands from the RCSB
Protein Data Bank. It uses OpenGL ES 3.0 for interactive molecular rendering.

## Run on Android

```bash
flutter pub get
flutter run
```

Use an Android device or emulator that supports OpenGL ES 3.0. An internet
connection is needed for uncached ligands. For Android builds, set `JAVA_HOME`
to a full JDK such as the `jbr` directory bundled with Android Studio.

`flutter build apk --debug` writes the APK to
`build/app/outputs/flutter-apk/app-debug.apk`.

## Implemented

- **Launch and access.** The molecular app icon supports adaptive Android
  launchers. The branded launch screen animates for two seconds and respects
  Android's reduced motion setting. Local accounts use salted password hashes
  and Android Keystore storage. Biometric unlock is available on supported
  devices, and the app locks when it leaves the foreground.
- **Ligand list and cache.** The list shows all 1,243 IDs in `ligands.txt` and
  filters as you type, without regard to case. A progress bar covers CIF
  download and background parsing. Previously opened ligands work offline
  while cached. The cache keeps up to 128 files and 32 MiB and evicts the least
  recently accessed files first.
- **3D models.** Switch between Ball-and-Stick, Space-Filling, Stick, and
  Wireframe without reloading the molecule or resetting the camera. The viewer
  uses CPK colors. Drag to rotate, pinch to zoom, and drag with two fingers to
  pan.
- **Atom tools.** Tap an atom to see its element, ID, and coordinates and to
  highlight all atoms of the same element. Use the ruler menu to measure a
  distance between two atoms in Å or a bond angle in degrees. Select the shared
  atom second when measuring an angle.
- **Appearance.** The app remembers the choice of light, dark, or system
  appearance. The list uses branded cards and short UI animations. The 3D
  viewer adjusts its lighting and contrast for a dark background.
- **Sharing and export.** Capture the current 3D view as PNG or JPEG and save
  it to the photo library or open the Android share sheet. The share message
  includes the ligand name, atom count, and molecular formula.

## Verification

The Android debug APK builds successfully. On a Pixel 10 emulator, a test
account was created and used to log in. ATP downloaded from RCSB, displayed as
47 atoms and 49 bonds, and reopened with Wi-Fi and cellular data disabled.
Local cache checks also covered malformed CIF recovery and both eviction limits.

PNG and JPEG exports from the ATP preview both saved to the emulator's photo
library and decoded at 1080 × 1893. The Android share sheet preview showed
the ligand name, 47 atoms, and the formula `C10 H16 N5 O13 P3` for both formats.

In a 60 Hz emulator run with a synthetic model of 840 atoms and 2,246 bonds,
SurfaceFlinger recorded 107 frames during a 1.9 second rotation gesture. It
reported no dropped frames for the OpenGL surface. Of the recorded intervals,
94 were in the 16 ms bucket and the longest was in the 25 ms bucket. This was a
single emulator run. Sustained 60 FPS on physical Android devices has yet to be
verified.

## Emulator troubleshooting

On this workstation, Pixel 10 and Medium Phone emulators crashed during boot
with `-gpu swiftshader_indirect`. Pixel 10 booted with host graphics:

```sh
emulator -avd Pixel_10 -gpu host -no-snapshot -no-audio
```

If the emulator cannot find the AVD, set `ANDROID_AVD_HOME` to the directory
containing `Pixel_10.ini`. Wait for `adb devices` to report `device` and
`adb shell getprop sys.boot_completed` to return `1` before installing the APK.

## Remaining device checks

- Verify biometric enrollment and failure paths, plus background locking on a
  physical Android device.
- Check model switching, atom picking, measurements, and gesture frame pacing
  with several ligand sizes on physical hardware.
- Check how selected receiving apps handle attached images and share text.

Android is the supported target. The generated iOS scaffold does not implement
the native Android features.
