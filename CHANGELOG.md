## 0.1.0

* Instagram-style picker:
  - `FilmkitPicker.pick` returns the picked media with their crop.
  - `FilmkitPicker.pickAndEdit` then opens filmkit's editor on each media in turn ("1/3"…, Next, back to the previous media).
* Crop preview with filmkit's `CropView`: drag and pinch, a ratio button (1:1, 4:5, original by default), one ratio shared by all the media, and a crop for each.
* Grid:
  - paginated;
  - albums;
  - photos, videos or both;
  - video durations;
  - videos playing muted in the preview.
* Single or multiple selection (`maxCount`), numbered in order.
* Library access:
  - the system prompt;
  - a refusal screen with a settings button, reloading on return;
  - a banner for limited access;
  - reload on library changes.
* `MediaLibrary` interface, `PhotoManagerLibrary` by default.
* `FilmkitPickerPage` with an `onNext` callback.
* `PickerTexts` for the labels.
