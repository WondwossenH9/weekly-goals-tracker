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

/// The Week row for whatever week is currently selected — live-updating,
/// not a one-shot fetch. This does NOT create the row if missing; by the
/// time anything watches this, _StartupGate has already guaranteed the
/// current week's row exists (and History only ever selects weeks that
/// already exist), so null here should only ever be a brief transient
/// state, never a steady-state outcome.
final currentWeekProvider = StreamProvider<Week?>((ref) {
  final weekStart = ref.watch(selectedWeekStartProvider);
  return ref.watch(weeksRepositoryProvider).watchWeek(weekStart);
});

final goalsForCurrentWeekProvider = StreamProvider<List<Goal>>((ref) {
  final weekAsync = ref.watch(currentWeekProvider);
  return weekAsync.when(
    data: (week) => week == null
        ? const Stream.empty()
        : ref.watch(goalsRepositoryProvider).watchGoalsForWeek(week.id),
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

/// Resolves the currently-selected week for one-off actions (adding a
/// goal, cycling a todo) that need a concrete Week row right now rather
/// than a stream to watch. Self-heals by creating the row if the reactive
/// stream somehow hasn't produced one yet — should only ever be a narrow
/// startup-timing edge case, never the normal path.
Future<Week> resolveCurrentWeek(WidgetRef ref) async {
  final week = await ref.read(currentWeekProvider.future);
  if (week != null) return week;
  final weekStart = ref.read(selectedWeekStartProvider);
  return ref.read(weeksRepositoryProvider).getOrCreateWeek(weekStart);
}
