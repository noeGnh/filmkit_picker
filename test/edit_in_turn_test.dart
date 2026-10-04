import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:filmkit_picker/src/filmkit_picker.dart' show editInTurn;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// An editor opening, as recorded by [FakeEditor].
typedef Opening = ({String path, bool? isVideo, EditorOptions options, EditorState? initialState, String? title});

/// Answers each editor opening with the next of [answers]: a state for Done (exported to a
/// new temporary file), `null` for closing.
class FakeEditor {
  FakeEditor(this.answers, this.dir);

  final List<EditorState?> answers;
  final Directory dir;
  final openings = <Opening>[];
  final exports = <String>[];

  Future<EditorResult?> open(
    BuildContext context, {
    required String path,
    bool? isVideo,
    EditorOptions? options,
    EditorState? initialState,
    String? title,
  }) async {
    openings.add((path: path, isVideo: isVideo, options: options!, initialState: initialState, title: title));
    final state = answers.removeAt(0);
    if (state == null) return null;
    final file = File('${dir.path}/export_${exports.length}.jpg')..writeAsStringSync('x');
    exports.add(file.path);
    return EditorResult(
      edit: const EditSpec(),
      export: ExportResult(path: file.path, width: 1, height: 1),
      state: state,
    );
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('filmkit_picker_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  PickedMedia picked(MediaItem item, {CropAspect aspect = CropAspect.square, double zoom = 1}) => PickedMedia(
    item: item,
    path: '/media/${item.id}',
    crop: CropState(mediaAspect: item.aspect, aspect: aspect, zoom: zoom),
  );

  /// Runs [editInTurn] with [editor] from a real BuildContext.
  Future<List<EditorResult>?> run(
    WidgetTester tester,
    List<PickedMedia> media,
    FakeEditor editor, {
    EditorOptions options = const EditorOptions(),
  }) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    return tester.runAsync<List<EditorResult>?>(() => editInTurn(context, media, editorOptions: options, nextLabel: 'Suivant', open: editor.open));
  }

  const looked = EditorState(look: 'Mono');

  testWidgets('a single media: no title, Done, and the options as given', (tester) async {
    final editor = FakeEditor([looked], dir);
    final results = await run(tester, [picked(photo('a'), zoom: 2)], editor, options: const EditorOptions(outputPath: '/out.jpg'));
    expect(results!.single.state, looked);
    final opening = editor.openings.single;
    expect(opening.path, '/media/a');
    expect(opening.isVideo, isFalse);
    expect(opening.title, isNull);
    expect(opening.options.texts.done, 'Done');
    expect(opening.options.outputPath, '/out.jpg');
    expect(opening.initialState!.aspect, CropAspect.square);
    expect(opening.initialState!.cropZoom, 2);
  });

  testWidgets('several media in turn: titles, Next until the last, no shared output path', (tester) async {
    final editor = FakeEditor([looked, const EditorState(look: 'Warm'), const EditorState(look: 'Cool')], dir);
    final media = [picked(photo('a')), picked(video('b')), picked(photo('c'))];
    final results = await run(tester, media, editor, options: const EditorOptions(outputPath: '/out.jpg', quality: 70));
    expect(results!.map((r) => r.state.look), ['Mono', 'Warm', 'Cool']);
    expect(editor.openings.map((o) => o.title), ['1/3', '2/3', '3/3']);
    expect(editor.openings.map((o) => o.options.texts.done), ['Suivant', 'Suivant', 'Done']);
    expect(editor.openings.map((o) => o.options.outputPath), everyElement(isNull));
    expect(editor.openings.map((o) => o.options.quality), everyElement(70));
    expect(editor.openings[1].isVideo, isTrue);
    expect(editor.exports.every((p) => File(p).existsSync()), isTrue);
  });

  testWidgets("closing goes back to the previous media with its edits, and a redone export replaces the first", (tester) async {
    final editor = FakeEditor([looked, null, const EditorState(look: 'Warm'), const EditorState(look: 'Cool')], dir);
    final results = await run(tester, [picked(photo('a')), picked(photo('b'))], editor);
    expect(editor.openings.map((o) => o.path), ['/media/a', '/media/b', '/media/a', '/media/b']);
    expect(editor.openings[2].initialState, looked, reason: 'reopened where the user left off');
    expect(results!.map((r) => r.state.look), ['Warm', 'Cool']);
    expect(File(editor.exports[0]).existsSync(), isFalse, reason: 'replaced');
    expect(results.map((r) => File(r.export!.path).existsSync()), everyElement(isTrue));
  });

  testWidgets('closing the first editor returns null and deletes the exports', (tester) async {
    final editor = FakeEditor([looked, null, null], dir);
    final results = await run(tester, [picked(photo('a')), picked(photo('b'))], editor);
    expect(results, isNull);
    expect(File(editor.exports.single).existsSync(), isFalse);
  });

  testWidgets("adds the picker's ratio to the editor's when missing", (tester) async {
    final editor = FakeEditor([looked, looked], dir);
    const wide = CropAspect('2:1', 2);
    await run(
      tester,
      [picked(photo('a'), aspect: wide)],
      editor,
      options: const EditorOptions(aspects: [CropAspect.square]),
    );
    expect(editor.openings.single.options.aspects, [wide, CropAspect.square]);
    await run(tester, [picked(photo('a'))], editor, options: const EditorOptions(aspects: [CropAspect.original, CropAspect.square]));
    expect(editor.openings.last.options.aspects, [CropAspect.original, CropAspect.square]);
  });

  testWidgets('nothing to edit', (tester) async {
    expect(await run(tester, [], FakeEditor([], dir)), isEmpty);
  });

  test('PickedMedia exposes its crop for the editor', () {
    final media = PickedMedia(
      item: photo('a'),
      path: '/a.jpg',
      crop: const CropState(mediaAspect: 1.5, aspect: CropAspect.square, zoom: 2, center: Offset(0.3, 0.6)),
    );
    expect(media.cropRect.width, closeTo(1 / 3, 1e-9));
    expect(media.editorState, const EditorState(aspect: CropAspect.square, cropZoom: 2, cropCenter: Offset(0.3, 0.6)));
  });
}
