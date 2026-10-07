# Lab 8 - DuckDB

## Como levantar el ambiente

Requisitos: Docker (con Compose) y Git. Docker Desktop debe estar en ejecucion.
Espacio en disco: el primer `--build` necesita ~5 GB libres (imagenes ~2 GB + cache de build ~3 GB,
que se libera con `docker builder prune -af`) y los datos 2024-2026 ocupan ~2 GB. En Windows el disco
virtual de Docker no devuelve solo el espacio liberado (ver [`docs/01_ambiente.md`](docs/01_ambiente.md)).
Una vez construidas las imagenes, use `docker compose up -d` (sin `--build`).

```bash
git clone https://github.com/GerardoFdez7/duckdb-analysis && cd duckdb-analysis
docker compose up --build -d     # construye las imagenes y levanta los servicios
docker compose ps                # lab8-lab y lab8-metabase deben estar "Up"
```

| Servicio | URL | Verificacion |
|---|---|---|
| JupyterLab (`lab8-lab`) | http://127.0.0.1:8888 (sin token) | `curl http://127.0.0.1:8888/api` -> 200 |
| Metabase (`lab8-metabase`) | http://127.0.0.1:3000 | `curl http://127.0.0.1:3000/api/health` -> `{"status":"ok"}` (tarda ~1 min) |

Para ejecutar comandos dentro del ambiente: `docker exec lab8-lab <comando>`
(en Git Bash de Windows anteponga `MSYS_NO_PATHCONV=1` si el comando lleva rutas absolutas).
Para apagarlo: `docker compose down`. Detalle y explicacion en [`docs/01_ambiente.md`](docs/01_ambiente.md).

## Como descargar los datos

```bash
docker exec lab8-lab python scripts/download_data.py                     # 2026 (por defecto)
docker exec lab8-lab python scripts/download_data.py --years 2024 2025 2026   # varios anios
docker exec lab8-lab python scripts/download_data.py --taxi yellow --years 2024
docker exec lab8-lab sh -c "cd scripts && python verify_downloads.py --years 2024 2025 2026"
```

- Se descarga yellow y green a `data/raw/<tipo>/<anio>/`; lo que ya existe no se vuelve a bajar.
- Los meses no publicados por la TLC se omiten y se descargaran en una ejecucion posterior.
- `verify_downloads.py` compara tamano local vs. `Content-Length` remoto y valida el footer Parquet.
- Tambien descarga el catalogo de zonas de la TLC (`data/raw/zonas/taxi_zone_lookup.csv`, 12 KB) que usan los indicadores.
- Estado actual: 2024 y 2025 (12 meses c/u) y 2026 (ene-ago) = 64 archivos, ~2 GB.
- Cambios al script: [`docs/02_descarga.md`](docs/02_descarga.md); validacion de 2024: [`docs/05_incorporacion_2024.md`](docs/05_incorporacion_2024.md);
  incorporacion de 2025: [`docs/08_incorporacion_2025.md`](docs/08_incorporacion_2025.md).

## Como ejecutar el analisis

Las consultas viven en `sql/` y se ejecutan con `scripts/run_sql.py` (o desde los notebooks en JupyterLab):

| Ejercicio | SQL | Documentacion | Notebook |
|---|---|---|---|
| 3. Consultas directas sobre Parquet (2026) | `sql/03_exploracion_parquet.sql` | `docs/03_exploracion_parquet.md` | `notebooks/03_05_consultas_parquet.ipynb` |
| 4. Analisis exploratorio (2026) | `sql/04_eda.sql` | `docs/04_analisis_exploratorio.md` | `notebooks/04_analisis_exploratorio.ipynb` |
| 5. Validacion 2024 + 2026 | `sql/05_validacion_2024_2026.sql` | `docs/05_incorporacion_2024.md` | `notebooks/03_05_consultas_parquet.ipynb` |
| 6. Parquet vs tabla DuckDB | `sql/06_benchmark.sql` | `docs/06_benchmark.md` | `notebooks/06_benchmark.ipynb` |
| 7. Indicadores y tablero Metabase | `sql/07_indicadores.sql` | `docs/07_indicadores_metabase.md` | `notebooks/07_09_indicadores.ipynb` |
| 8. Incorporacion de 2025 | (mismas consultas) | `docs/08_incorporacion_2025.md` | `notebooks/07_09_indicadores.ipynb` |
| 9. Evolucion 2024-2026 | `sql/09_evolucion.sql` | `docs/09_evolucion_2024_2026.md` | `notebooks/07_09_indicadores.ipynb` |

```bash
docker exec lab8-lab python scripts/run_sql.py sql/03_exploracion_parquet.sql
docker exec lab8-lab python scripts/run_sql.py sql/05_validacion_2024_2026.sql
docker exec lab8-lab python scripts/run_sql.py sql/09_evolucion.sql --db data/processed/indicadores.duckdb --solo-lectura
```

## Como generar el tablero de Metabase

```bash
docker exec lab8-lab python scripts/build_indicadores.py             # tablas agregadas -> data/processed/indicadores.duckdb (~2 min)
docker compose restart metabase                                       # solo si Metabase ya tenia abierta una version anterior
docker exec lab8-lab python scripts/metabase_dashboard.py --publico   # setup, conexion DuckDB, 17 tarjetas y tablero
```

- Abrir http://127.0.0.1:3000 (usuario local `lab8@example.com` / `Lab8-duckdb!`) -> coleccion "Lab 8 - DuckDB".
- Al agregar un anio: descargarlo y repetir los tres comandos; no hay que cambiar SQL.
- Captura del tablero (Windows): `powershell -ExecutionPolicy Bypass -File scripts/capturar_tablero.ps1 <enlace-publico> docs/img/tablero.png`.
- Detalle y decisiones: [`docs/07_indicadores_metabase.md`](docs/07_indicadores_metabase.md).

## Como reproducir los benchmarks

Requiere los datos de 2024 y 2026 descargados (el benchmark usa solo esos anios aunque exista 2025)
y ~2 GB libres para `taxi.duckdb`.

```bash
docker exec lab8-lab python scripts/benchmark.py     # ver --help para repeticiones y salida
```

Crea `data/processed/taxi.duckdb` (ignorada por Git), mide cada consulta sobre Parquet y sobre la
tabla materializada con distintos volumenes de datos y escribe `docs/benchmark_resultados.csv`.
Resultados e interpretacion: [`docs/06_benchmark.md`](docs/06_benchmark.md).

## Como generar los resultados principales

Secuencia completa desde cero:

```bash
docker compose up --build -d
docker exec lab8-lab python scripts/download_data.py --years 2024 2025 2026
docker exec lab8-lab python scripts/run_sql.py sql/03_exploracion_parquet.sql
docker exec lab8-lab python scripts/run_sql.py sql/05_validacion_2024_2026.sql
docker exec lab8-lab python scripts/benchmark.py
docker exec lab8-lab python scripts/build_indicadores.py
docker exec lab8-lab python scripts/metabase_dashboard.py
docker exec lab8-lab python scripts/run_sql.py sql/09_evolucion.sql --db data/processed/indicadores.duckdb --solo-lectura
# Notebooks: abrir http://127.0.0.1:8888 y ejecutar notebooks/*.ipynb (Run All),
# o por linea de comandos:
docker exec lab8-lab jupyter nbconvert --to notebook --execute --inplace /workspace/notebooks/04_analisis_exploratorio.ipynb
```

Notas para los notebooks:
- `04_analisis_exploratorio` necesita ~3 GB de RAM. Con Docker Desktop limitado a 4 GB, el kernel
  muere si Metabase esta corriendo (usa ~0,8 GB): ejecutar antes `docker compose stop metabase`
  (y `docker compose start metabase` al terminar) o subir la memoria en Docker Desktop.
- `06_benchmark` lee `data/processed/taxi.duckdb`, que crea `scripts/benchmark.py`: correr el benchmark primero.

