// ====== DOWNLOAD STATUS ======
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DLStatus { idle, loading, done, error }

// ====== SIMPLE MODEL ======
class DownloadItem {
  DownloadItem({
    required this.id,
    required this.url,
    required this.filename,
    this.taskId,
    this.progress = 0,
    this.status = DLStatus.idle,
  });

  final String id; // your business id
  final String url;
  final String filename;

  String? taskId; // flutter_downloader task id
  int progress;
  DLStatus status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'taskId': taskId,
        'progress': progress,
        'status': status.name,
      };

  static DownloadItem fromJson(Map<String, dynamic> j) => DownloadItem(
        id: j['id'],
        url: j['url'],
        filename: j['filename'],
        taskId: j['taskId'],
        progress: j['progress'] ?? 0,
        status:
            DLStatus.values.firstWhere((e) => e.name == (j['status'] ?? 'idle'), orElse: () => DLStatus.idle),
      );
}

// ====== PERSISTENCE ======
class DownloadStore {
  DownloadStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'downloads:list';

  List<DownloadItem> load() {
    final s = _prefs.getStringList(_key) ?? const [];
    return s
        .map((e) => DownloadItem.fromJson(Map<String, dynamic>.from(
              (e.isEmpty) ? {} : jsonDecode(e),
            )))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  Future<void> save(List<DownloadItem> list) async {
    final payload = list.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(_key, payload);
  }
}
