import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/local/database.dart";
import "../../providers/providers.dart";
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
          weekAsync.maybeWhen(
            data: (week) => Padding(
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
      final week = await ref.read(currentWeekProvider.future);
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
                              final week = await ref.read(currentWeekProvider.future);
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
