import 'dart:ui';

import 'package:filmkit/filmkit.dart';
import 'package:flutter/foundation.dart';

import 'media_library.dart';

/// A photo or video the user picked, with the crop chosen in the preview.
@immutable
class PickedMedia {
  const PickedMedia({required this.item, required this.path, required this.crop});

  final MediaItem item;

  /// The file, readable by filmkit's exporters.
  final String path;

  /// The crop chosen in the preview: its ratio (shared by all the picked media), zoom and
  /// position.
  final CropState crop;

  bool get isVideo => item.isVideo;
  CropAspect get aspect => crop.aspect;

  /// The crop, normalized to the displayed media (as `EditSpec.crop`).
  Rect get cropRect => crop.rect;

  /// Opens filmkit's editor with this crop: `FilmkitEditor.open(initialState: media.editorState)`.
  EditorState get editorState => EditorState(aspect: crop.aspect, cropZoom: crop.zoom, cropCenter: crop.center);

  @override
  String toString() => 'PickedMedia($path, $crop)';
}
