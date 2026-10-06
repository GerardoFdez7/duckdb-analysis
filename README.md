# Lab 8 - DuckDB

Repositorio base del laboratorio 8 del curso **CC3084 - Data Science**
(Universidad del Valle de Guatemala, Ciclo 2, 2026).

Este es el repositorio **proporcionado por el docente**. Contiene la estructura
del proyecto, el ambiente de ejecucion basado en Docker y un script que descarga
los datos de **2026**. Todo lo demas debe ser construido por cada equipo.

## Trabajo con fork

El laboratorio se desarrolla y se entrega sobre un **fork** de este repositorio.
No se trabaja directamente sobre el repositorio del docente.

1. Realice un fork de este repositorio:
   <https://github.com/menene/duckdb>

2. Clone **su propio fork** (no el del docente):

   ```bash
   git clone https://github.com/<su-usuario>/duckdb.git
   cd duckdb
   ```

3. Opcional, para recibir correcciones publicadas por el docente:

   ```bash
   git remote add upstream https://github.com/menene/duckdb.git
   git fetch upstream
   ```

Realice commits frecuentes y descriptivos: el historial del repositorio es parte
de la evaluacion. **La entrega del laboratorio es la URL de su fork.**

## Estructura

```text
duckdb/
|
+-- data/
|   +-- raw/
|   +-- processed/
|
+-- notebooks/
|
+-- scripts/
|
+-- sql/
|
+-- docs/
|
+-- Dockerfile
+-- metabase.Dockerfile
+-- docker-compose.yml
+-- README.md
```

## Requisitos

- Docker, con Docker Compose
- Git

La primera construccion del ambiente descarga varios cientos de MB y puede
tardar algunos minutos.

Considere el espacio en disco: las imagenes de Docker ocupan unos 3 GB y los
datos de los tres anios del laboratorio superan 1.5 GB, a los que se suma la
base materializada del Ejercicio 6. Se recomienda tener al menos 10 GB libres.

## Datos

El repositorio incluye `scripts/download_data.py`, que descarga los archivos de
2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
archivos se guardan en `data/raw/<tipo>/<anio>/`.

La TLC publica cada mes con varias semanas de atraso, por lo que los ultimos
meses de 2026 todavia no existen. El script consulta al servidor que meses estan
publicados, de modo que vuelve a ejecutarse sin problema conforme aparezcan
nuevos archivos.

Los datos descargados **no deben incluirse en el repositorio Git**. El archivo
`.gitignore` ya esta configurado para evitarlo.

Fuente de datos: NYC TLC Trip Record Data
<https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page>

Dentro de los contenedores, la carpeta `data/` del proyecto esta montada en
`/workspace/data`. Esa es la ruta que deben usar las herramientas que corren
dentro del ambiente, no la ruta de su computadora.

> **Nota sobre DuckDB:** un archivo `.duckdb` admite un solo proceso con permiso
> de escritura a la vez. Si conecta una herramienta externa a su base de datos,
> use el modo de solo lectura (`read_only`) en esa conexion; de lo contrario los
> demas procesos no podran abrir el archivo.

## Material a entregar

Al finalizar, su fork debe contener:

- el codigo fuente modificado y los scripts de descarga;
- las consultas SQL desarrolladas;
- el notebook o notebooks utilizados;
- la documentacion de las consultas;
- los scripts utilizados para los benchmarks;
- el codigo de los indicadores y visualizaciones;
- el tablero o la evidencia del tablero desarrollado;
- este `README.md`, completado segun la siguiente seccion.

Los archivos de datos descargados **no** deben incluirse.

---

# Documentacion del equipo

Las siguientes secciones deben ser completadas por cada equipo. El README final
debe permitir que una persona que no participo en el desarrollo pueda levantar el
ambiente, descargar los datos, ejecutar el analisis, reproducir los benchmarks y
generar los resultados principales.

## Como levantar el ambiente

Requisitos: Docker (con Compose) y Git. Docker Desktop debe estar en ejecucion.

```bash
git clone https://github.com/<su-usuario>/duckdb.git && cd duckdb
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

