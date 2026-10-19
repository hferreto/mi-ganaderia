-- =====================================================================
-- Mi Ganado v3 · Fotos/documentos y Finanzas
-- Pegar en: Supabase → SQL Editor → New query → Run  (→ "Run and enable RLS")
-- Requiere haber ejecutado antes supabase-mi-ganado.sql. Se puede repetir.
-- =====================================================================

-- ---------- ARCHIVOS: fotos y documentos de cada animal ----------
create table if not exists public.archivos (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  finca_id    text not null references public.fincas(id) on delete cascade,
  animal_id   text references public.animales(id) on delete cascade,
  tipo        text not null,          -- foto, cert_vacunacion, cert_registro, cert_sanitario, cert_propiedad, guia, otro
  nombre      text,
  ruta        text,                   -- ubicación en Storage: <user_id>/<id>.<ext>
  mime        text,
  tamano      bigint,                 -- bytes
  fecha       date,
  notas       text,
  portada     boolean not null default false,
  borrado     boolean not null default false,
  mod         bigint,
  updated_at  timestamptz not null default now()
);

-- ---------- MOVIMIENTOS: ingresos y gastos ----------
create table if not exists public.movimientos (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  finca_id     text not null references public.fincas(id) on delete cascade,
  tipo         text not null check (tipo in ('ingreso','gasto')),
  categoria    text not null,
  fecha        date not null,
  monto        numeric not null default 0,
  descripcion  text,
  cantidad     numeric,
  unidad       text,
  precio_unit  numeric,
  animal_id    text,                  -- opcional: gasto/ingreso de un animal
  lote_id      text,                  -- opcional: asignado a un lote
  tercero      text,                  -- proveedor o cliente
  evento_id    text,                  -- si lo creó un evento (vacuna, venta…)
  borrado      boolean not null default false,
  mod          bigint,
  updated_at   timestamptz not null default now()
);

-- ---------- Triggers, índices y seguridad (igual que las demás tablas) ----------
do $$
declare t text;
begin
  foreach t in array array['archivos','movimientos'] loop
    execute format('drop trigger if exists trg_%1$s_updated on public.%1$I', t);
    execute format('create trigger trg_%1$s_updated before insert or update on public.%1$I
                    for each row execute function public.mg_set_updated_at()', t);
    execute format('create index if not exists idx_%1$s_sync on public.%1$I (user_id, updated_at)', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "solo_mis_datos" on public.%I', t);
    execute format('create policy "solo_mis_datos" on public.%I for all to authenticated
                    using ((select auth.uid()) = user_id)
                    with check ((select auth.uid()) = user_id)', t);
  end loop;
end $$;
alter table public.archivos enable row level security;
alter table public.movimientos enable row level security;

create index if not exists idx_archivos_animal on public.archivos (animal_id);
create index if not exists idx_mov_fecha on public.movimientos (finca_id, fecha);

grant select, insert, update, delete on public.archivos, public.movimientos to authenticated;

-- ---------- STORAGE: carpeta privada para los archivos ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('archivos', 'archivos', false, 10485760)          -- máximo 10 MB por archivo
on conflict (id) do update set public = false, file_size_limit = 10485760;

-- Cada usuario solo puede ver y subir dentro de su propia carpeta (<su user_id>/...)
drop policy if exists "mg_archivos_leer"    on storage.objects;
drop policy if exists "mg_archivos_subir"   on storage.objects;
drop policy if exists "mg_archivos_cambiar" on storage.objects;
drop policy if exists "mg_archivos_borrar"  on storage.objects;

create policy "mg_archivos_leer" on storage.objects for select to authenticated
  using (bucket_id = 'archivos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "mg_archivos_subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'archivos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "mg_archivos_cambiar" on storage.objects for update to authenticated
  using (bucket_id = 'archivos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "mg_archivos_borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'archivos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------- Vista de ejemplo: resumen financiero mensual ----------
create or replace view public.v_finanzas_mensual
with (security_invoker = true) as
select finca_id,
       date_trunc('month', fecha)::date                         as mes,
       sum(monto) filter (where tipo = 'ingreso')               as ingresos,
       sum(monto) filter (where tipo = 'gasto')                 as gastos,
       coalesce(sum(monto) filter (where tipo = 'ingreso'),0)
     - coalesce(sum(monto) filter (where tipo = 'gasto'),0)     as ganancia
from public.movimientos
where not borrado
group by finca_id, date_trunc('month', fecha);

grant select on public.v_finanzas_mensual to authenticated;
