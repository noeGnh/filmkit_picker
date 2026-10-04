import 'package:filmkit/filmkit.dart';
import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith replaces only the given options and texts', () {
    const options = PickerOptions(maxCount: 5, texts: PickerTexts(next: 'Suivant'));
    final copy = options.copyWith(
      type: PickerMediaType.videos,
      columns: 3,
      texts: options.texts.copyWith(empty: 'Rien'),
    );
    expect(copy.type, PickerMediaType.videos);
    expect(copy.maxCount, 5);
    expect(copy.columns, 3);
    expect(copy.pageSize, 80);
    expect(copy.aspects, [CropAspect.square, CropAspect.portrait, CropAspect.original]);
    expect(copy.texts.next, 'Suivant');
    expect(copy.texts.empty, 'Rien');
    expect(copy.texts.manage, 'Manage');
  });

  test('media and albums are equal by id', () {
    expect(const MediaItem(id: 'a', isVideo: false, width: 1, height: 1), const MediaItem(id: 'a', isVideo: false, width: 2, height: 2));
    expect(const MediaItem(id: 'a', isVideo: false, width: 0, height: 0).aspect, 1);
    expect(const MediaAlbum(id: 'x', name: 'A', count: 1), const MediaAlbum(id: 'x', name: 'B', count: 2));
  });
}
