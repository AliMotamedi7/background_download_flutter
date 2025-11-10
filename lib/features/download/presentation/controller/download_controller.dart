import 'package:background_download_flutter/features/download/domain/entity/download_store.dart';
import 'package:background_download_flutter/main.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

class DownloadController extends GetxController {
  DownloadController(this.store);

  final DownloadStore store;

  final items = <DownloadItem>[].obs;

  // quick aggregate states
  bool get isAnyLoading => items.any((e) => e.status == DLStatus.loading);

  int get activeProgress =>
      items.where((e) => e.status == DLStatus.loading).fold(0, (a, b) => a + (b.progress));

  Future<void> restoreFromDisk() async {
    items.assignAll(store.load());
    update();
  }

  Future<void> cancelAllActive({bool deleteFiles = false}) async {
    final snapshot = List<DownloadItem>.from(items);

    for (final it in snapshot) {
      final id = it.taskId;
      if (id == null) continue;

      if (it.status == DLStatus.loading) {
        try {
          await FlutterDownloader.cancel(taskId: id);
        } catch (_) {
          /* ignore */
        }
      }

      try {
        await FlutterDownloader.remove(
          taskId: id,
          shouldDeleteContent: deleteFiles,
        );
      } catch (_) {
        /* ignore */
      }

      // Update local state + notification
      it.status = DLStatus.error; // or make a separate DLStatus.canceled if you prefer
      it.progress = 0;
      await localNoti.cancel(it.id.hashCode & 0x7fffffff);
    }

    // Replace the mutated items and persist
    snapshot.clear();
    items.assignAll(snapshot);
    await persist();
    update();
  }

  Future<void> reconcileWithSystem() async {
    final tasks = await FlutterDownloader.loadTasks() ?? const <DownloadTask>[];
    bool changed = false;

    Map<String, DownloadTask> byTask = {for (final t in tasks) t.taskId: t};

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.taskId != null && byTask.containsKey(it.taskId)) {
        final t = byTask[it.taskId]!;
        it.progress = t.progress;
        it.status = switch (t.status) {
          DownloadTaskStatus.complete => DLStatus.done,
          DownloadTaskStatus.failed => DLStatus.error,
          DownloadTaskStatus.canceled => DLStatus.error,
          DownloadTaskStatus.paused =>
          DLStatus.loading, // show as “loading/paused” if you want a distinct state
          DownloadTaskStatus.enqueued => DLStatus.loading,
          DownloadTaskStatus.running => DLStatus.loading,
          _ => it.status,
        };
        items[i] = it;
        changed = true;
      }
    }

    if (changed) {
      await persist();
      update();
    }
  }

  Future<void> persist() => store.save(items);

  Future<void> addAndStart(DownloadItem item) async {
    item.status = DLStatus.loading;
    items.removeWhere((e) => e.id == item.id);
    items.add(item);
    await persist();
    final taskId = await FlutterDownloader.enqueue(
      url: item.url,
      savedDir: '/sdcard/Download',
      fileName: item.filename,
      showNotification: false,
      openFileFromNotification: false,
    );

    // attach task id and persist
    item.taskId = taskId;
    await persist();

    // also show our own tappable progress notification
    await _showOrUpdateLocalNotification(item);
  }

  Future<void> updateFromCallback(String taskId, int progress, DownloadTaskStatus status) async {
    final i = items.indexWhere((e) => e.taskId == taskId);
    if (i == -1) return;

    final item = items[i];
    item.progress = progress;

    if (status == DownloadTaskStatus.complete) {
      item.status = DLStatus.done;
      item.progress = 100;
      await _showDoneLocalNotification(item);
    } else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
      item.status = DLStatus.error;
    } else {
      item.status = DLStatus.loading;
      await _showOrUpdateLocalNotification(item);
    }

    items[i] = item;
    await persist();
    update();
  }

  Future<void> _showOrUpdateLocalNotification(DownloadItem item) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'Background downloads',
        ongoing: true,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: 100,
        progress: item.progress,
        importance: Importance.low,
        priority: Priority.low,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'cancel', // <-- actionId
            'Cancel',
            showsUserInterface: true, // bring app to foreground so we can cancel
            cancelNotification: true, // dismiss this notification after tap
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await localNoti.show(
      item.id.hashCode & 0x7fffffff,
      'Downloading ${item.filename}',
      '${item.progress}%',
      details,
      // include task id to cancel
      payload: 'task:${item.taskId};route:/downloads?current=${Uri.encodeComponent(item.id)}',
    );
  }

  Future<void> _showDoneLocalNotification(DownloadItem item) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'Background downloads',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await localNoti.show(
      item.id.hashCode & 0x7fffffff,
      'Download complete',
      item.filename,
      details,
      payload: 'route:/downloads?current=${Uri.encodeComponent(item.id)}',
    );
  }
}

extension CancelTask on DownloadController {
  Future<void> cancelTask(String taskId) async {
    try {
      await FlutterDownloader.cancel(taskId: taskId);
    } catch (_) {
      /* ignore */
    }

    final idx = items.indexWhere((e) => e.taskId == taskId);
    if (idx != -1) {
      final it = items[idx];
      it.status = DLStatus.error;
      it.progress = 0;
      items[idx] = it;
      await persist();
      update();
      await localNoti.cancel(it.id.hashCode & 0x7fffffff);
    }
  }
}