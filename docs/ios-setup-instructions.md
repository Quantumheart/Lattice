# iOS Platform Setup for Lattice

Hi! I need you to generate the iOS project files for our Flutter app so we can ship to the App Store. This should take ~10 minutes.

## Prerequisites

- A Mac (any Mac — Intel or Apple Silicon)
- Xcode installed from the Mac App Store
- Flutter SDK installed — [flutter.dev/docs/get-started/install/macos](https://flutter.dev/docs/get-started/install/macos)

## Steps

### 1. Clone the repo and switch to the release branch

```bash
git clone https://github.com/Quantumheart/Lattice.git
cd Lattice
git checkout claude/ios-app-store-release-z2PlK
```

### 2. Verify Flutter can see Xcode

```bash
flutter doctor
```

Make sure the "Xcode" line shows a green checkmark. If it doesn't, run:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 3. Generate the iOS project files

```bash
flutter create --platforms=ios .
```

This adds an `ios/` folder. It won't touch any existing code.

### 4. Install the iOS native dependencies

```bash
cd ios
pod install
cd ..
```

### 5. Verify it builds

```bash
flutter build ios --no-codesign
```

The `--no-codesign` flag skips signing since we'll handle that in CI. If this succeeds, you're done.

### 6. Commit and push

```bash
git add ios/
git commit -m "feat: add iOS platform support"
git push -u origin claude/ios-app-store-release-z2PlK
```

That's it! Don't worry about signing certificates, provisioning profiles, or App Store settings — those will be handled in CI after you push.
