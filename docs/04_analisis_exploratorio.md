# Ejercicio 4 - Analisis exploratorio con DuckDB (NYC TLC 2026)

Datos: viajes yellow y green de enero a agosto de 2026 (`/workspace/data/raw/{yellow,green}/2026/*.parquet`), 29.703.355 viajes yellow y 337.114 green (green = 1,1 % del total).
Todo se ejecuto con DuckDB sobre los Parquet, sin cargar los datos a otro sistema.

Archivos del ejercicio:

- `sql/04_eda.sql`: consultas numeradas Q1 a Q22 (cada una marcada con `-- @Qn`).
- `notebooks/04_analisis_exploratorio.ipynb`: las mismas consultas ejecutadas, con salidas y graficos.
- `docs/img/04_temporal.png`, `04_distribuciones.png`, `04_pagos.png`: graficos generados por el notebook.

## 4.1 Preguntas de analisis y justificacion

| # | Pregunta | Por que importa |
|---|----------|-----------------|
| P1 | Como evoluciona la demanda por mes, dia de la semana y hora? | Dimensiona la operacion y permite detectar estacionalidad y picos. |
| P2 | Como son un viaje tipico (distancia, duracion, pasajeros) y su cola larga? | Define que rangos son "normales" antes de limpiar. |
| P3 | En que se diferencian amarillo y verde? | Son dos servicios con reglas y zonas distintas; unirlos sin entenderlos sesga las medias. |
| P4 | Como se paga y cuanta propina se deja? | Los ingresos del conductor y la calidad del dato de propina dependen del metodo de pago. |
| P5 | Que inconsistencias hay y cuanto sesgan los resultados? | Distancias o tarifas imposibles distorsionan promedios; hay que cuantificarlas antes de modelar. |

## 4.2 y 4.3 Consultas documentadas

**Preparacion (comun a todas).** Vista `viajes` creada en `sql/04_eda.sql` (`@SETUP`): normaliza `tpep_*`/`lpep_*` a `pickup`/`dropoff`, agrega `servicio`, `trip_type` (solo green, NULL en yellow), `filename` y `duracion_min` con `date_diff`. Se unen con `UNION ALL BY NAME`. `ehail_fee`, `Airport_fee`, etc. no se usan y se descartan. Fuente de todas las consultas: los Parquet 2026 de yellow y green a traves de esa vista.

Criterio de "datos plausibles" usado en promedios y percentiles: pickup en 2026, `0 < distancia < 100` mi, `1 <= duracion <= 360` min y `0 < total <= 1000` USD (segun la consulta). Las consultas de conteo (Q2, Q3, Q4, Q6, Q12) no filtran por calidad salvo el ano 2026.

| Consulta | Objetivo | Resultado principal (real) |
|----------|----------|----------------------------|
| Q1 | Volumen y rango de fechas por servicio | yellow 29,70 M viajes y 893,2 M USD; green 0,337 M y 8,6 M USD. Hay pickups desde 2001 (yellow) y 2008 (green). |
| Q2 | Viajes por mes | Yellow: min. febrero (3,40 M), max. mayo (4,09 M); green: min. febrero (37,4 mil), max. mayo (44,9 mil). |
| Q3 | Viajes por dia de la semana | Yellow: sabado 4,63 M y jueves 4,74 M altos, lunes 3,55 M el mas bajo. Green: jueves 55,7 mil max., domingo 38,6 mil min. |
| Q4 | Viajes por hora | Yellow: pico 18 h (7,04 %), valle 4 h (0,82 %). Green: pico 17 h (7,78 %). |
| Q5 | Distancia, duracion, pasajeros medios | Yellow: 3,53 mi media / 1,94 mediana, 17,7 min, 1,25 pas.; green: 3,38 / 2,16 mi, 17,4 min, 1,32 pas. |
| Q6 | Distribucion de pasajeros | 1 pasajero = 60,8 % yellow y 70,7 % green; pasajeros NULL = 26,0 % yellow y 14,5 % green; 0 pasajeros 91.359 yellow. |
| Q7 | Percentiles (p05..p99) | Distancia p50 / p99: yellow 1,92 / 19,57 mi; green 2,14 / 17,80. Total p50 / p99: yellow 23,69 / 105,75 USD; green 20,50 / 97,20. |
| Q8 | Histograma de distancia | 31 % de los viajes yellow plausibles miden 1-2 mi; hay un segundo grupo en 16-18 mi (198 mil, 274 mil, 192 mil viajes) compatible con viajes a aeropuertos. |
| Q9 | Histograma de duracion | Moda en 5-15 min en ambos; 95,8 mil yellow y 1,55 mil green superan 90 min. |
| Q10 | Amarillo vs verde (promedios plausibles) | Tarifa 21,21 vs 16,98 USD; propina 2,89 vs 2,65; total 30,17 vs 25,37; USD por milla 13,83 vs 10,55. |
| Q11 | `trip_type` en green | 1 (calle) 273.386; 2 (despacho) 14.951; NULL 48.777. |
| Q12 | Metodo de pago | Yellow: tarjeta 63,8 %, tipo 0 (flex) 26,0 %, efectivo 9,1 %. Green: tarjeta 65,3 %, efectivo 19,6 %, NULL 14,5 %. |
| Q13 | Propinas por metodo | Tarjeta: 91,1 % (yellow) y 90,4 % (green) dejan propina, 21,5 % y 20,9 % de la tarifa. Efectivo: 0 USD en ambos. |
| Q14 | Tramos de propina (tarjeta) | Yellow: 20-30 % = 7,87 M viajes, >=30 % = 6,08 M, sin propina 1,69 M. Green: 20-30 % = 118 mil. |
| Q15 | Componentes del total | Yellow: tarifa 21,52, extra 1,13, mta 0,49, propina 2,85, peajes 0,54, total 30,40. |
| Q16 | Ingresos y total medio por mes | Total medio yellow estable (29,8-30,7 USD); green sube de 24,30 (ene) a 26,73 (ago). |
| Q17 | Inconsistencias por regla | Ver tabla de 4.4. |
| Q18 | Fechas fuera de 2026 | 17 yellow y 14 green: 2001-01, 2008-12, 2009-01 y 2025-12. |
| Q19 | Top 10 distancias | Todas son yellow y superan 270.000 mi (max. 328.522 mi con duracion de 22 min). |
| Q20 | Velocidades > 80 mph (dist > 1 mi) | 6.836 yellow y 603 green. |
| Q21 | Top 10 zonas de origen | Zonas 237, 161, 132, 236 y 186 concentran 4,35 %, 4,07 %, 3,93 %, 3,90 % y 3,01 % de los viajes. |
| Q22 | Efecto de los atipicos en la distancia media | Yellow 5,55 mi cruda vs 3,51 limpia; green 13,35 vs 3,36. |

Graficos: `docs/img/04_temporal.png` (mes, dia, hora), `docs/img/04_distribuciones.png` (histogramas de distancia y duracion) y `docs/img/04_pagos.png` (metodos de pago y tramos de propina).

## 4.4 Explicacion de resultados

**Temporal.** La demanda yellow sigue el ciclo escolar y laboral: sube de febrero (mes corto) a mayo y baja en julio-agosto (3,53 y 3,34 M). Por dia, el yellow tiene mas viajes de jueves a sabado; el sabado (4,63 M) supera claramente al lunes (3,55 M), lo que indica uso de ocio/nocturno. El green, en cambio, es un servicio de uso laboral y de barrio: cae en fin de semana (domingo 38,6 mil frente a 55,7 mil del jueves). Por hora, ambos tienen valle de madrugada y pico en la tarde-noche (17-18 h), pero el yellow mantiene mucha actividad hasta medianoche (a las 0 h tiene 3,14 % de sus viajes frente a 1,57 % del green).

**Caracteristicas.** El viaje tipico es corto: mediana de 1,9 mi y 14 min, con velocidad media de unas 11 mph, coherente con trafico urbano. La media (3,5 mi) esta bastante por encima de la mediana por la cola derecha (p99 cercano a 20 mi) y por el grupo de 16-18 mi de los aeropuertos. Mas de 8 de cada 10 viajes con pasajeros informados son de 1 pasajero.

**Amarillo vs verde.** El yellow cobra mas por viaje (tarifa 21,21 vs 16,98 USD) y por milla (13,83 vs 10,55), tiene un percentil 99 de total mas alto (105,75 vs 97,20) y mas peajes y extras; el green tiene mediana de distancia algo mayor (2,16 vs 1,94 mi) pero menos cola larga. El green es solo el 1,1 % de los viajes, por lo que cualquier promedio global se parece al del yellow.

**Pagos.** La tarjeta domina (alrededor del 64-65 %). Las propinas solo se registran en pagos con tarjeta; el efectivo siempre tiene propina 0, lo que no significa que no haya propina sino que no se captura. En tarjeta, 9 de cada 10 viajes tienen propina y el promedio es ~21 % de la tarifa; 32 % de los viajes yellow con tarjeta dejan 30 % o mas, un valor alto que sugiere opciones de propina preseleccionadas en el taximetro. El `payment_type` 0 (flex fare) es 26 % del yellow y coincide exactamente con los viajes sin `passenger_count` (7.716.688); su propina media es de solo 0,40 USD, por lo que esos viajes subestiman la propina real.

**Atipicos.** Muchos valores atipicos son defectos del taximetro y no viajes reales: distancia 0 en 952.231 viajes yellow (3,2 %) y 12.212 green (3,6 %), tarifas y totales negativos (reembolsos o disputas: 62 % de los totales negativos yellow tienen payment_type 4, 100.854 de 161.835), distancias mayores a 100 mi (1.223 yellow, 72 green) con un maximo imposible de 328.522 mi en 22 minutos, 17 + 14 fechas fuera de 2026 (2001, 2008, 2009 y diciembre de 2025) y velocidades superiores a 80 mph. Sin limpiar, la distancia media del green pasa de 3,36 a 13,35 mi: unos pocos registros bastan para arruinar un promedio, por eso se usaron medianas, percentiles y filtros de plausibilidad.

### Inconsistencias (Q17, un viaje puede cumplir varias reglas)

| Regla | Yellow | Green |
|-------|-------:|------:|
| pasajeros NULL | 7.716.688 | 48.775 |
| distancia 0 | 952.231 | 12.212 |
| duracion 0 | 371.673 | 229 |
| total negativo | 161.835 | 1.023 |
| tarifa negativa | 157.364 | 999 |
| pasajeros 0 | 91.359 | 4.527 |
| duracion > 6 h | 7.315 | 1.104 |
| total cero | 5.258 | 543 |
| distancia > 100 mi | 1.223 | 72 |
| propina negativa | 883 | 69 |
| total > 1000 USD | 49 | 1 |
| pasajeros > 6 | 28 | 99 |
| pickup fuera de 2026 | 17 | 14 |
| duracion negativa (dropoff < pickup) | 10 | 5 |

## 4.5 Hallazgos relevantes

1. **El yellow domina el mercado y tiene estacionalidad clara.** 29,70 M de viajes frente a 0,34 M del green (98,9 % vs 1,1 %). Los viajes yellow suben de 3,40 M en febrero a 4,09 M en mayo (+20 %) y bajan a 3,34 M en agosto; los ingresos yellow suman 893 M USD en 8 meses con total medio estable (~30 USD). Los patrones por hora y dia muestran uso distinto: el yellow es fuerte el sabado y de noche, el green es laboral y casi no opera en fines de semana.
2. **Casi 1 de cada 4 viajes yellow tiene datos incompletos por el tipo de pago flex.** El 26,0 % (7,72 M) tiene `payment_type = 0` y `passenger_count` NULL, y propina media de 0,40 USD. Cualquier analisis de pasajeros o de propinas debe excluirlos o tratarlos aparte. Por otro lado, en pagos con tarjeta la propina media es 21 % de la tarifa y 91 % de los viajes dejan propina; en efectivo siempre es 0, por lo que la propina total esta subestimada.
3. **Los atipicos son poco frecuentes pero distorsionan los promedios.** 3,2 % de los viajes yellow tienen distancia 0 y 0,54 % total negativo; hay distancias de hasta 328.522 mi. La distancia media del yellow baja de 5,55 a 3,51 mi y la del green de 13,35 a 3,36 mi al aplicar un filtro de plausibilidad (0 < d < 100 mi). Hay ademas 31 viajes con pickup fuera de 2026 (en 2001, 2008-2009 y diciembre de 2025) y 7.439 con velocidad mayor a 80 mph. Recomendacion: definir reglas de limpieza (como las de Q17) antes de agregar o modelar.
4. **Los viajes a aeropuertos forman un segundo modo en la distancia.** El histograma de distancia yellow muestra un repunte entre 16 y 18 mi (190-270 mil viajes por bin) sobre una cola decreciente, y la zona 132 es el tercer origen mas frecuente (3,93 %), coherente con el aeropuerto JFK.

Limitaciones: se trabajo solo con enero-agosto 2026, no se cruzaron las zonas con la tabla oficial de zonas TLC (la identificacion de las zonas 237, 161, 132 en el texto proviene del catalogo publico TLC, no de los datos cargados), y los umbrales de plausibilidad son criterios propios, no oficiales.
