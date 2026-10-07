# Ejercicio 7 - Indicadores y tablero en Metabase

SQL: [`sql/07_indicadores.sql`](../sql/07_indicadores.sql) ·
Scripts: [`scripts/build_indicadores.py`](../scripts/build_indicadores.py),
[`scripts/metabase_dashboard.py`](../scripts/metabase_dashboard.py),
[`scripts/capturar_tablero.ps1`](../scripts/capturar_tablero.ps1)

Este documento describe el tablero construido con los datos de **2024 y 2026** (estado previo al
Ejercicio 8). La version con 2025 incluido esta en [`docs/08_incorporacion_2025.md`](08_incorporacion_2025.md).

## 7.1 Arquitectura

```
data/raw/{yellow,green}/<anio>/*.parquet ──┐
data/raw/zonas/taxi_zone_lookup.csv ───────┤  build_indicadores.py (DuckDB, ~1-2 min)
                                           ▼
                     data/processed/indicadores.duckdb   (5 tablas agregadas, 1,5 MB)
                                           │  driver DuckDB de Metabase (solo lectura)
                                           ▼
                     Metabase: 17 tarjetas SQL nativas -> tablero "Lab 8 - Indicadores NYC Taxi"
```

Decisiones:

1. **Tablas agregadas en vez de consultar Parquet desde Metabase.** Cada tarjeta leeria 72 M de
   filas (113 M con 2025) en cada apertura del tablero; con las tablas agregadas cada tarjeta
   responde en milisegundos y el archivo pesa 1,5 MB (frente a 1,5 GB de la tabla completa del
   Ejercicio 6). Las agregaciones pesadas se pagan una vez, al reconstruir.
2. **Una sola fuente de verdad para el SQL.** Cada tarjeta es un bloque `-- @tarjeta <id> | <grafico> | <titulo>`
   de `sql/07_indicadores.sql`; `metabase_dashboard.py` crea las tarjetas a partir de ese archivo,
   asi que el SQL documentado y el del tablero no pueden divergir.
3. **El SQL no menciona anios.** El anio y el mes salen del nombre del archivo (`regexp_extract` sobre
   `filename`), no del timestamp (que trae fechas fuera de rango, ver Ej. 3), y la ruta usa `*/*.parquet`.
4. **Viajes "validos"** (mismas reglas que el EDA del Ej. 4): pickup dentro del mes del archivo,
   0 < distancia < 100 mi, 1-360 min, 0 < total <= 1000 USD, tarifa >= 0. Lo descartado no se
   esconde: es un indicador (P10).
5. **Metabase abre la base en solo lectura** (`read_only: true`); la reconstruccion escribe a un
   archivo temporal y lo reemplaza al final, para que Metabase nunca vea una base a medio construir.

Tablas que se materializan:

| Tabla | Grano | Contenido |
|---|---|---|
| `zonas` | LocationID | Catalogo oficial TLC (265 zonas) |
| `ind_mensual` | anio, mes, servicio | Registros, viajes validos, ingresos, ticket, tarifa/milla, distancia, duracion, velocidad, pasajeros, propina, aeropuertos, cargo CBD y contadores de calidad |
| `ind_pago` | anio, mes, servicio, metodo | Viajes por metodo de pago |
| `ind_hora` | anio, servicio, tipo de dia, hora | Viajes, velocidad media y ticket |
| `ind_zonas` | anio, servicio, zona de origen | Viajes e ingresos |

## 7.2 Indicadores

4 KPI + 12 indicadores + 1 tabla resumen. Cada tarjeta tiene en Metabase la pregunta que
responde como descripcion. Resultados con 2024 + 2026:

| Id | Pregunta | Definicion | Lectura (2024 + 2026) |
|---|---|---|---|
| K1-K4 | Tamano del sistema | Viajes validos, ingresos, ticket medio, % verde | 68,6 M viajes; 2.003,6 M USD; 29,19 USD; verde 1,36 % |
| P1 | Como evoluciona la demanda? | Viajes por mes, una serie por anio | 2026 supera a 2024 en todos los meses ene-ago (+10,7 % yellow); estacionalidad: picos en marzo-mayo y caida en julio-agosto |
| P2 | Cuanto se factura y quien? | Ingresos mensuales por servicio | 80-120 M USD/mes; yellow aporta ~99 % |
| P3 | Se encarece el viaje? | Ticket medio y tarifa por milla | Ticket yellow 28,3 -> 30,2 USD (+6,7 %) y tarifa por milla 5,69 -> 6,01 USD (+5,6 %, ene-ago, ambos servicios): sube la tarifa base y ademas se suma el cargo CBD |
| P4 | Cambia la propina? | Propina / tarifa en pagos con tarjeta | Estable: ~22 % yellow, ~21 % green |
| P5 | Como se paga? | % de viajes por metodo de pago | Tarjeta 74 % -> 64 %; "Flex / sin dato" (`payment_type = 0`) 9 % -> 26 %; efectivo 14 % -> 9 % |
| P6 | A que hora se viaja? | % de viajes por hora, laboral vs fin de semana | Laboral: pico 17-19 h; fin de semana: madrugada (0-3 h) alta y manana baja |
| P7 | Cuando hay congestion? | Velocidad media por hora (dia laboral) | ~10 mph entre 9 y 17 h vs ~20 mph de madrugada; 2026 algo mas lento que 2024 |
| P8 | Donde se origina la demanda? | Top 10 zonas de origen | Upper East Side South, Midtown Center, JFK, Upper East Side North; 8 de 10 en Manhattan |
| P9 | Pesan los aeropuertos? | % de viajes con origen o destino JFK/LGA/EWR | Yellow 10,0 % (2024) -> 8,1 % (2026); green ~3-4 % |
| P10 | Es estable la calidad? | % de registros descartados por mes | Yellow 3,9 % (2024) -> 5,2 % (2026); green ~5-7 % |
| P11 | Que alcance tiene el cargo CBD? | % de viajes con `cbd_congestion_fee > 0` | 0 % en 2024 (no existia); ~73 % de los viajes yellow en 2026 |
| P12 | Gana o pierde mercado el verde? | % de viajes green sobre el total | Baja de 1,6 % a 1,1 % |
| T1 | Resumen anual | Viajes, ingresos, ticket, distancia, % aeropuerto, % descartados por anio y servicio | Ver captura |

Nota: con solo 2024 y 2026 las series temporales (P2-P4, P9-P11) unen diciembre de 2024 con enero
de 2026 con una recta que **no es un dato**: falta 2025. En P11 esa recta sugiere un aumento gradual
del cargo CBD que en realidad fue un salto en enero de 2025 (ver Ej. 8).

## 7.3 Tablero

![Tablero con 2024 y 2026](img/07_tablero_2024_2026.png)

## 7.4 Como reproducirlo

```bash
docker exec lab8-lab python scripts/build_indicadores.py           # crea indicadores.duckdb e imprime cada tarjeta
docker compose restart metabase                                     # solo si Metabase ya tenia abierta una version anterior
docker exec lab8-lab python scripts/metabase_dashboard.py --publico # setup, conexion, 17 tarjetas y tablero
```

- Usuario de Metabase (solo para el ambiente local): `lab8@example.com` / `Lab8-duckdb!`. Si es la
  primera vez, el script hace el setup inicial; tablero en http://127.0.0.1:3000 -> coleccion "Lab 8 - DuckDB".
- `--publico` imprime un enlace publico (solo accesible en 127.0.0.1) que permite capturar el
  tablero sin iniciar sesion. Captura (Windows, Edge headless):
  `powershell -ExecutionPolicy Bypass -File scripts\capturar_tablero.ps1 <enlace> docs\img\tablero.png`.
- El script es idempotente: archiva las tarjetas y el tablero anteriores de la coleccion y los crea de nuevo.
- `build_indicadores.py --csv <dir>` guarda el resultado de cada tarjeta como CSV.

## 7.5 Problemas encontrados

1. **Metabase mostraba datos viejos tras reconstruir la base.** El driver DuckDB mantiene abierta la
   instancia del archivo anterior (que fue reemplazado), aunque se actualice la conexion por la API.
   Solucion: `docker compose restart metabase` tras reconstruir. `metabase_dashboard.py` compara el
   total de registros del archivo con lo que responde Metabase y se detiene con un mensaje si difieren.
2. **`GROUP BY ALL` junto con funciones de ventana** funciona en DuckDB 1.5.5 (Python) pero falla en la
   version del driver de Metabase ("Cannot mix aggregates with non-aggregated columns"); las tarjetas
   usan `GROUP BY` explicito.
3. **Bloqueo del archivo.** Metabase mantiene un lock de lectura sobre `indicadores.duckdb`; para
   consultarlo a la vez desde el contenedor `lab` hay que abrirlo en solo lectura
   (`run_sql.py --solo-lectura`).
