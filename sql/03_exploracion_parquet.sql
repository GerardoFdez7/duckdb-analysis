-- Ejercicio 3: exploracion directa de archivos Parquet (sin importar a tablas)
-- Fuente: data/raw/{yellow,green}/2026/*.parquet  (en el contenedor: /workspace/data/raw/...)
-- Se ejecuta con: python scripts/run_sql.py sql/03_exploracion_parquet.sql

-- Q1 (3.1) Cantidad de archivos por tipo
SELECT regexp_extract(file, '(yellow|green)_tripdata', 1) AS tipo, count(*) AS archivos
FROM glob('/workspace/data/raw/*/2026/*.parquet') t(file)
GROUP BY tipo ORDER BY tipo;

-- Q2 (3.2) Registros por tipo y mes (usa solo metadatos del footer)
SELECT regexp_extract(file_name, '(yellow|green)_tripdata_(\d{4}-\d{2})', 1) AS tipo,
       regexp_extract(file_name, '(\d{4}-\d{2})\.parquet', 1) AS mes,
       sum(num_rows) AS registros
FROM parquet_file_metadata('/workspace/data/raw/*/2026/*.parquet')
GROUP BY ALL ORDER BY tipo, mes;

-- Q2b (3.2) Total de registros por tipo
SELECT regexp_extract(filename, '(yellow|green)_tripdata', 1) AS tipo, count(*) AS registros
FROM read_parquet('/workspace/data/raw/*/2026/*.parquet', filename=true, union_by_name=true)
GROUP BY tipo ORDER BY tipo;

-- Q3/Q4 (3.3, 3.4) Columnas y tipos: yellow
DESCRIBE SELECT * FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet', union_by_name=true);

-- Q3/Q4 (3.3, 3.4) Columnas y tipos: green
DESCRIBE SELECT * FROM read_parquet('/workspace/data/raw/green/2026/*.parquet', union_by_name=true);

-- Q4b Consistencia de tipos entre archivos del mismo tipo (esquema por archivo)
SELECT regexp_extract(file_name, '[^/]+$') AS archivo, count(*) AS n_columnas,
       string_agg(DISTINCT type, ',') AS tipos
FROM parquet_schema('/workspace/data/raw/yellow/2026/*.parquet')
WHERE name <> 'schema'
GROUP BY file_name ORDER BY archivo;

-- Q5 (3.5) Muestra de registros (yellow)
SELECT * FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet') USING SAMPLE 5 ROWS;

-- Q5 (3.5) Muestra de registros (green)
SELECT * FROM read_parquet('/workspace/data/raw/green/2026/*.parquet') USING SAMPLE 5 ROWS;

-- Q6 (3.6) Nulos por columna clave (yellow)
SELECT count(*) AS total,
       count(*) - count(passenger_count) AS pasajeros_nulos,
       count(*) - count(RatecodeID) AS ratecode_nulos,
       count(*) - count(store_and_fwd_flag) AS flag_nulos,
       count(*) - count(congestion_surcharge) AS congestion_nulos,
       count(*) - count(Airport_fee) AS airport_nulos
FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet', union_by_name=true);

-- Q7 (3.6) Problemas de calidad (yellow)
SELECT
  count(*) FILTER (WHERE trip_distance = 0)                       AS distancia_cero,
  count(*) FILTER (WHERE trip_distance > 100)                     AS distancia_mayor_100mi,
  count(*) FILTER (WHERE passenger_count = 0)                     AS pasajeros_cero,
  count(*) FILTER (WHERE passenger_count > 6)                     AS pasajeros_mayor_6,
  count(*) FILTER (WHERE fare_amount < 0)                         AS tarifa_negativa,
  count(*) FILTER (WHERE total_amount <= 0)                       AS total_no_positivo,
  count(*) FILTER (WHERE tpep_dropoff_datetime < tpep_pickup_datetime) AS dropoff_antes_pickup,
  count(*) FILTER (WHERE tpep_dropoff_datetime - tpep_pickup_datetime > INTERVAL 24 HOUR) AS duracion_mayor_24h,
  count(*) FILTER (WHERE year(tpep_pickup_datetime) <> 2026)      AS fuera_de_2026
FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet', union_by_name=true);

-- Q8 (3.6) Problemas de calidad (green)
SELECT
  count(*) FILTER (WHERE trip_distance = 0)                       AS distancia_cero,
  count(*) FILTER (WHERE trip_distance > 100)                     AS distancia_mayor_100mi,
  count(*) FILTER (WHERE passenger_count = 0)                     AS pasajeros_cero,
  count(*) FILTER (WHERE fare_amount < 0)                         AS tarifa_negativa,
  count(*) FILTER (WHERE lpep_dropoff_datetime < lpep_pickup_datetime) AS dropoff_antes_pickup,
  count(*) FILTER (WHERE year(lpep_pickup_datetime) <> 2026)      AS fuera_de_2026,
  count(*) - count(ehail_fee)                                      AS ehail_fee_nulos
FROM read_parquet('/workspace/data/raw/green/2026/*.parquet', union_by_name=true);

-- Q9 (3.6) Fechas fuera de rango: pickups que no caen en el mes del archivo
SELECT regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
       strftime(tpep_pickup_datetime, '%Y-%m') AS mes_pickup, count(*) AS n
FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet', filename=true)
WHERE strftime(tpep_pickup_datetime, '%Y-%m') <> regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1)
GROUP BY ALL ORDER BY n DESC LIMIT 10;

-- Q10 (3.6) Valores de payment_type y RatecodeID (yellow) para detectar codigos desconocidos
SELECT payment_type, count(*) AS n
FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet', union_by_name=true)
GROUP BY 1 ORDER BY 1;
