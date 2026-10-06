# Ejercicio 5 - Incorporacion de datos de 2024

Consultas: [`sql/05_validacion_2024_2026.sql`](../sql/05_validacion_2024_2026.sql)
(`docker exec lab8-lab python scripts/run_sql.py sql/05_validacion_2024_2026.sql`).

## 5.1 - 5.4 Descarga
No hizo falta reescribir el sistema: el script ya aceptaba `--years` (ver `docs/02_descarga.md`).

```bash
docker exec lab8-lab python scripts/download_data.py --years 2024 2026
```
Resultado: **24 archivos descargados** (12 yellow + 12 green de 2024), **16 omitidos** (los de 2026
ya existian y no se tocaron ni se volvieron a bajar), 0 fallidos.

## 5.5 Verificacion
`python scripts/verify_downloads.py --years 2024 2026` -> `OK=40 faltantes=0 con_error=0`
(tamano local = Content-Length remoto y footer Parquet legible en los 40 archivos).

## 5.6 y 5.8 Consulta conjunta en DuckDB

| Q | Objetivo | Resultado |
|---|---|---|
| Q1 | Archivos por tipo y anio | green 2024: 12, green 2026: 8, yellow 2024: 12, yellow 2026: 8 |
| Q2 | Registros por tipo y anio en una sola lectura (`*/*/*.parquet`) | yellow 2024: 41.169.664; yellow 2026: 29.703.338; green 2024: 660.198; green 2026: 337.100 |
| Q3 | Meses y filas segun metadatos | yellow 2024: 12 meses / 41.169.720; green 2024: 12 / 660.218 |
| Q4 | Columnas que no existen en todos los archivos | `cbd_congestion_fee` (8 meses, solo 2026) y `request_source` (3 meses, jun-ago 2026) |
| Q5 | Consulta de calidad del Ej. 3 reutilizada por anio | 2024: 776.305 distancias 0, 401.354 pasajeros 0, 731.023 tarifas negativas; 2026: 952.231, 91.359, 157.363 |
| Q6 | Viajes yellow por mes, 2024 y 2026 | 20 meses (2024-01..2026-08) en una sola consulta |

(Las diferencias de unas pocas filas entre Q2 y Q3 son pickups con fecha de otro anio dentro de los
archivos; Q2 usa `HAVING count(*) > 1000` para ocultarlas.)

## 5.7 Las consultas anteriores necesitan cambios?
- **Logica SQL: no.** Basta cambiar el patron de ruta de `.../2026/*.parquet` a `.../*/*.parquet`
  (o a `{2024,2026}`). Las consultas de los Ej. 3 y 4 son validas para ambos anios.
- **Adaptaciones menores:**
  1. Las consultas que cuentan "todo" ahora mezclan anios; para reproducir los resultados de 2026
     hay que filtrar por anio (`year(pickup) = 2026` o por ruta). Las consultas de calidad del Ej. 3
     fijaban `year(...) <> 2026`; se generalizaron agrupando por anio (Q5).
  2. `union_by_name=true` es imprescindible: `cbd_congestion_fee` y `request_source` no existen en 2024;
     DuckDB las rellena con NULL en lugar de fallar.
  3. Mas del doble de datos: 2024 pesa mas que 2026 porque abarca 12 meses (71 M de filas yellow en total).
- El patron de calidad cambia: en 2024 hay mas pasajeros = 0 (401 mil) y tarifas negativas (731 mil)
  que en 2026, es decir los problemas de calidad no son estables entre anios.

## 5.9 Que caracteristicas del diseno permiten incorporar archivos sin rehacer todo
1. **Convencion de rutas** `data/raw/<tipo>/<anio>/<archivo>`: agregar un anio es agregar una carpeta;
   las consultas usan comodines, por lo que ven los archivos nuevos automaticamente.
2. **Descarga idempotente** (omite lo existente, valida contra el servidor): se puede ejecutar cuantas
   veces se quiera y solo trae lo nuevo, sin tocar lo anterior.
3. **Anio como parametro** (`--years`), no como constante en el codigo.
4. **Sin etapa de importacion obligatoria**: DuckDB consulta Parquet en sitio, no hay que reconstruir
   tablas para ver los datos nuevos.
5. **`union_by_name`** absorbe cambios de esquema entre anios.
6. **Verificacion automatica** (`verify_downloads.py`) que confirma la integridad de cada incorporacion.
