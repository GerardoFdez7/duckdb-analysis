-- Ejercicio 5: validacion de la incorporacion de 2024 junto a 2026
-- Fuente: data/raw/{yellow,green}/{2024,2026}/*.parquet

-- Q1 (5.5) Archivos por tipo y anio
SELECT regexp_extract(file, '(yellow|green)_tripdata', 1) AS tipo,
       regexp_extract(file, '_(\d{4})-', 1) AS anio, count(*) AS archivos
FROM glob('/workspace/data/raw/*/*/*.parquet') t(file)
GROUP BY ALL ORDER BY tipo, anio;

-- Q2 (5.6) Registros por tipo y anio, consultando 2024 y 2026 en una sola lectura
SELECT regexp_extract(filename, '(yellow|green)_tripdata', 1) AS tipo,
       year(coalesce(tpep_pickup_datetime, lpep_pickup_datetime)) AS anio_pickup,
       regexp_extract(filename, '_(\d{4})-', 1) AS anio_archivo,
       count(*) AS registros
FROM read_parquet('/workspace/data/raw/*/*/*.parquet', filename=true, union_by_name=true)
GROUP BY ALL HAVING count(*) > 1000 ORDER BY tipo, anio_archivo, anio_pickup;

-- Q3 (5.6) Meses cubiertos por anio y tipo (metadatos)
SELECT regexp_extract(file_name, '(yellow|green)_tripdata', 1) AS tipo,
       regexp_extract(file_name, '_(\d{4})-', 1) AS anio,
       count(*) AS meses, sum(num_rows) AS registros
FROM parquet_file_metadata('/workspace/data/raw/*/*/*.parquet')
GROUP BY ALL ORDER BY tipo, anio;

-- Q4 (5.7) Diferencias de esquema entre anios (yellow): columnas que no existen en todos los archivos
SELECT name, count(DISTINCT regexp_extract(file_name, '_(\d{4}-\d{2})', 1)) AS meses_con_columna
FROM parquet_schema('/workspace/data/raw/yellow/*/*.parquet')
WHERE name <> 'schema'
GROUP BY name
-- Total de meses calculado, no fijo: con un "< 20" (2024+2026) la columna cbd_congestion_fee
-- desaparecia del resultado al agregar 2025 (Ejercicio 8).
HAVING meses_con_columna < (SELECT count(DISTINCT file_name) FROM parquet_metadata('/workspace/data/raw/yellow/*/*.parquet'))
ORDER BY name;

-- Q5 (5.7) Consulta de Ej.3 (calidad, yellow) reutilizada SIN cambios de logica, solo con otro glob, por anio
SELECT year(tpep_pickup_datetime) AS anio_pickup,
       count(*) FILTER (WHERE trip_distance = 0) AS distancia_cero,
       count(*) FILTER (WHERE passenger_count = 0) AS pasajeros_cero,
       count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa
FROM read_parquet('/workspace/data/raw/yellow/*/*.parquet', union_by_name=true)
GROUP BY 1 HAVING count(*) > 1000 ORDER BY 1;

-- Q6 (5.7) Consulta temporal: viajes por mes en 2024 y 2026 (pickups dentro del anio del archivo)
SELECT strftime(tpep_pickup_datetime, '%Y-%m') AS mes, count(*) AS viajes_yellow
FROM read_parquet('/workspace/data/raw/yellow/*/*.parquet', union_by_name=true)
WHERE year(tpep_pickup_datetime) IN (2024, 2026)
GROUP BY 1 ORDER BY 1;
