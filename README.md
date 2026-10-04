# filmkit_picker

Instagram-style photo and video picker for Flutter: a crop preview over the gallery grid, albums, single or multiple selection, then [filmkit](https://pub.dev/packages/filmkit)'s editor on each picked media.

> **Status**: 0.1. Tested on the Android emulator and the iOS simulator.

## Pick and edit

```dart
final results = await FilmkitPicker.pickAndEdit(
  context,
  options: const PickerOptions(maxCount: 10),
);
if (results != null) {
  for (final result in results) {
    print(result.export!.path); // the exported JPEG or MP4
  }
}
```

- The top of the screen previews the selected media, playing videos muted. Drag and pinch it to choose the crop. The ratio button goes through `PickerOptions.aspects` (1:1, 4:5 and the media's own ratio by default). The ratio is shared by all the picked media; each one keeps its own crop.
- With `maxCount` above 1, a button turns on multiple selection. The media are numbered in the order they were picked. Tapping the previewed media again deselects it.
- `pickAndEdit` opens the editor on each media in turn, titled "1/3", "2/3"…, with **Next** until the last one. Closing an editor goes back to the previous media with its edits, or to the picker from the first one. The results come back in the order of selection. Pass `editorOptions:` for the editor's looks, ratios, export size, etc.
- With several media, each one is exported when the user moves on to the next, to a new temporary file (`EditorOptions.outputPath` is only used for a single media). Exports that are redone or abandoned are deleted.

## Pick only

```dart
final media = await FilmkitPicker.pick(context, options: const PickerOptions(type: PickerMediaType.photos));
for (final m in media ?? []) {
  print('${m.path}: ${m.aspect.label}, ${m.cropRect}');
  // Later: FilmkitEditor.open(context, path: m.path, initialState: m.editorState)
}
```

`PickedMedia` has:
- `path`: the file path.
- `item`: the library item. Its `source` is the photo_manager `AssetEntity`.
- `crop`, and `cropRect`, normalized as `EditSpec.crop`.
- `editorState`: opens filmkit's editor with that crop.

## Options

- `PickerOptions`:
  - `type`: all, photos or videos.
  - `maxCount`: 1 by default.
  - `aspects`: the crop ratios.
  - `columns`: of the grid.
  - `pageSize`: media loaded at a time.
  - `texts`: to translate the labels (`PickerTexts`).
- `FilmkitPickerPage` is the screen itself, for apps that handle navigation themselves. Its `onNext` callback runs when the user taps Next: return a value to close the picker with it, or `null` to keep it open.
- `MediaLibrary` is where the media come from. It is `PhotoManagerLibrary` (the device's photo library) by default. Pass `library:` to serve other media, or fake ones in tests.

## Setup

### Android

Add the permissions to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

photo_manager still applies the Kotlin Gradle plugin itself: keep `android.builtInKotlin=false` in `gradle.properties` until it migrates.

### iOS

Add `NSPhotoLibraryUsageDescription` to `Info.plist`.

## Access to the library

- On first open, the picker asks for access.
- If the user refuses, it explains why and offers a button to the system settings. It reloads when the app comes back to the foreground with access given.
- With limited access (iOS 14+, Android 14+), a banner lets the user change the selection.
- The grid follows changes to the library: media added or deleted, or a new selection.

## Development

- Dart tests: `flutter test`. The picker runs against a fake `MediaLibrary` and video player, see `test/fakes.dart`.
- Integration tests run on a device against the real photo library: `flutter test integration_test/picker_test.dart -d <device>` in `example`. Access must be given first, because a test can't answer the system prompt:
  - Android: install the app (`flutter build apk --debug`, `adb install -r build/app/outputs/flutter-apk/app-debug.apk`), then `adb shell pm grant dev.noegnh.filmkit_picker_example android.permission.READ_MEDIA_IMAGES`, and the same for `READ_MEDIA_VIDEO`. `flutter test` reinstalls the app and keeps the access, but uninstalls it at the end: repeat before each run.
  - iOS simulator: `xcrun simctl privacy <device> grant photos dev.noegnh.filmkitPickerExample`.

  The tests add two samples to the library (`filmkit_picker_sample.jpg` and `.mp4`) once, and find them again on later runs.

  On iOS simulators, `flutter test` often never sees the app start (flutter/flutter#181771). The CI runs the same tests through XCTest instead, with `example/ios/RunnerTests/RunnerTests.m`: `flutter build ios --config-only --simulator --debug integration_test/picker_test.dart`, then `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=<device>' -only-testing:RunnerTests`.
- CI (`.github/workflows/ci.yml`): format, analysis and Dart tests; Android build; the integration tests on an Android emulator and an iOS simulator (through XCTest).
