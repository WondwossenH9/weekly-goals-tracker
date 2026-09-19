import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/theme/app_theme.dart";
import "features/history/history_screen.dart";
import "features/settings/settings_screen.dart";
import "features/summary/summary_screen.dart";
import "features/weekly_view/weekly_view_screen.dart";
import "providers/providers.dart";

class WeeklyGoalsApp extends ConsumerWidget {
  const WeeklyGoalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: "Weekly Goals",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _StartupGate(),
    );
  }
}

/// Makes sure this weeks recurring goals exist *before* showing any UI, so
/// the weekly view never flashes an empty state that then repopulates.
class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate();

  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate>
    with WidgetsBindingObserver {
  late final Future<void> _ready = _initialize();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on resume in case the app was left open across a week
    // boundary (e.g. left running overnight Sun -> Mon), and reschedule
    // notifications in case the OS dropped them (e.g. after a reboot).
    if (state == AppLifecycleState.resumed) {
      ref.read(recurrenceEngineProvider).ensureCurrentWeekIsPopulated();
      ref.read(syncServiceProvider).sync();
      _rescheduleNotifications();
    }
  }

  Future<void> _rescheduleNotifications() async {
    final settings = await ref.read(notificationSettingsRepositoryProvider).get();
    final service = await ref.read(notificationServiceProvider.future);
    await service.rescheduleFromSettings(settings);
  }

  Future<void> _initialize() async {
    await ref.read(recurrenceEngineProvider).ensureCurrentWeekIsPopulated();
    await _rescheduleNotifications();
    // Fire-and-forget: sync should never block first paint, and should
    // never crash startup if the device is offline.
    unawaited(ref.read(syncServiceProvider).sync());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return const _RootShell();
      },
    );
  }
}

void unawaited(Future<void> future) {}

/// Adaptive nav shell: bottom NavigationBar on phones, a side
/// NavigationRail on wide (desktop) windows — same three-tab structure
/// either way, per the shared-codebase / Material-You-adaptive requirement.
class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  static const _screens = [
    WeeklyViewScreen(),
    SummaryScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.checklist), label: "Week"),
    NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: "Summary"),
    NavigationDestination(icon: Icon(Icons.history), label: "History"),
    NavigationDestination(icon: Icon(Icons.settings_outlined), label: "Settings"),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                      icon: d.icon, label: Text(d.label)))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: IndexedStack(index: _index, children: _screens)),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}
