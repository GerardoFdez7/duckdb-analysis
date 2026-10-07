#!/usr/bin/env python3
"""Ejecuta un archivo .sql con DuckDB e imprime cada resultado.

Uso: python scripts/run_sql.py sql/03_exploracion_parquet.sql [--db RUTA.duckdb] [--solo-lectura]
--solo-lectura permite leer una base que Metabase tiene abierta (p. ej. indicadores.duckdb).
Las sentencias se separan por ';'. Los comentarios '-- Qn ...' se muestran como titulo.
"""
import argparse
import re
import sys

import duckdb
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 50)
pd.set_option("display.max_rows", 100)


def ejecutar(archivo: str, con) -> None:
    texto = open(archivo, encoding="utf-8").read()
    for bloque in re.split(r";\s*\n", texto):
        sql = bloque.strip()
        if not sql or all(l.startswith("--") for l in sql.splitlines() if l.strip()):
            continue
        titulos = [l for l in sql.splitlines() if l.startswith("-- Q")]
        print("\n>>", titulos[0][3:] if titulos else sql.splitlines()[0])
        print(con.execute(sql).df().to_string(index=False))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("archivo")
    ap.add_argument("--db", default=":memory:")
    ap.add_argument("--solo-lectura", action="store_true")
    a = ap.parse_args()
    ejecutar(a.archivo, duckdb.connect(a.db, read_only=a.solo_lectura))
    return 0


if __name__ == "__main__":
    sys.exit(main())
