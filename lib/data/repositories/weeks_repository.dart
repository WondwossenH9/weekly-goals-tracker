import "package:drift/drift.dart";

import "../local/database.dart";
import "../../core/week_utils.dart";

class WeeksRepository {
  WeeksRepository(this._db);
  final AppDatabase _db;

  /// Fetches the week row for [weekStart], creating it if it does not
  /// exist yet (e.g. the first time the app is opened in a new week).
  Future<Week> getOrCreateWeek(String weekStart) async {
    final existing = await (_db.select(_db.weeks)
          ..where((w) => w.startDate.equals(weekStart)))
        .getSingleOrNull();
    if (existing != null) return existing;

    final id = await _db.into(_db.weeks).insertReturning(
          WeeksCompanion.insert(startDate: weekStart),
        );
    return id;
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
