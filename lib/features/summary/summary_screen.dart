import "package:fl_chart/fl_chart.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/week_utils.dart";
import "../../data/local/database.dart";
import "../../providers/providers.dart";
import "../reflection/reflection_field.dart";

/// End-of-week summary: overall %, per-goal %, per-day %, plus the
/// reflection field. Also reachable "anytime" (not just at week end) per
/// the spec — it just always reflects whatever week is selected.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekAsync = ref.watch(currentWeekProvider);
    final goalsAsync = ref.watch(goalsForCurrentWeekProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Week Summary")),
      body: weekAsync.when(
        data: (week) => week == null
            ? const Center(child: CircularProgressIndicator())
            : goalsAsync.when(
                data: (goals) => _SummaryBody(week: week, goals: goals),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text("$e")),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("$e")),
      ),
    );
  }
}

class _SummaryBody extends ConsumerWidget {
  const _SummaryBody({required this.week, required this.goals});
  final Week week;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosRepo = ref.watch(todosRepositoryProvider);

    return StreamBuilder<Map<String, List<TodoItem>>>(
      stream: todosRepo.watchTodosByGoalForWeek(goals.map((g) => g.id).toList()),
      builder: (context, snapshot) {
        final byGoal = snapshot.data ?? {};
        final allTodos = byGoal.values.expand((t) => t).toList();

        final perDay = <int, List<TodoItem>>{
          for (var d = 1; d <= 7; d++)
            d: allTodos.where((t) => t.dayOfWeek == d).toList(),
        };

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        startDegreeOffset: -90,
                        sectionsSpace: 0,
                        centerSpaceRadius: 60,
                        sections: [
                          PieChartSectionData(
                            value: week.completionPct,
                            color: Theme.of(context).colorScheme.primary,
                            showTitle: false,
                            radius: 18,
                          ),
                          PieChartSectionData(
                            value: 100 - week.completionPct,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            showTitle: false,
                            radius: 18,
                          ),
                        ],
                      ),
                    ),
                    Text("${week.completionPct.round()}%",
                        style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text("By goal", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final goal in goals)
              _GoalCompletionBar(
                title: goal.title,
                todos: byGoal[goal.id] ?? const [],
              ),
            const SizedBox(height: 24),
            Text("By day", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) => Text(
                          WeekUtils.dayLabel(value.toInt() + 1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var d = 1; d <= 7; d++)
                      BarChartGroupData(x: d - 1, barRods: [
                        BarChartRodData(
                          toY: _pct(perDay[d] ?? const []),
                          width: 18,
                          borderRadius: BorderRadius.circular(4),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text("Reflection", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ReflectionField(week: week),
          ],
        );
      },
    );
  }

  double _pct(List<TodoItem> todos) {
    if (todos.isEmpty) return 0;
    final done = todos.where((t) => t.state == TodoState.done).length;
    return done / todos.length * 100;
  }
}

class _GoalCompletionBar extends StatelessWidget {
  const _GoalCompletionBar({required this.title, required this.todos});
  final String title;
  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    final pct = todos.isEmpty
        ? 0.0
        : todos.where((t) => t.state == TodoState.done).length /
            todos.length *
            100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
              Text("${pct.round()}%"),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 8),
          ),
        ],
      ),
    );
  }
}
