-- =====================================================================
-- Ejercicio 4: Analisis exploratorio (EDA) NYC TLC 2026 con DuckDB
-- Fuente: /workspace/data/raw/{yellow,green}/2026/*.parquet
-- Cada consulta esta separada por un marcador "-- @Q<n>: titulo".
-- =====================================================================

-- @SETUP: vista unificada y normalizada (yellow + green)
CREATE OR REPLACE VIEW viajes AS
WITH y AS (
    SELECT 'yellow' AS servicio, tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff,
           passenger_count, trip_distance, PULocationID, DOLocationID, payment_type,
           fare_amount, extra, mta_tax, tip_amount, tolls_amount, total_amount,
           CAST(NULL AS BIGINT) AS trip_type, filename
    FROM read_parquet('/workspace/data/raw/yellow/2026/*.parquet', union_by_name = true, filename = true)
), g AS (
    SELECT 'green' AS servicio, lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff,
           passenger_count, trip_distance, PULocationID, DOLocationID, payment_type,
           fare_amount, extra, mta_tax, tip_amount, tolls_amount, total_amount,
           trip_type, filename
    FROM read_parquet('/workspace/data/raw/green/2026/*.parquet', union_by_name = true, filename = true)
)
SELECT *, date_diff('second', pickup, dropoff) / 60.0 AS duracion_min
FROM (SELECT * FROM y UNION ALL BY NAME SELECT * FROM g);

-- @Q1: Volumen total y rango de fechas por servicio
SELECT servicio, count(*) AS viajes, min(pickup) AS primer_pickup, max(pickup) AS ultimo_pickup,
       round(sum(total_amount)/1e6, 1) AS ingresos_millones_usd
FROM viajes GROUP BY servicio ORDER BY servicio;

-- @Q2: Viajes por mes (pickup) y servicio, solo 2026
SELECT month(pickup) AS mes, servicio, count(*) AS viajes
FROM viajes WHERE year(pickup) = 2026
GROUP BY ALL ORDER BY mes, servicio;

-- @Q3: Viajes por dia de la semana (1=lunes ... 7=domingo)
SELECT isodow(pickup) AS dia_semana, dayname(pickup) AS dia, servicio, count(*) AS viajes
FROM viajes WHERE year(pickup) = 2026
GROUP BY ALL ORDER BY dia_semana, servicio;

-- @Q4: Viajes por hora del dia, con porcentaje sobre el servicio
SELECT hour(pickup) AS hora, servicio, count(*) AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY servicio), 2) AS pct
FROM viajes WHERE year(pickup) = 2026
GROUP BY hour(pickup), servicio ORDER BY hora, servicio;

-- @Q5: Caracteristicas de los viajes: distancia, duracion y pasajeros (datos plausibles)
SELECT servicio, count(*) AS viajes,
       round(avg(trip_distance), 2) AS dist_media_mi,
       round(median(trip_distance), 2) AS dist_mediana_mi,
       round(avg(duracion_min), 2) AS dur_media_min,
       round(median(duracion_min), 2) AS dur_mediana_min,
       round(avg(passenger_count) FILTER (WHERE passenger_count BETWEEN 1 AND 6), 2) AS pasajeros_medio,
       round(avg(trip_distance / (duracion_min / 60.0)), 1) AS vel_media_mph
FROM viajes
WHERE year(pickup) = 2026 AND trip_distance > 0 AND trip_distance < 100
  AND duracion_min BETWEEN 1 AND 360
GROUP BY servicio ORDER BY servicio;

-- @Q6: Distribucion de pasajeros
SELECT servicio, passenger_count AS pasajeros, count(*) AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY servicio), 2) AS pct
FROM viajes WHERE year(pickup) = 2026
GROUP BY servicio, passenger_count ORDER BY servicio, pasajeros;

-- @Q7: Percentiles de distancia, duracion y total_amount (datos plausibles)
SELECT servicio, 'distancia_mi' AS variable,
       round(quantile_cont(trip_distance, 0.05),2) AS p05, round(quantile_cont(trip_distance, 0.25),2) AS p25,
       round(quantile_cont(trip_distance, 0.50),2) AS p50, round(quantile_cont(trip_distance, 0.75),2) AS p75,
       round(quantile_cont(trip_distance, 0.95),2) AS p95, round(quantile_cont(trip_distance, 0.99),2) AS p99
FROM viajes WHERE year(pickup)=2026 AND trip_distance > 0 AND trip_distance < 100 GROUP BY servicio
UNION ALL
SELECT servicio, 'duracion_min',
       round(quantile_cont(duracion_min, 0.05),2), round(quantile_cont(duracion_min, 0.25),2),
       round(quantile_cont(duracion_min, 0.50),2), round(quantile_cont(duracion_min, 0.75),2),
       round(quantile_cont(duracion_min, 0.95),2), round(quantile_cont(duracion_min, 0.99),2)
FROM viajes WHERE year(pickup)=2026 AND duracion_min BETWEEN 1 AND 360 GROUP BY servicio
UNION ALL
SELECT servicio, 'total_amount_usd',
       round(quantile_cont(total_amount, 0.05),2), round(quantile_cont(total_amount, 0.25),2),
       round(quantile_cont(total_amount, 0.50),2), round(quantile_cont(total_amount, 0.75),2),
       round(quantile_cont(total_amount, 0.95),2), round(quantile_cont(total_amount, 0.99),2)
FROM viajes WHERE year(pickup)=2026 AND total_amount > 0 AND total_amount < 1000 GROUP BY servicio
ORDER BY variable, servicio;

-- @Q8: Histograma de distancia (bins de 1 milla hasta 20, resto en 20+)
SELECT servicio, least(floor(trip_distance), 20)::INT AS milla_bin, count(*) AS viajes
FROM viajes WHERE year(pickup)=2026 AND trip_distance > 0 AND trip_distance < 100
GROUP BY ALL ORDER BY servicio, milla_bin;

-- @Q9: Histograma de duracion (bins de 5 min hasta 90, resto en 90+)
SELECT servicio, least(floor(duracion_min / 5) * 5, 90)::INT AS min_bin, count(*) AS viajes
FROM viajes WHERE year(pickup)=2026 AND duracion_min BETWEEN 0 AND 360
GROUP BY ALL ORDER BY servicio, min_bin;

-- @Q10: Amarillo vs verde (comparacion de promedios de tarifa y propina, datos plausibles)
SELECT servicio, count(*) AS viajes,
       round(avg(fare_amount), 2) AS tarifa_media,
       round(avg(tip_amount), 2) AS propina_media,
       round(avg(total_amount), 2) AS total_medio,
       round(avg(total_amount / trip_distance), 2) AS usd_por_milla,
       round(100.0 * avg((PULocationID <> DOLocationID)::INT), 1) AS pct_cruzan_zona
FROM viajes
WHERE year(pickup)=2026 AND trip_distance BETWEEN 0.1 AND 100 AND fare_amount > 0
  AND total_amount BETWEEN 1 AND 1000 AND duracion_min BETWEEN 1 AND 360
GROUP BY servicio ORDER BY servicio;

-- @Q11: Tipo de viaje en verde (1=calle, 2=despacho) y valores nulos
SELECT coalesce(trip_type::VARCHAR, 'NULL') AS trip_type, count(*) AS viajes
FROM viajes WHERE servicio = 'green' GROUP BY ALL ORDER BY 1;

-- @Q12: Metodo de pago (0=flex, 1=tarjeta, 2=efectivo, 3=sin cargo, 4=disputa, 5=desconocido, 6=anulado)
SELECT servicio, coalesce(payment_type::VARCHAR, 'NULL') AS payment_type, count(*) AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY servicio), 2) AS pct,
       round(avg(total_amount), 2) AS total_medio
FROM viajes WHERE year(pickup)=2026
GROUP BY servicio, payment_type ORDER BY servicio, payment_type;

-- @Q13: Propinas por metodo de pago (solo viajes con tarifa positiva)
SELECT servicio, payment_type,
       count(*) AS viajes,
       round(avg(tip_amount), 2) AS propina_media,
       round(100.0 * avg((tip_amount > 0)::INT), 1) AS pct_con_propina,
       round(100.0 * sum(tip_amount) / sum(fare_amount), 1) AS propina_pct_de_tarifa
FROM viajes
WHERE year(pickup)=2026 AND fare_amount > 0 AND payment_type IN (1, 2)
GROUP BY ALL ORDER BY servicio, payment_type;

-- @Q14: Porcentaje de propina (sobre tarifa) en pagos con tarjeta, por tramos
SELECT servicio,
       CASE WHEN tip_amount = 0 THEN '0% (sin propina)'
            WHEN tip_amount/fare_amount < 0.10 THEN '<10%'
            WHEN tip_amount/fare_amount < 0.20 THEN '10-20%'
            WHEN tip_amount/fare_amount < 0.30 THEN '20-30%'
            ELSE '>=30%' END AS tramo_propina,
       count(*) AS viajes
FROM viajes
WHERE year(pickup)=2026 AND payment_type = 1 AND fare_amount > 0
GROUP BY ALL ORDER BY servicio, tramo_propina;

-- @Q15: Componentes de la tarifa promedio (viajes plausibles)
SELECT servicio, round(avg(fare_amount),2) AS tarifa, round(avg(extra),2) AS extra,
       round(avg(mta_tax),2) AS mta_tax, round(avg(tip_amount),2) AS propina,
       round(avg(tolls_amount),2) AS peajes, round(avg(total_amount),2) AS total
FROM viajes
WHERE year(pickup)=2026 AND fare_amount > 0 AND total_amount BETWEEN 1 AND 1000
GROUP BY servicio ORDER BY servicio;

-- @Q16: Ingresos y total medio por mes
SELECT month(pickup) AS mes, servicio, round(sum(total_amount)/1e6, 2) AS ingresos_millones,
       round(avg(total_amount), 2) AS total_medio
FROM viajes WHERE year(pickup)=2026 AND total_amount BETWEEN 0 AND 1000
GROUP BY ALL ORDER BY mes, servicio;

-- @Q17: Inconsistencias - conteo por regla de calidad (un viaje puede violar varias reglas)
SELECT servicio, regla, count(*) AS viajes FROM (
  SELECT servicio, unnest(list_filter([
        CASE WHEN year(pickup) <> 2026 THEN 'pickup fuera de 2026' END,
        CASE WHEN dropoff < pickup THEN 'duracion negativa' END,
        CASE WHEN duracion_min = 0 THEN 'duracion cero' END,
        CASE WHEN duracion_min > 360 THEN 'duracion > 6 h' END,
        CASE WHEN trip_distance = 0 THEN 'distancia 0' END,
        CASE WHEN trip_distance > 100 THEN 'distancia > 100 mi' END,
        CASE WHEN trip_distance < 0 THEN 'distancia negativa' END,
        CASE WHEN passenger_count = 0 THEN 'pasajeros 0' END,
        CASE WHEN passenger_count > 6 THEN 'pasajeros > 6' END,
        CASE WHEN passenger_count IS NULL THEN 'pasajeros NULL' END,
        CASE WHEN fare_amount < 0 THEN 'tarifa negativa' END,
        CASE WHEN total_amount < 0 THEN 'total negativo' END,
        CASE WHEN total_amount = 0 THEN 'total cero' END,
        CASE WHEN tip_amount < 0 THEN 'propina negativa' END,
        CASE WHEN total_amount > 1000 THEN 'total > 1000 usd' END
      ], x -> x IS NOT NULL)) AS regla
  FROM viajes
) GROUP BY ALL ORDER BY servicio, viajes DESC;

-- @Q18: Viajes con fechas fuera de 2026 (por anio-mes de pickup)
SELECT servicio, strftime(pickup, '%Y-%m') AS anio_mes, count(*) AS viajes
FROM viajes WHERE year(pickup) <> 2026
GROUP BY ALL ORDER BY viajes DESC LIMIT 15;

-- @Q19: Extremos de distancia (top 10)
SELECT servicio, pickup, round(trip_distance,1) AS dist_mi, round(duracion_min,1) AS dur_min,
       fare_amount, total_amount
FROM viajes WHERE year(pickup)=2026
ORDER BY trip_distance DESC LIMIT 10;

-- @Q20: Velocidades imposibles (> 80 mph con distancia > 1 mi)
SELECT servicio, count(*) AS viajes
FROM viajes
WHERE year(pickup)=2026 AND duracion_min > 0 AND trip_distance > 1
  AND trip_distance / (duracion_min/60.0) > 80
GROUP BY servicio ORDER BY servicio;

-- @Q21: Top 10 zonas de origen (PULocationID) y su participacion
SELECT PULocationID, count(*) AS viajes, round(100.0*count(*)/sum(count(*)) OVER (), 2) AS pct
FROM viajes WHERE year(pickup)=2026
GROUP BY PULocationID ORDER BY viajes DESC LIMIT 10;

-- @Q22: Impacto de los atipicos sobre la distancia media
SELECT servicio,
       round(avg(trip_distance), 2) AS dist_media_cruda,
       round(avg(trip_distance) FILTER (WHERE trip_distance > 0 AND trip_distance < 100), 2) AS dist_media_limpia,
       max(trip_distance) AS dist_maxima
FROM viajes WHERE year(pickup)=2026
GROUP BY servicio ORDER BY servicio;
