import sqlite3
from pathlib import Path

OUTPUT_DB = Path(r"app/src/main/assets/knowledge.db")
if OUTPUT_DB.exists():
    OUTPUT_DB.unlink()

conn = sqlite3.connect(OUTPUT_DB)
conn.execute("""
CREATE TABLE knowledge_nodes (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    subject TEXT NOT NULL,
    chapter TEXT,
    parent_id TEXT,
    description TEXT,
    content TEXT,
    exam_frequency INTEGER NOT NULL DEFAULT 0,
    sort_weight INTEGER NOT NULL DEFAULT 0
)
""")
conn.commit()
conn.close()
print("Database created successfully!")
