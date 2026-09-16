-- =========================================================
-- MundoAuto · Tabla para el formulario de suscripción (95% OFF)
-- Ejecutar en Supabase → SQL Editor
-- =========================================================
create table if not exists public.suscripciones (
  id                 uuid primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  codigo             text unique,
  nombre             text not null,
  dni                text not null,
  fecha_nacimiento   date,
  estado_civil       text,
  domicilio          text,
  telefono           text,
  codigo_postal      text,
  localidad          text,
  provincia          text,
  profesion          text,
  situacion_laboral  text,
  datos_laborales    text,
  ingresos_mensuales numeric default 0,
  fecha_cobro        text,
  doc_frente_url     text,
  doc_dorso_url      text,
  doc_estado         text default 'pendiente',  -- pendiente | parcial | completa
  promo              text,
  precio_lista       numeric,
  precio_promo       numeric,
  estado             text default 'nueva'       -- nueva | contactado | aprobada | descartada
);

create index if not exists suscripciones_dni_idx on public.suscripciones (dni);
create index if not exists suscripciones_created_idx on public.suscripciones (created_at desc);

-- RLS: el público SOLO puede insertar (cargar su solicitud), nunca leer.
alter table public.suscripciones enable row level security;

drop policy if exists "suscripciones_insert_publico" on public.suscripciones;
create policy "suscripciones_insert_publico"
  on public.suscripciones for insert
  to anon, authenticated
  with check (true);

-- Lectura sólo para usuarios autenticados (panel interno).
drop policy if exists "suscripciones_select_auth" on public.suscripciones;
create policy "suscripciones_select_auth"
  on public.suscripciones for select
  to authenticated
  using (true);

-- Si querés ver las solicitudes desde el panel actual (que usa la key anon),
-- descomentá esta política. Ojo: expone los datos a cualquiera con la key.
-- create policy "suscripciones_select_anon"
--   on public.suscripciones for select to anon using (true);

-- =========================================================
-- Storage: el formulario sube las fotos del DNI al bucket
-- "comprobantes" en la carpeta suscripciones/<dni>/...
-- Asegurate de permitir INSERT en ese bucket para anon.
-- =========================================================
-- insert into storage.buckets (id, name, public) values ('comprobantes','comprobantes', true)
--   on conflict (id) do nothing;
