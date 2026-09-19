import "package:drift/drift.dart";

import "../local/database.dart";
import "weeks_repository.dart";

class TodosRepository {
  TodosRepository(this._db, this._weeksRepository);
  final AppDatabase _db;
  final WeeksRepository _weeksRepository;

  Stream<List<TodoItem>> watchTodosForGoal(String goalId) {
    return (_db.select(_db.todos)
          ..where((t) => t.goalId.equals(goalId))
          ..orderBy([(t) => OrderingTerm.asc(t.dayOfWeek)]))
        .watch();
  }

  /// All todos for every goal in a week, keyed by goalId — this is what the
  /// weekly view screen renders as its day x goal grid.
  Future<Map<String, List<TodoItem>>> todosByGoalForWeek(
      List<String> goalIds) async {
    if (goalIds.isEmpty) return {};
    final rows = await (_db.select(_db.todos)
          ..where((t) => t.goalId.isIn(goalIds)))
        .get();
    final map = <String, List<TodoItem>>{};
    for (final row in rows) {
      map.putIfAbsent(row.goalId, () => []).add(row);
    }
    return map;
  }

  Future<void> ensureTodosForGoal(
    String goalId, {
    required List<int> daysOfWeek,
  }) async {
    final existing = await (_db.select(_db.todos)
          ..where((t) => t.goalId.equals(goalId)))
        .map((t) => t.dayOfWeek)
        .get();
    final missing = daysOfWeek.where((d) => !existing.contains(d));
    for (final day in missing) {
      await _db.into(_db.todos).insert(
            TodosCompanion.insert(goalId: goalId, dayOfWeek: day),
          );
    }
  }

  /// Cycles a todo through Not Done -> Ongoing -> Done -> Not Done, and
  /// keeps the parent weeks completion_pct in sync.
  Future<void> cycleState(TodoItem todo, String weekId) async {
    final next = switch (todo.state) {
      TodoState.notDone => TodoState.ongoing,
      TodoState.ongoing => TodoState.done,
      TodoState.done => TodoState.notDone,
    };
    await (_db.update(_db.todos)..where((t) => t.id.equals(todo.id))).write(
      TodosCompanion(
        state: Value(next),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ),
    );
    await _weeksRepository.recomputeCompletion(weekId);
  }
}
