import 'dart:io';
import 'dart:ui' as ui;

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';

/// The picker against the device's real photo library. Access must be given beforehand
/// (`adb shell pm grant`, `xcrun simctl privacy grant photos`): the system prompt can't be
/// answered from a test. Two samples are added to the library once and found again by name
/// on later runs: a photo displayed at 300×200 but stored rotated (EXIF orientation 6) and a
/// 640×360, 6 s video.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const photoName = 'filmkit_picker_sample.jpg';
  const videoName = 'filmkit_picker_sample.mp4';
  final library = PhotoManagerLibrary();
  late MediaItem photo;
  late MediaItem video;

  /// Finds a sample in the library by file name, or adds it.
  Future<AssetEntity> sample(String name, String asset, Future<AssetEntity> Function(Uint8List bytes) save) async {
    // No album at all in an empty library (a new emulator).
    final all = (await PhotoManager.getAssetPathList(onlyAll: true)).firstOrNull;
    if (all != null) {
      for (final entity in await all.getAssetListRange(start: 0, end: await all.assetCountAsync)) {
        if (await entity.titleAsync == name) return entity;
      }
    }
    final data = await rootBundle.load('assets/$asset');
    return save(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  setUpAll(() async {
    expect(await library.requestPermission(PickerMediaType.all), MediaPermission.authorized, reason: 'grant the photo access before the tests');
    await sample(photoName, 'oriented_6.jpg', (bytes) => PhotoManager.editor.saveImage(bytes, filename: photoName, title: photoName));
    await sample(videoName, 'landscape.mp4', (bytes) async {
      final file = File('${Directory.systemTemp.path}/$videoName');
      await file.writeAsBytes(bytes, flush: true);
      return PhotoManager.editor.saveVideo(file, title: videoName);
    });
    // The library's own view of them.
    final all = (await library.albums(PickerMediaType.all)).first;
    final items = <MediaItem>[];
    for (var page = 0; items.length < all.count; page++) {
      items.addAll(await library.items(all, page: page, size: 200));
    }
    Future<MediaItem> named(String name) async {
      for (final item in items) {
        if (await (item.source! as AssetEntity).titleAsync == name) return item;
      }
      throw StateError('$name not found');
    }

    photo = await named(photoName);
    video = await named(videoName);
  });

  group('PhotoManagerLibrary', () {
    testWidgets('lists the "all" album first, newest first', (tester) async {
      final albums = await library.albums(PickerMediaType.all);
      expect(albums.first.isAll, isTrue);
      expect(albums.first.count, greaterThanOrEqualTo(2));
      final page = await library.items(albums.first, page: 0, size: 50);
      final dates = [for (final item in page) (item.source! as AssetEntity).createDateTime];
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i].isAfter(dates[i - 1]), isFalse, reason: 'newest first');
      }
    });

    testWidgets('filters photos and videos', (tester) async {
      final photos = (await library.albums(PickerMediaType.photos)).first;
      final videos = (await library.albums(PickerMediaType.videos)).first;
      expect(await library.items(photos, page: 0, size: 500), isNot(contains(video)));
      expect(await library.items(videos, page: 0, size: 500), everyElement(predicate<MediaItem>((i) => i.isVideo)));
    });

    testWidgets('gives displayed sizes and video durations', (tester) async {
      expect((photo.width, photo.height, photo.isVideo), (300, 200, false));
      expect((video.width, video.height, video.isVideo), (640, 360, true));
      expect(video.duration.inSeconds, inInclusiveRange(5, 6));
    });

    testWidgets('makes oriented thumbnails', (tester) async {
      Future<ui.Image> decode(Uint8List? bytes) async => (await (await ui.instantiateImageCodec(bytes!)).getNextFrame()).image;
      final fit = await decode(await library.thumbnail(photo, width: 150, height: 100));
      expect(fit.width / fit.height, closeTo(1.5, 0.05), reason: 'oriented, aspect kept');
      final frame = await decode(await library.thumbnail(video, width: 160, height: 90));
      expect(frame.width / frame.height, closeTo(16 / 9, 0.05));
      final cell = await decode(await library.thumbnail(photo, width: 128, height: 128, fill: true));
      expect(cell.width, greaterThanOrEqualTo(128));
      expect(cell.height, greaterThanOrEqualTo(128));
    });

    testWidgets('reads the files', (tester) async {
      final photoPath = await library.file(photo);
      final videoPath = await library.file(video);
      expect(File(photoPath!).lengthSync(), greaterThan(0));
      final info = await Filmkit.getVideoInfo(videoPath!);
      expect((info.width, info.height), (640, 360));
    });
  });

  group('picker', () {
    Finder key(String name) => find.byKey(ValueKey('filmkit_picker.$name'));

    Future<void> pumpFor(WidgetTester tester, Duration duration) async {
      final end = DateTime.now().add(duration);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Pumps until [finder] finds something, for at most [timeout].
    Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 60)}) async {
      final end = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    /// Opens [open] from a button, then shows the samples.
    Future<({bool Function() closed, Object? Function() result})> openPicker(WidgetTester tester, Future<Object?> Function(BuildContext) open) async {
      var closed = false;
      Object? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async {
                result = await open(context);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await pumpUntilFound(tester, key('grid'));
      return (closed: () => closed, result: () => result);
    }

    /// Taps the editor's Done (or Next) once the media is loaded: it's disabled until then.
    Future<void> tapDone(WidgetTester tester) async {
      final done = find.byKey(const ValueKey('filmkit.done'));
      final end = DateTime.now().add(const Duration(minutes: 1));
      // One editor at a time: the previous one may still be leaving.
      while ((done.evaluate().length != 1 || tester.widget<TextButton>(done).onPressed == null) && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<TextButton>(done).onPressed, isNotNull, reason: 'editor loaded');
      // The route transition.
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.tap(done);
      await tester.pump();
    }

    Future<void> tapItem(WidgetTester tester, MediaItem item) async {
      final finder = key('item.${item.id}');
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.descendant(of: key('grid'), matching: find.byType(Scrollable)),
      );
      await tester.tap(finder);
      await pumpFor(tester, const Duration(milliseconds: 500));
    }

    testWidgets('picks a photo and a video with their crop', (tester) async {
      final picker = await openPicker(tester, (context) => FilmkitPicker.pick(context, options: const PickerOptions(maxCount: 5)));
      await tester.tap(key('multiple'));
      await tester.pump();
      await tapItem(tester, photo);
      await tapItem(tester, video);
      // The video plays in the preview.
      await pumpUntilFound(tester, find.descendant(of: key('preview.${video.id}'), matching: find.byType(VideoPlayer)));

      await tester.tap(key('next'));
      await pumpUntilFound(tester, find.byKey(const ValueKey('open')));
      // The newest media, selected at start, may be another one.
      final picked = {for (final m in picker.result()! as List<PickedMedia>) m.item: m};
      expect(picked.keys, containsAll([photo, video]));
      expect(picked.values.every((m) => File(m.path).existsSync()), isTrue);
      expect(picked.values.map((m) => m.aspect), everyElement(CropAspect.square));
      expect(picked[photo]!.cropRect.width, closeTo(2 / 3, 1e-9));
      expect(picked[video]!.isVideo, isTrue);
    });

    testWidgets('edits a photo and a video in turn and exports them square', (tester) async {
      final picker = await openPicker(
        tester,
        (context) => FilmkitPicker.pickAndEdit(context, options: const PickerOptions(maxCount: 2, type: PickerMediaType.all)),
      );
      // Single selection: the photo, then multiple selection adds the video.
      await tapItem(tester, photo);
      await tester.tap(key('multiple'));
      await tester.pump();
      await tapItem(tester, video);

      await tester.tap(key('next'));
      await pumpUntilFound(tester, find.text('1/2'));
      expect(find.text('Next'), findsOneWidget, reason: 'Done reads Next before the last media');
      await tapDone(tester);
      await pumpUntilFound(tester, find.text('2/2'));
      expect(find.text('Done'), findsOneWidget);
      await tapDone(tester);
      await pumpUntilFound(tester, find.byKey(const ValueKey('open')), timeout: const Duration(minutes: 3));

      final results = picker.result()! as List<EditorResult>;
      expect(results, hasLength(2));
      expect(results.map((r) => r.aspect), everyElement(CropAspect.square));
      final photoExport = results[0].export!;
      expect((photoExport.width, photoExport.height), (200, 200));
      final videoInfo = await Filmkit.getVideoInfo(results[1].export!.path);
      expect(videoInfo.width, videoInfo.height);
      expect(videoInfo.width, 360);
    });
  });
}
