import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import 'media_library.dart';

/// The device's photo library, through photo_manager.
class PhotoManagerLibrary implements MediaLibrary {
  PhotoManagerLibrary();

  static RequestType _requestType(PickerMediaType type) => switch (type) {
    PickerMediaType.all => RequestType.common,
    PickerMediaType.photos => RequestType.image,
    PickerMediaType.videos => RequestType.video,
  };

  static final _newestFirst = FilterOptionGroup(orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)]);

  static PermissionRequestOption _permissionOption(PickerMediaType type) => PermissionRequestOption(
    androidPermission: AndroidPermission(type: _requestType(type), mediaLocation: false),
  );

  @override
  Future<MediaPermission> requestPermission(PickerMediaType type) async =>
      _permission(await PhotoManager.requestPermissionExtend(requestOption: _permissionOption(type)));

  @override
  Future<MediaPermission> permission(PickerMediaType type) async => _permission(await PhotoManager.getPermissionState(requestOption: _permissionOption(type)));

  static MediaPermission _permission(PermissionState state) {
    return switch (state) {
      PermissionState.authorized => MediaPermission.authorized,
      PermissionState.limited => MediaPermission.limited,
      _ => MediaPermission.denied,
    };
  }

  @override
  Future<List<MediaAlbum>> albums(PickerMediaType type) async {
    final paths = await PhotoManager.getAssetPathList(type: _requestType(type), filterOption: _newestFirst);
    final albums = <MediaAlbum>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0 && !path.isAll) continue;
      albums.add(MediaAlbum(id: path.id, name: path.name, count: count, isAll: path.isAll, source: path));
    }
    albums.sort((a, b) => a.isAll == b.isAll ? 0 : (a.isAll ? -1 : 1));
    return albums;
  }

  @override
  Future<List<MediaItem>> items(MediaAlbum album, {required int page, required int size}) async {
    final assets = await (album.source! as AssetPathEntity).getAssetListPaged(page: page, size: size);
    return [
      for (final asset in assets)
        if (asset.type == AssetType.image || asset.type == AssetType.video)
          MediaItem(
            id: asset.id,
            isVideo: asset.type == AssetType.video,
            width: asset.orientatedWidth,
            height: asset.orientatedHeight,
            duration: asset.videoDuration,
            source: asset,
          ),
    ];
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item, {required int width, required int height, bool fill = false}) {
    final asset = item.source! as AssetEntity;
    final size = ThumbnailSize(width, height);
    // Android keeps the aspect (at least the requested size); the grid covers its cells anyway.
    final option = Platform.isIOS
        ? ThumbnailOption.ios(
            size: size,
            resizeContentMode: fill ? ResizeContentMode.fill : ResizeContentMode.fit,
            // The grid takes the fast, maybe degraded, image; the preview waits for the real one.
            deliveryMode: fill ? DeliveryMode.opportunistic : DeliveryMode.highQualityFormat,
            quality: 90,
          )
        : ThumbnailOption(size: size, quality: 90);
    return asset.thumbnailDataWithOption(option);
  }

  @override
  Future<String?> file(MediaItem item) async => (await (item.source! as AssetEntity).file)?.path;

  @override
  Future<void> manageLimitedAccess(PickerMediaType type) => PhotoManager.presentLimited(type: _requestType(type));

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Stream<void> get changes => _changes.stream;

  late final _changes = StreamController<void>.broadcast(onListen: _startNotify, onCancel: _stopNotify);

  void _onChange(MethodCall _) => _changes.add(null);

  Future<void> _startNotify() async {
    PhotoManager.addChangeCallback(_onChange);
    await PhotoManager.startChangeNotify();
  }

  Future<void> _stopNotify() async {
    PhotoManager.removeChangeCallback(_onChange);
    await PhotoManager.stopChangeNotify();
  }
}
