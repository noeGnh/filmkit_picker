import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'picker_options.dart';

/// A photo or video just taken with [CameraCapture].
typedef Capture = ({String path, bool isVideo});

/// The camera tab of the picker: a preview, a shutter (or record button), the flash (photos)
/// and a button to switch between the cameras.
class CameraCapture extends StatefulWidget {
  const CameraCapture({super.key, required this.video, required this.texts, required this.onCaptured, this.maxVideoDuration, this.onOpenSettings});

  /// Records videos rather than taking photos.
  final bool video;
  final PickerTexts texts;
  final Duration? maxVideoDuration;

  /// Called with each photo taken or video recorded.
  final Future<void> Function(Capture capture) onCaptured;

  /// Opens the app's settings, to give the camera access after a refusal.
  final VoidCallback? onOpenSettings;

  @override
  State<CameraCapture> createState() => CameraCaptureState();
}

class CameraCaptureState extends State<CameraCapture> with WidgetsBindingObserver {
  List<CameraDescription>? _cameras;
  int _cameraIndex = 0;
  CameraController? _controller;

  /// Why the camera can't be shown, if it can't.
  String? _error;
  bool _denied = false;
  FlashMode _flash = FlashMode.off;
  bool _busy = false;
  bool _recording = false;
  Duration _recorded = Duration.zero;
  Timer? _recordTimer;

  /// Incremented when the controller is replaced: late initializations are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(CameraCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Photo and video controllers differ (audio).
    if (oldWidget.video != widget.video) _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _generation++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera is released while the app is in the background, as the plugin recommends.
    if (state == AppLifecycleState.inactive) {
      _close();
    } else if (state == AppLifecycleState.resumed && _controller == null && _cameras != null) {
      _open();
    }
  }

  /// Releases the camera (e.g. while the editor is open), until [resume].
  void pause() => _close();

  void resume() {
    if (_controller == null && _cameras != null && mounted) _open();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = widget.texts.noCamera);
        return;
      }
      // The back camera first.
      final back = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameras = cameras;
      _cameraIndex = back < 0 ? 0 : back;
      await _open();
    } on CameraException catch (e) {
      _fail(e);
    }
  }

  void _close() {
    _generation++;
    _recordTimer?.cancel();
    final controller = _controller;
    _controller = null;
    _recording = false;
    if (mounted) setState(() {});
    controller?.dispose();
  }

  Future<void> _open() async {
    _close();
    final generation = _generation;
    final controller = CameraController(_cameras![_cameraIndex], ResolutionPreset.high, enableAudio: widget.video);
    try {
      await controller.initialize();
      if (!widget.video) await controller.setFlashMode(_flash);
    } on CameraException catch (e) {
      await controller.dispose();
      if (generation == _generation) _fail(e);
      return;
    }
    if (!mounted || generation != _generation) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _error = null;
      _denied = false;
    });
  }

  void _fail(CameraException e) {
    if (!mounted) return;
    final denied = e.code.contains('AccessDenied') || e.code.contains('Permission');
    setState(() {
      _denied = denied;
      _error = denied ? widget.texts.cameraDenied : '${widget.texts.cameraFailed} (${e.description ?? e.code})';
    });
  }

  Future<void> _switchCamera() async {
    final cameras = _cameras;
    if (cameras == null || cameras.length < 2 || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % cameras.length;
    await _open();
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException {
      // No flash on this camera.
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      await widget.onCaptured((path: file.path, isVideo: false));
    } on CameraException catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    if (!_recording) {
      try {
        await controller.startVideoRecording();
      } on CameraException catch (e) {
        _fail(e);
        return;
      }
      setState(() {
        _recording = true;
        _recorded = Duration.zero;
      });
      const tick = Duration(milliseconds: 200);
      _recordTimer = Timer.periodic(tick, (_) {
        if (!mounted) return;
        setState(() => _recorded += tick);
        final max = widget.maxVideoDuration;
        if (max != null && _recorded >= max) _toggleRecording();
      });
      return;
    }
    _recordTimer?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final file = await controller.stopVideoRecording();
      await widget.onCaptured((path: file.path, isVideo: true));
    } on CameraException catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, key: const ValueKey('filmkit_picker.camera.error'), textAlign: TextAlign.center),
              if (_denied && widget.onOpenSettings != null) ...[
                const SizedBox(height: 16),
                FilledButton(key: const ValueKey('filmkit_picker.camera.settings'), onPressed: widget.onOpenSettings, child: Text(widget.texts.openSettings)),
              ],
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    return Column(
      children: [
        Expanded(
          child: controller == null
              ? const Center(child: CircularProgressIndicator())
              : Center(child: CameraPreview(controller, key: const ValueKey('filmkit_picker.camera.preview'))),
        ),
        _controls(controller),
      ],
    );
  }

  Widget _controls(CameraController? controller) {
    final ready = controller != null && !_busy;
    final canSwitch = (_cameras?.length ?? 0) > 1 && !_recording;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.video)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _formatRecorded(_recorded),
                key: const ValueKey('filmkit_picker.camera.timer'),
                style: TextStyle(color: _recording ? Colors.redAccent : Colors.white70, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 48,
                child: widget.video
                    ? null
                    : IconButton(
                        key: const ValueKey('filmkit_picker.camera.flash'),
                        tooltip: widget.texts.flash,
                        onPressed: ready ? _toggleFlash : null,
                        icon: Icon(switch (_flash) {
                          FlashMode.auto => Icons.flash_auto,
                          FlashMode.always => Icons.flash_on,
                          _ => Icons.flash_off,
                        }),
                      ),
              ),
              _shutter(ready),
              SizedBox(
                width: 48,
                child: IconButton(
                  key: const ValueKey('filmkit_picker.camera.switch'),
                  tooltip: widget.texts.switchCamera,
                  onPressed: canSwitch && ready ? _switchCamera : null,
                  icon: const Icon(Icons.cameraswitch_outlined),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shutter(bool ready) {
    final recording = _recording;
    return Semantics(
      button: true,
      label: widget.video ? widget.texts.record : widget.texts.takePhoto,
      child: GestureDetector(
        key: const ValueKey('filmkit_picker.camera.shutter'),
        onTap: !ready && !recording ? null : (widget.video ? _toggleRecording : _takePicture),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.all(recording ? 14 : 0),
            decoration: BoxDecoration(
              color: widget.video ? Colors.redAccent : (ready ? Colors.white : Colors.white38),
              borderRadius: BorderRadius.circular(recording ? 6 : 36),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatRecorded(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
