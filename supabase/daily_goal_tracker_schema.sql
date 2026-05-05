create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  category text not null check (length(trim(category)) > 0),
  platform text not null check (length(trim(platform)) > 0),
  section text,
  topic text,
  target text not null check (length(trim(target)) > 0),
  estimated_time text,
  priority text not null default 'Medium' check (priority in ('Low', 'Medium', 'High')),
  active boolean not null default true,
  repeat_daily boolean not null default true,
  sort_order integer not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

create index if not exists idx_tasks_owner_active_sort on public.tasks(owner_id, active, sort_order, category, title);
create index if not exists idx_tasks_owner on public.tasks(owner_id);

create table if not exists public.daily_status (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete restrict,
  day_date date not null,
  completed boolean not null default false,
  submitted_at timestamptz not null default now(),
  task_title_snapshot text,
  category_snapshot text,
  platform_snapshot text,
  section_snapshot text,
  target_snapshot text,
  priority_snapshot text,
  estimated_time_snapshot text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_status_unique_owner_day_task unique(owner_id, day_date, task_id)
);

drop trigger if exists daily_status_set_updated_at on public.daily_status;
create trigger daily_status_set_updated_at
before update on public.daily_status
for each row execute function public.set_updated_at();

create index if not exists idx_daily_status_owner_date on public.daily_status(owner_id, day_date);
create index if not exists idx_daily_status_owner_task on public.daily_status(owner_id, task_id);

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  day_date date,
  action text not null check (length(trim(action)) > 0),
  task_id uuid references public.tasks(id) on delete set null,
  task_title text,
  category text,
  platform text,
  details text,
  created_at timestamptz not null default now()
);

create index if not exists idx_activity_log_owner_created on public.activity_log(owner_id, created_at desc);
create index if not exists idx_activity_log_owner_day on public.activity_log(owner_id, day_date);

alter table public.tasks enable row level security;
alter table public.daily_status enable row level security;
alter table public.activity_log enable row level security;

drop policy if exists tasks_select_own on public.tasks;
drop policy if exists tasks_insert_own on public.tasks;
drop policy if exists tasks_update_own on public.tasks;
drop policy if exists tasks_delete_own on public.tasks;
create policy tasks_select_own on public.tasks for select using (owner_id = auth.uid());
create policy tasks_insert_own on public.tasks for insert with check (owner_id = auth.uid());
create policy tasks_update_own on public.tasks for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy tasks_delete_own on public.tasks for delete using (owner_id = auth.uid());

drop policy if exists daily_status_select_own on public.daily_status;
drop policy if exists daily_status_insert_own on public.daily_status;
drop policy if exists daily_status_update_own on public.daily_status;
drop policy if exists daily_status_delete_own on public.daily_status;
create policy daily_status_select_own on public.daily_status for select using (owner_id = auth.uid());
create policy daily_status_insert_own on public.daily_status for insert with check (
  owner_id = auth.uid()
  and exists (select 1 from public.tasks t where t.id = daily_status.task_id and t.owner_id = auth.uid())
);
create policy daily_status_update_own on public.daily_status for update using (owner_id = auth.uid()) with check (
  owner_id = auth.uid()
  and exists (select 1 from public.tasks t where t.id = daily_status.task_id and t.owner_id = auth.uid())
);
create policy daily_status_delete_own on public.daily_status for delete using (owner_id = auth.uid());

drop policy if exists activity_log_select_own on public.activity_log;
drop policy if exists activity_log_insert_own on public.activity_log;
drop policy if exists activity_log_update_own on public.activity_log;
drop policy if exists activity_log_delete_own on public.activity_log;
create policy activity_log_select_own on public.activity_log for select using (owner_id = auth.uid());
create policy activity_log_insert_own on public.activity_log for insert with check (owner_id = auth.uid());
create policy activity_log_update_own on public.activity_log for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy activity_log_delete_own on public.activity_log for delete using (owner_id = auth.uid());
