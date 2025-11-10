import 'package:background_download_flutter/features/download/presentation/controller/download_controller.dart';
import 'package:background_download_flutter/main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

class DownloadNotification {
  late final NotificationAppLaunchDetails? _launchDetails;

  Future<void> initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    _launchDetails = await localNoti.getNotificationAppLaunchDetails();

    await localNoti.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) async {
        await handleNotificationResponse(resp);
      },
      onDidReceiveBackgroundNotificationResponse: onBgNotificationAction, // optional
    );
  }

  Future<void> handleNotificationResponse(NotificationResponse resp) async {
    final payload = resp.payload ?? '';
    final action = resp.actionId; // "cancel" for your action button
    final taskId = extractTaskId(payload);

    if (action == 'cancel' && taskId != null) {
      await Get.find<DownloadController>().cancelTask(taskId);
      return;
    }

    if (payload.contains('route:')) {
      final route = payload.split('route:').last;
      // ensure controller exists before navigating
      Get.toNamed(route);
    }
  }

  Future<void> maybeHandleInitialNotificationRoute() async {
    if ((_launchDetails?.didNotificationLaunchApp ?? false) &&
        (_launchDetails?.notificationResponse?.payload?.isNotEmpty ?? false)) {
      final resp = _launchDetails!.notificationResponse!;
      await handleNotificationResponse(resp);
    }
  }

  String? extractTaskId(String payload) {
    final i = payload.indexOf('task:');
    if (i == -1) return null;
    final semi = payload.indexOf(';', i);
    return payload.substring(i + 5, semi == -1 ? payload.length : semi);
  }
}