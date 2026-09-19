import "package:drift/drift.dart";
import "package:uuid/uuid.dart";

import "../../core/week_utils.dart";
import "../local/database.dart";

class RecurrenceTemplatesRepository {
  RecurrenceTemplatesRepository(this._db);
  final AppDatabase _db;

  Stream<List<RecurrenceTemplate>> watchAll() {
    return (_db.select(_db.recurrenceTemplates)
          ..orderBy([(t) => OrderingTerm.asc(t.goalTitle)]))
        .watch();
  }

  /// Creates a new template. [rule] is one of "weekly", "biweekly",
  /// "custom". [customDays] (ISO weekdays, e.g. [1,3,5]) is required for
  /// "custom" and ignored otherwise. The biweekly anchor is always "this
  /// week" — i.e. a new biweekly goal starts counting from whichever week
  /// you create it in, not a week the user has to pick.
  Future<RecurrenceTemplate> create({
    required String goalTitle,
    required String rule,
    List<int>? customDays,
  }) {
    return _db.into(_db.recurrenceTemplates).insertReturning(
          RecurrenceTemplatesCompanion.insert(
            id: const Uuid().v4(),
            goalTitle: goalTitle,
            rule: rule,
            customDays: Value(
              rule == "custom" && customDays != null
                  ? customDays.join(",")
                  : null,
            ),
            biweeklyAnchor: Value(
              rule == "biweekly" ? WeekUtils.currentWeekStart() : null,
            ),
          ),
        );
  }

  /// Edits only affect weeks generated *after* this call — past weeks'
  /// Goal rows already exist and are never touched here.
  Future<void> update(
    String id, {
    String? goalTitle,
    String? rule,
    List<int>? customDays,
  }) {
    return (_db.update(_db.recurrenceTemplates)..where((t) => t.id.equals(id)))
        .write(RecurrenceTemplatesCompanion(
      goalTitle: goalTitle == null ? const Value.absent() : Value(goalTitle),
      rule: rule == null ? const Value.absent() : Value(rule),
      customDays: customDays == null
          ? const Value.absent()
          : Value(customDays.join(",")),
      updatedAt: Value(DateTime.now()),
      pendingSync: const Value(true),
    ));
  }

  Future<void> setActive(String id, bool active) {
    return (_db.update(_db.recurrenceTemplates)..where((t) => t.id.equals(id)))
        .write(RecurrenceTemplatesCompanion(
      active: Value(active),
      updatedAt: Value(DateTime.now()),
      pendingSync: const Value(true),
    ));
  }

  /// Deletes the template. Existing Goal rows that reference it keep
  /// their history (recurrence_template_id is set null via the table's
  /// onDelete: setNull) — deleting a template never deletes past goals.
  Future<void> delete(String id) {
    return (_db.delete(_db.recurrenceTemplates)..where((t) => t.id.equals(id)))
        .go();
  }
}
