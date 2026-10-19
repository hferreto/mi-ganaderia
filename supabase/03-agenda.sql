-- =====================================================================
-- Mi Ganado v4 · Agenda de tareas
-- Pegar en: Supabase → SQL Editor → New query → Run  (→ "Run and enable RLS")
-- Requiere los scripts 01 y 02. Se puede ejecutar más de una vez.
-- =====================================================================

create table if not exists public.tareas (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  finca_id     text not null references public.fincas(id) on delete cascade,
  tipo         text not null,          -- vacuna, desparasitacion, veterinario, pesaje, reproduccion, potreros, compra, mantenimiento, otro
  titulo       text,
  fecha        date not null,
  hora         text,
  animal_id    text,                   -- opcional
  lote_id      text,                   -- opcional
  repetir      text,                   -- '', d7, d14, m1, m2, m3, m4, m6, m12
  notas        text,
  hecha        boolean not null default false,
  fecha_hecha  date,
  borrado      boolean not null default false,
  mod          bigint,
  updated_at   timestamptz not null default now()
);

drop trigger if exists trg_tareas_updated on public.tareas;
create trigger trg_tareas_updated before insert or update on public.tareas
  for each row execute function public.mg_set_updated_at();
create index if not exists idx_tareas_sync  on public.tareas (user_id, updated_at);
create index if not exists idx_tareas_fecha on public.tareas (finca_id, fecha);

alter table public.tareas enable row level security;
drop policy if exists "solo_mis_datos" on public.tareas;
create policy "solo_mis_datos" on public.tareas for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.tareas to authenticated;
