# Lab 8 - DuckDB

## Como levantar el ambiente

Requisitos: Docker (con Compose) y Git. Docker Desktop debe estar en ejecucion.

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
docker exec lab8-lab python scripts/download_data.py --years 2024 2026   # varios anios
docker exec lab8-lab python scripts/download_data.py --taxi yellow --years 2024
docker exec lab8-lab sh -c "cd scripts && python verify_downloads.py --years 2024 2026"
```

- Se descarga yellow y green a `data/raw/<tipo>/<anio>/`; lo que ya existe no se vuelve a bajar.
- Los meses no publicados por la TLC se omiten y se descargaran en una ejecucion posterior.
- `verify_downloads.py` compara tamano local vs. `Content-Length` remoto y valida el footer Parquet.
- Estado actual: 2024 (12 meses) y 2026 (ene-ago) = 40 archivos, ~1,2 GB. El 2025 (Ejercicio 8)
  no se incluyo en este trabajo, pero basta `--years 2024 2025 2026` para obtenerlo.
- Cambios al script: [`docs/02_descarga.md`](docs/02_descarga.md); validacion de 2024: [`docs/05_incorporacion_2024.md`](docs/05_incorporacion_2024.md).

## Como ejecutar el analisis

Las consultas viven en `sql/` y se ejecutan con `scripts/run_sql.py` (o desde los notebooks en JupyterLab):

| Ejercicio | SQL | Documentacion | Notebook |
|---|---|---|---|
| 3. Consultas directas sobre Parquet (2026) | `sql/03_exploracion_parquet.sql` | `docs/03_exploracion_parquet.md` | `notebooks/03_05_consultas_parquet.ipynb` |
| 4. Analisis exploratorio (2026) | `sql/04_eda.sql` | `docs/04_analisis_exploratorio.md` | `notebooks/04_analisis_exploratorio.ipynb` |
| 5. Validacion 2024 + 2026 | `sql/05_validacion_2024_2026.sql` | `docs/05_incorporacion_2024.md` | `notebooks/03_05_consultas_parquet.ipynb` |
| 6. Parquet vs tabla DuckDB | `sql/06_benchmark.sql` | `docs/06_benchmark.md` | `notebooks/06_benchmark.ipynb` |

```bash
docker exec lab8-lab python scripts/run_sql.py sql/03_exploracion_parquet.sql
docker exec lab8-lab python scripts/run_sql.py sql/05_validacion_2024_2026.sql
```

## Como reproducir los benchmarks

Requiere los datos de 2024 y 2026 descargados.

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
docker exec lab8-lab python scripts/download_data.py --years 2024 2026
docker exec lab8-lab python scripts/run_sql.py sql/03_exploracion_parquet.sql
docker exec lab8-lab python scripts/run_sql.py sql/05_validacion_2024_2026.sql
docker exec lab8-lab python scripts/benchmark.py
# Notebooks: abrir http://127.0.0.1:8888 y ejecutar notebooks/*.ipynb (Run All),
# o por linea de comandos:
docker exec lab8-lab jupyter nbconvert --to notebook --execute --inplace /workspace/notebooks/04_analisis_exploratorio.ipynb
```

