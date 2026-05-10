import os
from flask import Flask
from flask_cors import CORS
from models import db
from routes import api
import firebase_admin
from firebase_admin import credentials

def create_app():
    app = Flask(__name__)
    CORS(app, resources={r"/*": {"origins": "*"}}, allow_headers=["Content-Type", "Authorization", "X-User-Id", "X-App-Token"])

    # Database Configuration
    basedir = os.path.abspath(os.path.dirname(__file__))
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///' + os.path.join(basedir, 'app.db')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # Initialize Database
    db.init_app(app)

    # Initialize Firebase Admin
    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(os.path.join(basedir, 'firebase-key.json.json'))
            firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"Firebase Admin Initialization Error: {e}")

    # Register Blueprints (Routes)
    app.register_blueprint(api)

    # Create tables and required directories if they do not exist
    with app.app_context():
        db.create_all()
        
        # --- Safe Migration: Add created_at to member table if missing ---
        import sqlite3
        db_path = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'app.db')
        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("PRAGMA table_info(member)")
            columns = [row[1] for row in cursor.fetchall()]
            if 'created_at' not in columns:
                print("🔧 Migration: Adding 'created_at' column to member table...")
                # SQLite does NOT allow non-constant defaults in ALTER TABLE
                # So we add it as NULL first, then fill existing rows
                cursor.execute("ALTER TABLE member ADD COLUMN created_at DATETIME")
                cursor.execute("UPDATE member SET created_at = datetime('now') WHERE created_at IS NULL")
                conn.commit()
                print("✅ Migration complete.")
            conn.close()
        except Exception as e:
            print(f"Migration warning: {e}")
        
        # Auto-create download directories
        platforms = ['android', 'ios', 'windows', 'macos', 'linux']
        for p in platforms:
            dir_path = os.path.join(basedir, 'static', 'downloads', p)
            os.makedirs(dir_path, exist_ok=True)
            
        # Initialize Owner
        from models import Member
        owner = Member.query.filter_by(role='owner').first()
        if not owner:
            owner = Member(
                full_name="المالك (المبرمج)",
                phone="0",
                username="q.e_lith_j.s",
                role="owner"
            )
            owner.set_password("l1i2t3h4")
            db.session.add(owner)
            db.session.commit()

    return app

if __name__ == '__main__':
    app = create_app()
    # Runs the server in Debug Mode and allows local network connections (e.g., from a real phone)
    app.run(host='0.0.0.0', debug=True, port=5000)