## 0.2.0

* Camera: `PickerOptions.camera` adds Photo and Video tabs next to the gallery, only the one matching `type` for photos or videos only.
  * The flash is off, auto or on, and a button switches between the front and back cameras.
  * Recording stops by itself after `maxVideoDuration` (60 s by default).
  * A capture is picked at once, alone, with the current ratio. `pickAndEdit` opens the editor on it; closing the editor goes back to the camera and deletes the capture.
  * `saveCaptures` also adds the captures to the photo library.
  * The camera is released while editing and while the app is in the background.
* `MediaLibrary.saveCapture`, a breaking change for custom libraries.
* `PickerTexts`: the tab and camera labels.
* Depends on `camera`: on Android, the app gets the `CAMERA` and `RECORD_AUDIO` permissions (see the README to drop them).

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
