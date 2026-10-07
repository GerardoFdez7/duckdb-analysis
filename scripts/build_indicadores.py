#!/usr/bin/env python3
"""Ejercicios 7 y 8: construye la base de indicadores que usa el tablero de Metabase.

Ejecuta sql/07_indicadores.sql: crea las vistas sobre los Parquet (@setup),
materializa las tablas agregadas (@tabla) en data/processed/indicadores.duckdb
y luego corre cada tarjeta del tablero (@tarjeta) para verificar que funciona,
imprimiendo su resultado (o exportandolo a CSV con --csv).

Uso (dentro del contenedor):
    docker exec lab8-lab python scripts/build_indicadores.py
    docker exec lab8-lab python scripts/build_indicadores.py --csv docs/indicadores

No hay anios en el codigo ni en el SQL: al descargar un anio nuevo basta con
volver a ejecutarlo. La base se escribe en un archivo temporal y se reemplaza
al final, de modo que Metabase nunca ve una base a medio construir.
"""
import argparse
import os
import re
import sys
import time

import duckdb
import pandas as pd

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 30)
pd.set_option("display.max_rows", 60)


def leer_bloques(ruta):
    """Devuelve [(tipo, id, visualizacion, titulo, sql)] segun los marcadores del archivo."""
    bloques, actual = [], None
    for linea in open(ruta, encoding="utf-8"):
        m = re.match(r"-- @(setup|tabla|tarjeta|fin)\b\s*(.*)", linea)
        if m:
            if actual:
                bloques.append(actual)
            tipo, resto = m.group(1), m.group(2).strip()
            if tipo == "fin":
                actual = None
                continue
            partes = [p.strip() for p in resto.split("|")] if resto else []
            actual = {"tipo": tipo, "id": partes[0] if partes else tipo,
                      "visualizacion": partes[1] if len(partes) > 1 else None,
                      "titulo": partes[2] if len(partes) > 2 else None, "lineas": []}
        elif actual is not None:
            actual["lineas"].append(linea)
    if actual:
        bloques.append(actual)
    for b in bloques:
        b["sql"] = "".join(b.pop("lineas")).strip()
    return bloques


def sentencias(sql):
    """Separa un bloque en sentencias (';' al final de linea), sin lineas de comentario."""
    for s in re.split(r";\s*\n", sql + "\n"):
        limpio = "\n".join(l for l in s.splitlines() if not l.strip().startswith("--")).strip()
        if limpio:
            yield limpio.rstrip(";")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sql", default=os.path.join(BASE, "sql", "07_indicadores.sql"))
    ap.add_argument("--db", default=os.path.join(BASE, "data", "processed", "indicadores.duckdb"))
    ap.add_argument("--csv", help="directorio donde guardar el resultado de cada tarjeta")
    ap.add_argument("--memoria", default="2GB", help="memory_limit de DuckDB (por defecto 2GB)")
    a = ap.parse_args()

    bloques = leer_bloques(a.sql)
    tmp = a.db + ".tmp"
    for f in (tmp, tmp + ".wal"):
        if os.path.exists(f):
            os.remove(f)
    os.makedirs(os.path.dirname(a.db), exist_ok=True)

    con = duckdb.connect(tmp)
    con.execute(f"SET memory_limit='{a.memoria}'; SET preserve_insertion_order=false;"
                " SET temp_directory='/tmp/duckdb_tmp'")
    inicio = time.perf_counter()
    for b in bloques:
        if b["tipo"] not in ("setup", "tabla"):
            continue
        t = time.perf_counter()
        for s in sentencias(b["sql"]):
            con.execute(s)
        if b["tipo"] == "tabla":
            n = con.execute(f'SELECT count(*) FROM {b["id"]}').fetchone()[0]
            print(f"tabla {b['id']:12s} {n:>8,} filas  {time.perf_counter() - t:6.1f} s", flush=True)
    # Las vistas leen Parquet: se eliminan para que Metabase solo vea las tablas agregadas.
    con.execute("DROP VIEW viajes_validos; DROP VIEW viajes")
    anios = con.execute("SELECT string_agg(DISTINCT anio::VARCHAR, ', ' ORDER BY anio::VARCHAR) FROM ind_mensual").fetchone()[0]
    con.execute("CHECKPOINT")
    con.close()
    os.replace(tmp, a.db)
    print(f"\nBase {a.db} lista en {time.perf_counter() - inicio:.1f} s (anios: {anios})")

    con = duckdb.connect(a.db, read_only=True)
    if a.csv:
        os.makedirs(a.csv, exist_ok=True)
    for b in bloques:
        if b["tipo"] != "tarjeta":
            continue
        df = con.execute(b["sql"]).df()
        print(f"\n>> {b['id']} [{b['visualizacion']}] {b['titulo']}  ({len(df)} filas)")
        print(df.to_string(index=False, max_rows=40))
        if a.csv:
            df.to_csv(os.path.join(a.csv, f"{b['id']}.csv"), index=False)
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
