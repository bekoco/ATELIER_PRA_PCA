import os
import sqlite3
from datetime import datetime
from flask import Flask, jsonify, request

DB_PATH = os.getenv("DB_PATH", "/data/app.db")

app = Flask(__name__)

# ---------- DB helpers ----------
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    return conn

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = get_conn()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts TEXT NOT NULL,
            message TEXT NOT NULL
        )
    """)
    conn.commit()
    conn.close()

# ---------- Routes ----------

@app.get("/")
def hello():
    init_db()
    return jsonify(status="Bonjour tout le monde !")


@app.get("/health")
def health():
    init_db()
    return jsonify(status="ok")

@app.get("/add")
def add():
    init_db()

    msg = request.args.get("message", "hello")
    ts = datetime.utcnow().isoformat() + "Z"

    conn = get_conn()
    conn.execute(
        "INSERT INTO events (ts, message) VALUES (?, ?)",
        (ts, msg)
    )
    conn.commit()
    conn.close()

    return jsonify(
        status="added",
        timestamp=ts,
        message=msg
    )

@app.get("/consultation")
def consultation():
    init_db()

    conn = get_conn()
    cur = conn.execute(
        "SELECT id, ts, message FROM events ORDER BY id DESC LIMIT 50"
    )

    rows = [
        {"id": r[0], "timestamp": r[1], "message": r[2]}
        for r in cur.fetchall()
    ]

    conn.close()

    return jsonify(rows)

@app.get("/count")
def count():
    init_db()

    conn = get_conn()
    cur = conn.execute("SELECT COUNT(*) FROM events")
    n = cur.fetchone()[0]
    conn.close()

    return jsonify(count=n)

@app.get("/status")
def status():
    import os
    import time
    from flask import jsonify

    init_db() # On s'assure que la DB est initialisée

    # 1. Compter les événements dans la base de données (Le vrai code est ici !)
    conn = get_conn()
    cur = conn.execute("SELECT COUNT(*) FROM events")
    nombre_evenements = cur.fetchone()[0]
    conn.close()

    # 2. Analyser le dossier des backups
    backup_dir = '/backup'
    last_backup_file = "Aucun backup"
    backup_age_seconds = 0

    if os.path.exists(backup_dir):
        files = [f for f in os.listdir(backup_dir) if os.path.isfile(os.path.join(backup_dir, f))]
        
        if files:
            # Trouver le fichier le plus récent
            last_backup_file = max(files, key=lambda f: os.path.getmtime(os.path.join(backup_dir, f)))
            last_backup_path = os.path.join(backup_dir, last_backup_file)
            
            # Calculer son âge en secondes
            backup_age_seconds = int(time.time() - os.path.getmtime(last_backup_path))

    # 3. Retourner le résultat en JSON
    return jsonify({
        "count": nombre_evenements,
        "last_backup_file": last_backup_file,
        "backup_age_seconds": backup_age_seconds
    })

# ---------- Main ----------
if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080)