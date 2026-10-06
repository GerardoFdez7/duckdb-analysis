# Ejercicio 2 - Sistema de descarga

## 2.1 Analisis del script base
`scripts/download_data.py` ya tenia reintentos, descarga atomica (`.part` -> rename),
omision de archivos existentes y consulta `HEAD` para saber que meses estan publicados.
Lo que estaba fijo y debia cambiar: la constante `ANIO = 2026`, usada en nombres, URLs,
rutas y mensajes, de modo que solo podia descargar un anio.

## 2.2 - 2.4, 2.6 Cambios realizados
| Cambio | Detalle |
|---|---|
| `ANIO` -> parametro | `construir_nombre`, `construir_url`, `ruta_destino` y `descargar` reciben `anio`. Se conserva `ANIO_POR_DEFECTO = 2026`. |
| Nuevo argumento `--years` | `python scripts/download_data.py --years 2024 2026`. Sin argumento descarga 2026 (comportamiento original). |
| Bucle por anio | `main()` itera anios x tipos de taxi. |
| `DIR_DESTINO` absoluto | Se calcula desde la ubicacion del script, por lo que funciona desde cualquier directorio de trabajo. |
| Idempotencia | Se mantiene: si el archivo existe y pesa > 0 se omite sin consultar la red. |
| Estructura | `data/raw/<tipo>/<anio>/<tipo>_tripdata_<anio>-<mm>.parquet` |

Se agrego `scripts/verify_downloads.py` para verificar la completitud (ver 2.7).

## 2.5 Ejecucion
```bash
docker exec lab8-lab python scripts/download_data.py            # 2026
```
Resultado: 16 archivos descargados (8 yellow + 8 green, enero-agosto 2026), 0 fallidos.
Septiembre-diciembre 2026 figuran como "aun no publicados" (la TLC publica con retraso).
Una segunda ejecucion reporto `descargados: 0, ya existian: 16`.

## 2.7 Como se determino que el conjunto esta completo
1. El servidor (HEAD) es la fuente de verdad de que meses existen; el script no asume 12 meses.
2. `verify_downloads.py` compara, para cada archivo, el tamano local con el `Content-Length`
   remoto (deben coincidir byte a byte) y abre el footer Parquet con pyarrow (valida que no
   este truncado), obteniendo ademas el numero de filas.
3. Lista los meses publicados en el servidor pero ausentes localmente (debe ser 0).
4. Resultado: `OK=16 faltantes=0 con_error=0`; luego `OK=40` al incluir 2024.
5. DuckDB confirma el conteo: 8 archivos por tipo para 2026 (`sql/03_exploracion_parquet.sql`, Q1)
   y los metadatos de filas coinciden con `count(*)` (Q2 vs Q2b).
