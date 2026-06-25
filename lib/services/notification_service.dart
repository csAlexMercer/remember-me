import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/remember_item.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _notificationsAllowed = false;
  bool _exactAlarmsAllowed = false;

  bool get notificationsAllowed => _notificationsAllowed;
  bool get exactAlarmsAllowed => _exactAlarmsAllowed;

  static const String _settingsBoxName = 'notification_settings';
  static const String _quietStartKey = 'quiet_start_hour';
  static const String _quietEndKey = 'quiet_end_hour';
  static const String _quietEnabledKey = 'quiet_enabled';

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[NotificationService] $message');
    }
  }

  Future<void> init() async {
    _log('init: start');
    tz.initializeTimeZones();
    _log('init: timezone database initialized');
    await _configureLocalTimeZone();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS initialization settings
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) async {
            _log(
              'response: received action=${notificationResponse.actionId} payload=${notificationResponse.payload}',
            );
            await _handleNotificationResponse(notificationResponse);
          },
    );
    _log('init: plugin initialized');

    // Request and capture permission results where supported.
    final androidImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      _notificationsAllowed =
          await androidImpl?.requestNotificationsPermission() ?? false;
      _log('init: android notifications permission=$_notificationsAllowed');
    } catch (_) {
      _notificationsAllowed = false;
      _log('init: android notifications permission request failed');
    }

    try {
      _exactAlarmsAllowed =
          await androidImpl?.requestExactAlarmsPermission() ?? false;
      _log('init: android exact alarm permission=$_exactAlarmsAllowed');
    } catch (_) {
      _exactAlarmsAllowed = false;
      _log('init: android exact alarm permission request failed');
    }

    final iosImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    try {
      final iosAllowed =
          await iosImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      _notificationsAllowed = _notificationsAllowed || iosAllowed;
      _log('init: iOS permission=$iosAllowed');
    } catch (_) {}

    final macImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    try {
      final macAllowed =
          await macImpl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      _notificationsAllowed = _notificationsAllowed || macAllowed;
      _log('init: macOS permission=$macAllowed');
    } catch (_) {}

    _log(
      'init: complete notificationsAllowed=$_notificationsAllowed exactAlarmsAllowed=$_exactAlarmsAllowed',
    );
  }

  Future<void> _configureLocalTimeZone() async {
    try {
      _log('timezone: resolving local timezone');
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
      _log('timezone: configured ${timezoneInfo.identifier}');
    } catch (e) {
      _log('timezone: failed to configure local timezone: $e');
    }
  }

  /// Schedule a reminder, respecting quiet hours if enabled.
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    _log(
      'schedule: requested id=$id title="$title" scheduledDate=${scheduledDate.toIso8601String()} payload=$payload',
    );

    if (!_notificationsAllowed) {
      _log('schedule: skipped id=$id because notifications are not allowed');
      return;
    }

    DateTime adjustedDate = await _adjustForQuietHours(scheduledDate);
    final now = DateTime.now();

    _log(
      'schedule: after quiet-hours adjustment id=$id adjustedDate=${adjustedDate.toIso8601String()} now=${now.toIso8601String()}',
    );

    // flutter_local_notifications requires a strictly future timestamp.
    if (!adjustedDate.isAfter(now)) {
      _log(
        'schedule: adjustedDate is not in the future for id=$id, pushing by 1 minute',
      );
      adjustedDate = await _adjustForQuietHours(
        now.add(const Duration(minutes: 1)),
      );
      _log(
        'schedule: fallback adjustedDate for id=$id is ${adjustedDate.toIso8601String()}',
      );
    }

    _log(
      'schedule: calling zonedSchedule id=$id tz=${tz.local.name} finalDate=${adjustedDate.toIso8601String()}',
    );
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(adjustedDate, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'remember_me_channel',
          'Remember Me Notifications',
          channelDescription: 'Reminders for your tasks and ideas',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );

    _log(
      'schedule: success id=$id finalDate=${adjustedDate.toIso8601String()} requested=${scheduledDate.toIso8601String()}',
    );
  }

  Future<void> cancelReminder(int id) async {
    _log('cancel: requested id=$id');
    await flutterLocalNotificationsPlugin.cancel(id: id);
    _log('cancel: completed id=$id');
  }

  // ─── Quiet Hours ───────────────────────────────────────────

  /// Adjust a scheduled date to fall outside quiet hours.
  /// If the date falls within quiet hours, push it to the end of the quiet period.
  Future<DateTime> _adjustForQuietHours(DateTime scheduledDate) async {
    final settings = await getQuietHoursSettings();
    _log(
      'quiet-hours: evaluating ${scheduledDate.toIso8601String()} with enabled=${settings['enabled']} start=${settings['startHour']} end=${settings['endHour']}',
    );
    if (!settings['enabled']) {
      _log('quiet-hours: disabled, no adjustment');
      return scheduledDate;
    }

    final quietStart = settings['startHour'] as int;
    final quietEnd = settings['endHour'] as int;
    final hour = scheduledDate.hour;

    bool inQuietHours;
    if (quietStart <= quietEnd) {
      // e.g., 22:00 to 22:00 (no range) or 9:00 to 17:00
      inQuietHours = hour >= quietStart && hour < quietEnd;
    } else {
      // e.g., 22:00 to 07:00 (overnight)
      inQuietHours = hour >= quietStart || hour < quietEnd;
    }

    if (inQuietHours) {
      // Push to the end of quiet hours
      DateTime adjusted = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
        quietEnd,
        0,
      );
      // If quiet end is the next day (overnight quiet hours)
      if (quietStart > quietEnd && hour >= quietStart) {
        adjusted = adjusted.add(const Duration(days: 1));
      }
      _log(
        'quiet-hours: adjusted from ${scheduledDate.toIso8601String()} to ${adjusted.toIso8601String()}',
      );
      return adjusted;
    }

    _log('quiet-hours: scheduled date is outside quiet hours, no adjustment');
    return scheduledDate;
  }

  /// Get quiet hours settings from Hive.
  Future<Map<String, dynamic>> getQuietHoursSettings() async {
    _log('quiet-hours: loading settings from Hive');
    final box = await Hive.openBox(_settingsBoxName);
    final settings = {
      'enabled': box.get(_quietEnabledKey, defaultValue: false) as bool,
      'startHour': box.get(_quietStartKey, defaultValue: 22) as int,
      'endHour': box.get(_quietEndKey, defaultValue: 7) as int,
    };
    _log(
      'quiet-hours: loaded enabled=${settings['enabled']} start=${settings['startHour']} end=${settings['endHour']}',
    );
    return settings;
  }

  /// Save quiet hours settings to Hive.
  Future<void> setQuietHoursSettings({
    required bool enabled,
    required int startHour,
    required int endHour,
  }) async {
    _log('quiet-hours: saving enabled=$enabled start=$startHour end=$endHour');
    final box = await Hive.openBox(_settingsBoxName);
    await box.put(_quietEnabledKey, enabled);
    await box.put(_quietStartKey, startHour);
    await box.put(_quietEndKey, endHour);
    _log('quiet-hours: save complete');
  }

  Future<void> _handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      _log('response: no payload, skipping follow-up');
      return;
    }

    try {
      _log('response: looking up item for payload=$payload');

      final possible = await FirebaseFirestore.instance
          .collectionGroup('items')
          .where(FieldPath.documentId, isEqualTo: payload)
          .limit(1)
          .get();

      if (possible.docs.isEmpty) {
        _log('response: no document found for payload=$payload');
        return;
      }

      final snap = possible.docs.first;
      final item = RememberItem.fromFirestore(snap);
      _log(
        'response: found item id=${item.id} title="${item.title}" reminderCount=${item.reminderCount} isAsleep=${item.isAsleep}',
      );

      final updated = item.copyWith(
        reminderCount: item.reminderCount + 1,
        lastReminderSent: DateTime.now(),
      );

      final nextDate = updated.calculateNextReminderDate();
      _log(
        'response: computed nextDate=${nextDate?.toIso8601String()} for id=${item.id}',
      );

      _log('response: updating Firestore for id=${item.id}');
      await snap.reference.update({
        'reminderCount': updated.reminderCount,
        'lastReminderSent': Timestamp.fromDate(updated.lastReminderSent!),
        'nextScheduledReminder': nextDate != null
            ? Timestamp.fromDate(nextDate)
            : null,
      });
      _log('response: Firestore update complete for id=${item.id}');

      if (nextDate != null && !updated.isAsleep) {
        _log('response: scheduling next reminder for id=${item.id}');
        await scheduleReminder(
          id: updated.notificationId,
          title: 'Remember: ${updated.title}',
          body: updated.description.isNotEmpty
              ? updated.description
              : 'Time to revisit this thought.',
          scheduledDate: nextDate,
          payload: updated.id,
        );
      } else {
        _log('response: no follow-up schedule needed for id=${item.id}');
      }
    } catch (e) {
      _log('response: error handling notification response: $e');
    }
  }
}
