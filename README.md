# Weekly Goals Tracker

Offline-first weekly goals + daily todo tracker, built with Flutter (Android +
Linux desktop, shared codebase) and Supabase.

## What's in this repo right now

This is a complete, wired-together **starting codebase** — architecture,
local database, repositories, sync, notifications, and all four screens are
real, working Dart code. It was written without a Flutter/Dart toolchain
available (no compiler in the environment that generated it), so **you are
the first compiler it will meet.** Treat the first `flutter pub get` /
`flutter run` as step one, not a formality — read "Known gaps" below before
you start.

| Area | Status |
|---|---|
| Project scaffold, theme, adaptive nav shell | Done |
| Local DB (drift): goals, todos, weeks, recurrence templates, notification settings | Done |
| Repositories (CRUD + completion-% calculation) | Done |
| Weekly view, Summary, History, Settings screens | Done, actually verified running on Linux desktop |
| Goal management: create, rename, archive (+ restore), delete | Done |
| Recurring goals: engine + authoring UI (Settings > Manage recurring goals) | Done, not yet tested across a real week boundary |
| History: browse + filter by date range, completion %, and goal name | Done |
| Sync status indicator (☁️/⏳/⚠️) | Done, shows idle/synced until a real Supabase project is connected |
| Supabase schema + auth (magic link) + sync service | Code done, **not yet tested against a real project** |
| Notifications: daily nudge, weekly reflection, recurring setup — persisted + rescheduled on launch/resume | Code done, **not yet verified to actually fire** |
| `android/` platform folder, Android build | **Not started — deliberately deferred until desktop is fully hardened** |
| Tests | Not written |

## Known gaps / things to double-check first

- **Per-row, not per-field, last-write-wins.** The sync conflict rule
  compares each row's `updated_at`. If you edit a goal's title on your phone
  and its `archived` flag on desktop while both are offline, whichever
  device syncs its full row second wins outright — the other edit is lost.
  True per-field merging needs per-field timestamps or a CRDT approach; that
  was a deliberate scope cut, not an oversight. Fine for a single-user app
  that's rarely offline on two devices at once; worth hardening if that
  changes.
- **Device timezone is hardcoded to `Africa/Addis_Ababa`** in
  `notification_service.dart` (`_deviceTimeZoneName()`) — correct for
  Ethiopia, but a fixed default rather than autodetected. If the app ever
  needs to follow the device instead (travel, a second user elsewhere), add
  the `flutter_timezone` package and read the real IANA zone there instead.
- **Quick-add (the "Add goal" sheet on the Weekly view) only creates plain,
  one-off goals.** Recurring goals are authored from Settings > Manage
  recurring goals, which both creates the template and immediately
  materializes it into the current week — there's no "make this existing
  goal recurring after the fact" shortcut yet; delete and recreate it as a
  template instead.
- Nothing has been run through `flutter analyze` or a real compiler. Expect
  a handful of small fixes (an import order, a nullable that needs a `!`)
  on the first build — normal for hand-written code that hasn't touched a
  toolchain yet, but budget an hour for it, not zero.

## If you built this before schemaVersion 3

An early version had a real startup race: on desktop, Flutter can fire an
initial `AppLifecycleState.resumed` callback before first-time
initialization finishes, and two concurrent calls to
`ensureCurrentWeekIsPopulated()` could both decide "no row for this week
yet" and both insert one — leaving two `Week` rows with the same
`start_date`. Every later lookup by date then throws `Bad state: too many
elements`, which breaks goal creation, the weekly view, and the Summary
screen all at once (that's one bug, not three). Fixed by: a guard so the
lifecycle callback can't run before initialization completes, a unique
index on `weeks.start_date` as a DB-level backstop, and a local sqlite
path fix (`getApplicationSupportDirectory()` instead of
`getApplicationDocumentsDirectory()`, which was dropping the db file in
your visible `~/Documents` rather than a private app-data folder).

None of this retroactively fixes duplicate rows already sitting in a local
database from before this fix. If you ran the app before pulling this
change, delete the old database file once, then rebuild:

```bash
find ~ -iname "weekly_goals_tracker.sqlite*" -delete
flutter run -d linux
```

## If Summary looked frozen at 0% after toggling todos

Separate bug, same debugging session: `currentWeekProvider` was a one-shot
`FutureProvider` — fetched the `Week` row exactly once and cached it
forever, even though toggling a todo updates `completion_pct` in the
database on every tap. The day chips still worked because they're on
their own live stream watching the `todos` table directly; nothing wired
Summary's ring, per-goal bars, or per-day chart up the same way — they
either read that stale one-shot value, or (for the per-goal/per-day
breakdown) used a plain one-shot `Future` inside a `FutureBuilder` that
never re-ran on its own. Fixed by making `currentWeekProvider` a
`StreamProvider` that watches the DB reactively, and adding
`TodosRepository.watchTodosByGoalForWeek()` (a live stream) in place of
the old one-shot `todosByGoalForWeek()`, which has been removed entirely
rather than left around for something else to accidentally call again.
No schema change here — just `git pull` and rebuild, no need to clear
local data for this one.

## 1. Local setup

```bash
# Install Flutter (if you haven't): https://docs.flutter.dev/get-started/install/linux
flutter doctor

cd weekly_goals_tracker

# Generate the android/ and linux/ platform folders — these aren't
# included in this drop since they're toolchain-generated boilerplate,
# not hand-written source.
flutter create --platforms=android,linux .

# Get packages
flutter pub get

# Generate drift's *.g.dart and any riverpod codegen
dart run build_runner build --delete-conflicting-outputs

cp .env.example .env
# then edit .env with your Supabase project's URL + anon key
```

## 2. Supabase project setup

1. Create a project at supabase.com.
2. In the SQL editor, run `supabase/schema.sql` from this repo.
3. Auth -> Providers -> Email: enable, and turn OFF "Confirm email" if you
   want magic-link sign-in to work without an extra confirmation step.
4. Auth -> URL Configuration: add `io.supabase.weeklygoals://login-callback/`
   as a redirect URL (this must also be registered in
   `android/app/src/main/AndroidManifest.xml` as an intent filter once that
   folder exists — see Supabase Flutter's deep-link setup docs for the exact
   manifest snippet, since it's a few lines of platform-specific XML rather
   than Dart).
5. Copy the Project URL and anon public key into your `.env`.

## 3. Build instructions

**Android** (target: Samsung Galaxy A53, Android 16 / One UI 8.0):
```bash
flutter build apk --release
# or, with a device connected / emulator running:
flutter run -d android
```

**Linux desktop** (target: Ubuntu 26.04 LTS):
```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
flutter build linux --release
# binary lands in build/linux/x64/release/bundle/
flutter run -d linux
```

## 4. Sync architecture

- **Local SQLite (via drift) is the source of truth on-device**, always.
  Every write (toggle a todo, edit a reflection, add a goal) lands in
  SQLite first and immediately updates the UI — the app is fully usable
  with no network at all.
- Every syncable table has a `pendingSync` flag and an `updatedAt`
  timestamp. `SyncService.sync()`, called on app start, on resume, and
  whenever `connectivity_plus` reports the device came back online:
  1. **Push**: upserts every row with `pendingSync = true` to Supabase,
     then clears the flag.
  2. **Pull**: fetches remote rows updated since the last successful sync,
     and applies each one locally — *unless* the local row is itself
     pending with a newer `updatedAt`, in which case the local edit is left
     alone (it'll win on the next push).
- Conflicts are resolved **per row** (see "Known gaps" above).
- The sync indicator (☁️ / ⏳ / ⚠️) described in the spec maps directly onto
  `SyncStatus` in `sync_service.dart` — wire a small `StreamProvider` around
  `SyncService.sync()`'s return value to drive it in the app bar; that
  plumbing wasn't added yet since it's pure UI wiring once the enum exists.

## 5. Notifications

`NotificationService` wraps `flutter_local_notifications` with three
independently toggleable schedules — daily nudge, end-of-week reflection,
and a new-week recurring-goals reminder — each stored as its own
notification ID so toggling one off never touches the others. All three
preferences (on/off, day, time) persist in the local `NotificationSettings`
table (single row, local-only — never synced, since reminder times are a
per-device thing) and are re-applied via `rescheduleFromSettings()` on
every app start and resume, so they survive an app restart and a device
reboot without the user having to re-toggle anything. Android 13+'s runtime
notification permission is requested on init; Do Not Disturb is respected
automatically by the OS for `Importance.defaultImportance` notifications;
bump to `Importance.high` only if you decide DND should be bypassed, which
the spec doesn't ask for.

## 6. Recurring goals

`RecurrenceEngine` (consumer) and `RecurringTemplatesScreen` (author) are
both wired up:

- **Settings > Manage recurring goals** lists every template, lets you
  create one (title + Weekly / Biweekly / Custom-days), edit it, pause it
  with the switch, or delete it.
- Creating a template immediately calls
  `RecurrenceEngine.ensureCurrentWeekIsPopulated()` so it shows up in the
  current week's Weekly view right away, not just from next week onward.
- Editing a template's title/rule only affects weeks generated *after* the
  edit — a week's `Goal` row is a snapshot taken at generation time and is
  never rewritten by a later template edit.
- Deleting a template does not delete goals already generated from it; the
  historical `Goal` rows just lose their `recurrence_template_id` link
  (`onDelete: setNull`), so past weeks keep their history.

## 7. Tech stack (as specified)

Flutter was chosen for one codebase across Android and Linux desktop
without a from-scratch native rewrite per platform. Material 3 (adaptive)
gives a look consistent with One UI on the phone while allowing a proper
sidebar layout on desktop from the same widget tree. drift/SQLite is the
offline-first local store since it's a real relational DB with reactive
streams, not just a key-value cache. Supabase supplies Postgres + Auth +
Realtime without standing up custom backend infrastructure for a
single-user app. Riverpod keeps the data layer testable and avoids
`InheritedWidget` boilerplate as features grow.

## 8. Pushing to GitHub

```bash
git init
git add -A
git commit -m "Initial scaffold: local DB, sync, notifications, recurring goals UI"
git branch -M main
git remote add origin https://github.com/wondwossenh9/weekly-goals-tracker.git
git push -u origin main
```

Note: the `weekly-goals-tracker` repo needs to already exist (empty) on
GitHub before this push works — create it at github.com/new first (no
description or README needed, this repo brings its own).

## Desktop hardening checklist (before Android)

Everything code-level against the original spec is now implemented,
including a couple of gaps found by re-reading the spec against the code
rather than just testing the happy path (goal rename/archive/delete had
repository methods but no UI at all; the History screen's completion-%
and goal-name filters were the same story; the ☁️/⏳/⚠️ sync indicator
didn't exist anywhere). What's left is testing, not building:

1. **Recurring goals across a real week boundary.** Everything so far has
   only been exercised within a single calendar week. To actually verify
   a template regenerates correctly next week (and that a biweekly
   template correctly skips the *following* week), you need either to
   wait, or to simulate it — temporarily disable NTP and move the system
   clock forward (`sudo timedatectl set-ntp false && sudo date -s
   "next monday 09:00"`), relaunch the app, check the new week populated
   correctly, then `sudo timedatectl set-ntp true` to resync.
2. **History with real historical data.** The same clock trick above is
   also the fastest way to generate actual past weeks to browse and
   filter, rather than looking at an empty History screen.
3. **A real Supabase project.** Follow "2. Supabase project setup" below,
   then sign in from Settings and confirm: the sync indicator moves
   through ⏳ pending -> ☁️ synced, data actually lands in the Supabase
   dashboard, and (ideally) a second local sqlite file signed into the
   same account pulls it back down.
4. **Notifications actually firing.** Set a reminder a minute or two in
   the future from Settings and confirm it appears — the scheduling code
   has never been run against the real OS notification system.

## Suggested next steps (lower priority / polish)

1. Add `flutter_timezone` if the app should ever autodetect timezone
   instead of the current fixed Ethiopia default.
2. Desktop layout polish pass (the adaptive shell is functional, not
   pixel-tuned).
3. Consider a "make this goal recurring" action on an existing plain goal
   in the Weekly view, if the current "author it in Settings first" flow
   feels like one extra step in practice.
4. `WeeksRepository.watchPastWeeks()`'s goal-name filter isn't reactive to
   a goal being renamed after the fact (see its doc comment) — acceptable
   for now, revisit if it's ever noticeable in practice.
