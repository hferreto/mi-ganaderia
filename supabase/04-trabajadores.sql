-- =====================================================================
-- Mi Ganado v5 · Trabajadores con roles (varias personas por finca)
-- Pegar en: Supabase → SQL Editor → New query → Run
-- Requiere los scripts 01, 02 y 03. Se puede ejecutar más de una vez.
--
-- Roles:  propietario  → todo, incluso agregar y quitar trabajadores
--         administrador→ todo menos manejar trabajadores
--         veterinario  → ver todo menos finanzas; registrar eventos, fotos y tareas
--         peon         → igual que veterinario (la app le oculta ventas y borrados)
--         visitante    → solo ver (sin finanzas)
-- =====================================================================

-- ---------- Miembros de cada finca ----------
create table if not exists public.miembros (
  finca_id    text not null references public.fincas(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  email       text,
  rol         text not null check (rol in ('administrador','veterinario','peon','visitante')),
  agregado_por uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  primary key (finca_id, user_id)
);
create index if not exists idx_miembros_user on public.miembros (user_id);
alter table public.miembros enable row level security;

-- ---------- ¿Qué rol tengo en esta finca? ----------
create or replace function public.mg_rol(f text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.fincas where id = f and user_id = auth.uid()) then 'propietario'
    else (select rol from public.miembros where finca_id = f and user_id = auth.uid())
  end
$$;
revoke all on function public.mg_rol(text) from public;
grant execute on function public.mg_rol(text) to authenticated;

-- Fincas a las que tengo acceso y mi rol en cada una
create or replace function public.mg_mis_fincas()
returns table (finca_id text, rol text) language sql stable security definer set search_path = public as $$
  select id, 'propietario'::text from public.fincas where user_id = auth.uid() and not borrado
  union all
  select m.finca_id, m.rol from public.miembros m where m.user_id = auth.uid()
$$;
revoke all on function public.mg_mis_fincas() from public;
grant execute on function public.mg_mis_fincas() to authenticated;

-- El propietario agrega (o cambia el rol de) un trabajador por su correo.
-- La cuenta del trabajador debe existir (Authentication → Users → Add user).
create or replace function public.mg_agregar_miembro(p_finca text, p_email text, p_rol text)
returns text language plpgsql security definer set search_path = public as $$
declare v_uid uuid;
begin
  if public.mg_rol(p_finca) is distinct from 'propietario' then
    raise exception 'Solo el propietario puede agregar trabajadores';
  end if;
  if p_rol not in ('administrador','veterinario','peon','visitante') then
    raise exception 'Rol no válido';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  if v_uid is null then
    raise exception 'No existe una cuenta con el correo %. Creala primero en Supabase → Authentication → Users → Add user.', p_email;
  end if;
  if v_uid = auth.uid() then
    raise exception 'Vos ya sos el propietario de esta finca';
  end if;
  insert into public.miembros (finca_id, user_id, email, rol)
  values (p_finca, v_uid, lower(trim(p_email)), p_rol)
  on conflict (finca_id, user_id) do update set rol = excluded.rol, email = excluded.email;
  return 'ok';
end $$;
revoke all on function public.mg_agregar_miembro(text, text, text) from public;
grant execute on function public.mg_agregar_miembro(text, text, text) to authenticated;

-- Miembros: todos los de la finca ven el equipo; solo el propietario cambia o quita
drop policy if exists "mg_miembros_ver"    on public.miembros;
drop policy if exists "mg_miembros_cambiar" on public.miembros;
drop policy if exists "mg_miembros_quitar" on public.miembros;
create policy "mg_miembros_ver" on public.miembros for select to authenticated
  using (public.mg_rol(finca_id) is not null);
create policy "mg_miembros_cambiar" on public.miembros for update to authenticated
  using (public.mg_rol(finca_id) = 'propietario') with check (public.mg_rol(finca_id) = 'propietario');
create policy "mg_miembros_quitar" on public.miembros for delete to authenticated
  using (public.mg_rol(finca_id) = 'propietario' or user_id = (select auth.uid()));
grant select, update, delete on public.miembros to authenticated;

-- ---------- Que borrar la cuenta de un trabajador NO borre lo que registró ----------
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tabla, c.conname
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.contype = 'f' and a.attname = 'user_id'
      and c.conrelid::regclass::text in ('lotes','animales','eventos','archivos','movimientos','tareas',
                                         'public.lotes','public.animales','public.eventos','public.archivos','public.movimientos','public.tareas')
  loop
    execute format('alter table %s drop constraint %I', r.tabla, r.conname);
  end loop;
end $$;

-- ---------- Nuevas reglas de acceso por finca y rol ----------
-- FINCAS
drop policy if exists "solo_mis_datos" on public.fincas;
drop policy if exists "mg_fincas_ver" on public.fincas;
drop policy if exists "mg_fincas_crear" on public.fincas;
drop policy if exists "mg_fincas_cambiar" on public.fincas;
create policy "mg_fincas_ver" on public.fincas for select to authenticated
  using (user_id = (select auth.uid()) or public.mg_rol(id) is not null);
create policy "mg_fincas_crear" on public.fincas for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "mg_fincas_cambiar" on public.fincas for update to authenticated
  using (public.mg_rol(id) in ('propietario','administrador'))
  with check (public.mg_rol(id) in ('propietario','administrador'));

-- Tablas de datos de la finca
do $$
declare t text; quien text;
begin
  foreach t in array array['lotes','animales','eventos','archivos','movimientos','tareas'] loop
    quien := case t
      when 'lotes'       then $q$('propietario','administrador')$q$
      when 'movimientos' then $q$('propietario','administrador')$q$
      else                    $q$('propietario','administrador','veterinario','peon')$q$ end;
    execute format('drop policy if exists "solo_mis_datos" on public.%I', t);
    execute format('drop policy if exists "mg_ver" on public.%I', t);
    execute format('drop policy if exists "mg_crear" on public.%I', t);
    execute format('drop policy if exists "mg_cambiar" on public.%I', t);
    if t = 'movimientos' then
      execute format('create policy "mg_ver" on public.%I for select to authenticated
                      using (public.mg_rol(finca_id) in (''propietario'',''administrador''))', t);
    else
      execute format('create policy "mg_ver" on public.%I for select to authenticated
                      using (public.mg_rol(finca_id) is not null)', t);
    end if;
    execute format('create policy "mg_crear" on public.%I for insert to authenticated
                    with check (public.mg_rol(finca_id) in %s)', t, quien);
    execute format('create policy "mg_cambiar" on public.%I for update to authenticated
                    using (public.mg_rol(finca_id) in %s) with check (public.mg_rol(finca_id) in %s)', t, quien, quien);
  end loop;
end $$;
-- (config sigue siendo personal de cada usuario: política "solo_mis_datos")

-- ---------- Fotos y documentos: ver y borrar los del equipo ----------
drop policy if exists "mg_archivos_leer"   on storage.objects;
drop policy if exists "mg_archivos_borrar" on storage.objects;
create policy "mg_archivos_leer" on storage.objects for select to authenticated
  using (bucket_id = 'archivos' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.archivos a where a.ruta = storage.objects.name
               and public.mg_rol(a.finca_id) is not null)));
create policy "mg_archivos_borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'archivos' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.archivos a where a.ruta = storage.objects.name
               and public.mg_rol(a.finca_id) in ('propietario','administrador'))));
