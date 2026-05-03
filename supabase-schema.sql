-- ==========================================
-- 🗄️ SUPABASE SCHEMA (v2.0 - Fixed)
-- Сохрани как supabase-schema.sql в репозиторий GitHub
-- Выполняй в Supabase → SQL Editor → Run
-- ==========================================

-- 1. РАСШИРЕНИЯ
create extension if not exists "uuid-ossp";

-- 2. ТАБЛИЦА ПРОФИЛЕЙ
create table if not exists profiles (
    id uuid references auth.users on delete cascade primary key,
    email text unique,
    full_name text,
    role text check (role in ('user', 'cadet', 'staff', 'deputy_head', 'head', 'moderator')) default 'user',
    registration_date timestamptz default now(),
    is_active boolean default true,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Гарантируем наличие колонки username (безопасно при повторном запуске)
alter table profiles add column if not exists username text;
alter table profiles drop constraint if exists profiles_username_key;
alter table profiles add constraint profiles_username_key unique (username);

-- 3. ТРИГГЕР АВТО-СОЗДАНИЯ ПРОФИЛЯ
create or replace function handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, email, username, full_name, role)
    values (
        new.id, 
        new.email, 
        coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        coalesce(new.raw_user_meta_data->>'full_name', 'Пользователь'),
        'user'
    );
    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure handle_new_user();

-- 4. ТАБЛИЦА ФОРМ
create table if not exists forms (
    id uuid default uuid_generate_v4() primary key,
    title text not null,
    description text,
    type text check (type in ('lecture_request', 'exam_request', 'custom')) not null,
    fields jsonb not null default '[]'::jsonb,
    is_active boolean default true,
    created_by uuid references profiles(id),
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- 5. ТАБЛИЦА ОТВЕТОВ НА ФОРМЫ
create table if not exists form_submissions (
    id uuid default uuid_generate_v4() primary key,
    form_id uuid references forms(id) on delete cascade,
    user_id uuid references profiles(id),
    answers jsonb not null default '{}'::jsonb,
    status text check (status in ('pending', 'approved', 'rejected')) default 'pending',
    submitted_at timestamptz default now(),
    reviewed_at timestamptz,
    reviewed_by uuid references profiles(id)
);

-- 6. RLS (Row Level Security)
alter table profiles enable row level security;
alter table forms enable row level security;
alter table form_submissions enable row level security;

-- Удаляем старые политики, чтобы не было конфликтов при повторном запуске
drop policy if exists "profiles_read_own" on profiles;
drop policy if exists "profiles_read_moderators" on profiles;
drop policy if exists "profiles_public_login" on profiles;
drop policy if exists "forms_read" on forms;
drop policy if exists "forms_insert_mod" on forms;
drop policy if exists "forms_update_mod" on forms;
drop policy if exists "forms_delete_mod" on forms;
drop policy if exists "submissions_read_own" on form_submissions;
drop policy if exists "submissions_read_mod" on form_submissions;
drop policy if exists "submissions_insert" on form_submissions;

-- Создаем политики заново
-- 🔓 Публичный доступ для поиска username при входе (критично для работы логина)
create policy "profiles_public_login" on profiles
    for select using (true);

--  Остальные политики безопасности
create policy "profiles_read_moderators" on profiles
    for select using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

create policy "forms_read" on forms
    for select using (auth.role() = 'authenticated');

create policy "forms_insert_mod" on forms
    for insert with check (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

create policy "forms_update_mod" on forms
    for update using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

create policy "forms_delete_mod" on forms
    for delete using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

create policy "submissions_read_own" on form_submissions
    for select using (auth.uid() = user_id);

create policy "submissions_read_mod" on form_submissions
    for select using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head', 'staff'))
    );

create policy "submissions_insert" on form_submissions
    for insert with check (auth.uid() = user_id);

-- 7. ИНДЕКСЫ (безопасное создание)
create index if not exists idx_profiles_role on profiles(role);
create index if not exists idx_profiles_username on profiles(username);
create index if not exists idx_forms_type on forms(type);
create index if not exists idx_forms_active on forms(is_active);
create index if not exists idx_submissions_user on form_submissions(user_id);
create index if not exists idx_submissions_form on form_submissions(form_id);
create index if not exists idx_submissions_status on form_submissions(status);
