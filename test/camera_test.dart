import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:filmkit/filmkit.dart';
import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late List<int> photoBytes;
  late FakeFilmkit filmkit;

  setUpAll(() async => photoBytes = await pngBytes(300, 200));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filmkit_picker_camera');
    VideoPlayerPlatform.instance = FakeVideoPlayer();
    FilmkitPlatform.instance = filmkit = FakeFilmkit();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Finder key(String name) => find.byKey(ValueKey('filmkit_picker.$name'));

  /// Runs real I/O and pumps until [condition] holds.
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String reason = ''}) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(condition(), isTrue, reason: 'timed out: $reason');
  }

  /// Opens the picker with the camera; returns whether it closed, and what it popped.
  Future<({bool Function() closed, Object? Function() result})> open(
    WidgetTester tester,
    FakeCamera camera, {
    PickerOptions options = const PickerOptions(camera: true),
    FakeLibrary? library,
    PickerNextCallback? onNext,
  }) async {
    CameraPlatform.instance = camera;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var closed = false;
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () async {
              result = await Navigator.of(context).push<Object>(
                MaterialPageRoute(
                  builder: (_) => FilmkitPickerPage(
                    options: options,
                    library: library ?? FakeLibrary(items: [photo('a')]),
                    onNext: onNext,
                  ),
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return (closed: () => closed, result: () => result);
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(key('tab.$tab'));
    await tester.pump();
    await pumpUntil(tester, () => key('camera.preview').evaluate().isNotEmpty || key('camera.error').evaluate().isNotEmpty, reason: 'camera');
  }

  testWidgets('no camera tabs unless asked', (tester) async {
    await open(
      tester,
      FakeCamera(dir: dir, photo: photoBytes),
      options: const PickerOptions(),
    );
    expect(key('tab.gallery'), findsNothing);
    expect(key('tab.photo'), findsNothing);
  });

  testWidgets('only the tab matching the media type', (tester) async {
    await open(
      tester,
      FakeCamera(dir: dir, photo: photoBytes),
      options: const PickerOptions(camera: true, type: PickerMediaType.photos),
    );
    expect(key('tab.gallery'), findsOneWidget);
    expect(key('tab.photo'), findsOneWidget);
    expect(key('tab.video'), findsNothing);
  });

  testWidgets('takes a photo with the back camera and picks it with the current ratio', (tester) async {
    final camera = FakeCamera(dir: dir, photo: photoBytes);
    final picker = await open(tester, camera);
    await openTab(tester, 'photo');
    expect(camera.created, [('back', false)], reason: 'back camera first, no audio for photos');
    expect(key('next'), findsNothing, reason: 'the shutter picks at once');

    await tester.tap(key('camera.shutter'));
    await pumpUntil(tester, picker.closed, reason: 'picked');
    final picked = (picker.result()! as List<PickedMedia>).single;
    expect(picked.path, '${dir.path}/photo_1.png');
    expect(picked.isVideo, isFalse);
    expect(picked.item.aspect, closeTo(1.5, 0.05));
    expect(picked.aspect, CropAspect.square);
    expect(picked.cropRect.width, closeTo(2 / 3, 0.03));
    expect(camera.disposed, isNotEmpty, reason: 'camera released');
  });

  testWidgets('records a video, with audio, stopped at the maximum duration', (tester) async {
    final camera = FakeCamera(dir: dir, photo: photoBytes);
    final picker = await open(tester, camera, options: const PickerOptions(camera: true, maxVideoDuration: Duration(seconds: 2)));
    await openTab(tester, 'video');
    expect(camera.created.last, ('back', true));
    expect(key('camera.flash'), findsNothing);

    await tester.tap(key('camera.shutter'));
    await tester.pump();
    expect(camera.recording, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(camera.recording, isFalse, reason: 'stopped at 2 s');
    await pumpUntil(tester, picker.closed, reason: 'picked');
    final picked = (picker.result()! as List<PickedMedia>).single;
    expect(picked.isVideo, isTrue);
    expect((picked.item.width, picked.item.height), (1080, 1920));
    expect(picked.item.duration, filmkit.videoInfo.duration);
    // 9:16 under a square: the full width.
    expect(picked.cropRect.width, closeTo(1, 1e-9));
  });

  testWidgets('saves the capture to the library when asked', (tester) async {
    final library = FakeLibrary(items: [photo('a')]);
    final picker = await open(
      tester,
      FakeCamera(dir: dir, photo: photoBytes),
      library: library,
      options: const PickerOptions(camera: true, saveCaptures: true),
    );
    await openTab(tester, 'photo');
    await tester.tap(key('camera.shutter'));
    await pumpUntil(tester, picker.closed, reason: 'picked');
    final picked = (picker.result()! as List<PickedMedia>).single;
    expect(library.savedCaptures, [picked.path]);
    expect(picked.item.id, 'saved1');
    expect(picked.item.aspect, closeTo(1.5, 0.05), reason: 'the size read from the file');
  });

  testWidgets('back from the editor: the camera reopens and the capture is deleted', (tester) async {
    final camera = FakeCamera(dir: dir, photo: photoBytes);
    final calls = <String>[];
    var releasedWhileEditing = false;
    final picker = await open(
      tester,
      camera,
      onNext: (context, media) async {
        calls.add(media.single.path);
        // CameraController.dispose reaches the platform a few microtasks later.
        for (var i = 0; i < 10; i++) {
          await Future<void>.microtask(() {});
        }
        releasedWhileEditing = camera.disposed.isNotEmpty;
        return null;
      },
    );
    await openTab(tester, 'photo');
    await tester.tap(key('camera.shutter'));
    await pumpUntil(tester, () => calls.isNotEmpty, reason: 'onNext');
    await pumpUntil(tester, () => camera.created.length == 2 && key('camera.preview').evaluate().isNotEmpty, reason: 'camera reopened');
    expect(picker.closed(), isFalse);
    expect(releasedWhileEditing, isTrue, reason: 'camera released while editing');
    await pumpUntil(tester, () => !File(calls.single).existsSync(), reason: 'capture deleted');
  });

  testWidgets('switches camera and flash', (tester) async {
    final camera = FakeCamera(dir: dir, photo: photoBytes);
    await open(tester, camera);
    await openTab(tester, 'photo');
    await tester.tap(key('camera.flash'));
    await tester.pump();
    expect(camera.flashModes.last, FlashMode.auto);
    expect(find.byIcon(Icons.flash_auto), findsOneWidget);
    await tester.tap(key('camera.switch'));
    await tester.pump();
    await pumpUntil(tester, () => camera.created.length == 2, reason: 'front camera');
    expect(camera.created.last.$1, 'front');
  });

  testWidgets('a single camera: no switch', (tester) async {
    await open(tester, FakeCamera(dir: dir, photo: photoBytes, cameras: const [FakeCamera.front]));
    await openTab(tester, 'photo');
    expect(tester.widget<IconButton>(key('camera.switch')).onPressed, isNull);
  });

  testWidgets('without camera access, offers the settings', (tester) async {
    final library = FakeLibrary(items: [photo('a')]);
    await open(
      tester,
      FakeCamera(dir: dir, photo: photoBytes, initError: CameraException('CameraAccessDenied', 'denied')),
      library: library,
    );
    await openTab(tester, 'photo');
    expect(find.text('Allow access to the camera to take photos and videos.'), findsOneWidget);
    await tester.tap(key('camera.settings'));
    expect(library.settingsOpened, 1);
  });

  testWidgets('a device without camera says so', (tester) async {
    await open(tester, FakeCamera(dir: dir, photo: photoBytes, cameras: const []));
    await openTab(tester, 'photo');
    expect(find.text('No camera on this device'), findsOneWidget);
  });

  testWidgets('back to the gallery keeps its selection', (tester) async {
    final picker = await open(
      tester,
      FakeCamera(dir: dir, photo: photoBytes),
      library: FakeLibrary(items: [photo('a'), photo('b')]),
    );
    await tester.tap(key('item.b'));
    await tester.pumpAndSettle();
    await openTab(tester, 'video');
    await tester.tap(key('tab.gallery'));
    await tester.pumpAndSettle();
    expect(key('preview.b'), findsOneWidget);
    await tester.tap(key('next'));
    await tester.pumpAndSettle();
    expect((picker.result()! as List<PickedMedia>).single.item.id, 'b');
  });
}
