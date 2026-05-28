from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()

# --- Models ---
class Member(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    full_name = db.Column(db.String(150), nullable=False)
    phone = db.Column(db.String(20), nullable=False)
    is_wajeeh = db.Column(db.Boolean, default=False)
    
    # Auth Fields
    username = db.Column(db.String(100), unique=True, nullable=True)
    password = db.Column(db.String(200), nullable=True)
    role = db.Column(db.String(20), default='member') # owner, sheikh, admin, wajeeh, member
    fcm_token = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    balance = db.Column(db.Float, default=0.0)
    
    # Optional foreign key linking a member to a Wajeeh (who is also a Member)
    wajeeh_id = db.Column(db.Integer, db.ForeignKey('member.id'), nullable=True)
    
    # Relationship to easily access members under this Wajeeh
    members = db.relationship('Member', backref=db.backref('wajeeh', remote_side=[id]))

    def set_password(self, password):
        self.password = generate_password_hash(password)
        
    def check_password(self, password):
        if not self.password: return False
        return check_password_hash(self.password, password)

    def to_dict(self):
        return {
            "id": self.id,
            "full_name": self.full_name,
            "phone": self.phone,
            "is_wajeeh": self.is_wajeeh,
            "wajeeh_id": self.wajeeh_id,
            "wajeeh_name": self.wajeeh.full_name if self.wajeeh else None,
            "username": self.username,
            "role": self.role,
            "fcm_token": self.fcm_token,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "balance": self.balance
        }

class Diyah(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    amount = db.Column(db.Float, nullable=False)
    description = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    manual_date = db.Column(db.DateTime, nullable=True)
    is_finished = db.Column(db.Boolean, default=False)
    is_fully_paid = db.Column(db.Boolean, default=False)
    caused_by_id = db.Column(db.Integer, db.ForeignKey('member.id'), nullable=True)

    total_members_count = db.Column(db.Integer, default=0)
    share_per_member = db.Column(db.Float, default=0.0)
    rounded_share = db.Column(db.Float, nullable=True)
    owner_percentage = db.Column(db.Float, nullable=True) # Percentage owner pays (e.g., 35.0)
    paid_from_old_diyah_fund = db.Column(db.Float, default=0.0)

    caused_by = db.relationship('Member', foreign_keys=[caused_by_id], backref='diyahs_caused')
    payments = db.relationship('DiyahPayment', backref='diyah', cascade='all, delete-orphan')

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "amount": self.amount,
            "description": self.description,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "manual_date": self.manual_date.isoformat() if self.manual_date else None,
            "is_finished": self.is_finished,
            "is_fully_paid": self.is_fully_paid,
            "caused_by_id": self.caused_by_id,
            "caused_by_name": self.caused_by.full_name if self.caused_by else None,
            "total_members_count": self.total_members_count,
            "share_per_member": self.share_per_member,
            "rounded_share": self.rounded_share,
            "owner_percentage": self.owner_percentage,
            "paid_from_old_diyah_fund": self.paid_from_old_diyah_fund
        }

class DiyahPayment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    diyah_id = db.Column(db.Integer, db.ForeignKey('diyah.id'), nullable=False)
    member_id = db.Column(db.Integer, db.ForeignKey('member.id'), nullable=False)
    amount = db.Column(db.Float, nullable=True) # Actual amount paid
    paid_at = db.Column(db.DateTime, default=datetime.utcnow)

    member = db.relationship('Member', backref='payments_made')

    def to_dict(self):
        return {
            "id": self.id,
            "diyah_id": self.diyah_id,
            "member_id": self.member_id,
            "amount": self.amount,
            "paid_at": self.paid_at.isoformat()
        }

class WalletTransaction(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    member_id = db.Column(db.Integer, db.ForeignKey('member.id'), nullable=False)
    diyah_id = db.Column(db.Integer, db.ForeignKey('diyah.id'), nullable=True)
    amount = db.Column(db.Float, nullable=False) # Positive for credit (payment), negative for debit (obligation)
    transaction_type = db.Column(db.String(50), nullable=False) # 'diyah_share', 'cash_payment', 'admin_adjustment'
    description = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    member = db.relationship('Member', backref='wallet_transactions')
    diyah = db.relationship('Diyah', backref='wallet_transactions')

    def to_dict(self):
        return {
            "id": self.id,
            "member_id": self.member_id,
            "member_name": self.member.full_name if self.member else None,
            "diyah_id": self.diyah_id,
            "diyah_title": self.diyah.title if self.diyah else None,
            "amount": self.amount,
            "transaction_type": self.transaction_type,
            "description": self.description,
            "created_at": self.created_at.isoformat()
        }

class Notification(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    message = db.Column(db.Text, nullable=False)
    target_user_id = db.Column(db.Integer, db.ForeignKey('member.id'), nullable=True) # If null, it's for everyone
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "message": self.message,
            "target_user_id": self.target_user_id,
            "created_at": self.created_at.isoformat()
        }
