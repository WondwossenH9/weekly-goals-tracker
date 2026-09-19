import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:timezone/data/latest_all.dart" as tz_data;
import "package:timezone/timezone.dart" as tz;

import "../../data/local/database.dart";

enum NotificationKind { dailyNudge, weeklyReflection, recurringSetup }

/// Wraps flutter_local_notifications with the three notification types
/// this app needs. Each kind is scheduled independently and can be
/// individually enabled/disabled from Settings (see SettingsScreen), which
/// just calls [cancel] / the matching `scheduleX` method again.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationDetails(
    "weekly_goals_channel",
    "Weekly Goals reminders",
    channelDescription: "Daily nudges and weekly reflection prompts",
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _deviceTimeZoneName()));

    const androidInit = AndroidInitializationSettings("@mipmap/ic_launcher");
    const linuxInit = LinuxInitializationSettings(
      defaultActionName: "Open",
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, linux: linuxInit),
    );

    // Android 13+ requires this runtime permission request; a no-op on
    // Linux desktop and on older Android versions.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Best-effort device timezone name. Hardcoded to Africa/Addis_Ababa
  /// (EAT, UTC+3, no DST) as a fixed default rather than autodetected —
  /// correct as long as the app runs from Ethiopia. If this ever needs to
  /// follow the device (e.g. travel, or a second user elsewhere), swap
  /// this for the `flutter_timezone` package's `getLocalTimezone()` call
  /// instead of hardcoding.
  Future<String> _deviceTimeZoneName() async => "Africa/Addis_Ababa";

  Future<void> scheduleDailyNudge({
    required int hour,
    required int minute,
  }) async {
    await _plugin.zonedSchedule(
      NotificationKind.dailyNudge.index,
      "Update today\u2019s todos",
      "Quick check-in: mark what\u2019s done, ongoing, or not done today.",
      _nextInstanceOfDaily(hour, minute),
      const NotificationDetails(android: _androidChannel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Default anchor: Sunday, matching the natural "end of week" moment —
  /// configurable in Settings if the user runs their week differently.
  Future<void> scheduleWeeklyReflection({
    required int weekday, // 1-7, Dart DateTime.weekday convention
    required int hour,
    required int minute,
  }) async {
    await _plugin.zonedSchedule(
      NotificationKind.weeklyReflection.index,
      "Reflect on this week",
      "Your week\u2019s summary is ready \u2014 add a quick reflection.",
      _nextInstanceOfWeekly(weekday, hour, minute),
      const NotificationDetails(android: _androidChannel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> scheduleRecurringSetupReminder({
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    await _plugin.zonedSchedule(
      NotificationKind.recurringSetup.index,
      "New week, new goals",
      "Review this week\u2019s auto-generated recurring goals.",
      _nextInstanceOfWeekly(weekday, hour, minute),
      const NotificationDetails(android: _androidChannel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancel(NotificationKind kind) => _plugin.cancel(kind.index);

  /// Applies a persisted [NotificationSettingsRow] in full — call this
  /// once on app start (and after resume) so scheduled reminders survive
  /// an app restart / device reboot, which flutter_local_notifications
  /// does not guarantee on its own on Android.
  Future<void> rescheduleFromSettings(NotificationSettingsRow settings) async {
    if (settings.dailyNudgeEnabled) {
      await scheduleDailyNudge(
        hour: settings.dailyNudgeHour,
        minute: settings.dailyNudgeMinute,
      );
    } else {
      await cancel(NotificationKind.dailyNudge);
    }

    if (settings.weeklyReflectionEnabled) {
      await scheduleWeeklyReflection(
        weekday: settings.reflectionWeekday,
        hour: settings.reflectionHour,
        minute: settings.reflectionMinute,
      );
    } else {
      await cancel(NotificationKind.weeklyReflection);
    }

    if (settings.recurringSetupEnabled) {
      await scheduleRecurringSetupReminder(
        weekday: settings.recurringWeekday,
        hour: settings.recurringHour,
        minute: settings.recurringMinute,
      );
    } else {
      await cancel(NotificationKind.recurringSetup);
    }
  }

  tz.TZDateTime _nextInstanceOfDaily(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekly(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfDaily(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
