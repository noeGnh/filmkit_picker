import 'dart:async';
import 'dart:typed_data';

import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A 1×1 PNG, served as every thumbnail.
final onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// A photo (3:2 landscape unless sized otherwise) or a video, with the id [id].
MediaItem photo(String id, {int width = 300, int height = 200}) => MediaItem(id: id, isVideo: false, width: width, height: height);
MediaItem video(String id, {Duration duration = const Duration(seconds: 7)}) => MediaItem(id: id, isVideo: true, width: 1920, height: 1080, duration: duration);

/// A library of albums held in memory, recording the calls.
class FakeLibrary implements MediaLibrary {
  FakeLibrary({Map<MediaAlbum, List<MediaItem>>? albums, List<MediaItem>? items, this.access = MediaPermission.authorized})
    : albumItems = albums ?? {const MediaAlbum(id: 'all', name: 'Recents', count: 0, isAll: true): items ?? []};

  /// Each album's media, newest first.
  final Map<MediaAlbum, List<MediaItem>> albumItems;
  MediaPermission access;

  /// Items whose file can't be read.
  final unreadable = <String>{};

  int permissionRequests = 0;
  int limitedManaged = 0;
  int settingsOpened = 0;
  final pageCalls = <(String, int)>[];
  final _changes = StreamController<void>.broadcast();

  /// Simulates a change in the photo library.
  void notifyChange() => _changes.add(null);

  @override
  Future<MediaPermission> requestPermission(PickerMediaType type) async {
    permissionRequests++;
    return access;
  }

  @override
  Future<MediaPermission> permission(PickerMediaType type) async => access;

  @override
  Future<List<MediaAlbum>> albums(PickerMediaType type) async => [
    for (final MapEntry(key: album, value: items) in albumItems.entries) MediaAlbum(id: album.id, name: album.name, count: items.length, isAll: album.isAll),
  ];

  @override
  Future<List<MediaItem>> items(MediaAlbum album, {required int page, required int size}) async {
    pageCalls.add((album.id, page));
    final items = albumItems.entries.firstWhere((e) => e.key.id == album.id).value;
    return items.skip(page * size).take(size).toList();
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item, {required int width, required int height, bool fill = false}) async => onePixelPng;

  @override
  Future<String?> file(MediaItem item) async => unreadable.contains(item.id) ? null : '/media/${item.id}.${item.isVideo ? 'mp4' : 'jpg'}';

  @override
  Future<void> manageLimitedAccess(PickerMediaType type) async => limitedManaged++;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Stream<void> get changes => _changes.stream;
}

/// A video player that initializes at once, recording which files were opened.
class FakeVideoPlayer extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  final opened = <String?>[];
  final playing = <int, bool>{};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _create(dataSource.uri);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _create(options.dataSource.uri);

  int _create(String? uri) {
    opened.add(uri);
    final id = _next++;
    _events[id] = StreamController<VideoEvent>(
      onListen: () => _events[id]!.add(VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(seconds: 7), size: const Size(1920, 1080))),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events.remove(playerId)?.close();

  @override
  Future<void> play(int playerId) async => playing[playerId] = true;

  @override
  Future<void> pause(int playerId) async => playing[playerId] = false;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}
