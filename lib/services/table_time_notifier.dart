import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/models.dart';

/// Schedules phone notifications for fixed-time sessions: a warning shortly
/// before the booked time ends and an alert when it does.
///
/// They are scheduled on the device itself from the table list, so every
/// phone that has the app open gets them, and they still fire if the app is
/// later closed. There is no server involved.
class TableTimeNotifier {
  static const warnBefore = Duration(minutes: 5);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _scheduledFor; // the table end times currently scheduled

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'table_time',
      'Stol vaqti',
      channelDescription: 'Belgilangan vaqt tugashi haqida ogohlantirish',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
        presentAlert: true, presentSound: true, presentBanner: true),
  );

  /// Asks for permission and gets ready to schedule. Safe to call again.
  Future<void> init() async {
    // The plugin has no web implementation.
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      // Without this Android may deliver the alert several minutes late.
      if (android != null &&
          !(await android.canScheduleExactNotifications() ?? false)) {
        await android.requestExactAlarmsPermission();
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Makes the scheduled notifications match [tables]. Call whenever the
  /// table list changes.
  Future<void> sync(List<TableModel> tables) async {
    if (!_ready) return;
    final timed = tables
        .where((t) =>
            t.status == TableStatus.active && t.sessionEndsAt != null)
        .toList();
    // The table stream emits on every change; only reschedule when an end
    // time actually moved.
    final key = timed
        .map((t) => '${t.id}@${t.sessionEndsAt!.millisecondsSinceEpoch}')
        .join(',');
    if (key == _scheduledFor) return;
    _scheduledFor = key;

    try {
      await _plugin.cancelAllPendingNotifications();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final exact = await android?.canScheduleExactNotifications() ?? true;
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      final now = DateTime.now();
      for (var i = 0; i < timed.length; i++) {
        final table = timed[i];
        final end = table.sessionEndsAt!;
        final warnAt = end.subtract(warnBefore);
        if (warnAt.isAfter(now)) {
          await _schedule(i * 2, warnAt, mode, table.name,
              '${warnBefore.inMinutes} daqiqadan keyin vaqt tugaydi');
        }
        if (end.isAfter(now)) {
          await _schedule(i * 2 + 1, end, mode, '${table.name}: vaqt tugadi',
              'Mijozga xabar bering yoki vaqtni uzaytiring');
        }
      }
    } catch (e) {
      debugPrint('Could not schedule notifications: $e');
    }
  }

  Future<void> _schedule(int id, DateTime at, AndroidScheduleMode mode,
          String title, String body) =>
      _plugin.zonedSchedule(
        id: id,
        // An absolute instant, so the device's time zone doesn't matter.
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: mode,
        title: title,
        body: body,
      );

  /// Drops everything scheduled, e.g. at sign-out.
  Future<void> clear() async {
    _scheduledFor = null;
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {}
  }
}
