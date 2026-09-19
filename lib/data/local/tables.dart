import "package:drift/drift.dart";
import "package:uuid/uuid.dart";

/// One row per calendar week the user has ever had a goal in.
/// week start is always a Monday (ISO week), stored as a date-only string
/// (yyyy-MM-dd) so it is stable across timezones.
@DataClassName('Week')
class Weeks extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get startDate => text()(); // yyyy-MM-dd, Monday of that week
  RealColumn get completionPct => real().withDefault(const Constant(0))();
  TextColumn get reflectionText => text().withDefault(const Constant(""))();
  DateTimeColumn get reflectionUpdatedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A goal that lives inside a specific week. Recurring goals are generated
/// as new rows each week (linked back to their template via
/// recurrenceTemplateId) so editing one week never touches another.
@DataClassName('Goal')
class Goals extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get weekId =>
      text().references(Weeks, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceTemplateId => text()
      .nullable()
      .references(RecurrenceTemplates, #id, onDelete: KeyAction.setNull)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

enum TodoState { done, ongoing, notDone }

@DataClassName('TodoItem')
class Todos extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get goalId =>
      text().references(Goals, #id, onDelete: KeyAction.cascade)();
  // 1 = Monday ... 7 = Sunday, matching DateTime.weekday.
  IntColumn get dayOfWeek => integer()();
  TextColumn get state =>
      textEnum<TodoState>().withDefault(const Constant("notDone"))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The reusable "template" behind a recurring goal (e.g. "Exercise 3x/week").
/// Editing this only affects weeks generated after the edit.
@DataClassName('RecurrenceTemplate')
class RecurrenceTemplates extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get goalTitle => text()();
  // One of: weekly, biweekly, custom
  TextColumn get rule => text()();
  // For custom: comma-separated ISO weekdays this goal should get a todo
  // on, e.g. "1,3,5" for Mon/Wed/Fri. Null for weekly/biweekly.
  TextColumn get customDays => text().nullable()();
  // For biweekly: the Monday (yyyy-MM-dd) of the first week it should
  // apply to, so we can compute odd/even week offsets.
  TextColumn get biweeklyAnchor => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row table tracking sync bookkeeping.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row table of notification preferences. Deliberately local-only
/// (no pendingSync/updatedAt, never touched by SyncService) — reminder
/// times are a per-device thing, not something that should overwrite a
/// different device's schedule on sync.
@DataClassName('NotificationSettingsRow')
class NotificationSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  BoolColumn get dailyNudgeEnabled =>
      boolean().withDefault(const Constant(true))();
  IntColumn get dailyNudgeHour => integer().withDefault(const Constant(20))();
  IntColumn get dailyNudgeMinute => integer().withDefault(const Constant(0))();

  BoolColumn get weeklyReflectionEnabled =>
      boolean().withDefault(const Constant(true))();
  // DateTime.weekday convention: 1 = Monday ... 7 = Sunday.
  IntColumn get reflectionWeekday => integer().withDefault(const Constant(7))();
  IntColumn get reflectionHour => integer().withDefault(const Constant(10))();
  IntColumn get reflectionMinute => integer().withDefault(const Constant(0))();

  BoolColumn get recurringSetupEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get recurringWeekday => integer().withDefault(const Constant(1))();
  IntColumn get recurringHour => integer().withDefault(const Constant(7))();
  IntColumn get recurringMinute => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
