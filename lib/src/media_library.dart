import 'package:flutter/foundation.dart';

/// Which media the picker shows.
enum PickerMediaType { all, photos, videos }

/// The access the user gave to their photo library.
enum MediaPermission {
  /// The whole library.
  authorized,

  /// Only the photos and videos the user selected (iOS 14+, Android 14+).
  limited,
  denied,
}

/// An album (or folder, on Android) of the photo library.
@immutable
class MediaAlbum {
  const MediaAlbum({required this.id, required this.name, required this.count, this.isAll = false, this.source});

  final String id;
  final String name;

  /// Number of media of the requested type.
  final int count;

  /// The album of every photo and video ("Recents").
  final bool isAll;

  /// The library's own object (an `AssetPathEntity` with [PhotoManagerLibrary]).
  final Object? source;

  @override
  bool operator ==(Object other) => other is MediaAlbum && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaAlbum($name, $count)';
}

/// A photo or video of the library.
@immutable
class MediaItem {
  const MediaItem({required this.id, required this.isVideo, required this.width, required this.height, this.duration = Duration.zero, this.source});

  final String id;
  final bool isVideo;

  /// Displayed size (orientation applied), in pixels; 0 when unknown.
  final int width;
  final int height;

  /// Length of a video.
  final Duration duration;

  /// The library's own object (an `AssetEntity` with [PhotoManagerLibrary]).
  final Object? source;

  /// Displayed width / height; 1 when the size is unknown.
  double get aspect => width > 0 && height > 0 ? width / height : 1;

  @override
  bool operator ==(Object other) => other is MediaItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaItem($id, ${isVideo ? 'video' : 'photo'}, ${width}x$height)';
}

/// Access to the device's photos and videos. [PhotoManagerLibrary] is the default; another
/// implementation can serve other sources, or fake ones in tests.
abstract class MediaLibrary {
  /// Asks for access (with the system prompt the first time) and returns the access given.
  Future<MediaPermission> requestPermission(PickerMediaType type);

  /// The access currently given, without prompting.
  Future<MediaPermission> permission(PickerMediaType type);

  /// The albums with media of [type], the "all" album first.
  Future<List<MediaAlbum>> albums(PickerMediaType type);

  /// The [page]th page (from 0) of [size] media of [album], newest first.
  Future<List<MediaItem>> items(MediaAlbum album, {required int page, required int size});

  /// An image of [item] (a frame for videos), oriented, at least [width] × [height] keeping its
  /// aspect, or filling exactly that size when [fill] (centered).
  Future<Uint8List?> thumbnail(MediaItem item, {required int width, required int height, bool fill = false});

  /// The file of [item], downloaded first when it's in the cloud; `null` if it can't be read.
  Future<String?> file(MediaItem item);

  /// With limited access: lets the user change which media the app can see.
  Future<void> manageLimitedAccess(PickerMediaType type);

  /// Opens the app's system settings, to give access after a refusal.
  Future<void> openSettings();

  /// Fires when the library changes (media added or removed, access changed).
  Stream<void> get changes;
}
