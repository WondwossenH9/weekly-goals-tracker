import "package:drift/drift.dart";

import "../../core/week_utils.dart";
import "../../data/local/database.dart";
import "../../data/repositories/goals_repository.dart";
import "../../data/repositories/todos_repository.dart";
import "../../data/repositories/weeks_repository.dart";

/// Generates each new weeks recurring goals (and their todos) from the
/// active [RecurrenceTemplates]. Call [ensureCurrentWeekIsPopulated] once
/// on app start (and again after midnight-rollover / resume-from-background)
/// so a new week always has its recurring goals ready without the user
/// doing anything.
///
/// Editing a template only ever affects future calls to this method — past
/// weeks rows are untouched, matching the "future weeks only" requirement.
class RecurrenceEngine {
  RecurrenceEngine(
    this._db,
    this._weeksRepository,
    this._goalsRepository,
    this._todosRepository,
  );

  final AppDatabase _db;
  final WeeksRepository _weeksRepository;
  final GoalsRepository _goalsRepository;
  final TodosRepository _todosRepository;

  Future<void> ensureCurrentWeekIsPopulated() =>
      ensureWeekIsPopulated(WeekUtils.currentWeekStart());

  /// Does the actual work, for whatever [weekStart] you give it — normal
  /// app operation always calls this via [ensureCurrentWeekIsPopulated]
  /// above, but taking the week as a parameter (rather than hardcoding
  /// "today") is also what lets the debug "jump to week" tool in Settings
  /// exercise this exact logic against an arbitrary past or future week,
  /// without needing to touch the system clock to test it.
  Future<void> ensureWeekIsPopulated(String weekStart) async {
    final week = await _weeksRepository.getOrCreateWeek(weekStart);

    final templates = await (_db.select(_db.recurrenceTemplates)
          ..where((t) => t.active.equals(true)))
        .get();

    for (final template in templates) {
      if (!_appliesToWeek(template, weekStart)) continue;

      final existing = await (_db.select(_db.goals)
            ..where((g) =>
                g.weekId.equals(week.id) &
                g.recurrenceTemplateId.equals(template.id))
            ..limit(1))
          .get();
      if (existing.isNotEmpty) continue;

      final goal = await _goalsRepository.createGoal(
        weekId: week.id,
        title: template.goalTitle,
        isRecurring: true,
        recurrenceTemplateId: template.id,
      );
      await _todosRepository.ensureTodosForGoal(
        goal.id,
        daysOfWeek: _daysForTemplate(template),
      );
    }
  }

  bool _appliesToWeek(RecurrenceTemplate template, String weekStart) {
    switch (template.rule) {
      case "weekly":
        return true;
      case "biweekly":
        final anchor = template.biweeklyAnchor;
        if (anchor == null) return true;
        final delta = WeekUtils.weeksBetween(anchor, weekStart);
        return delta >= 0 && delta.isEven;
      case "custom":
        // Custom-day templates still get a goal every week; the days
        // themselves are what is restricted (see _daysForTemplate).
        return true;
      default:
        return false;
    }
  }

  List<int> _daysForTemplate(RecurrenceTemplate template) {
    if (template.rule == "custom" && template.customDays != null) {
      return template.customDays!
          .split(",")
          .where((s) => s.trim().isNotEmpty)
          .map(int.parse)
          .toList();
    }
    // weekly / biweekly default to every day of the week; the user can
    // still toggle individual days off from the weekly view.
    return const [1, 2, 3, 4, 5, 6, 7];
  }
}
