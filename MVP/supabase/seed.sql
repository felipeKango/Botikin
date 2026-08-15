-- Datos de desarrollo/demo (NO correr en producción)

insert into public.discount_codes (codigo, meses_gratis, usos_maximos, activo, expira_el) values
  ('KANGO2026',   1, 500,  true, '2026-12-31'),
  ('INFLUENCER1', 1, 100,  true, null),
  ('LANZAMIENTO', 2, 1000, true, '2026-09-30'),
  ('AGOTADO',     1, 1,    true, null),
  ('INACTIVO',    1, 100,  false, null)
on conflict (codigo) do nothing;

-- Marca el código AGOTADO como sin usos restantes (para probar el error)
update public.discount_codes set usos_actuales = 1 where codigo = 'AGOTADO';
