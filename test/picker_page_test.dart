import 'package:filmkit/filmkit.dart';
import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:filmkit_picker/src/picker_page.dart' show formatDuration;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fakes.dart';

void main() {
  late FakeVideoPlayer player;

  setUp(() => VideoPlayerPlatform.instance = player = FakeVideoPlayer());

  Finder key(String name) => find.byKey(ValueKey('filmkit_picker.$name'));
  Finder item(String id) => key('item.$id');

  /// Opens the picker; returns whether it closed, and what it popped.
  Future<({bool Function() closed, Object? Function() result})> open(
    WidgetTester tester,
    MediaLibrary library, {
    PickerOptions options = const PickerOptions(),
    PickerNextCallback? onNext,
  }) async {
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
                  builder: (_) => FilmkitPickerPage(options: options, library: library, onNext: onNext),
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<List<PickedMedia>> next(WidgetTester tester, bool Function() closed, Object? Function() result) async {
    await tap(tester, key('next'));
    expect(closed(), isTrue);
    return result()! as List<PickedMedia>;
  }

  /// The number badge of [id] in multiple selection, `null` when not selected.
  String? badge(WidgetTester tester, String id) {
    final texts = find.descendant(of: item(id), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data!);
    return texts.where((t) => int.tryParse(t) != null).firstOrNull;
  }

  final items = [photo('a'), photo('b', width: 200, height: 300), video('c'), photo('d')];

  testWidgets('previews and selects the newest media, and returns it with a square crop', (tester) async {
    final library = FakeLibrary(items: items);
    final picker = await open(tester, library);
    expect(library.permissionRequests, 1);
    expect(find.text('Recents'), findsOneWidget);
    expect(key('preview.a'), findsOneWidget);
    expect(key('multiple'), findsNothing, reason: 'maxCount 1');

    final picked = await next(tester, picker.closed, picker.result);
    expect(picked, hasLength(1));
    expect(picked.single.path, '/media/a.jpg');
    expect(picked.single.aspect, CropAspect.square);
    // A square in a 3:2 photo: two thirds of the width, centered.
    expect(picked.single.cropRect.width, closeTo(2 / 3, 1e-9));
    expect(picked.single.cropRect.center.dx, closeTo(0.5, 1e-9));
    expect(picked.single.editorState.aspect, CropAspect.square);
  });

  testWidgets('a tap replaces the selection in single selection', (tester) async {
    final picker = await open(tester, FakeLibrary(items: items));
    await tap(tester, item('b'));
    expect(key('preview.b'), findsOneWidget);
    final picked = await next(tester, picker.closed, picker.result);
    expect(picked.map((m) => m.item.id), ['b']);
    // A square in a 2:3 photo: the full width.
    expect(picked.single.cropRect.width, closeTo(1, 1e-9));
  });

  testWidgets('multiple selection numbers the media in order and keeps their own crop', (tester) async {
    final picker = await open(tester, FakeLibrary(items: items), options: const PickerOptions(maxCount: 3));
    await tap(tester, key('multiple'));
    expect(badge(tester, 'a'), '1');
    await tap(tester, item('c'));
    await tap(tester, item('b'));
    expect([badge(tester, 'a'), badge(tester, 'b'), badge(tester, 'c')], ['1', '3', '2']);

    // Pans the previewed media (b): only its crop moves.
    await tester.drag(key('preview.b'), const Offset(0, 200));
    await tester.pumpAndSettle();

    // A fourth is refused.
    await tap(tester, item('d'));
    expect(badge(tester, 'd'), isNull);
    expect(find.text('You can select up to 3 items'), findsOneWidget);

    final picked = await next(tester, picker.closed, picker.result);
    expect(picked.map((m) => m.item.id), ['a', 'c', 'b']);
    expect(picked.map((m) => m.aspect), everyElement(CropAspect.square));
    expect(picked[0].cropRect.center.dx, closeTo(0.5, 1e-9));
    expect(picked[0].cropRect.center.dy, closeTo(0.5, 1e-9));
    expect(picked[2].cropRect.center.dy, lessThan(0.5), reason: 'dragging down shows the top');
    expect(picked[1].path, '/media/c.mp4');
    expect(picked[1].isVideo, isTrue);
  });

  testWidgets('tapping the previewed media deselects it, except the last one', (tester) async {
    await open(tester, FakeLibrary(items: items), options: const PickerOptions(maxCount: 5));
    await tap(tester, key('multiple'));
    await tap(tester, item('b'));
    await tap(tester, item('a')); // previews a, still selected
    expect(key('preview.a'), findsOneWidget);
    expect(badge(tester, 'a'), '1');
    await tap(tester, item('a')); // deselects a, previews the last one
    expect(badge(tester, 'a'), isNull);
    expect(badge(tester, 'b'), '1');
    expect(key('preview.b'), findsOneWidget);
    await tap(tester, item('b'));
    expect(badge(tester, 'b'), '1', reason: 'the last one stays');
  });

  testWidgets('turning multiple selection off keeps the previewed media', (tester) async {
    final picker = await open(tester, FakeLibrary(items: items), options: const PickerOptions(maxCount: 5));
    await tap(tester, key('multiple'));
    await tap(tester, item('b'));
    await tap(tester, item('d'));
    await tap(tester, key('multiple'));
    expect(badge(tester, 'b'), isNull);
    final picked = await next(tester, picker.closed, picker.result);
    expect(picked.map((m) => m.item.id), ['d']);
  });

  testWidgets('the ratio button goes through the ratios, shared by all the media', (tester) async {
    final picker = await open(tester, FakeLibrary(items: items), options: const PickerOptions(maxCount: 2));
    await tap(tester, key('multiple'));
    await tap(tester, item('b'));
    expect(find.descendant(of: key('aspect'), matching: find.text('1:1')), findsOneWidget);
    await tap(tester, key('aspect'));
    expect(find.descendant(of: key('aspect'), matching: find.text('4:5')), findsOneWidget);
    await tap(tester, key('aspect'));
    await tap(tester, key('aspect'));
    expect(
      find.descendant(of: key('aspect'), matching: find.text('1:1')),
      findsOneWidget,
      reason: 'back to the first',
    );
    await tap(tester, key('aspect'));
    final picked = await next(tester, picker.closed, picker.result);
    expect(picked.map((m) => m.aspect), everyElement(CropAspect.portrait));
    // 4:5 in a 3:2 photo: the full height.
    expect(picked[0].cropRect.height, closeTo(1, 1e-9));
  });

  testWidgets('a single ratio hides the button', (tester) async {
    final picker = await open(
      tester,
      FakeLibrary(items: items),
      options: const PickerOptions(aspects: [CropAspect.original]),
    );
    expect(key('aspect'), findsNothing);
    final picked = await next(tester, picker.closed, picker.result);
    expect(picked.single.crop.isFull, isTrue);
  });

  testWidgets('a video shows its duration and plays in the preview', (tester) async {
    await open(tester, FakeLibrary(items: items));
    expect(find.descendant(of: item('c'), matching: find.text('0:07')), findsOneWidget);
    expect(player.opened, isEmpty);
    await tap(tester, item('c'));
    expect(player.opened.single, endsWith('/media/c.mp4'));
    expect(player.playing[0], isTrue);
    await tap(tester, item('a'));
    expect(player.playing, isNot(contains(1)), reason: 'no player for photos');
  });

  testWidgets('loads more pages while scrolling', (tester) async {
    final library = FakeLibrary(items: [for (var i = 0; i < 190; i++) photo('p$i')]);
    await open(tester, library, options: const PickerOptions(pageSize: 40));
    expect(library.pageCalls.first, ('all', 0));
    for (var i = 0; i < 20 && !library.pageCalls.contains(('all', 4)); i++) {
      await tester.drag(key('grid'), const Offset(0, -1500));
      await tester.pumpAndSettle();
    }
    expect(library.pageCalls, contains(('all', 4)));
    await tester.drag(key('grid'), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(item('p189'), findsOneWidget);
    expect(library.pageCalls, isNot(contains(('all', 5))), reason: 'the last page was short');
  });

  testWidgets('switches albums and keeps the selection', (tester) async {
    const all = MediaAlbum(id: 'all', name: 'Recents', count: 0, isAll: true);
    const camera = MediaAlbum(id: 'camera', name: 'Camera', count: 0);
    final library = FakeLibrary(
      albums: {
        all: items,
        camera: [photo('x'), photo('y')],
      },
    );
    final picker = await open(tester, library, options: const PickerOptions(maxCount: 3));
    await tap(tester, key('multiple'));
    await tap(tester, key('albums'));
    expect(find.text('Camera'), findsOneWidget);
    await tap(tester, key('album.camera'));
    expect(item('x'), findsOneWidget);
    expect(item('a'), findsNothing);
    await tap(tester, item('y'));
    final picked = await next(tester, picker.closed, picker.result);
    expect(picked.map((m) => m.item.id), ['a', 'y']);
  });

  testWidgets('reloads when the library changes', (tester) async {
    final library = FakeLibrary(items: [...items]);
    await open(tester, library);
    library.albumItems.values.first.insert(0, photo('new'));
    library.notifyChange();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(item('new'), findsOneWidget);
    expect(key('preview.a'), findsOneWidget, reason: 'the preview stays');
  });

  testWidgets('without access, offers the settings and reloads once given', (tester) async {
    final library = FakeLibrary(items: items, access: MediaPermission.denied);
    await open(tester, library);
    expect(find.text('Allow access to your photos and videos to pick them.'), findsOneWidget);
    await tap(tester, key('settings'));
    expect(library.settingsOpened, 1);

    library.access = MediaPermission.authorized;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(item('a'), findsOneWidget);
    expect(library.permissionRequests, 1, reason: 'no second prompt');
  });

  testWidgets('with limited access, lets the user manage the selection', (tester) async {
    final library = FakeLibrary(items: [...items], access: MediaPermission.limited);
    await open(tester, library);
    expect(key('limited'), findsOneWidget);
    library.albumItems.values.first.add(photo('e'));
    await tap(tester, key('manage'));
    expect(library.limitedManaged, 1);
    expect(item('e'), findsOneWidget);
  });

  testWidgets('an empty library says so and disables Next', (tester) async {
    await open(tester, FakeLibrary(items: []));
    expect(find.text('No photos or videos'), findsOneWidget);
    expect(tester.widget<TextButton>(key('next')).onPressed, isNull);
  });

  testWidgets('a file that cannot be read keeps the picker open', (tester) async {
    final library = FakeLibrary(items: items)..unreadable.add('a');
    final picker = await open(tester, library);
    await tap(tester, key('next'));
    expect(picker.closed(), isFalse);
    expect(find.text("Can't open this file"), findsOneWidget);
  });

  testWidgets('closing returns null', (tester) async {
    final picker = await open(tester, FakeLibrary(items: items));
    await tap(tester, key('close'));
    expect(picker.closed(), isTrue);
    expect(picker.result(), isNull);
  });

  testWidgets('onNext: the picker stays open while it returns null, and pops its result', (tester) async {
    final calls = <List<String>>[];
    Object? answer;
    final picker = await open(
      tester,
      FakeLibrary(items: items),
      onNext: (context, media) async {
        calls.add([for (final m in media) m.item.id]);
        return answer;
      },
    );
    await tap(tester, key('next'));
    expect(picker.closed(), isFalse);
    expect(key('next'), findsOneWidget, reason: 'Next enabled again');
    answer = 'edited';
    await tap(tester, key('next'));
    expect(calls, [
      ['a'],
      ['a'],
    ]);
    expect(picker.result(), 'edited');
  });

  test('formats durations', () {
    expect(formatDuration(const Duration(seconds: 7)), '0:07');
    expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 5, seconds: 3)), '1:05:03');
  });
}
