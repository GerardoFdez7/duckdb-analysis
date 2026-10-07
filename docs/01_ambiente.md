# Ejercicio 1 - Preparacion del ambiente

## 1.0 Proposito de cada directorio

| Ruta | Proposito |
|---|---|
| `data/raw/` | Datos originales descargados de la TLC, sin modificar (`<tipo>/<anio>/*.parquet`). Ignorado por Git. |
| `data/processed/` | Datos derivados: la base materializada `taxi.duckdb`, extractos. Ignorado por Git. |
| `notebooks/` | Notebooks de Jupyter con exploracion, analisis y benchmarks ejecutados. |
| `scripts/` | Codigo reproducible: descarga, verificacion, benchmark, ejecucion de SQL. |
| `sql/` | Consultas SQL versionadas, numeradas por ejercicio. |
| `docs/` | Documentacion de consultas, resultados, graficos y decisiones. |
| `Dockerfile`, `metabase.Dockerfile`, `docker-compose.yml` | Definicion del ambiente (JupyterLab + Python y Metabase con driver DuckDB). |

## 1.2 - 1.5 Procedimiento y verificacion

```bash
docker compose up --build -d      # construye y levanta lab y metabase
docker compose ps                 # ambos servicios "Up"
curl http://127.0.0.1:8888/api    # JupyterLab responde 200
curl http://127.0.0.1:3000/api/health   # Metabase: {"status":"ok"} (tarda ~1 min en inicializar)
```

Servicios verificados: `lab8-lab` (JupyterLab en http://127.0.0.1:8888) y
`lab8-metabase` (http://127.0.0.1:3000).

Herramientas disponibles dentro del contenedor `lab`: Python 3.11, DuckDB 1.5.5,
pandas 3.0.6, pyarrow 25.0.1, matplotlib 3.11.2, requests 2.34.2, JupyterLab 4.6.4 y curl.
Metabase 0.63.19 incluye el driver DuckDB 1.5.5.0 (misma version que el paquete `duckdb`
de Python, por compatibilidad del archivo `.duckdb`).

## 1.6 Por que un ambiente reproducible

Un analisis es util solo si otra persona (o uno mismo en seis meses) puede obtener los
mismos resultados. Con versiones fijas de Python, DuckDB y librerias dentro de Docker se
elimina el "en mi maquina funciona": un cambio de version de DuckDB o pandas puede alterar
tipos inferidos, redondeos o rendimiento, lo que haria incomparables los benchmarks.
Ademas el ambiente se documenta como codigo (versionado), se levanta con un solo comando
y no contamina el sistema del analista.

## 1.7 Nota: espacio en disco con Docker Desktop en Windows

Docker Desktop guarda imagenes, contenedores y cache en un disco virtual
(`%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`) que **crece pero no se achica solo**:
borrar imagenes o cache libera espacio dentro de Docker, no en Windows. Al reproducir el lab con
el disco C: casi lleno, el primer `--build` (~5 GB temporales) agoto el espacio a mitad de la
construccion y dejo la imagen `lab` con archivos de Python truncados (el contenedor se reiniciaba en
bucle con `ImportError` de `tornado`). Recomendaciones:

1. Tener ~8 GB libres antes del primer `docker compose up --build -d` y usar `docker compose up -d`
   en los arranques siguientes.
2. Si una construccion se corto por falta de espacio, reconstruir sin cache:
   `docker compose build --no-cache lab` (o `metabase`).
3. Para devolver el espacio a Windows (PowerShell como administrador, con Docker abierto):
   ```powershell
   docker builder prune -af
   wsl -d docker-desktop -u root fstrim -av      # marca los bloques libres del disco virtual
   # cerrar Docker Desktop y ejecutar: wsl --shutdown
   # luego en diskpart: select vdisk file="<ruta al .vhdx>" / attach vdisk readonly / compact vdisk / detach vdisk
   ```
   Sin el `fstrim` previo, `compact vdisk` no recupera nada. En este equipo paso de 13,1 GB a 8,4 GB.
