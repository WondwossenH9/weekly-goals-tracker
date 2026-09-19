import "package:drift/drift.dart";

import "../local/database.dart";

class GoalsRepository {
  GoalsRepository(this._db);
  final AppDatabase _db;

  Stream<List<Goal>> watchGoalsForWeek(String weekId) {
    return (_db.select(_db.goals)
          ..where((g) => g.weekId.equals(weekId) & g.archived.equals(false))
          ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
        .watch();
  }

  Future<Goal> createGoal({
    required String weekId,
    required String title,
    bool isRecurring = false,
    String? recurrenceTemplateId,
  }) {
    return _db.into(_db.goals).insertReturning(
          GoalsCompanion.insert(
            weekId: weekId,
            title: title,
            isRecurring: Value(isRecurring),
            recurrenceTemplateId: Value(recurrenceTemplateId),
          ),
        );
  }

  Future<void> renameGoal(String goalId, String title) {
    return (_db.update(_db.goals)..where((g) => g.id.equals(goalId))).write(
      GoalsCompanion(
        title: Value(title),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
  }

  Future<void> archiveGoal(String goalId) {
    return (_db.update(_db.goals)..where((g) => g.id.equals(goalId))).write(
      GoalsCompanion(
        archived: const Value(true),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
  }

  Future<void> deleteGoal(String goalId) {
    return (_db.delete(_db.goals)..where((g) => g.id.equals(goalId))).go();
  }
}
