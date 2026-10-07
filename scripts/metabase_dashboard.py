#!/usr/bin/env python3
"""Ejercicio 7.5: crea (o recrea) el tablero de indicadores en Metabase via su API.

Pasos:
  1. Si Metabase esta recien instalado, hace el setup inicial con el usuario
     administrador indicado; si no, inicia sesion con ese usuario.
  2. Registra la base DuckDB data/processed/indicadores.duckdb (solo lectura).
  3. Crea una tarjeta (pregunta SQL nativa) por cada bloque "-- @tarjeta" de
     sql/07_indicadores.sql, con la visualizacion indicada en el marcador y la
     pregunta/lectura de los comentarios como descripcion.
  4. Organiza las tarjetas en el tablero "Lab 8 - Indicadores NYC Taxi".

Tras reconstruir la base con build_indicadores.py hay que reiniciar Metabase
(docker compose restart metabase): su driver DuckDB conserva abierta la version
anterior del archivo. El script lo detecta y se detiene si no se hizo.

Es idempotente: al volver a ejecutarlo archiva las tarjetas y el tablero
anteriores de la coleccion y los crea de nuevo (p. ej. tras agregar 2025).

Uso (dentro del contenedor, Metabase se alcanza por el nombre del servicio):
    docker exec lab8-lab python scripts/metabase_dashboard.py
Opciones: --url, --email, --password, --sql, --db-file y --publico (crea un enlace
publico local del tablero, para capturarlo con un navegador headless).
Credenciales por defecto (solo para el ambiente local): lab8@example.com / Lab8-duckdb!
"""
import argparse
import os
import sys
import time

import duckdb
import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_indicadores import leer_bloques  # noqa: E402

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOMBRE_DB = "Indicadores NYC Taxi (DuckDB)"
NOMBRE_COLECCION = "Lab 8 - DuckDB"
NOMBRE_TABLERO = "Lab 8 - Indicadores NYC Taxi"

# Disposicion en la grilla de 24 columnas: id -> (fila, columna, ancho, alto)
DISPOSICION = {
    "K1": (2, 0, 6, 3), "K2": (2, 6, 6, 3), "K3": (2, 12, 6, 3), "K4": (2, 18, 6, 3),
    "I1": (5, 0, 12, 7), "I2": (5, 12, 12, 7),
    "I3": (12, 0, 12, 7), "I4": (12, 12, 12, 7),
    "I5": (19, 0, 12, 7), "I6": (19, 12, 12, 7),
    "I7": (26, 0, 12, 7), "I8": (26, 12, 12, 7),
    "I9": (33, 0, 12, 7), "I10": (33, 12, 12, 7),
    "I11": (40, 0, 12, 7), "I12": (40, 12, 12, 7),
    "T1": (47, 0, 24, 7),
}
ENCABEZADO = (
    "# NYC TLC - Taxis amarillos y verdes\n"
    "Indicadores calculados con DuckDB sobre los Parquet de la TLC "
    "(tablas agregadas en `data/processed/indicadores.duckdb`, SQL en `sql/07_indicadores.sql`). "
    "Solo viajes plausibles: pickup dentro del mes del archivo, 0-100 mi, 1-360 min, 0-1000 USD."
)


class Metabase:
    def __init__(self, url):
        self.url = url.rstrip("/")
        self.s = requests.Session()

    def api(self, metodo, ruta, **kw):
        r = self.s.request(metodo, f"{self.url}/api{ruta}", timeout=120, **kw)
        if not r.ok:
            raise RuntimeError(f"{metodo} {ruta} -> {r.status_code}: {r.text[:500]}")
        return r.json() if r.content else None

    def esperar(self, segundos=300):
        fin = time.time() + segundos
        while time.time() < fin:
            try:
                if self.s.get(f"{self.url}/api/health", timeout=10).json().get("status") == "ok":
                    return
            except (requests.RequestException, ValueError):
                pass
            time.sleep(5)
        raise RuntimeError("Metabase no respondio a tiempo")

    def autenticar(self, email, password):
        props = self.api("GET", "/session/properties")
        if not props.get("has-user-setup"):
            print("Setup inicial de Metabase (usuario administrador)")
            self.api("POST", "/setup", json={
                "token": props["setup-token"],
                "user": {"email": email, "password": password, "first_name": "Lab", "last_name": "Ocho",
                         "site_name": "Lab 8 DuckDB"},
                "prefs": {"site_name": "Lab 8 DuckDB", "site_locale": "es", "allow_tracking": False},
            })
        sesion = self.api("POST", "/session", json={"username": email, "password": password})
        self.s.headers["X-Metabase-Session"] = sesion["id"]


def descripcion(sql):
    """Lineas '-- Pregunta:' / '-- Lectura:' del bloque, usadas como descripcion de la tarjeta."""
    lineas = [l.strip()[3:].strip() for l in sql.splitlines() if l.strip().startswith("-- ")]
    return " ".join(lineas) or None


def ajustes(vis, columnas):
    """visualization_settings segun el tipo de grafico y las columnas devueltas."""
    if vis in ("line", "bar", "row", "area"):
        dims = columnas[:-1] if len(columnas) >= 3 else columnas[:1]
        cfg = {"graph.dimensions": dims, "graph.metrics": [columnas[-1]],
               "graph.x_axis.title_text": dims[0], "graph.y_axis.title_text": columnas[-1]}
        if vis == "bar" and len(dims) > 1:
            cfg["stackable.stack_type"] = "stacked"
        return cfg
    return {}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=os.environ.get("MB_URL", "http://metabase:3000"))
    ap.add_argument("--email", default=os.environ.get("MB_EMAIL", "lab8@example.com"))
    ap.add_argument("--password", default=os.environ.get("MB_PASSWORD", "Lab8-duckdb!"))
    ap.add_argument("--sql", default=os.path.join(BASE, "sql", "07_indicadores.sql"))
    ap.add_argument("--db-file", default="/workspace/data/processed/indicadores.duckdb",
                    help="ruta del .duckdb vista desde el contenedor de Metabase")
    ap.add_argument("--publico", action="store_true", help="crea un enlace publico local para capturas")
    a = ap.parse_args()

    mb = Metabase(a.url)
    mb.esperar()
    mb.autenticar(a.email, a.password)

    # Base de datos DuckDB (solo lectura: el contenedor lab la reconstruye)
    detalles = {"database_file": a.db_file, "read_only": True, "old_implicit_casting": True}
    bases = mb.api("GET", "/database")
    bases = bases["data"] if isinstance(bases, dict) else bases
    db = next((d for d in bases if d["name"] == NOMBRE_DB), None)
    if db:
        mb.api("PUT", f"/database/{db['id']}", json={"details": detalles})
    else:
        db = mb.api("POST", "/database", json={"engine": "duckdb", "name": NOMBRE_DB, "details": detalles})
    mb.api("POST", f"/database/{db['id']}/sync_schema")
    print(f"Base registrada: {NOMBRE_DB} (id {db['id']}) -> {a.db_file}")

    # build_indicadores.py reemplaza el archivo y el driver DuckDB de Metabase mantiene
    # abierta la instancia anterior: sin reiniciar Metabase, el tablero mostraria datos viejos.
    control = "SELECT sum(registros) FROM ind_mensual"
    with duckdb.connect(a.db_file, read_only=True) as con:
        esperado = con.execute(control).fetchone()[0]
    visto = mb.api("POST", "/dataset", json={"database": db["id"], "type": "native",
                                              "native": {"query": control}})["data"]["rows"][0][0]
    if int(visto) != int(esperado):
        sys.exit(f"Metabase ve una version anterior de la base ({int(visto):,} registros, el archivo "
                 f"tiene {int(esperado):,}). Ejecute 'docker compose restart metabase' y repita.")

    # Coleccion: se archiva lo creado en ejecuciones anteriores
    col = next((c for c in mb.api("GET", "/collection") if c.get("name") == NOMBRE_COLECCION
                and not c.get("archived")), None)
    if col is None:
        col = mb.api("POST", "/collection", json={"name": NOMBRE_COLECCION, "color": "#509EE3"})
    items = mb.api("GET", f"/collection/{col['id']}/items")
    for it in (items["data"] if isinstance(items, dict) else items):
        if it["model"] in ("card", "dashboard"):
            mb.api("PUT", f"/{it['model']}/{it['id']}", json={"archived": True})

    # Tarjetas
    tarjetas = {}
    for b in (b for b in leer_bloques(a.sql) if b["tipo"] == "tarjeta"):
        consulta = {"database": db["id"], "type": "native", "native": {"query": b["sql"]}}
        res = mb.api("POST", "/dataset", json=consulta)
        if res.get("status") == "failed" or res.get("error"):
            raise RuntimeError(f"La tarjeta {b['id']} fallo en Metabase: {res.get('error')}")
        columnas = [c["name"] for c in res["data"]["cols"]]
        carta = mb.api("POST", "/card", json={
            "name": b["titulo"],
            "description": descripcion(b["sql"]),
            "display": b["visualizacion"], "dataset_query": consulta,
            "visualization_settings": ajustes(b["visualizacion"], columnas),
            "collection_id": col["id"],
        })
        tarjetas[b["id"]] = carta["id"]
        print(f"  tarjeta {b['id']:4s} {b['visualizacion']:6s} {len(res['data']['rows']):4d} filas  {b['titulo']}")

    # Tablero
    tablero = mb.api("POST", "/dashboard", json={"name": NOMBRE_TABLERO, "collection_id": col["id"],
                                                  "description": "Ejercicios 7 y 8 del Lab 8 (CC3084)."})
    dashcards = [{"id": -1, "card_id": None, "row": 0, "col": 0, "size_x": 24, "size_y": 3,
                  "visualization_settings": {"virtual_card": {"name": None, "display": "text",
                                                              "visualization_settings": {}, "archived": False},
                                             "text": ENCABEZADO}}]
    for i, (cid, card_id) in enumerate(tarjetas.items(), start=2):
        fila, colu, ancho, alto = DISPOSICION.get(cid, (54 + 7 * i, 0, 12, 7))
        dashcards.append({"id": -i, "card_id": card_id, "row": fila + 1, "col": colu,
                          "size_x": ancho, "size_y": alto, "visualization_settings": {}})
    mb.api("PUT", f"/dashboard/{tablero['id']}", json={"dashcards": dashcards})
    print(f"\nTablero listo: http://127.0.0.1:3000/dashboard/{tablero['id']}  ({len(tarjetas)} tarjetas)")

    if a.publico:
        # Enlace publico (sin login) para capturar el tablero con un navegador headless.
        # Metabase solo escucha en 127.0.0.1, asi que el enlace no sale de la maquina.
        mb.api("PUT", "/setting/enable-public-sharing", json={"value": True})
        uuid = mb.api("POST", f"/dashboard/{tablero['id']}/public_link")["uuid"]
        print(f"Enlace publico: http://127.0.0.1:3000/public/dashboard/{uuid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
