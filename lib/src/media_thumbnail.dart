import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'media_library.dart';

/// An image of a library item from [MediaLibrary.thumbnail], cached by Flutter's image cache.
@immutable
class MediaThumbnail extends ImageProvider<MediaThumbnail> {
  const MediaThumbnail(this.library, this.item, {required this.width, required this.height, this.fill = false});

  final MediaLibrary library;
  final MediaItem item;
  final int width;
  final int height;
  final bool fill;

  @override
  Future<MediaThumbnail> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(MediaThumbnail key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(
    _load(decode),
    informationCollector: () => [DiagnosticsProperty('Media', item)],
  );

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await library.thumbnail(item, width: width, height: height, fill: fill);
    if (bytes == null || bytes.isEmpty) {
      // Evicted so that a later attempt retries (e.g. a cloud item once downloaded).
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      throw StateError('No thumbnail for $item');
    }
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    final frame = await codec.getNextFrame();
    codec.dispose();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaThumbnail && other.library == library && other.item == item && other.width == width && other.height == height && other.fill == fill;

  @override
  int get hashCode => Object.hash(library, item, width, height, fill);

  @override
  String toString() => 'MediaThumbnail(${item.id}, ${width}x$height${fill ? ', fill' : ''})';
}
