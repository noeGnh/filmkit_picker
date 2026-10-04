import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';

import 'media_library.dart';
import 'picked_media.dart';
import 'picker_options.dart';
import 'picker_page.dart';

/// The Instagram-style picker: a crop preview over the gallery grid.
abstract final class FilmkitPicker {
  /// Opens the picker and returns the picked media with their crop, `null` if the user closes
  /// it. [library] defaults to the device's photo library.
  static Future<List<PickedMedia>?> pick(BuildContext context, {PickerOptions options = const PickerOptions(), MediaLibrary? library}) =>
      Navigator.of(context).push<List<PickedMedia>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FilmkitPickerPage(options: options, library: library),
        ),
      );

  /// Opens the picker, then filmkit's editor on each picked media in turn (starting from the
  /// crop chosen in the picker), and returns the editor results in the order of selection;
  /// `null` if the user closes the picker. Closing the editor goes back to the previous media,
  /// or to the picker from the first one.
  ///
  /// With several media, each one is exported when the user moves on to the next (unless
  /// `editorOptions.export` is false), to a new temporary file: `editorOptions.outputPath` is
  /// only used for a single media.
  static Future<List<EditorResult>?> pickAndEdit(
    BuildContext context, {
    PickerOptions options = const PickerOptions(),
    EditorOptions editorOptions = const EditorOptions(),
    MediaLibrary? library,
  }) => Navigator.of(context).push<List<EditorResult>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FilmkitPickerPage(
        options: options,
        library: library,
        onNext: (context, media) => editInTurn(context, media, editorOptions: editorOptions, nextLabel: options.texts.next),
      ),
    ),
  );
}

/// Opens an editor; [FilmkitEditor.open] in the app, replaceable in tests.
typedef EditorOpener = Future<EditorResult?> Function(
  BuildContext context, {
  required String path,
  bool? isVideo,
  EditorOptions options,
  EditorState? initialState,
  String? title,
});

/// Edits [media] one after the other ("1/3", "2/3"…), with [nextLabel] in place of Done until
/// the last one. Closing an editor goes back to the previous media, with its edits; closing the
/// first returns `null`. Exports left behind (redone or abandoned) are deleted.
Future<List<EditorResult>?> editInTurn(
  BuildContext context,
  List<PickedMedia> media, {
  EditorOptions editorOptions = const EditorOptions(),
  String nextLabel = 'Next',
  EditorOpener open = FilmkitEditor.open,
}) async {
  if (media.isEmpty) return const [];
  final count = media.length;
  final results = List<EditorResult?>.filled(count, null);
  final options = _withAspects(editorOptions, media.first.aspect);
  var i = 0;
  while (i < count) {
    final last = i == count - 1;
    // Several exports can't share one path.
    var itemOptions = count == 1 ? options : _withoutOutputPath(options);
    if (!last) itemOptions = itemOptions.copyWith(texts: itemOptions.texts.copyWith(done: nextLabel));
    if (!context.mounted) return null;
    final result = await open(
      context,
      path: media[i].path,
      isVideo: media[i].isVideo,
      options: itemOptions,
      initialState: results[i]?.state ?? media[i].editorState,
      title: count == 1 ? null : '${i + 1}/$count',
    );
    if (result == null) {
      if (i == 0) {
        await Future.wait([for (final r in results) ?_deleteExport(r)]);
        return null;
      }
      i--;
      continue;
    }
    final previous = results[i];
    if (previous != null && previous.export?.path != result.export?.path) await _deleteExport(previous);
    results[i] = result;
    i++;
  }
  return [for (final r in results) r!];
}

Future<void>? _deleteExport(EditorResult? result) {
  final path = result?.export?.path;
  if (path == null) return null;
  return File(path).delete().then<void>((_) {}, onError: (_) {});
}

/// Adds the picker's ratio to the editor's, so that it shows as selected there.
EditorOptions _withAspects(EditorOptions options, CropAspect aspect) =>
    options.aspects.contains(aspect) ? options : options.copyWith(aspects: [aspect, ...options.aspects]);

EditorOptions _withoutOutputPath(EditorOptions o) => EditorOptions(
  looks: o.looks,
  aspects: o.aspects,
  export: o.export,
  maxDimension: o.maxDimension,
  quality: o.quality,
  keepLocation: o.keepLocation,
  minDuration: o.minDuration,
  maxDuration: o.maxDuration,
  texts: o.texts,
);
