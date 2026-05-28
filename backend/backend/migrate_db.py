import sqlite3
import os

db_path = os.path.join(os.path.dirname(__file__), 'app.db')

def migrate():
    if not os.path.exists(db_path):
        print("Database file not found.")
        return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Add is_finished column to diyah table
    try:
        cursor.execute("ALTER TABLE diyah ADD COLUMN is_finished BOOLEAN DEFAULT 0")
        print("Added 'is_finished' column to 'diyah' table.")
    except sqlite3.OperationalError:
        print("'is_finished' column already exists.")

    # Add caused_by_id column to diyah table
    try:
        cursor.execute("ALTER TABLE diyah ADD COLUMN caused_by_id INTEGER REFERENCES member(id)")
        print("Added 'caused_by_id' column to 'diyah' table.")
    except sqlite3.OperationalError:
        print("'caused_by_id' column already exists.")

    # Add owner_percentage column to diyah table
    try:
        cursor.execute("ALTER TABLE diyah ADD COLUMN owner_percentage FLOAT")
        print("Added 'owner_percentage' column to 'diyah' table.")
    except sqlite3.OperationalError:
        print("'owner_percentage' column already exists.")

    # Add amount column to diyah_payment table
    try:
        cursor.execute("ALTER TABLE diyah_payment ADD COLUMN amount FLOAT")
        print("Added 'amount' column to 'diyah_payment' table.")
    except sqlite3.OperationalError:
        print("'amount' column already exists.")

    conn.commit()
    conn.close()
    print("Migration complete.")

if __name__ == "__main__":
    migrate()
