# Ejercicio 9 - Discusion

Las respuestas se apoyan en lo medido durante el laboratorio; entre parentesis se indica el documento
donde esta la evidencia.

## 9.1 Que caracteristicas de DuckDB resultaron mas utiles?

1. **Consultar Parquet en sitio con comodines** (`read_parquet('data/raw/yellow/*/*.parquet')`): ningun paso de
   importacion; los anios nuevos aparecen solos en las consultas (Ej. 5 y 8).
2. **`union_by_name = true`**: absorbio los cambios de esquema entre anios (`cbd_congestion_fee` desde 2025,
   `request_source` desde jun-2026) rellenando con NULL en vez de fallar (Ej. 5 y 8).
3. **`filename = true` + `regexp_extract`**: permitio derivar anio y mes del nombre del archivo, mas fiable que
   el timestamp, que trae fechas de otros anios (Ej. 3, Q7-Q9).
4. **Funciones de metadatos** (`parquet_file_metadata`, `parquet_schema`, `parquet_metadata`): contar 30 M de
   filas o comparar esquemas leyendo solo los footers, al instante (Ej. 3 Q2, Ej. 5 Q3-Q4).
5. **SQL analitico completo**: `FILTER`, `GROUP BY ALL`, ventanas (`lag`, `rank`), `approx_quantile`,
   `UNION ALL BY NAME`. Los 5 agregados del tablero sobre 121 M de registros se calculan en ~100 s (Ej. 8).
6. **Motor embebido con limite de memoria y spill a disco**: corre dentro del contenedor, sin servidor, con
   `memory_limit='2GB'` sobre datos mucho mayores que la RAM.
7. **Integracion con Python y con Metabase**: `con.sql(...).df()` para graficar resultados pequenos, y el
   driver DuckDB de Metabase lee el mismo archivo `.duckdb` (misma version 1.5.5).

## 9.2 Ventajas y limitaciones de consultar directamente archivos Parquet

**Ventajas**
- Cero tiempo de carga y cero espacio extra: los 1.229 MB de 2024 + 2026 se consultan tal como llegan (Ej. 6).
- Los archivos nuevos se ven de inmediato; la fuente de verdad sigue siendo el archivo publicado por la TLC.
- Lectura columnar y estadisticas por row group: solo se leen las columnas usadas, y los conteos salen de los
  metadatos.
- El mismo archivo lo pueden leer otras herramientas (pandas, Spark, Metabase).

**Limitaciones**
- **Costo fijo en cada consulta**: abrir cada archivo, leer su footer y reconciliar esquemas. Un conteo sobre
  2024 tarda 0,189 s en Parquet frente a 0,006 s en la tabla (30x); las consultas ligeras son 3x a 30x mas
  lentas que en la tabla (Ej. 6).
- **Esquema distinto entre archivos**: sin `union_by_name` las consultas fallan al mezclar anios.
- **Sin normalizacion**: yellow (`tpep_*`) y green (`lpep_*`) usan nombres distintos y cada consulta debe
  repetir la unificacion (resuelto con una vista).
- **Calidad heredada tal cual**: timestamps fuera del periodo, tarifas negativas, distancias 0. Parquet no
  valida nada; la limpieza debe estar en cada consulta.
- Sin indices, restricciones ni actualizaciones.

## 9.3 Ventajas y limitaciones de las tablas materializadas

**Ventajas**
- Consultas ligeras 3x a 30x mas rapidas en caliente, con latencia estable (Ej. 6).
- Esquema ya normalizado (yellow + green, `anio`/`mes` como columnas): quien consulta no repite esa logica.
- **Tablas agregadas**: la version extrema de materializar. Las 5 tablas del tablero pesan 1,5 MB y cada
  tarjeta responde en milisegundos, frente a 72-121 M de filas por consulta si Metabase leyera Parquet (Ej. 7).

**Limitaciones**
- **Espacio**: la tabla ocupa 1.565 MB, un 27 % mas que los Parquet de origen (Ej. 6).
- **Tiempo de creacion** (~23 s para 72 M de filas) que solo se amortiza tras ~6 rondas de consultas (Ej. 6).
- **Se desactualiza**: al llegar 2025 hubo que reconstruir los indicadores (104 s) y reiniciar Metabase, que
  seguia mostrando la version anterior del archivo (Ej. 7 y 8).
- **Un solo escritor**: mientras Metabase tiene el archivo abierto, otro proceso solo puede abrirlo en modo
  lectura (`run_sql.py --solo-lectura`) (Ej. 7).
- No acelera el computo pesado: los percentiles exactos (Q6) tardan lo mismo en ambos formatos (8,1 s vs 8,3 s).
- Crear la tabla con `ORDER BY` agoto la memoria del contenedor (Ej. 6).

## 9.4 Ventajas frente a cargar todo con pandas

- **Memoria**: los 121 M de registros de 2024-2026, con ~20 columnas de 8 bytes, ocuparian ~20 GB en un DataFrame;
  la VM de Docker tiene 3,8 GB. DuckDB procesa por bloques, solo lee las columnas necesarias y respeta un limite
  de memoria. Incluso el notebook de EDA (que solo baja resultados agregados a pandas) se quedo sin memoria
  cuando Metabase estaba corriendo (README, notas de notebooks).
- **No hay paso de carga**: pandas tendria que leer todos los archivos antes de la primera consulta; DuckDB
  consulta en sitio y solo trae a Python el resultado (decenas de filas).
- **Paralelismo y ejecucion vectorizada** automaticos sobre todos los nucleos, sin codigo adicional.
- **SQL declarativo y documentable**: las consultas viven en `sql/*.sql`, las ejecutan scripts y notebooks, y
  las mismas consultas alimentan el tablero. Con pandas la logica quedaria repartida en celdas.
- pandas sigue siendo util al final del flujo: graficos y tablas pequenas (`.df()`).

## 9.5 Que permite incorporar nuevos datos con cambios minimos

1. **Convencion de rutas** `data/raw/<tipo>/<anio>/<archivo-original>.parquet` y consultas con comodines.
2. **Descarga parametrizada e idempotente**: `--years` como argumento; lo existente se omite (2025 se agrego
   con 0 re-descargas; la re-ejecucion completa tardo 7 s) y `verify_downloads.py` comprueba la integridad.
3. **Anio y mes derivados del nombre del archivo**, nunca escritos en el SQL de indicadores.
4. **`union_by_name`** para tolerar columnas nuevas.
5. **Capas separadas**: Parquet crudo (no se modifica) -> tablas agregadas (se reconstruyen con un comando) ->
   tablero (se regenera por API desde el mismo SQL).

El unico cambio necesario al agregar 2025 fue corregir un total de meses escrito a mano (`< 20`) en una consulta
del Ej. 5 (Ej. 8, 8.3).

## 9.6 Que deberia automatizarse en produccion

1. **Descarga programada** (p. ej. mensual): la TLC publica con semanas de atraso, y el script ya distingue
   "no publicado" de "fallido"; solo falta ejecutarlo con un planificador y reintentar los meses pendientes.
2. **Verificacion y controles de calidad con alertas**: tamano y footer (ya existe) y ademas umbrales sobre el
   % de registros descartados por mes. La anomalia de 2025 (hasta 13 % descartado por tarifas negativas) se
   habria detectado al llegar cada archivo y no meses despues.
3. **Deteccion de cambios de esquema**: avisar cuando aparece o desaparece una columna (`cbd_congestion_fee`,
   `request_source`).
4. **Reconstruccion incremental de los agregados y refresco del tablero** (incluido reiniciar o reconectar
   Metabase), disparados por la llegada de datos nuevos.
5. **Pruebas automaticas de las consultas** contra un conjunto ampliado, para detectar valores fijos como el `< 20`.
6. **Monitoreo de recursos** (disco y memoria): fueron la principal causa de fallos al reproducir el lab.

## 9.7 Decisiones de diseno importantes para la reproducibilidad

- **Docker con versiones fijas** (Python 3.11, DuckDB 1.5.5, Metabase 0.63.19 con driver DuckDB 1.5.5.0): la
  misma version de DuckDB en Python y en Metabase garantiza que ambos lean el mismo archivo `.duckdb`.
- **Datos fuera de Git** (`.gitignore` sobre `data/raw` y `data/processed`): el repositorio guarda como
  obtener los datos, no los datos.
- **Scripts idempotentes y verificables**: se pueden ejecutar varias veces y dan el mismo resultado.
- **Una sola fuente para el SQL**: los scripts y el tablero leen los archivos `sql/*.sql`; lo documentado
  es lo que se ejecuta.
- **Transformaciones explicitas** (filtros de limpieza, normalizacion yellow/green, derivacion de anio/mes)
  escritas en SQL y documentadas.
- **Resultados intermedios regenerables** (`taxi.duckdb`, `indicadores.duckdb`): se pueden borrar y reconstruir.
- **README con la secuencia completa**, validado ejecutandolo de principio a fin; esa validacion detecto
  requisitos que no estaban documentados (espacio en disco, memoria para el notebook de EDA).

## 9.8 Que se aprende que no seria evidente con datos pequenos

1. **Los recursos son parte del diseno.** Con 2 GB de datos, el disco y la memoria fallaron varias veces: un
   build de Docker lleno el disco y dejo una imagen corrupta, `ORDER BY` al materializar agoto la memoria y un
   notebook murio con Metabase en marcha. Con datos pequenos nada de eso aparece.
2. **La calidad del dato no es uniforme en el tiempo.** El % de registros invalidos va de 3,9 % (2024) a 9,7 %
   (2025) y 5,2 % (2026) en yellow, con un problema propio de 2025 (tarifas negativas en pagos Flex de enero a
   noviembre). Una muestra pequena de un mes no lo habria mostrado.
3. **El esquema cambia entre anios** (columnas nuevas, codigos de pago redefinidos): hay que disenar para eso.
4. **Los valores fijos fallan en silencio**: el `< 20` siguio "funcionando" y devolvio un resultado incorrecto
   sin errores.
5. **Interpolar sobre periodos faltantes engana**: con 2024 y 2026 parecia que la demanda crecio y que el cargo
   CBD se extendio poco a poco; con 2025 se vio que la demanda subio en 2025 y bajo en 2026, y que el cargo fue
   un salto en enero de 2025.
6. **Donde esta el costo**: con pocos datos todo es instantaneo; a escala se distingue lo que es lectura (lo
   resuelve una tabla) de lo que es computo (percentiles exactos: 8 s con cualquier formato), y conviene usar
   metadatos o aproximaciones (`approx_quantile`) cuando bastan.
7. **Comparar periodos exige la misma base**: 2026 tiene 8 meses; comparar anios completos habria inventado
   una caida. Las comparaciones anuales usan ene-ago.
