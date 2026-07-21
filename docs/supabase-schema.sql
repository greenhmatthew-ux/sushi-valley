create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  progress jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can read their own progress"
on public.profiles
for select
to authenticated
using (auth.uid() = id);

create policy "Users can insert their own progress"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

create policy "Users can update their own progress"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);
