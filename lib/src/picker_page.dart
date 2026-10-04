import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:filmkit/filmkit.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'media_library.dart';
import 'media_thumbnail.dart';
import 'photo_manager_library.dart';
import 'picked_media.dart';
import 'picker_options.dart';

/// Called with the picked media when the user taps Next. Its result is popped, unless it's
/// `null`: the picker then stays open with the same selection (e.g. the user closed the editor).
typedef PickerNextCallback = Future<Object?> Function(BuildContext context, List<PickedMedia> media);

/// The picker screen, for apps that handle navigation themselves: it pops the picked media
/// (`List<PickedMedia>`), or what [onNext] returns.
class FilmkitPickerPage extends StatefulWidget {
  const FilmkitPickerPage({super.key, this.options = const PickerOptions(), this.library, this.onNext});

  final PickerOptions options;

  /// Where the media come from; the device's photo library ([PhotoManagerLibrary]) by default.
  final MediaLibrary? library;
  final PickerNextCallback? onNext;

  @override
  State<FilmkitPickerPage> createState() => _FilmkitPickerPageState();
}

class _FilmkitPickerPageState extends State<FilmkitPickerPage> with WidgetsBindingObserver {
  late final MediaLibrary _library = widget.library ?? PhotoManagerLibrary();
  PickerOptions get _options => widget.options;
  PickerTexts get _texts => _options.texts;

  /// `null` while asking.
  MediaPermission? _permission;
  StreamSubscription<void>? _changes;
  Timer? _changeDebounce;

  List<MediaAlbum> _albums = [];
  MediaAlbum? _album;
  List<MediaItem> _items = [];
  int _pages = 0;
  bool _hasMore = true;
  bool _loadingPage = false;

  /// Incremented when the album or the library changes: late pages of the previous one are
  /// dropped.
  int _generation = 0;

  bool _multiple = false;
  final List<MediaItem> _selected = [];
  MediaItem? _current;
  late CropAspect _aspect = _options.aspects.firstOrNull ?? CropAspect.original;
  final Map<String, CropState> _crops = {};
  bool _touching = false;
  bool _submitting = false;

  final _videoPreview = GlobalKey<_VideoPreviewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _changeDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system settings, where the user may have given access.
    if (state == AppLifecycleState.resumed && _permission == MediaPermission.denied) _requestPermission(prompt: false);
  }

  Future<void> _requestPermission({bool prompt = true}) async {
    final permission = prompt ? await _library.requestPermission(_options.type) : await _library.permission(_options.type);
    if (!mounted) return;
    setState(() => _permission = permission);
    if (permission == MediaPermission.denied) return;
    _changes ??= _library.changes.listen((_) {
      _changeDebounce?.cancel();
      _changeDebounce = Timer(const Duration(milliseconds: 300), _reload);
    });
    await _reload();
  }

  /// Reloads the albums and the current album, as many pages as were shown.
  Future<void> _reload() async {
    final permission = await _library.permission(_options.type);
    final albums = permission == MediaPermission.denied ? <MediaAlbum>[] : await _library.albums(_options.type);
    if (!mounted) return;
    final album = albums.where((a) => a == _album).firstOrNull ?? albums.firstOrNull;
    final generation = ++_generation;
    final items = <MediaItem>[];
    var pages = 0;
    var hasMore = album != null;
    while (hasMore && pages < math.max(_pages, 1)) {
      final page = await _library.items(album!, page: pages, size: _options.pageSize);
      items.addAll(page);
      pages++;
      hasMore = page.length == _options.pageSize;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _permission = permission;
      _albums = albums;
      _album = album;
      _items = items;
      _pages = pages;
      _hasMore = hasMore;
      _selectFirstIfNone();
    });
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || !_hasMore || _loadingPage) return;
    _loadingPage = true;
    final generation = _generation;
    try {
      final page = await _library.items(album, page: _pages, size: _options.pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page];
        _pages++;
        _hasMore = page.length == _options.pageSize;
      });
    } finally {
      _loadingPage = false;
    }
  }

  Future<void> _openAlbum(MediaAlbum album) async {
    setState(() {
      _album = album;
      _items = [];
      _pages = 0;
      _hasMore = true;
      _generation++;
    });
    await _loadMore();
    if (mounted) setState(_selectFirstIfNone);
  }

  /// As Instagram, the newest media is previewed and selected at start.
  void _selectFirstIfNone() {
    if (_current != null || _items.isEmpty) return;
    _current = _items.first;
    _selected
      ..clear()
      ..add(_items.first);
  }

  CropState _cropOf(MediaItem item) => _crops[item.id] ??= CropState(mediaAspect: item.aspect, aspect: _aspect);

  void _onTap(MediaItem item) {
    setState(() {
      if (!_multiple) {
        _current = item;
        _selected
          ..clear()
          ..add(item);
        return;
      }
      if (!_selected.contains(item)) {
        if (_selected.length >= _options.maxCount) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(_texts.maxReached.replaceAll('{count}', '${_options.maxCount}'))));
          return;
        }
        _selected.add(item);
        _current = item;
      } else if (item != _current) {
        _current = item;
      } else if (_selected.length > 1) {
        // Tapping the previewed media again deselects it; the last one can't be.
        _selected.remove(item);
        _crops.remove(item.id);
        _current = _selected.last;
      }
    });
  }

  void _toggleMultiple() {
    setState(() {
      _multiple = !_multiple;
      if (!_multiple) {
        _selected
          ..clear()
          ..addAll([?_current]);
        _crops.removeWhere((id, _) => id != _current?.id);
      }
    });
  }

  void _nextAspect() {
    final aspects = _options.aspects;
    if (aspects.isEmpty) return;
    setState(() {
      _aspect = aspects[(aspects.indexOf(_aspect) + 1) % aspects.length];
      // The ratio is shared: every crop restarts from the full frame of the new one.
      _crops.clear();
    });
  }

  Future<void> _next() async {
    setState(() => _submitting = true);
    _videoPreview.currentState?.pause();
    try {
      final picked = <PickedMedia>[];
      for (final item in _selected) {
        final path = await _library.file(item);
        if (!mounted) return;
        if (path == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_texts.loadFailed)));
          return;
        }
        picked.add(PickedMedia(item: item, path: path, crop: _cropOf(item)));
      }
      final onNext = widget.onNext;
      final result = onNext == null ? picked : await onNext(context, picked);
      if (mounted && result != null) Navigator.of(context).pop(result);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        _videoPreview.currentState?.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.white, scaffoldBackgroundColor: Colors.black),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(key: const ValueKey('filmkit_picker.close'), icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            title: _album == null ? null : _albumButton(context),
            actions: [
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton(
                  key: const ValueKey('filmkit_picker.next'),
                  style: TextButton.styleFrom(foregroundColor: Colors.lightBlueAccent),
                  onPressed: _selected.isEmpty ? null : _next,
                  child: Text(_texts.next, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          body: _body(),
        ),
      ),
    );
  }

  Widget _albumButton(BuildContext context) {
    return InkWell(
      key: const ValueKey('filmkit_picker.albums'),
      onTap: () => _showAlbums(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(_album!.name, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    );
  }

  Future<void> _showAlbums(BuildContext context) async {
    final album = await showModalBottomSheet<MediaAlbum>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            for (final album in _albums)
              ListTile(
                key: ValueKey('filmkit_picker.album.${album.id}'),
                title: Text(album.name),
                trailing: Text('${album.count}'),
                selected: album == _album,
                onTap: () => Navigator.of(context).pop(album),
              ),
          ],
        ),
      ),
    );
    if (album != null && album != _album) await _openAlbum(album);
  }

  Widget _body() {
    final permission = _permission;
    if (permission == null) return const Center(child: CircularProgressIndicator());
    if (permission == MediaPermission.denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_texts.denied, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(key: const ValueKey('filmkit_picker.settings'), onPressed: _library.openSettings, child: Text(_texts.openSettings)),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = math.min(constraints.maxWidth, constraints.maxHeight * 0.5);
        return Column(
          children: [
            SizedBox(width: constraints.maxWidth, height: previewSize, child: _preview()),
            if (permission == MediaPermission.limited) _limitedBanner(),
            Expanded(child: _grid()),
          ],
        );
      },
    );
  }

  Widget _preview() {
    final item = _current;
    if (item == null) return const SizedBox();
    final crop = _cropOf(item);
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) => setState(() => _touching = true),
            onPointerUp: (_) => setState(() => _touching = false),
            onPointerCancel: (_) => setState(() => _touching = false),
            child: CropView(
              key: ValueKey('filmkit_picker.preview.${item.id}'),
              state: crop,
              interactive: true,
              showGrid: _touching,
              onChanged: (next) => setState(() => _crops[item.id] = next),
              child: _previewMedia(item),
            ),
          ),
        ),
        if (_options.aspects.length > 1)
          Positioned(
            left: 12,
            bottom: 12,
            child: _roundButton(
              key: const ValueKey('filmkit_picker.aspect'),
              tooltip: _texts.aspect,
              onPressed: _nextAspect,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.crop, size: 18),
                  const SizedBox(width: 4),
                  Text(_aspect.label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        if (_options.maxCount > 1)
          Positioned(
            right: 12,
            bottom: 12,
            child: _roundButton(
              key: const ValueKey('filmkit_picker.multiple'),
              tooltip: _texts.selectMultiple,
              onPressed: _toggleMultiple,
              selected: _multiple,
              child: const Icon(Icons.filter_none, size: 18),
            ),
          ),
      ],
    );
  }

  Widget _roundButton({required Key key, required String tooltip, required VoidCallback onPressed, required Widget child, bool selected = false}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        key: key,
        color: selected ? Colors.lightBlueAccent : const Color(0xB3303030),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: child),
        ),
      ),
    );
  }

  Widget _previewMedia(MediaItem item) {
    // At most 1080 px on the long side, as the editor's default output.
    const long = 1080;
    final aspect = item.aspect;
    final width = aspect >= 1 ? long : (long * aspect).round();
    final height = aspect >= 1 ? (long / aspect).round() : long;
    final image = Image(
      image: MediaThumbnail(_library, item, width: width, height: height),
      fit: BoxFit.fill,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF202020)),
    );
    if (!item.isVideo) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        _VideoPreview(key: _videoPreview, library: _library, item: item),
      ],
    );
  }

  Widget _limitedBanner() {
    return Container(
      key: const ValueKey('filmkit_picker.limited'),
      color: const Color(0xFF1C1C1C),
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Expanded(child: Text(_texts.limitedAccess, style: const TextStyle(fontSize: 13))),
          TextButton(
            key: const ValueKey('filmkit_picker.manage'),
            onPressed: () async {
              await _library.manageLimitedAccess(_options.type);
              await _reload();
            },
            child: Text(_texts.manage),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    if (_items.isEmpty) {
      return Center(child: _hasMore && _album != null ? const CircularProgressIndicator() : Text(_texts.empty));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _options.columns;
        // Thumbnail size in pixels, rounded up so that close sizes share the image cache.
        final cell = constraints.maxWidth / columns * MediaQuery.devicePixelRatioOf(context);
        final px = (cell / 64).ceil() * 64;
        return GridView.builder(
          key: const ValueKey('filmkit_picker.grid'),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 1, crossAxisSpacing: 1),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            if (index >= _items.length - _options.pageSize ~/ 2) scheduleMicrotask(_loadMore);
            return _cell(_items[index], px);
          },
        );
      },
    );
  }

  Widget _cell(MediaItem item, int px) {
    final index = _selected.indexOf(item);
    return GestureDetector(
      key: ValueKey('filmkit_picker.item.${item.id}'),
      onTap: () => _onTap(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: MediaThumbnail(_library, item, width: px, height: px, fill: true),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF202020)),
          ),
          if (item == _current) const ColoredBox(color: Color(0x66FFFFFF)),
          if (item.isVideo)
            Positioned(
              right: 4,
              bottom: 4,
              child: Text(
                formatDuration(item.duration),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white, shadows: [Shadow(blurRadius: 3)]),
              ),
            ),
          if (_multiple)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index >= 0 ? Colors.lightBlueAccent : const Color(0x33000000),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: index >= 0
                    ? Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// "0:07", "1:05:03".
String formatDuration(Duration d) {
  final s = d.inSeconds;
  final m = (s ~/ 60) % 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// Plays a video muted and looping over its thumbnail, once its file is ready.
class _VideoPreview extends StatefulWidget {
  const _VideoPreview({super.key, required this.library, required this.item});

  final MediaLibrary library;
  final MediaItem item;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _controller?.dispose();
      _controller = null;
      _load();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  Future<void> _load() async {
    final item = widget.item;
    final path = await widget.library.file(item);
    if (path == null || !mounted || widget.item != item) return;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
    } catch (_) {
      // The thumbnail stays.
      await controller.dispose();
      return;
    }
    if (!mounted || widget.item != item) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    if (!_paused) await controller.play();
  }

  void pause() {
    _paused = true;
    _controller?.pause();
  }

  void play() {
    _paused = false;
    _controller?.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox();
    return VideoPlayer(controller);
  }
}
