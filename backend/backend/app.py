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
        
        # --- Safe Migration: Add created_at and balance to member table if missing ---
        try:
            from sqlalchemy import inspect
            inspector = inspect(db.engine)
            columns = [col['name'] for col in inspector.get_columns('member')]
            
            if 'created_at' not in columns:
                print("Migration: Adding 'created_at' column to member table...")
                db.session.execute(db.text("ALTER TABLE member ADD COLUMN created_at DATETIME"))
                db.session.execute(db.text("UPDATE member SET created_at = datetime('now') WHERE created_at IS NULL"))
                db.session.commit()
                print("Migration for created_at complete.")
                
            if 'balance' not in columns:
                print("Migration: Adding 'balance' column to member table...")
                db.session.execute(db.text("ALTER TABLE member ADD COLUMN balance FLOAT DEFAULT 0.0"))
                db.session.commit()
                print("Migration for balance complete.")

            diyah_columns = [col['name'] for col in inspector.get_columns('diyah')]
            if 'is_fully_paid' not in diyah_columns:
                print("Migration: Adding 'is_fully_paid' column to diyah table...")
                db.session.execute(db.text("ALTER TABLE diyah ADD COLUMN is_fully_paid BOOLEAN DEFAULT 0"))
                db.session.commit()
                print("Migration for is_fully_paid complete.")
        except Exception as e:
            print("Migration warning: " + str(e).encode('ascii', 'ignore').decode('ascii'))

        # --- Initialize Account Ledger and Balances ---
        try:
            from models import Member, Diyah, DiyahPayment, WalletTransaction
            tx_count = WalletTransaction.query.count()
            if tx_count == 0:
                print("Initializing ledger transactions and balances for existing data...")
                for member in Member.query.all():
                    member.balance = 0.0
                
                all_diyahs = Diyah.query.all()
                for d in all_diyahs:
                    eligible_members = Member.query.filter(Member.created_at <= d.created_at, Member.role != 'owner').all()
                    for m in eligible_members:
                        if d.caused_by_id == m.id and d.owner_percentage is not None:
                            share = d.amount * (d.owner_percentage / 100.0)
                        else:
                            share = d.share_per_member
                        
                        tx = WalletTransaction(
                            member_id=m.id,
                            diyah_id=d.id,
                            amount=-share,
                            transaction_type='diyah_share',
                            description=f"خصم حصة دية: {d.title}",
                            created_at=d.created_at
                        )
                        db.session.add(tx)
                        m.balance -= share

                all_payments = DiyahPayment.query.all()
                for p in all_payments:
                    d = Diyah.query.get(p.diyah_id)
                    m = Member.query.get(p.member_id)
                    if not d or not m:
                        continue
                    
                    if p.amount is not None:
                        paid_amount = p.amount
                    else:
                        if d.caused_by_id == m.id and d.owner_percentage is not None:
                            paid_amount = d.amount * (d.owner_percentage / 100.0)
                        else:
                            paid_amount = d.share_per_member
                    
                    tx = WalletTransaction(
                        member_id=m.id,
                        diyah_id=d.id,
                        amount=paid_amount,
                        transaction_type='cash_payment',
                        description=f"تسديد نقدي لدية: {d.title}",
                        created_at=p.paid_at
                    )
                    db.session.add(tx)
                    m.balance += paid_amount
                
                db.session.commit()
                print("Ledger initialization complete.")
            else:
                print("Verifying and updating member balances...")
                for m in Member.query.all():
                    if m.role == 'owner':
                        m.balance = 0.0
                        continue
                    tx_sum = db.session.query(db.func.sum(WalletTransaction.amount)).filter_by(member_id=m.id).scalar() or 0.0
                    m.balance = round(tx_sum, 2)
                db.session.commit()
                print("Member balances verified.")
        except Exception as e:
            print("Ledger initialization/verification error: " + str(e).encode('ascii', 'ignore').decode('ascii'))
        
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