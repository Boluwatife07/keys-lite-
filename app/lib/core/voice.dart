import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'services.dart';
import 'voice_io.dart' if (dart.library.js_interop) 'voice_web.dart';

/// Records AAC (.m4a) on phones and Opus (.webm) in the browser.
class DeviceVoiceRecorder implements VoiceRecorder {
  final _rec = AudioRecorder();

  @override
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    if (kIsWeb) {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.opus), path: '');
    } else {
      final dir = await getTemporaryDirectory();
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    }
    return true;
  }

  @override
  Future<PickedFile?> stop() async {
    final path = await _rec.stop();
    if (path == null) return null;
    if (kIsWeb) {
      final bytes = (await http.get(Uri.parse(path))).bodyBytes;
      return PickedFile(bytes: bytes, name: 'voice.webm', mime: 'audio/webm');
    }
    return PickedFile(bytes: await readFileBytes(path), name: 'voice.m4a', mime: 'audio/mp4', path: path);
  }

  @override
  Future<void> cancel() => _rec.cancel();
}
