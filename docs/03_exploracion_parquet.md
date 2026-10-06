# Ejercicio 3 - Consultas directas sobre archivos Parquet (2026)

Todas las consultas estan en [`sql/03_exploracion_parquet.sql`](../sql/03_exploracion_parquet.sql)
y se ejecutan con `docker exec lab8-lab python scripts/run_sql.py sql/03_exploracion_parquet.sql`.
Fuente de todas: `data/raw/{yellow,green}/2026/*.parquet` (16 archivos). No se importo nada a tablas.

## Resultados y decisiones (3.1 - 3.8)

| Q | Objetivo (apartado) | Fuente | Resultado | Decision |
|---|---|---|---|---|
| Q1 | Cantidad de archivos (3.1) | `glob()` sobre ambos tipos | 8 yellow + 8 green = **16 archivos** (ene-ago) | Cobertura igual a lo publicado. |
| Q2 | Registros por mes via `parquet_file_metadata` (3.2) | footers de los 16 archivos | yellow 3,34-4,09 M/mes; green 37-45 mil/mes | Respuesta instantanea: solo lee metadatos. |
| Q2b | Registros totales con `count(*)` (3.2) | 16 archivos | yellow **29.703.355**, green **337.114** (total 30.040.469) | Coincide con Q2 (validacion cruzada). El verde es ~1,1 % del total. |
| Q3/Q4 | Columnas y tipos (3.3, 3.4) | yellow y green | 21 columnas en cada tipo (detalle abajo) | Timestamps con nombre distinto (`tpep_*` vs `lpep_*`): normalizar al unir. |
| Q4b | Consistencia de esquema entre archivos | yellow | 20 columnas en ene-may, **21 desde junio** (`request_source`, VARCHAR) | Usar siempre `union_by_name=true`. |
| Q5 | Muestra aleatoria (3.5) | yellow y green | Registros plausibles; green con `ehail_fee` NaN | `ehail_fee` es 100 % nula en green: se excluye. |
| Q6 | Nulos (3.6) | yellow | 7.716.688 nulos (26 %), identicos en `passenger_count`, `RatecodeID`, `store_and_fwd_flag`, `congestion_surcharge`, `Airport_fee` | Mismo conjunto de filas; coincide con `payment_type = 0` (Q10). Tratar como grupo aparte. |
| Q7 | Calidad yellow (3.6) | yellow | distancia 0: 952.231; distancia > 100 mi: 1.223; pasajeros 0: 91.359; pasajeros > 6: 28; tarifa negativa: 157.364; total <= 0: 167.093; dropoff < pickup: 10; duracion > 24 h: 263; pickup fuera de 2026: 17 | En el analisis (Ej. 4) filtrar distancias 0/extremas, duraciones <= 0 o > 24 h y tarifas negativas. |
| Q8 | Calidad green (3.6) | green | distancia 0: 12.212; > 100 mi: 72; pasajeros 0: 4.527; tarifa negativa: 999; dropoff < pickup: 5; fuera de 2026: 14 | Mismos filtros. |
| Q9 | Pickups fuera del mes del archivo | yellow | Hay filas con pickup en otro mes (p. ej. 38 filas de agosto dentro del archivo de julio) | Volumen pequeno; el analisis temporal usa la fecha de pickup, no el nombre del archivo. |
| Q10 | Codigos de `payment_type` (3.6) | yellow | 0: 7,7 M; 1: 18,9 M; 2: 2,7 M; 3: 98 mil; 4: 239 mil; 5: 2 | El codigo 0 no esta en el diccionario clasico (1-6): se trata como "desconocido". |

### Columnas y tipos (3.3, 3.4)
- Comunes: `VendorID`, `PULocationID`, `DOLocationID` INTEGER; `passenger_count`, `RatecodeID`,
  `payment_type` BIGINT; `trip_distance`, `fare_amount`, `extra`, `mta_tax`, `tip_amount`,
  `tolls_amount`, `improvement_surcharge`, `total_amount`, `congestion_surcharge`,
  `cbd_congestion_fee` DOUBLE; `store_and_fwd_flag`, `request_source` VARCHAR.
- Yellow: `tpep_pickup_datetime`, `tpep_dropoff_datetime` TIMESTAMP; `Airport_fee` DOUBLE.
- Green: `lpep_pickup_datetime`, `lpep_dropoff_datetime` TIMESTAMP; `ehail_fee` DOUBLE; `trip_type` BIGINT.
- No se observaron tipos conflictivos entre archivos del mismo tipo.

## 3.6 Problemas de calidad identificados
1. Nulos masivos coordinados (26 % en yellow) asociados a `payment_type = 0`.
2. Distancias cero (3,2 % en yellow) y distancias absurdas (> 100 millas).
3. Pasajeros = 0 y > 6.
4. Importes negativos o no positivos (reembolsos, ajustes o errores).
5. Duraciones negativas o de mas de 24 h; fechas fuera del periodo del archivo.
6. Esquema que cambia en el tiempo (columna nueva `request_source` desde junio).
7. Columna completamente nula (`ehail_fee` en green).

## 3.9 Que significa consultar directamente un Parquet
Parquet es un formato columnar con metadatos (esquema, estadisticas por grupo de filas,
numero de filas) en el footer. Consultarlo "directamente" significa que DuckDB lo trata como
una tabla sin cargarlo antes: `SELECT ... FROM read_parquet('ruta/*.parquet')`. DuckDB lee
solo las columnas que la consulta usa (*projection pushdown*), salta grupos de filas usando
las estadisticas min/max (*filter pushdown*) y procesa en paralelo.
Con grandes volumenes esto evita un paso de ETL, ahorra disco y memoria (los datos no se
duplican), permite consultar datos mas grandes que la RAM, y incorporar un archivo nuevo es
inmediato. Ejemplo: Q2 cuenta 30 M de filas leyendo solo los footers.
