import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/local/database.dart";
import "../../providers/providers.dart";
import "../sync/sync_status_indicator.dart";
import "widgets/todo_tile.dart";

class WeeklyViewScreen extends ConsumerWidget {
  const WeeklyViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekAsync = ref.watch(currentWeekProvider);
    final goalsAsync = ref.watch(goalsForCurrentWeekProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("This Week"),
        actions: [
          const SyncStatusIndicator(),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: "Archived goals",
            onPressed: () => _showArchivedGoals(context, ref),
          ),
          weekAsync.maybeWhen(
            data: (week) => week == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(
                      child: Text("${week.completionPct.round()}%",
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: goalsAsync.when(
        data: (goals) {
          if (goals.isEmpty) {
            return const _EmptyWeek();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: goals.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _GoalRow(goal: goals[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn\u2019t load this week: $e")),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddGoalSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text("Add goal"),
      ),
    );
  }

  void _showAddGoalSheet(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: "Goal title"),
                onSubmitted: (_) => _submit(ctx, ref, controller.text),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => _submit(ctx, ref, controller.text),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
      BuildContext context, WidgetRef ref, String title) async {
    if (title.trim().isEmpty) return;
    try {
      final week = await resolveCurrentWeek(ref);
      final goal = await ref
          .read(goalsRepositoryProvider)
          .createGoal(weekId: week.id, title: title.trim());
      await ref
          .read(todosRepositoryProvider)
          .ensureTodosForGoal(goal.id, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7]);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      // Surface failures instead of letting the sheet just sit there with
      // no feedback — this exact silence is what made the startup race
      // bug hard to diagnose from the UI alone.
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn\u2019t add goal: $e")));
      }
    }
  }

  Future<void> _showArchivedGoals(BuildContext context, WidgetRef ref) async {
    final week = await resolveCurrentWeek(ref);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ArchivedGoalsSheet(weekId: week.id),
    );
  }
}

class _GoalRow extends ConsumerWidget {
  const _GoalRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosRepo = ref.watch(todosRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (goal.isRecurring)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.repeat, size: 16),
                  ),
                Expanded(
                  child: Text(goal.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                PopupMenuButton<_GoalAction>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (action) => _handleAction(context, ref, action),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _GoalAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text("Rename"),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GoalAction.archive,
                      child: ListTile(
                        leading: Icon(Icons.archive_outlined),
                        title: Text("Archive"),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _GoalAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text("Delete"),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<TodoItem>>(
              stream: todosRepo.watchTodosForGoal(goal.id),
              builder: (context, snapshot) {
                final todos = snapshot.data ?? const <TodoItem>[];
                final byDay = {for (final t in todos) t.dayOfWeek: t};
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var day = 1; day <= 7; day++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TodoTile(
                            dayOfWeek: day,
                            todo: byDay[day],
                            onTap: () async {
                              final week = await resolveCurrentWeek(ref);
                              await todosRepo.cycleState(byDay[day]!, week.id);
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, _GoalAction action) async {
    switch (action) {
      case _GoalAction.rename:
        await _rename(context, ref);
      case _GoalAction.archive:
        await _archive(context, ref);
      case _GoalAction.delete:
        await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: goal.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename goal"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && newTitle != goal.title) {
      await ref.read(goalsRepositoryProvider).renameGoal(goal.id, newTitle);
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    await ref.read(goalsRepositoryProvider).archiveGoal(goal.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Archived \u201c${goal.title}\u201d"),
          action: SnackBarAction(
            label: "Undo",
            onPressed: () =>
                ref.read(goalsRepositoryProvider).unarchiveGoal(goal.id),
          ),
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete goal?"),
        content: Text(
          "\u201c${goal.title}\u201d and all its todos for this week will be "
          "permanently deleted. This can\u2019t be undone.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(goalsRepositoryProvider).deleteGoal(goal.id);
    }
  }
}

enum _GoalAction { rename, archive, delete }

class _ArchivedGoalsSheet extends ConsumerWidget {
  const _ArchivedGoalsSheet({required this.weekId});
  final String weekId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsRepo = ref.watch(goalsRepositoryProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Archived this week",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            StreamBuilder<List<Goal>>(
              stream: goalsRepo.watchArchivedGoalsForWeek(weekId),
              builder: (context, snapshot) {
                final archived = snapshot.data ?? const <Goal>[];
                if (archived.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text("No archived goals this week."),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: archived.length,
                  itemBuilder: (context, i) {
                    final goal = archived[i];
                    return ListTile(
                      title: Text(goal.title),
                      trailing: TextButton(
                        onPressed: () => goalsRepo.unarchiveGoal(goal.id),
                        child: const Text("Restore"),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text("No goals yet this week",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              "Tap \u201cAdd goal\u201d to break your week into daily todos.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
