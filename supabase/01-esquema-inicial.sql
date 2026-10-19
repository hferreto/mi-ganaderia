-- =====================================================================
-- Mi Ganado · Base de datos en Supabase (PostgreSQL)
-- Pegar completo en: Supabase → SQL Editor → New query → Run
-- Se puede ejecutar más de una vez sin dañar datos.
-- =====================================================================

-- ---------- Función común: marca la hora del servidor en cada cambio ----------
create or replace function public.mg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------- FINCAS ----------
create table if not exists public.fincas (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre       text not null,
  proposito    text,
  especie      text,
  ubicacion    text,
  area_total   numeric,
  area_ganado  numeric,
  borrado      boolean not null default false,
  mod          bigint,
  updated_at   timestamptz not null default now()
);

-- ---------- LOTES Y POTREROS ----------
create table if not exists public.lotes (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  finca_id     text not null references public.fincas(id) on delete cascade,
  nombre       text not null,
  tipo         text,                 -- 'Lote' o 'Potrero'
  area         numeric,
  borrado      boolean not null default false,
  mod          bigint,
  updated_at   timestamptz not null default now()
);

-- ---------- ANIMALES ----------
create table if not exists public.animales (
  id             text primary key,
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  finca_id       text not null references public.fincas(id) on delete cascade,
  codigo         text not null,
  nombre         text,
  especie        text,               -- bovino, bufalino, caprino, ovino, equino, porcino
  sexo           char(1) check (sexo in ('H','M')),
  fecha_nac      date,
  raza           text,
  proposito      text,
  lote_id        text,
  madre_id       text,
  padre_id       text,
  padre_txt      text,
  dieta          text,
  origen         text,
  fecha_ingreso  date,
  chip           text,
  nfc            text,
  qr             text,
  marca          text,
  notas          text,
  estado         text not null default 'activo' check (estado in ('activo','vendido','muerto')),
  fecha_salida   date,
  borrado        boolean not null default false,
  mod            bigint,
  updated_at     timestamptz not null default now()
);

-- ---------- EVENTOS (pesajes, leche, partos, vacunas, tratamientos…) ----------
create table if not exists public.eventos (
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  finca_id     text not null references public.fincas(id) on delete cascade,
  animal_id    text not null references public.animales(id) on delete cascade,
  tipo         text not null,        -- peso, leche, celo, servicio, chequeo, parto, aborto, secado,
                                     -- vacuna, desparasitacion, tratamiento, mastitis, lote, venta, muerte, nota
  fecha        date not null,
  datos        jsonb not null default '{}'::jsonb,   -- valores propios de cada tipo
  notas        text,
  borrado      boolean not null default false,
  mod          bigint,
  updated_at   timestamptz not null default now()
);

-- ---------- CONFIGURACIÓN DEL USUARIO (parámetros de alertas) ----------
create table if not exists public.config (
  user_id      uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  datos        jsonb not null default '{}'::jsonb,
  mod          bigint,
  updated_at   timestamptz not null default now()
);

-- ---------- Triggers e índices ----------
do $$
declare t text;
begin
  foreach t in array array['fincas','lotes','animales','eventos','config'] loop
    execute format('drop trigger if exists trg_%1$s_updated on public.%1$I', t);
    execute format('create trigger trg_%1$s_updated before insert or update on public.%1$I
                    for each row execute function public.mg_set_updated_at()', t);
    execute format('create index if not exists idx_%1$s_sync on public.%1$I (user_id, updated_at)', t);
  end loop;
end $$;

create index if not exists idx_animales_finca on public.animales (finca_id);
create index if not exists idx_eventos_animal on public.eventos (animal_id, fecha);
create index if not exists idx_eventos_tipo   on public.eventos (finca_id, tipo, fecha);

-- ---------- SEGURIDAD: cada usuario solo ve y modifica sus propios datos ----------
do $$
declare t text;
begin
  foreach t in array array['fincas','lotes','animales','eventos','config'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "solo_mis_datos" on public.%I', t);
    execute format('create policy "solo_mis_datos" on public.%I for all to authenticated
                    using ((select auth.uid()) = user_id)
                    with check ((select auth.uid()) = user_id)', t);
  end loop;
end $$;

grant select, insert, update, delete on public.fincas, public.lotes, public.animales,
  public.eventos, public.config to authenticated;

-- ---------- Vista de ejemplo para consultas (útil en SQL Editor) ----------
create or replace view public.v_produccion_leche_diaria
with (security_invoker = true) as
select e.finca_id,
       e.fecha,
       count(*)                                                       as vacas,
       sum(coalesce((e.datos->>'manana')::numeric,0)
         + coalesce((e.datos->>'tarde')::numeric,0))                  as litros
from public.eventos e
where e.tipo = 'leche' and not e.borrado
group by e.finca_id, e.fecha;

grant select on public.v_produccion_leche_diaria to authenticated;
