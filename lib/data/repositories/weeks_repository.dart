import "package:drift/drift.dart";
import "package:sqlite3/sqlite3.dart";
import "package:uuid/uuid.dart";

import "../local/database.dart";
import "../../core/week_utils.dart";

class WeeksRepository {
  WeeksRepository(this._db);
  final AppDatabase _db;

  /// Fetches the week row for [weekStart], creating it if it does not
  /// exist yet (e.g. the first time the app is opened in a new week).
  ///
  /// This is a check-then-insert, which isn't atomic on its own — a
  /// unique index on weeks.start_date (see database.dart's migration)
  /// is what actually prevents two concurrent callers from creating
  /// duplicate rows for the same week. If that race does happen, the
  /// loser's insert fails with a constraint violation, which we catch
  /// below and turn into "fetch what the winner just created" instead
  /// of surfacing a raw database error.
  Future<Week> getOrCreateWeek(String weekStart) async {
    final existing = await _rowForWeek(weekStart);
    if (existing != null) return existing;

    try {
      return await _db.into(_db.weeks).insertReturning(
            WeeksCompanion.insert(id: const Uuid().v4(), startDate: weekStart),
          );
    } on SqliteException catch (_) {
      final row = await _rowForWeek(weekStart);
      if (row == null) rethrow; // genuinely unexpected — don't swallow it
      return row;
    }
  }

  /// Tolerant of more than one matching row (rather than throwing, as
  /// getSingleOrNull would) — belt-and-suspenders alongside the unique
  /// index in case any duplicate ever slips through, e.g. from data
  /// created before that index existed.
  Future<Week?> _rowForWeek(String weekStart) async {
    final rows = await (_db.select(_db.weeks)
          ..where((w) => w.startDate.equals(weekStart))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Stream<Week?> watchWeek(String weekStart) {
    return (_db.select(_db.weeks)
          ..where((w) => w.startDate.equals(weekStart)))
        .watchSingleOrNull();
  }

  Future<List<Week>> pastWeeks({
    DateTime? fromDate,
    DateTime? toDate,
    double? minCompletionPct,
  }) async {
    final query = _db.select(_db.weeks)
      ..orderBy([(w) => OrderingTerm.desc(w.startDate)]);
    final rows = await query.get();
    return rows.where((w) {
      final start = WeekUtils.parse(w.startDate);
      if (fromDate != null && start.isBefore(fromDate)) return false;
      if (toDate != null && start.isAfter(toDate)) return false;
      if (minCompletionPct != null && w.completionPct < minCompletionPct) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> saveReflection(String weekId, String text) async {
    await (_db.update(_db.weeks)..where((w) => w.id.equals(weekId))).write(
      WeeksCompanion(
        reflectionText: Value(text),
        reflectionUpdatedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
  }

  /// Recomputes and stores the weeks completion_pct from its todos.
  /// Call this after any todo state change for that week.
  Future<void> recomputeCompletion(String weekId) async {
    final goalIds = await (_db.select(_db.goals)
          ..where((g) => g.weekId.equals(weekId)))
        .map((g) => g.id)
        .get();
    if (goalIds.isEmpty) {
      await (_db.update(_db.weeks)..where((w) => w.id.equals(weekId)))
          .write(const WeeksCompanion(completionPct: Value(0)));
      return;
    }
    final todos = await (_db.select(_db.todos)
          ..where((t) => t.goalId.isIn(goalIds)))
        .get();
    if (todos.isEmpty) return;
    final done = todos.where((t) => t.state == TodoState.done).length;
    final pct = done / todos.length * 100;
    await (_db.update(_db.weeks)..where((w) => w.id.equals(weekId))).write(
      WeeksCompanion(
        completionPct: Value(pct),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
  }
}
