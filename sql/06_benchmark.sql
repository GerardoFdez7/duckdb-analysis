-- =====================================================================
-- Ejercicio 6: Parquet vs tablas DuckDB (NYC TLC yellow + green, 2024 y 2026)
-- Este archivo documenta TODAS las consultas del benchmark y es leido por
-- scripts/benchmark.py (cada bloque "-- @consulta <id> <nombre>" es una
-- consulta que se ejecuta tal cual contra la vista/tabla `trips`).
-- Rutas dentro del contenedor: /workspace/data/raw/{yellow,green}/{2024,2026}/
-- =====================================================================

-- ---------------------------------------------------------------------
-- 6.1 Consulta directa a Parquet (sin cargar nada)
-- union_by_name=true: une esquemas distintos (2026 trae cbd_congestion_fee y
--   request_source; 2024 no). filename=true: agrega la columna `filename`.
-- ---------------------------------------------------------------------
-- SELECT count(*) AS viajes, min(filename), max(filename)
-- FROM read_parquet('/workspace/data/raw/yellow/*/*.parquet',
--                   union_by_name = true, filename = true);

-- ---------------------------------------------------------------------
-- 6.2 Tabla materializada (la crea scripts/benchmark.py y se mide su costo).
-- Misma proyeccion normalizada que usa la vista sobre Parquet, para que la
-- comparacion sea justa. anio/mes se extraen del NOMBRE DE ARCHIVO, de modo
-- que filtrar por anio/mes en la tabla equivale a elegir archivos en Parquet.
--
-- CREATE TABLE taxi_trips AS
-- SELECT 'yellow' AS tipo_taxi,
--        tpep_pickup_datetime  AS pickup_datetime,
--        tpep_dropoff_datetime AS dropoff_datetime,
--        passenger_count, trip_distance, PULocationID, DOLocationID,
--        payment_type, fare_amount, tip_amount, total_amount,
--        CAST(regexp_extract(filename, '(\d{4})-(\d{2})\.parquet', 1) AS SMALLINT) AS anio,
--        CAST(regexp_extract(filename, '(\d{4})-(\d{2})\.parquet', 2) AS SMALLINT) AS mes
-- FROM read_parquet('/workspace/data/raw/yellow/*/*.parquet', union_by_name = true, filename = true)
-- UNION ALL
-- SELECT 'green', lpep_pickup_datetime, lpep_dropoff_datetime, ... (idem)
-- FROM read_parquet('/workspace/data/raw/green/*/*.parquet', union_by_name = true, filename = true)
-- ;  (sin ORDER BY: los archivos se leen ordenados por anio/mes y se conserva el orden de insercion)
--
-- Vista equivalente para cada tamano de datos (la arma el script):
--   Parquet: CREATE TEMP VIEW trips AS <proyeccion sobre read_parquet([archivos del tamano])>;
--   Tabla  : CREATE TEMP VIEW trips AS SELECT * FROM taxi_trips WHERE <filtro anio/mes>;
-- Asi las 7 consultas de abajo son IDENTICAS para ambas fuentes.

-- ---------------------------------------------------------------------
-- 6.3 / 6.4 Consultas representativas
-- ---------------------------------------------------------------------

-- @consulta Q1 conteo_total
-- Escaneo minimo: en tabla basta con metadatos; en Parquet, footers de cada archivo.
SELECT count(*) AS viajes FROM trips;

-- @consulta Q2 agregacion_por_mes
-- Agregacion por anio/mes/tipo: viajes, ingresos y propina promedio.
SELECT anio, mes, tipo_taxi,
       count(*)                      AS viajes,
       round(sum(total_amount), 2)   AS ingresos,
       round(avg(tip_amount), 4)     AS propina_prom
FROM trips
GROUP BY anio, mes, tipo_taxi
ORDER BY anio, mes, tipo_taxi;

-- @consulta Q3 promedio_por_tipo
-- Distancia y tarifa promedio por tipo de taxi (solo 3 columnas leidas).
SELECT tipo_taxi,
       round(avg(trip_distance), 4) AS distancia_prom,
       round(avg(fare_amount), 4)   AS tarifa_prom,
       count(*)                     AS viajes
FROM trips
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- @consulta Q4 distribucion_por_hora
-- Distribucion de viajes por hora de recogida (funcion sobre timestamp).
SELECT extract(hour FROM pickup_datetime) AS hora,
       count(*)                           AS viajes,
       round(avg(total_amount), 4)        AS total_prom
FROM trips
GROUP BY hora
ORDER BY hora;

-- @consulta Q5 top_zonas
-- Top 10 zonas de recogida por numero de viajes.
SELECT PULocationID AS zona, count(*) AS viajes, round(avg(fare_amount), 4) AS tarifa_prom
FROM trips
GROUP BY PULocationID
ORDER BY viajes DESC, zona
LIMIT 10;

-- @consulta Q6 percentiles_propina
-- Percentiles de propina (solo pagos con tarjeta, payment_type = 1).
SELECT tipo_taxi,
       quantile_cont(tip_amount, 0.50) AS p50,
       quantile_cont(tip_amount, 0.90) AS p90,
       quantile_cont(tip_amount, 0.99) AS p99
FROM trips
WHERE payment_type = 1
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- @consulta Q7 filtro_selectivo
-- Consulta muy selectiva: pocos viajes largos y caros (aprovecha estadisticas min/max).
SELECT count(*) AS viajes, round(avg(total_amount), 4) AS total_prom
FROM trips
WHERE trip_distance > 100 AND total_amount > 300;

-- @fin
