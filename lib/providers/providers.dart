import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/week_utils.dart";
import "../data/local/database.dart";
import "../data/remote/supabase_service.dart";
import "../data/remote/sync_service.dart";
import "../data/repositories/goals_repository.dart";
import "../data/repositories/notification_settings_repository.dart";
import "../data/repositories/recurrence_templates_repository.dart";
import "../data/repositories/todos_repository.dart";
import "../data/repositories/weeks_repository.dart";
import "../features/notifications/notification_service.dart";
import "../features/recurring/recurrence_engine.dart";

/// One AppDatabase for the app lifetime. Overridden in tests with an
/// in-memory instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final weeksRepositoryProvider = Provider<WeeksRepository>((ref) {
  return WeeksRepository(ref.watch(databaseProvider));
});

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return GoalsRepository(ref.watch(databaseProvider));
});

final todosRepositoryProvider = Provider<TodosRepository>((ref) {
  return TodosRepository(
    ref.watch(databaseProvider),
    ref.watch(weeksRepositoryProvider),
  );
});

final recurrenceEngineProvider = Provider<RecurrenceEngine>((ref) {
  return RecurrenceEngine(
    ref.watch(databaseProvider),
    ref.watch(weeksRepositoryProvider),
    ref.watch(goalsRepositoryProvider),
    ref.watch(todosRepositoryProvider),
  );
});

final recurrenceTemplatesRepositoryProvider =
    Provider<RecurrenceTemplatesRepository>((ref) {
  return RecurrenceTemplatesRepository(ref.watch(databaseProvider));
});

final recurrenceTemplatesProvider =
    StreamProvider<List<RecurrenceTemplate>>((ref) {
  return ref.watch(recurrenceTemplatesRepositoryProvider).watchAll();
});

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
  return NotificationSettingsRepository(ref.watch(databaseProvider));
});

final notificationSettingsProvider =
    StreamProvider<NotificationSettingsRow>((ref) {
  return ref.watch(notificationSettingsRepositoryProvider).watch();
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(databaseProvider),
    ref.watch(supabaseServiceProvider),
  );
});

final notificationServiceProvider = FutureProvider<NotificationService>((ref) async {
  final service = NotificationService();
  await service.init();
  return service;
});

/// The Monday (yyyy-MM-dd) of the week currently shown in the UI. Defaults
/// to the real current week; the history screen can push a different value
/// when the user browses past weeks, but the weekly-view screen always
/// resets this back to "today" via [WeekUtils.currentWeekStart].
final selectedWeekStartProvider = StateProvider<String>((ref) {
  return WeekUtils.currentWeekStart();
});

/// Resolves (creating if necessary) the [Week] row for whatever week is
/// currently selected.
final currentWeekProvider = FutureProvider<Week>((ref) async {
  final weekStart = ref.watch(selectedWeekStartProvider);
  return ref.watch(weeksRepositoryProvider).getOrCreateWeek(weekStart);
});

final goalsForCurrentWeekProvider = StreamProvider<List<Goal>>((ref) {
  final weekAsync = ref.watch(currentWeekProvider);
  return weekAsync.when(
    data: (week) => ref.watch(goalsRepositoryProvider).watchGoalsForWeek(week.id),
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});
