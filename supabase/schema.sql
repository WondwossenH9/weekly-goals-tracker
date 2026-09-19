-- Weekly Goals Tracker — Supabase schema
-- Mirrors the local drift tables 1:1 so the sync layer can upsert row-for-row.
-- Run this in the Supabase SQL editor (or via `supabase db push`) on a fresh project.

create table if not exists public.weeks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_date date not null,
  completion_pct double precision not null default 0,
  reflection_text text not null default '',
  reflection_updated_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, start_date)
);

create table if not exists public.recurrence_templates (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_title text not null,
  rule text not null check (rule in ('weekly', 'biweekly', 'custom')),
  custom_days text,
  biweekly_anchor date,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.goals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  week_id uuid not null references public.weeks(id) on delete cascade,
  title text not null,
  is_recurring boolean not null default false,
  recurrence_template_id uuid references public.recurrence_templates(id) on delete set null,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.todos (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid not null references public.goals(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 1 and 7),
  state text not null default 'notDone' check (state in ('done', 'ongoing', 'notDone')),
  updated_at timestamptz not null default now()
);

create index if not exists goals_week_id_idx on public.goals(week_id);
create index if not exists todos_goal_id_idx on public.todos(goal_id);
create index if not exists weeks_updated_at_idx on public.weeks(user_id, updated_at);
create index if not exists goals_updated_at_idx on public.goals(user_id, updated_at);
create index if not exists todos_updated_at_idx on public.todos(user_id, updated_at);

-- Single-user app, but every table is still scoped with RLS by user_id so
-- the same Supabase project could safely host more than one person later.
alter table public.weeks enable row level security;
alter table public.recurrence_templates enable row level security;
alter table public.goals enable row level security;
alter table public.todos enable row level security;

create policy "weeks_owner" on public.weeks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "recurrence_templates_owner" on public.recurrence_templates
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "goals_owner" on public.goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "todos_owner" on public.todos
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
