# iOS Platform Setup for Lattice

Hi! I need you to generate the iOS project files for our Flutter app so we can ship to the App Store. This should take ~15 minutes.

## Prerequisites

- A Mac (any Mac — Intel or Apple Silicon)

## Steps

### 1. Install Xcode

1. Open the **App Store** on your Mac
2. Search for **Xcode**
3. Click **Get** / **Install** (it's free, but ~12 GB so it may take a while)
4. Once installed, open Xcode at least once and accept the license agreement
5. Then open Terminal and run these two commands to finish setup:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 2. Install Flutter

Follow the official guide for macOS: [docs.flutter.dev/get-started/install/macos](https://docs.flutter.dev/get-started/install/macos)

Once installed, verify everything is working:

```bash
flutter doctor
```

Make sure both the "Flutter" and "Xcode" lines show green checkmarks before continuing.

### 3. Clone the repo and create the branch

```bash
git clone https://github.com/Quantumheart/Lattice.git
cd Lattice
git checkout -b feature/ios_support
```

### 4. Generate the iOS project files

```bash
flutter create --platforms=ios .
```

This adds an `ios/` folder. It won't touch any existing code.

### 5. Install the iOS native dependencies

```bash
cd ios
pod install
cd ..
```

### 6. Verify it builds

```bash
flutter build ios --no-codesign
```

The `--no-codesign` flag skips signing since we'll handle that in CI. If this succeeds, you're done.

### 7. Commit and push

```bash
git add ios/
git commit -m "feat: add iOS platform support"
git push -u origin feature/ios_support
```

That's it! Don't worry about signing certificates, provisioning profiles, or App Store settings — those will be handled in CI after you push.
