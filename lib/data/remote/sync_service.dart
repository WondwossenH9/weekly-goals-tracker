import "package:drift/drift.dart";

import "../local/database.dart";
import "supabase_service.dart";

enum SyncStatus { idle, syncing, synced, pendingChanges, conflict, error }

/// Offline-first sync: local SQLite (via drift) is always the source of
/// truth on-device. This service pushes locally-changed rows up to
/// Supabase, then pulls anything changed remotely back down.
///
/// Conflict rule: last-write-wins **per row**, compared on `updated_at`.
/// If you need true per-field LWW (e.g. two devices editing different
/// fields of the same todo while offline, and wanting both edits kept),
/// that needs either per-field timestamp columns or a CRDT merge — a
/// deliberate scope cut for this MVP; see README "Sync architecture".
class SyncService {
  SyncService(this._db, this._supabase);
  final AppDatabase _db;
  final SupabaseService _supabase;

  Future<SyncStatus> sync() async {
    final user = _supabase.currentUser;
    if (user == null) return SyncStatus.idle; // not signed in yet

    try {
      await _pushWeeks(user.id);
      await _pushGoals(user.id);
      await _pushTodos(user.id);
      await _pushRecurrenceTemplates(user.id);

      final lastSynced = await _lastSyncedAt();
      await _pullWeeks(user.id, lastSynced);
      await _pullGoals(user.id, lastSynced);
      await _pullTodos(user.id, lastSynced);
      await _pullRecurrenceTemplates(user.id, lastSynced);

      await (_db.update(_db.syncMeta)..where((t) => t.id.equals(0)))
          .write(SyncMetaCompanion(lastSyncedAt: Value(DateTime.now())));
      return SyncStatus.synced;
    } catch (_) {
      // Local data is never lost on a failed sync — it just stays flagged
      // pendingSync and we retry on the next connectivity change / timer.
      return SyncStatus.error;
    }
  }

  Future<DateTime?> _lastSyncedAt() async {
    final row = await (_db.select(_db.syncMeta)
          ..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    return row?.lastSyncedAt;
  }

  /// Reactive — true whenever any syncable table has a row still flagged
  /// pendingSync. Drives the ⏳ "changes waiting to sync" state in the UI
  /// independently of whether a sync is actively running right now.
  /// Uses a raw query (rather than combining four separate watch streams,
  /// which would need a stream-combining package this project doesn't
  /// otherwise depend on) with readsFrom so drift still re-runs it
  /// whenever any of the four tables change.
  Stream<bool> watchHasPendingChanges() {
    final query = _db.customSelect(
      "SELECT ("
      "EXISTS(SELECT 1 FROM weeks WHERE pending_sync = 1) OR "
      "EXISTS(SELECT 1 FROM goals WHERE pending_sync = 1) OR "
      "EXISTS(SELECT 1 FROM todos WHERE pending_sync = 1) OR "
      "EXISTS(SELECT 1 FROM recurrence_templates WHERE pending_sync = 1)"
      ") AS has_pending",
      readsFrom: {_db.weeks, _db.goals, _db.todos, _db.recurrenceTemplates},
    );
    return query.watch().map((rows) => (rows.single.data["has_pending"] as int) != 0);
  }

  // ---- Push (local pendingSync=true rows -> Supabase) ----------------

  Future<void> _pushWeeks(String userId) async {
    final rows =
        await (_db.select(_db.weeks)..where((w) => w.pendingSync.equals(true)))
            .get();
    for (final w in rows) {
      await _supabase.client.from("weeks").upsert({
        "id": w.id,
        "user_id": userId,
        "start_date": w.startDate,
        "completion_pct": w.completionPct,
        "reflection_text": w.reflectionText,
        "reflection_updated_at": w.reflectionUpdatedAt?.toIso8601String(),
        "updated_at": w.updatedAt.toIso8601String(),
      });
    }
    if (rows.isNotEmpty) {
      await (_db.update(_db.weeks)..where((w) => w.pendingSync.equals(true)))
          .write(const WeeksCompanion(pendingSync: Value(false)));
    }
  }

  Future<void> _pushGoals(String userId) async {
    final rows =
        await (_db.select(_db.goals)..where((g) => g.pendingSync.equals(true)))
            .get();
    for (final g in rows) {
      await _supabase.client.from("goals").upsert({
        "id": g.id,
        "user_id": userId,
        "week_id": g.weekId,
        "title": g.title,
        "is_recurring": g.isRecurring,
        "recurrence_template_id": g.recurrenceTemplateId,
        "archived": g.archived,
        "created_at": g.createdAt.toIso8601String(),
        "updated_at": g.updatedAt.toIso8601String(),
      });
    }
    if (rows.isNotEmpty) {
      await (_db.update(_db.goals)..where((g) => g.pendingSync.equals(true)))
          .write(const GoalsCompanion(pendingSync: Value(false)));
    }
  }

  Future<void> _pushTodos(String userId) async {
    final rows =
        await (_db.select(_db.todos)..where((t) => t.pendingSync.equals(true)))
            .get();
    for (final t in rows) {
      await _supabase.client.from("todos").upsert({
        "id": t.id,
        "user_id": userId,
        "goal_id": t.goalId,
        "day_of_week": t.dayOfWeek,
        "state": t.state.name,
        "updated_at": t.updatedAt.toIso8601String(),
      });
    }
    if (rows.isNotEmpty) {
      await (_db.update(_db.todos)..where((t) => t.pendingSync.equals(true)))
          .write(const TodosCompanion(pendingSync: Value(false)));
    }
  }

  Future<void> _pushRecurrenceTemplates(String userId) async {
    final rows = await (_db.select(_db.recurrenceTemplates)
          ..where((t) => t.pendingSync.equals(true)))
        .get();
    for (final t in rows) {
      await _supabase.client.from("recurrence_templates").upsert({
        "id": t.id,
        "user_id": userId,
        "goal_title": t.goalTitle,
        "rule": t.rule,
        "custom_days": t.customDays,
        "biweekly_anchor": t.biweeklyAnchor,
        "active": t.active,
        "updated_at": t.updatedAt.toIso8601String(),
      });
    }
    if (rows.isNotEmpty) {
      await (_db.update(_db.recurrenceTemplates)
              ..where((t) => t.pendingSync.equals(true)))
          .write(const RecurrenceTemplatesCompanion(pendingSync: Value(false)));
    }
  }

  // ---- Pull (Supabase rows newer than last sync -> local, LWW by row) --

  Future<void> _pullWeeks(String userId, DateTime? since) async {
    var query = _supabase.client.from("weeks").select().eq("user_id", userId);
    if (since != null) query = query.gt("updated_at", since.toIso8601String());
    final remoteRows = await query;
    for (final r in remoteRows as List) {
      final remoteUpdatedAt = DateTime.parse(r["updated_at"] as String);
      final local = await (_db.select(_db.weeks)
            ..where((w) => w.id.equals(r["id"] as String)))
          .getSingleOrNull();
      if (local != null &&
          local.pendingSync &&
          local.updatedAt.isAfter(remoteUpdatedAt)) {
        continue; // unsynced local edit is newer — it will win on next push
      }
      await _db.into(_db.weeks).insertOnConflictUpdate(
            WeeksCompanion(
              id: Value(r["id"] as String),
              startDate: Value(r["start_date"] as String),
              completionPct: Value((r["completion_pct"] as num).toDouble()),
              reflectionText: Value(r["reflection_text"] as String? ?? ""),
              reflectionUpdatedAt: Value(r["reflection_updated_at"] == null
                  ? null
                  : DateTime.parse(r["reflection_updated_at"] as String)),
              updatedAt: Value(remoteUpdatedAt),
              pendingSync: const Value(false),
            ),
          );
    }
  }

  Future<void> _pullGoals(String userId, DateTime? since) async {
    var query = _supabase.client.from("goals").select().eq("user_id", userId);
    if (since != null) query = query.gt("updated_at", since.toIso8601String());
    final remoteRows = await query;
    for (final r in remoteRows as List) {
      final remoteUpdatedAt = DateTime.parse(r["updated_at"] as String);
      final local = await (_db.select(_db.goals)
            ..where((g) => g.id.equals(r["id"] as String)))
          .getSingleOrNull();
      if (local != null &&
          local.pendingSync &&
          local.updatedAt.isAfter(remoteUpdatedAt)) {
        continue;
      }
      await _db.into(_db.goals).insertOnConflictUpdate(
            GoalsCompanion(
              id: Value(r["id"] as String),
              weekId: Value(r["week_id"] as String),
              title: Value(r["title"] as String),
              isRecurring: Value(r["is_recurring"] as bool),
              recurrenceTemplateId:
                  Value(r["recurrence_template_id"] as String?),
              archived: Value(r["archived"] as bool),
              createdAt: Value(DateTime.parse(r["created_at"] as String)),
              updatedAt: Value(remoteUpdatedAt),
              pendingSync: const Value(false),
            ),
          );
    }
  }

  Future<void> _pullTodos(String userId, DateTime? since) async {
    var query = _supabase.client.from("todos").select().eq("user_id", userId);
    if (since != null) query = query.gt("updated_at", since.toIso8601String());
    final remoteRows = await query;
    for (final r in remoteRows as List) {
      final remoteUpdatedAt = DateTime.parse(r["updated_at"] as String);
      final local = await (_db.select(_db.todos)
            ..where((t) => t.id.equals(r["id"] as String)))
          .getSingleOrNull();
      if (local != null &&
          local.pendingSync &&
          local.updatedAt.isAfter(remoteUpdatedAt)) {
        continue;
      }
      await _db.into(_db.todos).insertOnConflictUpdate(
            TodosCompanion(
              id: Value(r["id"] as String),
              goalId: Value(r["goal_id"] as String),
              dayOfWeek: Value(r["day_of_week"] as int),
              state: Value(TodoState.values.byName(r["state"] as String)),
              updatedAt: Value(remoteUpdatedAt),
              pendingSync: const Value(false),
            ),
          );
    }
  }

  Future<void> _pullRecurrenceTemplates(String userId, DateTime? since) async {
    var query = _supabase.client
        .from("recurrence_templates")
        .select()
        .eq("user_id", userId);
    if (since != null) query = query.gt("updated_at", since.toIso8601String());
    final remoteRows = await query;
    for (final r in remoteRows as List) {
      final remoteUpdatedAt = DateTime.parse(r["updated_at"] as String);
      final local = await (_db.select(_db.recurrenceTemplates)
            ..where((t) => t.id.equals(r["id"] as String)))
          .getSingleOrNull();
      if (local != null &&
          local.pendingSync &&
          local.updatedAt.isAfter(remoteUpdatedAt)) {
        continue;
      }
      await _db.into(_db.recurrenceTemplates).insertOnConflictUpdate(
            RecurrenceTemplatesCompanion(
              id: Value(r["id"] as String),
              goalTitle: Value(r["goal_title"] as String),
              rule: Value(r["rule"] as String),
              customDays: Value(r["custom_days"] as String?),
              biweeklyAnchor: Value(r["biweekly_anchor"] as String?),
              active: Value(r["active"] as bool),
              updatedAt: Value(remoteUpdatedAt),
              pendingSync: const Value(false),
            ),
          );
    }
  }
}
