#!/usr/bin/env python3
"""Verifica que los archivos descargados esten completos (Ejercicios 2.7 y 5.5).

Para cada archivo local compara su tamano con el Content-Length que informa la
TLC y comprueba que el footer Parquet sea legible (pyarrow). Ademas lista los
meses que existen en el servidor pero faltan localmente.

Uso: python scripts/verify_downloads.py [--years 2026 2024]
"""
import argparse
import sys

import pyarrow.parquet as pq
import requests

from download_data import (ANIO_POR_DEFECTO, TIPOS_TAXI, construir_url,
                           esta_publicado, ruta_destino)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", type=int, nargs="+", default=[ANIO_POR_DEFECTO])
    args = ap.parse_args()
    ok = faltan = malos = 0
    print(f"{'archivo':50} {'bytes':>12} {'remoto':>12} {'filas':>10}  estado")
    for anio in sorted(set(args.years)):
        for tipo in TIPOS_TAXI:
            for mes in range(1, 13):
                destino = ruta_destino(tipo, anio, mes)
                url = construir_url(tipo, anio, mes)
                if not destino.exists():
                    if esta_publicado(url):
                        print(f"{destino.name:50} {'-':>12} {'-':>12} {'-':>10}  FALTA (publicado)")
                        faltan += 1
                    continue
                remoto = int(requests.head(url, timeout=60).headers.get("Content-Length", -1))
                local = destino.stat().st_size
                try:
                    filas = pq.ParquetFile(destino).metadata.num_rows
                    legible = True
                except Exception:
                    filas, legible = -1, False
                bien = legible and local == remoto
                print(f"{destino.name:50} {local:12} {remoto:12} {filas:10}  {'OK' if bien else 'ERROR'}")
                ok += bien
                malos += not bien
    print(f"\nOK={ok} faltantes={faltan} con_error={malos}")
    return 1 if (faltan or malos) else 0


if __name__ == "__main__":
    sys.exit(main())
