import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";

import "../../core/week_utils.dart";
import "../../data/local/database.dart";
import "../../providers/providers.dart";
import "../summary/summary_screen.dart";

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTimeRange? _range;
  double? _minCompletion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: FutureBuilder<List<Week>>(
        future: ref.read(weeksRepositoryProvider).pastWeeks(
              fromDate: _range?.start,
              toDate: _range?.end,
              minCompletionPct: _minCompletion,
            ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final weeks = snapshot.data!;
          if (weeks.isEmpty) {
            return const Center(child: Text("No weeks match those filters."));
          }
          return ListView.builder(
            itemCount: weeks.length,
            itemBuilder: (context, i) {
              final week = weeks[i];
              final start = WeekUtils.parse(week.startDate);
              return ListTile(
                title: Text(
                  "Week of ${DateFormat.MMMd().format(start)}",
                ),
                subtitle: week.reflectionText.isNotEmpty
                    ? Text(week.reflectionText, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Text("${week.completionPct.round()}%"),
                onTap: () async {
                  // Point the shared "selected week" provider at this past
                  // week for the duration of the pushed screen, then reset
                  // it back to the real current week on return so the
                  // Weekly/Summary tabs don't stay stuck on a past week.
                  ref.read(selectedWeekStartProvider.notifier).state =
                      week.startDate;
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SummaryScreen()),
                  );
                  ref.read(selectedWeekStartProvider.notifier).state =
                      WeekUtils.currentWeekStart();
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openFilters() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }
}
