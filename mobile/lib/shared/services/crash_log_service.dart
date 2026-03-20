import "dart:developer" as dev;
import "dart:io";
import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";

class CrashLogService {
  static final List<String> _buffer = [];
  static const int _maxBufferSize = 200;

  static void log(String tag, String message, {StackTrace? stack}) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = "[$timestamp] [$tag] $message"
        "${stack != null ? '\nSTACK:\n$stack' : ''}";

    if (kDebugMode) {
      dev.log(entry, name: "EduSysCrash");
    } else {
      debugPrint("EduSysCrash: $entry");
    }

    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    _writeToFile(entry);
  }

  static Future<void> _writeToFile(String entry) async {
    try {
      Directory dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final file = File("${dir.path}/crash_log.txt");
      await file.writeAsString(
        "$entry\n",
        mode: FileMode.append,
        flush: true,
      );
      await _writeToDownloads(entry);
    } catch (_) {}
  }

  static Future<void> _writeToDownloads(String entry) async {
    if (!Platform.isAndroid) return;
    try {
      final downloadsDir = Directory("/storage/emulated/0/Download");
      if (!await downloadsDir.exists()) return;
      final file = File("${downloadsDir.path}/crash_log.txt");
      await file.writeAsString(
        "$entry\n",
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static String getBufferedLogs() => _buffer.join("\n\n");

  static Future<void> clearFile() async {
    try {
      Directory dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final file = File("${dir.path}/crash_log.txt");
      if (await file.exists()) await file.delete();
      await _clearDownloads();
    } catch (_) {}
  }

  static Future<void> _clearDownloads() async {
    if (!Platform.isAndroid) return;
    try {
      final file = File("/storage/emulated/0/Download/crash_log.txt");
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
