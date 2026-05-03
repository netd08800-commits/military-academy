-- Включаем расширения
create extension if not exists "uuid-ossp";

-- ========================
-- ТАБЛИЦА ПРОФИЛЕЙ
-- ========================
create table profiles (
    id uuid references auth.users on delete cascade primary key,
    email text unique,
    full_name text,
    role text check (role in ('user', 'cadet', 'staff', 'deputy_head', 'head', 'moderator')) default 'user',
    registration_date timestamptz default now(),
    is_active boolean default true,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Триггер авто-создания профиля при регистрации
create or replace function handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, email, full_name, role)
    values (
        new.id, 
        new.email, 
        new.raw_user_meta_data->>'full_name',
        'user' -- По умолчанию обычный пользователь
    );
    return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure handle_new_user();

-- ========================
-- ТАБЛИЦА ФОРМ (для модератора)
-- ========================
create table forms (
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

-- ========================
-- ТАБЛИЦА ОТВЕТОВ НА ФОРМЫ
-- ========================
create table form_submissions (
    id uuid default uuid_generate_v4() primary key,
    form_id uuid references forms(id) on delete cascade,
    user_id uuid references profiles(id),
    answers jsonb not null default '{}'::jsonb,
    status text check (status in ('pending', 'approved', 'rejected')) default 'pending',
    submitted_at timestamptz default now(),
    reviewed_at timestamptz,
    reviewed_by uuid references profiles(id)
);

-- ========================
-- RLS (Row Level Security) — БЕЗОПАСНОСТЬ
-- ========================
alter table profiles enable row level security;
alter table forms enable row level security;
alter table form_submissions enable row level security;

-- Профили: каждый видит свой, модеры видят все
create policy "Просмотр своего профиля" on profiles
    for select using (auth.uid() = id);

create policy "Модеры видят все профили" on profiles
    for select using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

-- Формы: чтение всем авторизованным, запись только модераторам
create policy "Чтение форм" on forms
    for select using (auth.role() = 'authenticated');

create policy "Создание форм (модераторы)" on forms
    for insert with check (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

create policy "Редактирование форм (модераторы)" on forms
    for update using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

create policy "Удаление форм (модераторы)" on forms
    for delete using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head'))
    );

-- Подачи форм: пользователь видит свои, модеры видят все
create policy "Просмотр своих подач" on form_submissions
    for select using (auth.uid() = user_id);

create policy "Модеры видят все подачи" on form_submissions
    for select using (
        exists (select 1 from profiles where id = auth.uid() and role in ('moderator', 'head', 'deputy_head', 'staff'))
    );

create policy "Подача форм" on form_submissions
    for insert with check (auth.uid() = user_id);

-- ========================
-- ИНДЕКСЫ для скорости
-- ========================
create index idx_profiles_role on profiles(role);
create index idx_forms_type on forms(type);
create index idx_forms_active on forms(is_active);
create index idx_submissions_user on form_submissions(user_id);
create index idx_submissions_form on form_submissions(form_id);
create index idx_submissions_status on form_submissions(status);
