-- =====================================================================
-- Ejercicio 8 (8.5 - 8.7): evolucion de los indicadores 2024 - 2025 - 2026
-- Fuente: data/processed/indicadores.duckdb (tablas agregadas de sql/07_indicadores.sql)
-- Ejecutar despues de scripts/build_indicadores.py:
--   docker exec lab8-lab python scripts/run_sql.py sql/08_evolucion.sql --db data/processed/indicadores.duckdb --solo-lectura
-- 2026 solo tiene enero-agosto publicados: para comparar anios de forma justa,
-- las consultas anuales usan los MISMOS meses (ene-ago) en los tres anios.
-- =====================================================================

-- Q1 (8.5) Resumen anual comparable (ene-ago), yellow + green
SELECT anio,
       sum(registros) AS registros,
       sum(viajes) AS viajes_validos,
       round(sum(ingresos_usd) / 1e6, 1) AS ingresos_millones_usd,
       round(sum(ingresos_usd) / sum(viajes), 2) AS ticket_medio_usd,
       round(sum(tarifa_por_milla_usd * viajes) / sum(viajes), 2) AS tarifa_por_milla_usd,
       round(sum(distancia_media_mi * viajes) / sum(viajes), 2) AS distancia_media_mi,
       round(sum(velocidad_media_mph * viajes) / sum(viajes), 2) AS velocidad_mph,
       round(100.0 * sum(viajes_aeropuerto) / sum(viajes), 2) AS pct_aeropuerto,
       round(100.0 * sum(registros - viajes) / sum(registros), 2) AS pct_descartados
FROM ind_mensual WHERE mes <= 8
GROUP BY anio ORDER BY anio;

-- Q2 (8.5) Variacion interanual (ene-ago) por servicio, en %
WITH a AS (
    SELECT anio, servicio, sum(viajes) AS viajes, sum(ingresos_usd) AS ingresos,
           sum(ingresos_usd) / sum(viajes) AS ticket
    FROM ind_mensual WHERE mes <= 8 GROUP BY anio, servicio
)
SELECT anio, servicio, viajes,
       round(100.0 * (viajes / lag(viajes) OVER w - 1), 1) AS var_viajes_pct,
       round(100.0 * (ingresos / lag(ingresos) OVER w - 1), 1) AS var_ingresos_pct,
       round(100.0 * (ticket / lag(ticket) OVER w - 1), 1) AS var_ticket_pct
FROM a WINDOW w AS (PARTITION BY servicio ORDER BY anio)
ORDER BY servicio, anio;

-- Q3 (8.5) Viajes yellow mes a mes y variacion contra el mismo mes del anio anterior
SELECT mes,
       sum(viajes) FILTER (WHERE anio = 2024) AS viajes_2024,
       sum(viajes) FILTER (WHERE anio = 2025) AS viajes_2025,
       sum(viajes) FILTER (WHERE anio = 2026) AS viajes_2026,
       round(100.0 * (sum(viajes) FILTER (WHERE anio = 2025) / sum(viajes) FILTER (WHERE anio = 2024) - 1), 1) AS var_25_vs_24_pct,
       round(100.0 * (sum(viajes) FILTER (WHERE anio = 2026) / sum(viajes) FILTER (WHERE anio = 2025) - 1), 1) AS var_26_vs_25_pct
FROM ind_mensual WHERE servicio = 'yellow'
GROUP BY mes ORDER BY mes;

-- Q4 (8.5) Cargo por congestion CBD (vigente desde el 5-ene-2025): alcance y recaudacion, ene-ago
SELECT anio, servicio,
       round(100.0 * sum(viajes_con_cargo_cbd) / sum(viajes), 2) AS pct_viajes_con_cargo,
       round(sum(recaudado_cbd_usd) / 1e6, 2) AS recaudado_millones_usd,
       round(sum(ingresos_usd) / sum(viajes), 2) AS ticket_medio_usd
FROM ind_mensual WHERE mes <= 8
GROUP BY anio, servicio ORDER BY servicio, anio;

-- Q5 (8.5) Velocidad media en dia laboral: hora pico (7-19 h) vs resto, por anio
SELECT anio,
       round(sum(velocidad_media_mph * viajes) FILTER (WHERE hora BETWEEN 7 AND 19)
             / sum(viajes) FILTER (WHERE hora BETWEEN 7 AND 19), 2) AS mph_hora_pico,
       round(sum(velocidad_media_mph * viajes) FILTER (WHERE hora NOT BETWEEN 7 AND 19)
             / sum(viajes) FILTER (WHERE hora NOT BETWEEN 7 AND 19), 2) AS mph_resto,
       round(100.0 * sum(viajes) FILTER (WHERE hora BETWEEN 7 AND 19) / sum(viajes), 1) AS pct_viajes_hora_pico
FROM ind_hora WHERE tipo_dia = 'Laboral' AND servicio = 'yellow'
GROUP BY anio ORDER BY anio;

-- Q6 (8.5) Mezcla de metodos de pago por anio (ene-ago, % de viajes)
SELECT metodo_pago,
       round(100.0 * sum(viajes) FILTER (WHERE anio = 2024) / (SELECT sum(viajes) FROM ind_pago WHERE anio = 2024 AND mes <= 8), 2) AS pct_2024,
       round(100.0 * sum(viajes) FILTER (WHERE anio = 2025) / (SELECT sum(viajes) FROM ind_pago WHERE anio = 2025 AND mes <= 8), 2) AS pct_2025,
       round(100.0 * sum(viajes) FILTER (WHERE anio = 2026) / (SELECT sum(viajes) FROM ind_pago WHERE anio = 2026 AND mes <= 8), 2) AS pct_2026
FROM ind_pago WHERE mes <= 8
GROUP BY metodo_pago ORDER BY pct_2026 DESC;

-- Q7 (8.5) Propina con tarjeta y participacion del taxi verde, por anio (ene-ago)
SELECT anio,
       round(100 * sum(propina_pct_tarjeta * viajes_tarjeta) FILTER (WHERE servicio = 'yellow')
             / sum(viajes_tarjeta) FILTER (WHERE servicio = 'yellow'), 2) AS propina_pct_yellow,
       round(100 * sum(propina_pct_tarjeta * viajes_tarjeta) FILTER (WHERE servicio = 'green')
             / sum(viajes_tarjeta) FILTER (WHERE servicio = 'green'), 2) AS propina_pct_green,
       round(100.0 * sum(viajes) FILTER (WHERE servicio = 'green') / sum(viajes), 2) AS pct_viajes_green
FROM ind_mensual WHERE mes <= 8
GROUP BY anio ORDER BY anio;

-- Q8 (8.5) Top 10 zonas de origen de cada anio y su posicion en los otros anios
WITH r AS (
    SELECT anio, coalesce(zona, 'Zona ' || zona_id) AS zona, borough, sum(viajes) AS viajes,
           rank() OVER (PARTITION BY anio ORDER BY sum(viajes) DESC) AS puesto
    FROM ind_zonas GROUP BY anio, zona_id, zona, borough
)
SELECT zona, borough,
       max(puesto) FILTER (WHERE anio = 2024) AS puesto_2024,
       max(puesto) FILTER (WHERE anio = 2025) AS puesto_2025,
       max(puesto) FILTER (WHERE anio = 2026) AS puesto_2026
FROM r GROUP BY zona, borough
HAVING min(puesto) <= 10
ORDER BY puesto_2026;

-- Q9 (8.6) Calidad del dato por anio y servicio (todos los meses publicados, % de registros)
SELECT anio, servicio, sum(registros) AS registros,
       round(100.0 * sum(fecha_fuera_de_mes) / sum(registros), 3) AS pct_fecha_fuera_de_mes,
       round(100.0 * sum(distancia_cero) / sum(registros), 2) AS pct_distancia_cero,
       round(100.0 * sum(duracion_invalida) / sum(registros), 2) AS pct_duracion_invalida,
       round(100.0 * sum(total_no_positivo) / sum(registros), 2) AS pct_total_no_positivo,
       round(100.0 * sum(tarifa_negativa) / sum(registros), 2) AS pct_tarifa_negativa,
       round(100.0 * sum(pago_flex_o_nulo) / sum(registros), 2) AS pct_pago_flex_o_nulo,
       round(100.0 * sum(registros - viajes) / sum(registros), 2) AS pct_descartados
FROM ind_mensual GROUP BY anio, servicio ORDER BY servicio, anio;

-- Q10 (8.6) Yellow mes a mes: descartados, tarifa negativa y pago flex (explica el salto de 2025)
SELECT periodo, registros,
       round(100.0 * (registros - viajes) / registros, 2) AS pct_descartados,
       round(100.0 * tarifa_negativa / registros, 2) AS pct_tarifa_negativa,
       round(100.0 * pago_flex_o_nulo / registros, 2) AS pct_pago_flex_o_nulo
FROM ind_mensual WHERE servicio = 'yellow'
ORDER BY periodo;
