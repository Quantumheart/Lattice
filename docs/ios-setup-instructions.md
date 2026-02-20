# iOS Platform Setup for Lattice

Generate the iOS project files for our Flutter app so we can ship to the App Store.

## Prerequisites

This must be run on a Mac with:
- Xcode installed (install from the App Store if missing)
- Flutter SDK installed and on PATH
- Both `flutter doctor` checks for "Flutter" and "Xcode" passing

If Xcode was just installed, run these first:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

## Task

From the root of the Lattice repository, run these steps in order:

1. **Generate the iOS project files**

```bash
flutter create --platforms=ios .
```

This adds an `ios/` folder. It won't touch any existing Dart code.

2. **Install the iOS native dependencies**

```bash
cd ios && pod install && cd ..
```

3. **Verify it builds**

```bash
flutter build ios --no-codesign
```

The `--no-codesign` flag skips signing since that's handled in CI. If this command fails, check `flutter doctor` output and resolve any issues before retrying.

4. **Commit and push**

```bash
git checkout -b feature/ios_support
git add ios/
git commit -m "feat: add iOS platform support"
git push -u origin feature/ios_support
```

Don't worry about signing certificates, provisioning profiles, or App Store settings — those will be handled in CI after you push.
