-- =====================================================================
-- Ejercicios 7 y 8: indicadores para el tablero de Metabase
-- Fuente: /workspace/data/raw/{yellow,green}/*/*.parquet (todos los anios descargados)
--         /workspace/data/raw/zonas/taxi_zone_lookup.csv (catalogo oficial de zonas TLC)
-- Destino: /workspace/data/processed/indicadores.duckdb (ignorado por Git)
--
-- Lo ejecuta scripts/build_indicadores.py. El archivo tiene dos partes:
--   1) "-- @tabla <nombre>": tablas agregadas que se materializan una sola vez
--      leyendo los Parquet (las consultas pesadas, ~100 M de filas).
--   2) "-- @tarjeta <id> | <visualizacion> | <titulo>": la consulta de cada
--      tarjeta del tablero; scripts/metabase_dashboard.py las lee de aqui y
--      las crea en Metabase tal cual, asi que documentacion y tablero no
--      pueden divergir. Se ejecutan sobre las tablas agregadas (milisegundos).
--
-- El SQL no menciona ningun anio: al descargar un anio nuevo basta con volver
-- a ejecutar el script (Ejercicio 8).
-- =====================================================================

-- @setup
-- Vista unificada yellow + green. anio/mes salen del NOMBRE DEL ARCHIVO (no del
-- timestamp, que trae fechas fuera de rango); union_by_name absorbe columnas que
-- no existen en todos los anios (cbd_congestion_fee desde 2025, request_source).
CREATE OR REPLACE VIEW viajes AS
WITH y AS (
    SELECT 'yellow' AS servicio, tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff,
           passenger_count, trip_distance, PULocationID, DOLocationID, payment_type,
           fare_amount, tip_amount, total_amount, cbd_congestion_fee, filename
    FROM read_parquet('/workspace/data/raw/yellow/*/*.parquet', union_by_name = true, filename = true)
), g AS (
    SELECT 'green' AS servicio, lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff,
           passenger_count, trip_distance, PULocationID, DOLocationID, payment_type,
           fare_amount, tip_amount, total_amount, cbd_congestion_fee, filename
    FROM read_parquet('/workspace/data/raw/green/*/*.parquet', union_by_name = true, filename = true)
), u AS (
    SELECT * FROM y UNION ALL BY NAME SELECT * FROM g
)
SELECT *,
       CAST(regexp_extract(filename, '(\d{4})-\d{2}\.parquet', 1) AS INTEGER) AS anio,
       CAST(regexp_extract(filename, '\d{4}-(\d{2})\.parquet', 1) AS INTEGER) AS mes,
       date_diff('second', pickup, dropoff) / 60.0 AS duracion_min
FROM u;

-- Viajes "plausibles": mismas reglas de limpieza que los Ej. 3 y 4 (pickup dentro
-- del mes del archivo, 0 < distancia < 100 mi, 1 a 360 min, 0 < total <= 1000 USD,
-- tarifa no negativa). Los demas se cuentan en el indicador de calidad.
CREATE OR REPLACE VIEW viajes_validos AS
SELECT * FROM viajes
WHERE date_trunc('month', pickup) = make_date(anio, mes, 1)
  AND trip_distance > 0 AND trip_distance < 100
  AND duracion_min BETWEEN 1 AND 360
  AND total_amount > 0 AND total_amount <= 1000
  AND fare_amount >= 0;

-- @tabla zonas
-- Catalogo de zonas (265 filas) para poner nombre a PULocationID/DOLocationID.
CREATE TABLE zonas AS
SELECT LocationID AS zona_id, Borough AS borough, Zone AS zona, service_zone
FROM read_csv('/workspace/data/raw/zonas/taxi_zone_lookup.csv', header = true);

-- @tabla ind_mensual
-- Una fila por (anio, mes, servicio). Base de la mayoria de los indicadores.
CREATE TABLE ind_mensual AS
WITH todos AS (
    SELECT anio, mes, servicio,
           count(*) AS registros,
           count(*) FILTER (WHERE date_trunc('month', pickup) <> make_date(anio, mes, 1)) AS fecha_fuera_de_mes,
           count(*) FILTER (WHERE trip_distance = 0) AS distancia_cero,
           count(*) FILTER (WHERE trip_distance >= 100) AS distancia_extrema,
           count(*) FILTER (WHERE duracion_min < 1 OR duracion_min > 360) AS duracion_invalida,
           count(*) FILTER (WHERE total_amount <= 0) AS total_no_positivo,
           count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa,
           count(*) FILTER (WHERE payment_type = 0 OR payment_type IS NULL) AS pago_flex_o_nulo
    FROM viajes GROUP BY ALL
), validos AS (
    SELECT anio, mes, servicio,
           count(*) AS viajes,
           sum(total_amount) AS ingresos_usd,
           avg(total_amount) AS ticket_medio_usd,
           avg(fare_amount) AS tarifa_media_usd,
           sum(fare_amount) / sum(trip_distance) AS tarifa_por_milla_usd,
           avg(trip_distance) AS distancia_media_mi,
           approx_quantile(trip_distance, 0.5) AS distancia_mediana_mi,
           approx_quantile(duracion_min, 0.5) AS duracion_mediana_min,
           sum(trip_distance) / (sum(duracion_min) / 60.0) AS velocidad_media_mph,
           avg(passenger_count) FILTER (WHERE passenger_count BETWEEN 1 AND 6) AS pasajeros_medio,
           count(*) FILTER (WHERE payment_type = 1) AS viajes_tarjeta,
           sum(tip_amount) FILTER (WHERE payment_type = 1)
               / sum(fare_amount) FILTER (WHERE payment_type = 1) AS propina_pct_tarjeta,
           count(*) FILTER (WHERE PULocationID IN (1, 132, 138) OR DOLocationID IN (1, 132, 138)) AS viajes_aeropuerto,
           count(*) FILTER (WHERE cbd_congestion_fee > 0) AS viajes_con_cargo_cbd,
           sum(cbd_congestion_fee) FILTER (WHERE cbd_congestion_fee > 0) AS recaudado_cbd_usd
    FROM viajes_validos GROUP BY ALL
)
SELECT make_date(t.anio, t.mes, 1) AS periodo, t.*, v.* EXCLUDE (anio, mes, servicio)
FROM todos t LEFT JOIN validos v USING (anio, mes, servicio)
ORDER BY t.anio, t.mes, t.servicio;

-- @tabla ind_pago
-- Viajes por metodo de pago (todos los registros con pickup en el mes del archivo).
CREATE TABLE ind_pago AS
SELECT anio, mes, make_date(anio, mes, 1) AS periodo, servicio,
       CASE WHEN payment_type = 1 THEN 'Tarjeta'
            WHEN payment_type = 2 THEN 'Efectivo'
            WHEN payment_type IN (3, 4) THEN 'Sin cargo / disputa'
            WHEN payment_type = 0 OR payment_type IS NULL THEN 'Flex / sin dato'
            ELSE 'Otro' END AS metodo_pago,
       count(*) AS viajes
FROM viajes
WHERE date_trunc('month', pickup) = make_date(anio, mes, 1)
GROUP BY ALL;

-- @tabla ind_hora
-- Demanda y velocidad por anio, servicio, tipo de dia y hora (viajes validos).
CREATE TABLE ind_hora AS
SELECT anio, servicio,
       CASE WHEN isodow(pickup) >= 6 THEN 'Fin de semana' ELSE 'Laboral' END AS tipo_dia,
       hour(pickup) AS hora,
       count(*) AS viajes,
       sum(trip_distance) / (sum(duracion_min) / 60.0) AS velocidad_media_mph,
       avg(total_amount) AS ticket_medio_usd
FROM viajes_validos
GROUP BY ALL;

-- @tabla ind_zonas
-- Viajes e ingresos por zona de origen y anio (viajes validos).
CREATE TABLE ind_zonas AS
SELECT v.anio, v.servicio, v.PULocationID AS zona_id, z.borough, z.zona,
       count(*) AS viajes, sum(v.total_amount) AS ingresos_usd
FROM viajes_validos v LEFT JOIN zonas z ON z.zona_id = v.PULocationID
GROUP BY ALL;

-- =====================================================================
-- Tarjetas del tablero (se ejecutan sobre las tablas de arriba)
-- =====================================================================

-- @tarjeta K1 | scalar | Viajes validos (todos los anios, millones)
SELECT round(sum(viajes) / 1e6, 2) AS viajes_millones FROM ind_mensual;

-- @tarjeta K2 | scalar | Ingresos totales (millones USD)
SELECT round(sum(ingresos_usd) / 1e6, 1) AS ingresos_millones_usd FROM ind_mensual;

-- @tarjeta K3 | scalar | Ticket medio (USD)
SELECT round(sum(ingresos_usd) / sum(viajes), 2) AS ticket_medio_usd FROM ind_mensual;

-- @tarjeta K4 | scalar | Participacion del taxi verde (% de viajes)
SELECT round(100.0 * sum(viajes) FILTER (WHERE servicio = 'green') / sum(viajes), 2) AS pct_green
FROM ind_mensual;

-- @tarjeta I1 | line | P1. Demanda: viajes por mes, comparando anios (miles)
-- Pregunta: como evoluciona la demanda mes a mes y que anio tiene mas viajes?
SELECT mes, CAST(anio AS VARCHAR) AS anio, round(sum(viajes) / 1e3, 1) AS viajes_miles
FROM ind_mensual GROUP BY mes, ind_mensual.anio ORDER BY mes, anio;

-- @tarjeta I2 | bar | P2. Ingresos mensuales por servicio (millones USD)
-- Pregunta: cuanto factura el sistema cada mes y cuanto aporta cada servicio?
SELECT periodo, servicio, round(ingresos_usd / 1e6, 2) AS ingresos_millones_usd
FROM ind_mensual ORDER BY periodo, servicio;

-- @tarjeta I3 | line | P3. Precio: ticket medio y tarifa por milla (USD)
-- Pregunta: el viaje se encarece con el tiempo? difiere entre servicios?
SELECT periodo, servicio || ' - ticket medio' AS serie, round(ticket_medio_usd, 2) AS usd FROM ind_mensual
UNION ALL
SELECT periodo, servicio || ' - tarifa por milla', round(tarifa_por_milla_usd, 2) FROM ind_mensual
ORDER BY periodo, serie;

-- @tarjeta I4 | line | P4. Propina en pagos con tarjeta (% de la tarifa)
-- Pregunta: cambia la generosidad de los pasajeros entre servicios y en el tiempo?
SELECT periodo, servicio, round(100 * propina_pct_tarjeta, 2) AS propina_pct
FROM ind_mensual ORDER BY periodo, servicio;

-- @tarjeta I5 | bar | P5. Mezcla de metodos de pago por anio (yellow + green, %)
-- Pregunta: como se paga y crece el uso de la tarjeta o del pago flex?
SELECT CAST(anio AS VARCHAR) AS anio, metodo_pago,
       round(100.0 * sum(viajes) / sum(sum(viajes)) OVER (PARTITION BY anio), 2) AS pct_viajes
FROM ind_pago GROUP BY ind_pago.anio, metodo_pago ORDER BY anio, metodo_pago;

-- @tarjeta I6 | line | P6. Perfil horario: % de viajes por hora (yellow)
-- Pregunta: a que hora se concentra la demanda en dia laboral y en fin de semana?
SELECT hora, tipo_dia || ' ' || anio AS serie,
       round(100.0 * sum(viajes) / sum(sum(viajes)) OVER (PARTITION BY tipo_dia, anio), 2) AS pct_viajes
FROM ind_hora WHERE servicio = 'yellow' GROUP BY hora, tipo_dia, ind_hora.anio ORDER BY hora, serie;

-- @tarjeta I7 | line | P7. Congestion: velocidad media por hora en dia laboral (mph)
-- Pregunta: cuando es mas lento moverse por la ciudad y cambio con el cargo por congestion?
SELECT hora, CAST(anio AS VARCHAR) AS anio,
       round(sum(velocidad_media_mph * viajes) / sum(viajes), 2) AS velocidad_mph
FROM ind_hora WHERE tipo_dia = 'Laboral' GROUP BY hora, ind_hora.anio ORDER BY hora, anio;

-- @tarjeta I8 | row | P8. Top 10 zonas de origen (miles de viajes, todos los anios)
-- Pregunta: donde se origina la demanda?
SELECT coalesce(zona, 'Zona ' || zona_id) || ' (' || coalesce(borough, '?') || ')' AS zona,
       round(sum(viajes) / 1e3, 1) AS viajes_miles
FROM ind_zonas GROUP BY zona_id, zona, borough ORDER BY viajes_miles DESC LIMIT 10;

-- @tarjeta I9 | line | P9. Viajes con origen o destino en aeropuertos (% del mes)
-- Pregunta: que peso tienen JFK, LaGuardia y Newark y es estable?
SELECT periodo, servicio, round(100.0 * viajes_aeropuerto / viajes, 2) AS pct_aeropuerto
FROM ind_mensual ORDER BY periodo, servicio;

-- @tarjeta I10 | line | P10. Calidad: % de registros descartados por mes
-- Pregunta: la calidad del dato es estable o hay meses/servicios problematicos?
SELECT periodo, servicio, round(100.0 * (registros - coalesce(viajes, 0)) / registros, 2) AS pct_descartados
FROM ind_mensual ORDER BY periodo, servicio;

-- @tarjeta I11 | line | P11. Cargo por congestion CBD: % de viajes que lo pagan
-- Pregunta: que alcance tiene el cargo de congestion de Manhattan (vigente desde ene-2025)?
SELECT periodo, servicio, round(100.0 * viajes_con_cargo_cbd / viajes, 2) AS pct_con_cargo
FROM ind_mensual ORDER BY periodo, servicio;

-- @tarjeta I12 | line | P12. Participacion del taxi verde en el total (% de viajes)
-- Pregunta: el servicio verde gana o pierde mercado frente al amarillo?
SELECT periodo, round(100.0 * sum(viajes) FILTER (WHERE servicio = 'green') / sum(viajes), 3) AS pct_green
FROM ind_mensual GROUP BY periodo ORDER BY periodo;

-- @tarjeta T1 | table | Resumen anual por servicio
SELECT CAST(anio AS VARCHAR) AS anio, servicio,
       sum(viajes) AS viajes,
       round(sum(ingresos_usd) / 1e6, 1) AS ingresos_millones_usd,
       round(sum(ingresos_usd) / sum(viajes), 2) AS ticket_medio_usd,
       round(sum(distancia_media_mi * viajes) / sum(viajes), 2) AS distancia_media_mi,
       round(100.0 * sum(viajes_aeropuerto) / sum(viajes), 2) AS pct_aeropuerto,
       round(100.0 * sum(registros - viajes) / sum(registros), 2) AS pct_descartados
FROM ind_mensual GROUP BY ind_mensual.anio, servicio ORDER BY anio, servicio;

-- @fin
