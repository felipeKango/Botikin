-- ============================================================
-- Botikin — Esquema del agente de WhatsApp
-- Reemplaza el modelo de la app iOS (un usuario = un botiquín)
-- por el modelo del agente (un hogar = varias personas con edad).
--
-- Regla que atraviesa todo: la EDAD nunca se guarda, se calcula
-- contra hoy. Lo mismo el estado de vencimiento.
-- ============================================================

-- gen_random_uuid() es nativo en Postgres 13+: no hace falta uuid-ossp.
-- pg_cron y pg_net se habilitan desde el dashboard cuando llegue el
-- proceso diario de vencimientos (PRD 07), no antes.

-- ------------------------------------------------------------
-- Tipos
-- ------------------------------------------------------------
create type sexo_tipo            as enum ('femenino','masculino','otro','no_dice');
create type estado_suscripcion   as enum ('activa','morosa','en_pausa','cancelada');
create type origen_medicamento   as enum ('foto','descripcion','codigo','receta');
create type estado_medicamento   as enum ('vigente','agotado','descartado');
create type duracion_tipo        as enum ('dias','permanencia','sos');
create type estado_tratamiento   as enum ('activo','terminado','suspendido');
create type estado_toma          as enum ('pendiente','confirmada','saltada','sin_confirmar');
create type direccion_mensaje    as enum ('entrante','saliente');
create type paso_onboarding      as enum ('nuevo','conociendo_casa','listo');

-- ------------------------------------------------------------
-- hogares — la cuenta. El teléfono ES la identidad.
-- ------------------------------------------------------------
create table public.hogares (
  id                uuid primary key default gen_random_uuid(),
  telefono          text not null unique,          -- E.164: +56912345678
  nombre_titular    text not null default '',
  invitacion_id     uuid,                          -- por dónde entró
  onboarding        paso_onboarding not null default 'nuevo',
  zona_horaria      text not null default 'America/Santiago',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ------------------------------------------------------------
-- integrantes — las personas de la casa
-- La edad NO es un campo: sale de fecha_nacimiento contra hoy.
-- ------------------------------------------------------------
create table public.integrantes (
  id                 uuid primary key default gen_random_uuid(),
  hogar_id           uuid not null references public.hogares(id) on delete cascade,
  nombre             text not null,
  sexo               sexo_tipo not null default 'no_dice',
  fecha_nacimiento   date,                         -- puede faltar al principio
  es_titular         boolean not null default false,
  activo             boolean not null default true,
  created_at         timestamptz not null default now()
);
create index integrantes_hogar_idx on public.integrantes (hogar_id) where activo;

-- ------------------------------------------------------------
-- productos — el catálogo compartido entre todas las casas.
-- La llave de deduplicación del producto:
--   principio_activo + concentracion + forma_farmaceutica
-- Los tres. Sacar cualquiera produce un error peligroso
-- (jarabe pediátrico vs. comprimido de adulto).
-- ------------------------------------------------------------
create table public.productos (
  id                  uuid primary key default gen_random_uuid(),
  principio_activo    text not null,               -- "paracetamol"
  concentracion       text not null,               -- "500 mg"
  forma_farmaceutica  text not null,               -- "comprimido"
  nombres_comerciales text[] not null default '{}',-- Panadol, Kitadol, Tapsin
  registro_isp        text,                        -- identificador del ISP
  resuelto            boolean not null default false, -- false = NO deduplica
  created_at          timestamptz not null default now(),
  unique (principio_activo, concentracion, forma_farmaceutica)
);
comment on column public.productos.resuelto is
  'false = no se pudo confirmar contra el ISP. Un producto sin resolver NO participa de la deduplicación: es preferible no detectar un duplicado que inventar uno.';

-- ------------------------------------------------------------
-- medicamentos — la caja concreta que está en esa casa
-- NO hay unique por (hogar, producto): dos cajas del mismo
-- producto con distinto vencimiento son dos filas legítimas.
-- El duplicado se detecta consultando, no restringiendo.
-- ------------------------------------------------------------
create table public.medicamentos (
  id                 uuid primary key default gen_random_uuid(),
  hogar_id           uuid not null references public.hogares(id) on delete cascade,
  integrante_id      uuid references public.integrantes(id) on delete set null,
  producto_id        uuid references public.productos(id),
  marca_comprada     text not null default '',
  cantidad           numeric(10,2) not null default 0 check (cantidad >= 0),
  unidad             text not null default 'comprimido',  -- comprimido|mL|dosis|sobre
  fecha_vencimiento  date,                         -- del envase, NUNCA estimada
  lote               text,
  foto_path          text,
  origen             origen_medicamento not null default 'foto',
  receta_id          uuid,
  estado             estado_medicamento not null default 'vigente',
  avisado_30d        date,                         -- candado anti-repetición
  avisado_vencido    date,
  descartado_el      date,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index medicamentos_hogar_venc_idx
  on public.medicamentos (hogar_id, fecha_vencimiento)
  where estado = 'vigente';
create index medicamentos_producto_idx on public.medicamentos (hogar_id, producto_id);

-- ------------------------------------------------------------
-- recetas — el documento del médico y lo que se leyó de él
-- NO se guarda RUT, dirección ni teléfono del paciente.
-- ------------------------------------------------------------
create table public.recetas (
  id              uuid primary key default gen_random_uuid(),
  hogar_id        uuid not null references public.hogares(id) on delete cascade,
  integrante_id   uuid references public.integrantes(id) on delete set null,
  archivo_path    text not null,
  medico          text,
  centro          text,
  fecha_atencion  date,
  lectura         jsonb,
  estado          text not null default 'leida',   -- leida|con_dudas|confirmada
  created_at      timestamptz not null default now()
);
create index recetas_hogar_idx on public.recetas (hogar_id, created_at desc);

alter table public.medicamentos
  add constraint medicamentos_receta_fk
  foreign key (receta_id) references public.recetas(id) on delete set null;

-- ------------------------------------------------------------
-- tratamientos — la pauta que escribió el médico
-- 'permanencia' no tiene término. 'sos' no genera tomas.
-- ------------------------------------------------------------
create table public.tratamientos (
  id              uuid primary key default gen_random_uuid(),
  hogar_id        uuid not null references public.hogares(id) on delete cascade,
  integrante_id   uuid not null references public.integrantes(id) on delete cascade,
  medicamento_id  uuid references public.medicamentos(id) on delete set null,
  producto_id     uuid references public.productos(id),
  receta_id       uuid references public.recetas(id) on delete set null,
  dosis_cantidad  numeric(10,2) not null,
  dosis_unidad    text not null,                   -- comprimido | mL | inhalación
  cada_horas      integer,                         -- null si es sos
  duracion        duracion_tipo not null,
  duracion_dias   integer,
  fecha_inicio    date not null,
  fecha_termino   date,                            -- solo si duracion='dias'
  observaciones   text,
  estado          estado_tratamiento not null default 'activo',
  created_at      timestamptz not null default now(),
  -- Coherencia de la pauta: la trampa de la receta chilena
  constraint tratamiento_coherente check (
    (duracion = 'dias'        and duracion_dias is not null and cada_horas is not null) or
    (duracion = 'permanencia' and duracion_dias is null     and cada_horas is not null) or
    (duracion = 'sos'         and duracion_dias is null     and cada_horas is null)
  )
);
create index tratamientos_activos_idx
  on public.tratamientos (hogar_id, estado) where estado = 'activo';

-- ------------------------------------------------------------
-- tomas — cada evento de la pauta
-- Los 4 estados importan: 'saltada' (me dijo que no) NO es lo
-- mismo que 'sin_confirmar' (no sé). Mezclarlos convierte el
-- resumen semanal en una mentira que se le muestra a un médico.
-- ------------------------------------------------------------
create table public.tomas (
  id                 uuid primary key default gen_random_uuid(),
  tratamiento_id     uuid not null references public.tratamientos(id) on delete cascade,
  hogar_id           uuid not null references public.hogares(id) on delete cascade,
  momento_programado timestamptz not null,
  estado             estado_toma not null default 'pendiente',
  confirmada_at      timestamptz,
  created_at         timestamptz not null default now()
);
create index tomas_pendientes_idx
  on public.tomas (hogar_id, momento_programado) where estado = 'pendiente';

-- ------------------------------------------------------------
-- suscripciones — el estado del pago (Flow.cl)
-- Solo la escribe el backend desde el webhook firmado.
-- ------------------------------------------------------------
create table public.suscripciones (
  id                uuid primary key default gen_random_uuid(),
  hogar_id          uuid not null unique references public.hogares(id) on delete cascade,
  estado            estado_suscripcion not null default 'activa',
  flow_customer_id  text,
  flow_subscription_id text,
  proximo_cobro     date,
  ultimo_cobro_ok   date,
  intentos_fallidos integer not null default 0 check (intentos_fallidos >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ------------------------------------------------------------
-- invitaciones — el link de recomendación
-- ------------------------------------------------------------
create table public.invitaciones (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,
  hogar_origen   uuid references public.hogares(id) on delete set null,
  usos_maximos   integer not null default 10 check (usos_maximos > 0),
  usos_actuales  integer not null default 0 check (usos_actuales >= 0),
  activa         boolean not null default true,
  expira_el      date,
  created_at     timestamptz not null default now()
);

alter table public.hogares
  add constraint hogares_invitacion_fk
  foreign key (invitacion_id) references public.invitaciones(id) on delete set null;

-- ------------------------------------------------------------
-- conversaciones — el hilo y EL RELOJ DE LA VENTANA DE 24 H
-- ultimo_mensaje_usuario decide si podemos mandar texto libre
-- (gratis) o si hay que usar una plantilla aprobada (se paga).
-- ------------------------------------------------------------
create table public.conversaciones (
  id                     uuid primary key default gen_random_uuid(),
  hogar_id               uuid not null unique references public.hogares(id) on delete cascade,
  ultimo_mensaje_usuario timestamptz,
  estado                 text not null default 'activa',  -- activa|humano|cerrada
  updated_at             timestamptz not null default now()
);

-- ------------------------------------------------------------
-- mensajes — todo lo que entra y sale
-- ------------------------------------------------------------
create table public.mensajes (
  id              uuid primary key default gen_random_uuid(),
  hogar_id        uuid not null references public.hogares(id) on delete cascade,
  direccion       direccion_mensaje not null,
  tipo            text not null default 'texto',   -- texto|imagen|documento|plantilla
  texto           text,
  plantilla       text,                            -- si salió fuera de la ventana
  archivo_path    text,
  wamid           text,                            -- id de WhatsApp, para idempotencia
  estado_entrega  text,
  created_at      timestamptz not null default now()
);
create index mensajes_hogar_idx on public.mensajes (hogar_id, created_at desc);
create unique index mensajes_wamid_idx on public.mensajes (wamid) where wamid is not null;

-- ============================================================
-- FUNCIONES DE NEGOCIO
-- ============================================================

-- ------------------------------------------------------------
-- ventana_abierta: ¿podemos mandar texto libre sin costo?
-- Es LA pregunta del canal. Menos de 24 h desde el último
-- mensaje del usuario → sí. Si no, hay que usar plantilla.
-- ------------------------------------------------------------
create or replace function public.ventana_abierta(p_hogar uuid)
returns boolean language sql stable as $$
  select coalesce(
    (select ultimo_mensaje_usuario > now() - interval '24 hours'
       from conversaciones where hogar_id = p_hogar),
    false);
$$;

-- ------------------------------------------------------------
-- edad_de: la edad exacta contra hoy, nunca almacenada.
-- Devuelve años, meses y días — en pediatría los meses importan.
-- ------------------------------------------------------------
create or replace function public.edad_de(p_nacimiento date, p_hoy date default current_date)
returns table (anios int, meses int, dias int)
language sql immutable as $$
  select extract(year  from age(p_hoy, p_nacimiento))::int,
         extract(month from age(p_hoy, p_nacimiento))::int,
         extract(day   from age(p_hoy, p_nacimiento))::int;
$$;

-- ------------------------------------------------------------
-- buscar_duplicado: LA consulta que define el producto.
-- Devuelve lo que la casa YA tiene del mismo principio activo,
-- misma concentración y misma forma — antes de que compren.
-- Un producto sin resolver contra el ISP no participa.
-- ------------------------------------------------------------
create or replace function public.buscar_duplicado(
  p_hogar uuid,
  p_producto uuid
) returns table (
  medicamento_id uuid,
  marca text,
  cantidad numeric,
  unidad text,
  fecha_vencimiento date,
  de_quien text
) language sql stable as $$
  select m.id, m.marca_comprada, m.cantidad, m.unidad, m.fecha_vencimiento,
         coalesce(i.nombre, 'la casa')
    from medicamentos m
    join productos p on p.id = m.producto_id
    left join integrantes i on i.id = m.integrante_id
   where m.hogar_id = p_hogar
     and m.producto_id = p_producto
     and m.estado = 'vigente'
     and p.resuelto                       -- sin ISP no deduplicamos
     and (m.fecha_vencimiento is null or m.fecha_vencimiento >= current_date)
   order by m.fecha_vencimiento nulls last;
$$;

-- ------------------------------------------------------------
-- contexto_hogar: TODO lo que el agente necesita saber en un
-- solo viaje — hoy, la casa, el inventario y los tratamientos.
-- Es lo que se inyecta en cada turno de la conversación.
-- ------------------------------------------------------------
create or replace function public.contexto_hogar(p_hogar uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'hoy', to_char(now() at time zone 'America/Santiago', 'YYYY-MM-DD'),
    'ahora', to_char(now() at time zone 'America/Santiago', 'YYYY-MM-DD HH24:MI'),
    'onboarding', (select onboarding from hogares where id = p_hogar),
    'integrantes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'nombre', i.nombre, 'sexo', i.sexo,
        'fecha_nacimiento', i.fecha_nacimiento,
        'edad_anios', case when i.fecha_nacimiento is null then null
                      else extract(year from age(current_date, i.fecha_nacimiento))::int end,
        'edad_meses', case when i.fecha_nacimiento is null then null
                      else extract(month from age(current_date, i.fecha_nacimiento))::int end,
        'es_titular', i.es_titular))
      from integrantes i where i.hogar_id = p_hogar and i.activo), '[]'::jsonb),
    'inventario', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'principio_activo', p.principio_activo,
        'concentracion', p.concentracion,
        'forma', p.forma_farmaceutica,
        'marca', m.marca_comprada,
        'cantidad', m.cantidad, 'unidad', m.unidad,
        'vence', m.fecha_vencimiento,
        'dias_para_vencer', case when m.fecha_vencimiento is null then null
                            else (m.fecha_vencimiento - current_date) end,
        'de_quien', coalesce(i.nombre, 'la casa')))
      from medicamentos m
      left join productos p on p.id = m.producto_id
      left join integrantes i on i.id = m.integrante_id
      where m.hogar_id = p_hogar and m.estado = 'vigente'), '[]'::jsonb),
    'tratamientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'de_quien', i.nombre,
        'principio_activo', p.principio_activo,
        'dosis', t.dosis_cantidad || ' ' || t.dosis_unidad,
        'cada_horas', t.cada_horas,
        'duracion', t.duracion,
        'termina', t.fecha_termino))
      from tratamientos t
      join integrantes i on i.id = t.integrante_id
      left join productos p on p.id = t.producto_id
      where t.hogar_id = p_hogar and t.estado = 'activo'), '[]'::jsonb)
  );
$$;

-- ============================================================
-- SEGURIDAD
-- El cliente no toca nada: todo pasa por Edge Functions con
-- service_role. RLS activo y sin políticas = nadie entra con
-- la anon key.
-- ============================================================
alter table public.hogares        enable row level security;
alter table public.integrantes    enable row level security;
alter table public.productos      enable row level security;
alter table public.medicamentos   enable row level security;
alter table public.recetas        enable row level security;
alter table public.tratamientos   enable row level security;
alter table public.tomas          enable row level security;
alter table public.suscripciones  enable row level security;
alter table public.invitaciones   enable row level security;
alter table public.conversaciones enable row level security;
alter table public.mensajes       enable row level security;

-- ------------------------------------------------------------
-- Almacenamiento privado, una carpeta por hogar
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('cajas', 'cajas', false),
  ('recetas', 'recetas', false)
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- updated_at automático
-- ------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create trigger hogares_touch       before update on public.hogares
  for each row execute function public.touch_updated_at();
create trigger medicamentos_touch  before update on public.medicamentos
  for each row execute function public.touch_updated_at();
create trigger suscripciones_touch before update on public.suscripciones
  for each row execute function public.touch_updated_at();
