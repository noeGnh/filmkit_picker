import 'package:filmkit/filmkit.dart';
import 'package:flutter/foundation.dart';

import 'media_library.dart';

/// The picker's labels, in English by default.
@immutable
class PickerTexts {
  const PickerTexts({
    this.next = 'Next',
    this.selectMultiple = 'Select multiple',
    this.aspect = 'Crop ratio',
    this.maxReached = 'You can select up to {count} items',
    this.limitedAccess = "You've given access to a selection of photos and videos.",
    this.manage = 'Manage',
    this.denied = 'Allow access to your photos and videos to pick them.',
    this.openSettings = 'Open settings',
    this.empty = 'No photos or videos',
    this.loadFailed = "Can't open this file",
  });

  final String next;

  /// Tooltip of the multiple selection button.
  final String selectMultiple;

  /// Tooltip of the crop ratio button.
  final String aspect;

  /// Shown when the user taps one more media than `PickerOptions.maxCount`; `{count}` is
  /// replaced by it.
  final String maxReached;
  final String limitedAccess;
  final String manage;
  final String denied;
  final String openSettings;
  final String empty;

  /// Shown when a selected file can't be read (e.g. a cloud file without network).
  final String loadFailed;

  PickerTexts copyWith({
    String? next,
    String? selectMultiple,
    String? aspect,
    String? maxReached,
    String? limitedAccess,
    String? manage,
    String? denied,
    String? openSettings,
    String? empty,
    String? loadFailed,
  }) => PickerTexts(
    next: next ?? this.next,
    selectMultiple: selectMultiple ?? this.selectMultiple,
    aspect: aspect ?? this.aspect,
    maxReached: maxReached ?? this.maxReached,
    limitedAccess: limitedAccess ?? this.limitedAccess,
    manage: manage ?? this.manage,
    denied: denied ?? this.denied,
    openSettings: openSettings ?? this.openSettings,
    empty: empty ?? this.empty,
    loadFailed: loadFailed ?? this.loadFailed,
  );
}

@immutable
class PickerOptions {
  const PickerOptions({
    this.type = PickerMediaType.all,
    this.maxCount = 1,
    this.aspects = defaultAspects,
    this.columns = 4,
    this.pageSize = 80,
    this.texts = const PickerTexts(),
  }) : assert(maxCount >= 1),
       assert(columns >= 1),
       assert(pageSize >= 1);

  /// As Instagram: square by default, the button switches to portrait or the media's own ratio.
  static const defaultAspects = [CropAspect.square, CropAspect.portrait, CropAspect.original];

  final PickerMediaType type;

  /// How many media can be selected; above 1, a button turns on the multiple selection.
  final int maxCount;

  /// The crop ratios the preview's ratio button goes through, the first one selected at start
  /// (the media's own ratio when empty). Several media share the ratio, as on Instagram.
  final List<CropAspect> aspects;

  /// Columns of the grid.
  final int columns;

  /// Media loaded at a time while scrolling.
  final int pageSize;

  final PickerTexts texts;

  PickerOptions copyWith({PickerMediaType? type, int? maxCount, List<CropAspect>? aspects, int? columns, int? pageSize, PickerTexts? texts}) => PickerOptions(
    type: type ?? this.type,
    maxCount: maxCount ?? this.maxCount,
    aspects: aspects ?? this.aspects,
    columns: columns ?? this.columns,
    pageSize: pageSize ?? this.pageSize,
    texts: texts ?? this.texts,
  );
}
