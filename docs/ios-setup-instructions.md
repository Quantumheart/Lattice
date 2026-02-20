# iOS Platform Setup for Lattice

Generate the iOS project files for our Flutter app so we can ship to the App Store.

## Environment Setup

This must be run on a Mac. Before starting the task, ensure the following tools are installed.

### 1. Install Xcode

Check if Xcode is installed:

```bash
xcode-select -p
```

If that fails, Xcode must be installed from the Mac App Store manually — there is no CLI-only way to install it. Once installed, run:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 2. Install Homebrew (if missing)

```bash
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Install Flutter

```bash
brew install --cask flutter
```

On Apple Silicon Macs, also install Rosetta 2:

```bash
sudo softwareupdate --install-rosetta --agree-to-license
```

### 4. Install CocoaPods

```bash
brew install cocoapods
```

### 5. Verify the environment

```bash
flutter doctor
```

Both the "Flutter" and "Xcode" lines must show green checkmarks before continuing. Resolve any issues `flutter doctor` reports before proceeding.

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
