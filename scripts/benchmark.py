"""Ejercicio 6: benchmark Parquet directo vs tabla DuckDB materializada.

Uso (dentro del contenedor):
    docker exec lab8-lab python /workspace/scripts/benchmark.py --repeticiones 5
Argumentos: --repeticiones, --salida (CSV de resultados), --db, --datos, --sql, --tamanos.

Metodologia
- Para cada tamano de datos y cada consulta se ejecuta la MISMA consulta SQL
  sobre una vista `trips` (misma proyeccion normalizada) con dos fuentes:
    parquet: vista sobre read_parquet([archivos del tamano], union_by_name, filename)
    tabla  : vista sobre taxi_trips filtrada por anio/mes (tabla materializada UNA vez)
- Cada (tamano, fuente, consulta) usa una conexion NUEVA: la repeticion 1 es la
  ejecucion "fria" (conexion nueva, sin cache de metadatos/buffers de DuckDB) y
  las siguientes son "calientes". La cache de archivos del SO no se vacia.
- Se verifica que ambas fuentes devuelvan el mismo resultado.
- Tambien se mide el costo de materializar cada tamano (CSV *_creacion.csv).
"""
import argparse, csv, glob, os, re, sys, time
import duckdb

TIPOS = {"yellow": "tpep", "green": "lpep"}

# tamano -> {anio: lista de meses o None (todos)}
TAMANOS = {
    "1_mes (2024-01)": {2024: [1]},
    "3_meses (2024-01..03)": {2024: [1, 2, 3]},
    "2026 (8 meses)": {2026: None},
    "2024 (12 meses)": {2024: None},
    "2024+2026 (20 meses)": {2024: None, 2026: None},
}


def archivos(datos, tipo, spec):
    out = []
    for anio, meses in spec.items():
        for f in sorted(glob.glob(f"{datos}/{tipo}/{anio}/*.parquet")):
            m = int(re.search(r"-(\d{2})\.parquet$", f).group(1))
            if meses is None or m in meses:
                out.append(f)
    return out


def proyeccion(datos, spec=None):
    """SELECT normalizado yellow+green sobre los archivos de `spec` (None = todo)."""
    spec = spec or {2024: None, 2026: None}
    partes = []
    for tipo, p in TIPOS.items():
        lista = ", ".join("'%s'" % f for f in archivos(datos, tipo, spec))
        partes.append(f"""SELECT '{tipo}' AS tipo_taxi,
  {p}_pickup_datetime AS pickup_datetime, {p}_dropoff_datetime AS dropoff_datetime,
  passenger_count, trip_distance, PULocationID, DOLocationID, payment_type,
  fare_amount, tip_amount, total_amount,
  CAST(regexp_extract(filename, '(\\d{{4}})-(\\d{{2}})\\.parquet', 1) AS SMALLINT) AS anio,
  CAST(regexp_extract(filename, '(\\d{{4}})-(\\d{{2}})\\.parquet', 2) AS SMALLINT) AS mes
FROM read_parquet([{lista}], union_by_name = true, filename = true)""")
    return "\nUNION ALL\n".join(partes)


def filtro_tabla(spec):
    cond = []
    for anio, meses in spec.items():
        c = f"anio = {anio}"
        if meses is not None:
            c += " AND mes IN (%s)" % ", ".join(map(str, meses))
        cond.append(f"({c})")
    return " OR ".join(cond)


def leer_consultas(ruta):
    consultas, actual = {}, None
    for linea in open(ruta, encoding="utf-8"):
        m = re.match(r"-- @consulta (\S+) (\S+)", linea)
        if m:
            actual = f"{m.group(1)}_{m.group(2)}"
            consultas[actual] = []
        elif linea.startswith("-- @fin"):
            actual = None
        elif actual and not linea.startswith("--"):
            consultas[actual].append(linea)
    return {k: "".join(v).strip().rstrip(";") for k, v in consultas.items()}


def mb(ruta):
    return os.path.getsize(ruta) / 1e6


def normaliza(filas):
    return [tuple(round(x, 6) if isinstance(x, float) else x for x in f) for f in filas]


def crear_tabla(db, datos):
    """6.2: crea la tabla materializada completa y mide tiempo y tamano."""
    os.makedirs(os.path.dirname(db), exist_ok=True)
    if os.path.exists(db):
        os.remove(db)
    con = duckdb.connect(db)
    t = time.perf_counter()
    con.execute(f"CREATE TABLE taxi_trips AS {proyeccion(datos)}")
    con.execute("CHECKPOINT")
    seg = time.perf_counter() - t
    filas = con.execute("SELECT count(*) FROM taxi_trips").fetchone()[0]
    con.close()
    pq = sum(os.path.getsize(f) for f in glob.glob(f"{datos}/*/*/*.parquet")) / 1e6
    return {"tamano": "2024+2026 (20 meses)", "segundos_creacion": seg, "filas": filas,
            "mb_parquet": pq, "mb_duckdb": mb(db)}


def costo_creacion_por_tamano(datos, scratch):
    """Costo de materializar cada subconjunto (para el analisis de amortizacion)."""
    res = []
    for nombre, spec in TAMANOS.items():
        if os.path.exists(scratch):
            os.remove(scratch)
        con = duckdb.connect(scratch)
        t = time.perf_counter()
        con.execute(f"CREATE TABLE t AS {proyeccion(datos, spec)}")
        con.execute("CHECKPOINT")
        seg = time.perf_counter() - t
        filas = con.execute("SELECT count(*) FROM t").fetchone()[0]
        con.close()
        pq = sum(os.path.getsize(f) for tp in TIPOS for f in archivos(datos, tp, spec)) / 1e6
        res.append({"tamano": nombre, "segundos_creacion": seg, "filas": filas,
                    "mb_parquet": pq, "mb_duckdb": mb(scratch)})
    os.remove(scratch)
    return res


def abrir(fuente, db, datos, spec):
    if fuente == "tabla":
        con = duckdb.connect(db, read_only=True)
        con.execute(f"CREATE TEMP VIEW trips AS SELECT * FROM taxi_trips WHERE {filtro_tabla(spec)}")
    else:
        con = duckdb.connect()
        con.execute(f"CREATE TEMP VIEW trips AS {proyeccion(datos, spec)}")
    return con


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repeticiones", type=int, default=5)
    ap.add_argument("--salida", default="/workspace/docs/benchmark_resultados.csv")
    ap.add_argument("--db", default="/workspace/data/processed/taxi.duckdb")
    ap.add_argument("--datos", default="/workspace/data/raw")
    ap.add_argument("--sql", default="/workspace/sql/06_benchmark.sql")
    ap.add_argument("--tamanos", nargs="*", help="subcadenas de tamanos a correr (por defecto todos)")
    ap.add_argument("--solo-creacion", action="store_true")
    a = ap.parse_args()

    consultas = leer_consultas(a.sql)
    tamanos = {k: v for k, v in TAMANOS.items() if not a.tamanos or any(s in k for s in a.tamanos)}
    print(f"DuckDB {duckdb.__version__}; {len(consultas)} consultas; {len(tamanos)} tamanos; reps={a.repeticiones}")

    cre = crear_tabla(a.db, a.datos)
    print(f"Tabla creada: {cre['filas']:,} filas en {cre['segundos_creacion']:.2f}s; "
          f"{cre['mb_duckdb']:.0f} MB .duckdb vs {cre['mb_parquet']:.0f} MB parquet")
    scratch = os.path.join(os.path.dirname(a.db), "scratch_creacion.duckdb")
    creaciones = costo_creacion_por_tamano(a.datos, scratch)
    base = os.path.splitext(a.salida)[0]
    with open(base + "_creacion.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(creaciones[0]))
        w.writeheader()
        w.writerows(creaciones)
    for c in creaciones:
        print(f"  creacion {c['tamano']:24s} {c['segundos_creacion']:7.2f}s {c['filas']:>12,} filas "
              f"{c['mb_duckdb']:7.0f} MB duckdb / {c['mb_parquet']:7.0f} MB parquet")
    if a.solo_creacion:
        return

    filas_csv, discrepancias = [], 0
    for tam, spec in tamanos.items():
        for qid, sql in consultas.items():
            resultados = {}
            for fuente in ("parquet", "tabla"):
                con = abrir(fuente, a.db, a.datos, spec)
                for rep in range(1, a.repeticiones + 1):
                    t = time.perf_counter()
                    r = con.execute(sql).fetchall()
                    seg = time.perf_counter() - t
                    filas_csv.append({"tamano": tam, "consulta": qid, "fuente": fuente, "repeticion": rep,
                                      "fase": "frio" if rep == 1 else "caliente", "segundos": f"{seg:.6f}"})
                    resultados[fuente] = normaliza(r)
                con.close()
            ok = resultados["parquet"] == resultados["tabla"]
            discrepancias += not ok
            print(f"[{'OK' if ok else 'DIFIERE'}] {tam:24s} {qid:28s} filas={len(resultados['tabla'])}", flush=True)
    with open(a.salida, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(filas_csv[0]))
        w.writeheader()
        w.writerows(filas_csv)
    print(f"Resultados: {a.salida}; discrepancias entre fuentes: {discrepancias}")
    sys.exit(1 if discrepancias else 0)


if __name__ == "__main__":
    main()
