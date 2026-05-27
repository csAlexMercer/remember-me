import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:hive/hive.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _settingsBoxName = 'notification_settings';
  static const String _quietStartKey = 'quiet_start_hour';
  static const String _quietEndKey = 'quiet_end_hour';
  static const String _quietEnabledKey = 'quiet_enabled';

  Future<void> init() async {
    tz.initializeTimeZones();

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
            // Handle notification tapped logic here
          },
    );
  }

  /// Schedule a reminder, respecting quiet hours if enabled.
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    DateTime adjustedDate = await _adjustForQuietHours(scheduledDate);
    final now = DateTime.now();

    // flutter_local_notifications requires a strictly future timestamp.
    if (!adjustedDate.isAfter(now)) {
      adjustedDate = await _adjustForQuietHours(
        now.add(const Duration(minutes: 1)),
      );
    }

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
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelReminder(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  // ─── Quiet Hours ───────────────────────────────────────────

  /// Adjust a scheduled date to fall outside quiet hours.
  /// If the date falls within quiet hours, push it to the end of the quiet period.
  Future<DateTime> _adjustForQuietHours(DateTime scheduledDate) async {
    final settings = await getQuietHoursSettings();
    if (!settings['enabled']) return scheduledDate;

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
      return adjusted;
    }

    return scheduledDate;
  }

  /// Get quiet hours settings from Hive.
  Future<Map<String, dynamic>> getQuietHoursSettings() async {
    final box = await Hive.openBox(_settingsBoxName);
    return {
      'enabled': box.get(_quietEnabledKey, defaultValue: false) as bool,
      'startHour': box.get(_quietStartKey, defaultValue: 22) as int,
      'endHour': box.get(_quietEndKey, defaultValue: 7) as int,
    };
  }

  /// Save quiet hours settings to Hive.
  Future<void> setQuietHoursSettings({
    required bool enabled,
    required int startHour,
    required int endHour,
  }) async {
    final box = await Hive.openBox(_settingsBoxName);
    await box.put(_quietEnabledKey, enabled);
    await box.put(_quietStartKey, startHour);
    await box.put(_quietEndKey, endHour);
  }
}
