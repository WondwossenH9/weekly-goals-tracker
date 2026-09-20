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

/// Result of the most recent sync attempt (or "syncing" while one is in
/// flight). Only triggerSync() below should write to this — the actual
/// SyncService.sync() call is deliberately kept UI-agnostic.
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

/// Whether any local row is still waiting to be pushed. Independent of
/// syncStatusProvider: a sync can finish successfully and this can still
/// be true again a second later, the moment the next todo gets toggled.
final hasPendingChangesProvider = StreamProvider<bool>((ref) {
  return ref.watch(syncServiceProvider).watchHasPendingChanges();
});

/// The one place that should ever call SyncService.sync() from UI code —
/// keeps syncStatusProvider honestly in sync with what's actually
/// happening, rather than every call site remembering to update it.
Future<void> triggerSync(WidgetRef ref) async {
  ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
  final result = await ref.read(syncServiceProvider).sync();
  ref.read(syncStatusProvider.notifier).state = result;
}

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
  // .select() here is load-bearing, not a style choice: this provider
  // only needs the week's id, which is stable for a given week. Without
  // select, watching currentWeekProvider directly would re-run this
  // provider's build function (tearing down and recreating its stream
  // subscription, with a loading flicker in between) on every field
  // change to that row — including completion_pct on every todo toggle
  // and reflection_text on every reflection keystroke-save. That flicker
  // is what was destroying the reflection TextField's focus.
  final weekId = ref.watch(
    currentWeekProvider.select((async) => async.valueOrNull?.id),
  );
  if (weekId == null) return const Stream.empty();
  return ref.watch(goalsRepositoryProvider).watchGoalsForWeek(weekId);
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
