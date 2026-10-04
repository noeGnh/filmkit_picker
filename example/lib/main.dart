import 'dart:io';

import 'package:filmkit/filmkit.dart';
import 'package:filmkit_picker/filmkit_picker.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(title: 'filmkit_picker', home: HomePage()));

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PickerMediaType _type = PickerMediaType.all;
  bool _multiple = true;
  List<PickedMedia> _picked = [];
  List<EditorResult> _edited = [];

  PickerOptions get _options => PickerOptions(type: _type, maxCount: _multiple ? 10 : 1);

  Future<void> _pick() async {
    final picked = await FilmkitPicker.pick(context, options: _options);
    if (picked == null) return;
    setState(() {
      _picked = picked;
      _edited = [];
    });
  }

  Future<void> _pickAndEdit() async {
    final edited = await FilmkitPicker.pickAndEdit(context, options: _options);
    if (edited == null) return;
    setState(() {
      _picked = [];
      _edited = edited;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('filmkit_picker')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<PickerMediaType>(
            segments: const [
              ButtonSegment(value: PickerMediaType.all, label: Text('All')),
              ButtonSegment(value: PickerMediaType.photos, label: Text('Photos')),
              ButtonSegment(value: PickerMediaType.videos, label: Text('Videos')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.single),
          ),
          SwitchListTile(title: const Text('Multiple selection (up to 10)'), value: _multiple, onChanged: (v) => setState(() => _multiple = v)),
          FilledButton(key: const ValueKey('pick'), onPressed: _pick, child: const Text('Pick')),
          const SizedBox(height: 8),
          FilledButton(key: const ValueKey('pickAndEdit'), onPressed: _pickAndEdit, child: const Text('Pick and edit')),
          const SizedBox(height: 16),
          for (final media in _picked)
            ListTile(
              leading: media.isVideo ? const Icon(Icons.videocam) : Image.file(File(media.path), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168),
              title: Text(media.path.split('/').last),
              subtitle: Text('${media.aspect.label}, crop ${_rect(media.cropRect)}'),
            ),
          for (final result in _edited)
            ListTile(
              leading: result.export == null || !result.export!.path.endsWith('.jpg')
                  ? const Icon(Icons.movie)
                  : Image.file(File(result.export!.path), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168),
              title: Text(result.export?.path.split('/').last ?? 'not exported'),
              subtitle: Text('${result.export?.width}×${result.export?.height}, ${result.look?.name ?? 'no filter'}'),
            ),
        ],
      ),
    );
  }

  static String _rect(Rect r) => '(${r.left.toStringAsFixed(2)}, ${r.top.toStringAsFixed(2)}) ${r.width.toStringAsFixed(2)}×${r.height.toStringAsFixed(2)}';
}
