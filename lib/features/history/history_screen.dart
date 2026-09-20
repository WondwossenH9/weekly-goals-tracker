import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";

import "../../core/week_utils.dart";
import "../../data/local/database.dart";
import "../../providers/providers.dart";
import "../summary/summary_screen.dart";
import "../sync/sync_status_indicator.dart";

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTimeRange? _range;
  double? _minCompletion;
  String? _goalQuery;

  bool get _hasActiveFilters =>
      _range != null || _minCompletion != null || (_goalQuery?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final weeksRepo = ref.watch(weeksRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        actions: [
          const SyncStatusIndicator(),
          IconButton(
            icon: Icon(_hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: "Filter",
            onPressed: _openFilters,
          ),
        ],
      ),
      body: StreamBuilder<List<Week>>(
        stream: weeksRepo.watchPastWeeks(
          fromDate: _range?.start,
          toDate: _range?.end,
          minCompletionPct: _minCompletion,
          goalTitleQuery: _goalQuery,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final weeks = snapshot.data!;
          if (weeks.isEmpty) {
            return Center(
              child: Text(_hasActiveFilters
                  ? "No weeks match those filters."
                  : "No past weeks yet."),
            );
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
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        initialRange: _range,
        initialMinCompletion: _minCompletion,
        initialGoalQuery: _goalQuery,
      ),
    );
    if (result == null) return;
    setState(() {
      _range = result.range;
      _minCompletion = result.minCompletion;
      _goalQuery = result.goalQuery;
    });
  }
}

class _FilterResult {
  const _FilterResult({this.range, this.minCompletion, this.goalQuery});
  final DateTimeRange? range;
  final double? minCompletion;
  final String? goalQuery;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialRange,
    required this.initialMinCompletion,
    required this.initialGoalQuery,
  });
  final DateTimeRange? initialRange;
  final double? initialMinCompletion;
  final String? initialGoalQuery;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DateTimeRange? _range = widget.initialRange;
  late double _minCompletion = widget.initialMinCompletion ?? 0;
  late final _goalController = TextEditingController(text: widget.initialGoalQuery ?? "");

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Filter history", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _goalController,
            decoration: const InputDecoration(
              labelText: "Goal name contains",
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null
                      ? "Any date"
                      : "${DateFormat.MMMd().format(_range!.start)} \u2013 "
                          "${DateFormat.MMMd().format(_range!.end)}"),
                  onPressed: _pickRange,
                ),
              ),
              if (_range != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: "Clear date range",
                  onPressed: () => setState(() => _range = null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text("Minimum completion: ${_minCompletion.round()}%"),
          Slider(
            value: _minCompletion,
            min: 0,
            max: 100,
            divisions: 20,
            label: "${_minCompletion.round()}%",
            onChanged: (v) => setState(() => _minCompletion = v),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(const _FilterResult()),
                child: const Text("Clear all"),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_FilterResult(
                  range: _range,
                  minCompletion: _minCompletion > 0 ? _minCompletion : null,
                  goalQuery: _goalController.text.trim().isEmpty
                      ? null
                      : _goalController.text.trim(),
                )),
                child: const Text("Apply"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
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
