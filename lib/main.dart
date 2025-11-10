import 'dart:isolate';
import 'dart:ui';
import 'package:background_download_flutter/core/utils/download_notification.dart';
import 'package:background_download_flutter/features/download/domain/entity/download_store.dart';
import 'package:background_download_flutter/features/download/presentation/controller/download_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ====== GLOBALS ======
const String kPortName = 'downloader_send_port';
final FlutterLocalNotificationsPlugin localNoti = FlutterLocalNotificationsPlugin();

const String kRoutePayloadKey = 'route_payload';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(kPortName);
  send?.send([id, status, progress]);
}

@pragma('vm:entry-point')
Future<void> onBgNotificationAction(NotificationResponse resp) async {
  if (resp.actionId == 'cancel') {
    final taskId = DownloadNotification().extractTaskId(resp.payload ?? '');
    if (taskId != null) {
      try {
        await FlutterDownloader.cancel(taskId: taskId);
      } catch (_) {}
    }
  }
}


void _registerDownloaderPort(DownloadController ctrl) {
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(kPortName);
  IsolateNameServer.registerPortWithName(port.sendPort, kPortName);

  port.listen((dynamic data) async {
    final String taskId = data[0] as String;
    final int statusValue = data[1] as int;
    final int progress = data[2] as int;
    final status = DownloadTaskStatus.fromInt(statusValue);
    await ctrl.updateFromCallback(taskId, progress, status);
  });

  FlutterDownloader.registerCallback(downloadCallback);
}

// ====== UI ======
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, this.currentId});

  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DownloadController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'Cancel all',
            icon: const Icon(Icons.cancel_schedule_send),
            onPressed: () => ctrl.cancelAllActive(deleteFiles: false),
          ),
        ],
      ),
      body: Obx(() {
        final list = ctrl.items;
        if (list.isEmpty) return const Center(child: Text('No downloads yet'));
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (_, i) {
            final it = list[i];
            final isCurrent = (it.id == currentId);
            return ListTile(
              selected: isCurrent,
              title: Text(it.filename),
              subtitle: Text(
                switch (it.status) {
                  DLStatus.idle => 'Idle',
                  DLStatus.loading => 'Loading… ${it.progress}%',
                  DLStatus.done => 'Done',
                  DLStatus.error => 'Error',
                },
              ),
              trailing: it.status == DLStatus.loading
                  ? SizedBox(
                      width: 96,
                      child: LinearProgressIndicator(value: it.progress / 100.0),
                    )
                  : const SizedBox.shrink(),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final demo = DownloadItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            url:
                'https://storage.flashpte.ai/question/SPEAKING_SUMMARIZE_GROUP_DISCUSSION/2025/7b2f87bf-dc65-4d4c-8a7c-3e9052343b07.mp3?response-content-type=audio%2Fmpeg&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=minio%2F20251110%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20251110T085047Z&X-Amz-Expires=7200&X-Amz-SignedHeaders=host&X-Amz-Signature=ea771984bc0b62c40d9d2f647cef078b98982dfb117716c9bf1a334121d4f0ac',
            filename: 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          Get.find<DownloadController>().addAndStart(demo);
        },
        label: const Text('Start demo download'),
        icon: const Icon(Icons.download),
      ),
    );
  }
}

GetPage<dynamic> _downloadsRoute() => GetPage(
      name: '/downloads',
      page: () {
        final params = Get.parameters;
        return DownloadsPage(currentId: params['current']);
      },
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterDownloader.initialize(debug: false);
  await DownloadNotification().initLocalNotifications();

  final prefs = await SharedPreferences.getInstance();
  final store = DownloadStore(prefs);
  final ctrl = DownloadController(store);
  Get.put<DownloadController>(ctrl, permanent: true);

  await ctrl.restoreFromDisk();

  await ctrl.reconcileWithSystem();

  // Register isolate port + callback
  _registerDownloaderPort(ctrl);

  runApp(GetMaterialApp(
    initialRoute: '/downloads',
    getPages: [_downloadsRoute()],
  ));

  // If the app was launched via tapping your notification while killed, navigate now
  await DownloadNotification().maybeHandleInitialNotificationRoute();
}
