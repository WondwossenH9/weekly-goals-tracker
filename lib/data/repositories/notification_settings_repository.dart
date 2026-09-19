import "package:drift/drift.dart";

import "../local/database.dart";

/// Reads/writes the single notification-preferences row. Local-only by
/// design — see the comment on the NotificationSettings table.
class NotificationSettingsRepository {
  NotificationSettingsRepository(this._db);
  final AppDatabase _db;

  Stream<NotificationSettingsRow> watch() {
    return (_db.select(_db.notificationSettings)
          ..where((t) => t.id.equals(0)))
        .watchSingle();
  }

  Future<NotificationSettingsRow> get() {
    return (_db.select(_db.notificationSettings)
          ..where((t) => t.id.equals(0)))
        .getSingle();
  }

  Future<void> updateDailyNudge({bool? enabled, int? hour, int? minute}) {
    return (_db.update(_db.notificationSettings)..where((t) => t.id.equals(0)))
        .write(NotificationSettingsCompanion(
      dailyNudgeEnabled: enabled == null ? const Value.absent() : Value(enabled),
      dailyNudgeHour: hour == null ? const Value.absent() : Value(hour),
      dailyNudgeMinute: minute == null ? const Value.absent() : Value(minute),
    ));
  }

  Future<void> updateWeeklyReflection({
    bool? enabled,
    int? weekday,
    int? hour,
    int? minute,
  }) {
    return (_db.update(_db.notificationSettings)..where((t) => t.id.equals(0)))
        .write(NotificationSettingsCompanion(
      weeklyReflectionEnabled:
          enabled == null ? const Value.absent() : Value(enabled),
      reflectionWeekday: weekday == null ? const Value.absent() : Value(weekday),
      reflectionHour: hour == null ? const Value.absent() : Value(hour),
      reflectionMinute: minute == null ? const Value.absent() : Value(minute),
    ));
  }

  Future<void> updateRecurringSetup({
    bool? enabled,
    int? weekday,
    int? hour,
    int? minute,
  }) {
    return (_db.update(_db.notificationSettings)..where((t) => t.id.equals(0)))
        .write(NotificationSettingsCompanion(
      recurringSetupEnabled:
          enabled == null ? const Value.absent() : Value(enabled),
      recurringWeekday: weekday == null ? const Value.absent() : Value(weekday),
      recurringHour: hour == null ? const Value.absent() : Value(hour),
      recurringMinute: minute == null ? const Value.absent() : Value(minute),
    ));
  }
}
