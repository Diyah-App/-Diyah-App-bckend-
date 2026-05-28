from flask import Blueprint, jsonify, request, send_from_directory, abort
import os
import time
import hashlib
from collections import defaultdict
from models import db, Member, Diyah, DiyahPayment, Notification, WalletTransaction
from sqlalchemy import func, case
from datetime import datetime
from firebase_admin import messaging, remote_config

api = Blueprint('api', __name__)

APP_TOKEN = "Tribal_Secure_App_Token_2026_X77"

# --- Rate Limiting Storage (in-memory) ---
# Structure: {ip_hash: [(timestamp, success), ...]}
_login_attempts = defaultdict(list)
_LOGIN_WINDOW_SECONDS = 900  # 15 minutes
_MAX_FAILED_ATTEMPTS = 7     # max failed attempts per window

def _get_ip_hash():
    """Get a hashed version of the client IP for privacy-safe rate limiting."""
    ip = request.remote_addr or 'unknown'
    return hashlib.sha256(ip.encode()).hexdigest()[:16]

def _is_rate_limited():
    """Check if this IP is rate-limited for login. Returns True if blocked."""
    ip_hash = _get_ip_hash()
    now = time.time()
    window_start = now - _LOGIN_WINDOW_SECONDS
    
    # Clean old entries
    _login_attempts[ip_hash] = [
        (ts, ok) for ts, ok in _login_attempts[ip_hash] if ts > window_start
    ]
    
    failed = sum(1 for _, ok in _login_attempts[ip_hash] if not ok)
    return failed >= _MAX_FAILED_ATTEMPTS

def _record_login_attempt(success: bool):
    """Record a login attempt for rate limiting."""
    ip_hash = _get_ip_hash()
    _login_attempts[ip_hash].append((time.time(), success))


def log_to_file(message):
    try:
        log_path = os.path.join(os.path.dirname(__file__), 'request_logs.txt')
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(f"[{datetime.now().isoformat()}] {message}\n")
    except Exception as e:
        print(f"Logging error: {e}")

def log_action(actor_id, message):
    """Log an action performed by a user actor."""
    log_to_file(f"Action by user {actor_id}: {message}")

@api.before_request
def check_app_token():
    log_to_file(f"Incoming Request: {request.method} {request.path}")
    # Skip for simple public status, public downloads, and home
    if request.path == '/api/status' or request.path.startswith('/api/download/') or request.path == '/':
        return
        
    if request.method == 'OPTIONS':
        return # Allow CORS preflight
        
    app_token = request.headers.get('X-App-Token')
    if app_token != APP_TOKEN:
        log_to_file(f"Security Block! Invalid or missing App Token for: {request.method} {request.path}")
        return jsonify({'error': 'Unauthorized! Invalid App Fingerprint.'}), 403

    # Basic payload size limit: reject overly large JSON bodies (> 512KB)
    content_length = request.content_length
    if content_length and content_length > 512 * 1024:
        log_to_file(f"Security Block! Payload too large: {content_length} bytes for {request.path}")
        return jsonify({'error': 'Payload too large.'}), 413

@api.route('/api/download/<platform>', methods=['GET'])
def download_app(platform):
    # Security check: only allow specific platform names
    valid_platforms = ['android', 'ios', 'windows', 'macos', 'linux']
    if platform not in valid_platforms:
        return abort(404, description="Invalid platform.")
        
    # Build the path: backend/static/downloads/<platform>
    base_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'backend', 'static', 'downloads', platform)
    
    # Auto-create directory if it doesn't exist
    if not os.path.exists(base_dir):
        os.makedirs(base_dir, exist_ok=True)
        return "لا توجد نسخة متاحة حالياً. تم إنشاء المجلد، يرجى وضع الملف فيه.", 404
        
    # Get all files in the directory
    files = os.listdir(base_dir)
    # Filter out hidden files
    files = [f for f in files if not f.startswith('.')]
    
    if not files:
        return "جاري رفع النسخة الخاصة بهذا النظام قريباً...", 404
        
    # Download the first available file!
    file_name = files[0]
    return send_from_directory(base_dir, file_name, as_attachment=True)

@api.route('/api/settings/remote-config', methods=['PUT', 'OPTIONS'])
def update_remote_config():
    if request.method == 'OPTIONS':
        return '', 204
        
    data = request.json
    try:
        template = remote_config.get_template()
        
        def set_param(key, value):
            if value is not None:
                template.parameters[key] = remote_config.Parameter(
                    default_value=remote_config.ParameterValue(value=value)
                )
                
        set_param('api_url', data.get('api_url'))
        
        remote_config.publish_template(template)
        return jsonify({'message': 'Remote config updated successfully'}), 200
    except Exception as e:
        print(f"Error updating remote config: {e}")
        return jsonify({'error': str(e)}), 500

def send_push_notification(title, body, target_user_id=None):
    try:
        if target_user_id:
            user = Member.query.get(target_user_id)
            if user and user.fcm_token:
                message = messaging.Message(
                    notification=messaging.Notification(title=title, body=body),
                    token=user.fcm_token,
                )
                messaging.send(message)
        else:
            users = Member.query.filter(Member.fcm_token != None).all()
            tokens = [u.fcm_token for u in users]
            if tokens:
                message = messaging.MulticastMessage(
                    notification=messaging.Notification(title=title, body=body),
                    tokens=tokens,
                )
                messaging.send_each_for_multicast(message)
    except Exception as e:
        print(f"Failed to send push notification: {e}")

def recalculate_member_balance(member):
    if member.role == 'owner':
        member.balance = 0.0
        return 0.0
    tx_sum = db.session.query(db.func.sum(WalletTransaction.amount)).filter(
        WalletTransaction.member_id == member.id,
        WalletTransaction.transaction_type.in_(['diyah_share', 'cash_payment', 'admin_adjustment'])
    ).scalar() or 0.0
    member.balance = round(tx_sum, 2)
    return member.balance

@api.route('/api/wallet/status', methods=['GET'])
def get_wallet_status():
    members = Member.query.filter(Member.role != 'owner').all()
    total_balance = sum(m.balance for m in members)
    total_members = len(members)
    
    total_positive_funds = sum(m.balance for m in members if m.balance > 0)
    total_deficit = sum(abs(m.balance) for m in members if m.balance < 0)
    
    # Old diyahs fund (revenue collected from new members for old diyahs)
    old_diyah_payments_sum = db.session.query(db.func.sum(WalletTransaction.amount)).filter_by(
        transaction_type='old_diyah_payment'
    ).scalar() or 0.0
    
    total_balance += old_diyah_payments_sum
    total_positive_funds += old_diyah_payments_sum
    
    return jsonify({
        "total_balance": round(total_balance, 2),
        "total_members": total_members,
        "total_positive_funds": round(total_positive_funds, 2),
        "total_deficit": round(total_deficit, 2),
        "old_diyahs_fund": round(old_diyah_payments_sum, 2)
    })


@api.route('/api/wallet/transactions', methods=['GET'])
def get_wallet_transactions():
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 0))
    except ValueError:
        page = 1
        limit = 0

    query_str = request.args.get('query', '').strip()
    
    tx_query = WalletTransaction.query.join(Member)
    
    if query_str:
        tx_query = tx_query.filter(
            (Member.full_name.like(f"%{query_str}%")) | 
            (WalletTransaction.description.like(f"%{query_str}%")) |
            (WalletTransaction.transaction_type.like(f"%{query_str}%"))
        )
        
    tx_query = tx_query.order_by(WalletTransaction.created_at.desc())

    if limit > 0:
        total = tx_query.count()
        transactions = tx_query.limit(limit).offset((page - 1) * limit).all()
        return jsonify({
            "data": [tx.to_dict() for tx in transactions],
            "has_more": (page * limit) < total,
            "total": total
        })
    else:
        transactions = tx_query.all()
        return jsonify({
            "data": [tx.to_dict() for tx in transactions],
            "has_more": False,
            "total": len(transactions)
        })

@api.route('/', methods=['GET'])
def home():
    return jsonify({"message": "Welcome to the Tribal Covenant App Backend!"})

@api.route('/api/status', methods=['GET'])
def status():
    return jsonify({"status": "Backend is modular and running flawlessly!", "db": "SQLite3"})

@api.route('/api/members/<int:member_id>/fcm-token', methods=['PUT'])
def update_fcm_token(member_id):
    data = request.json
    member = Member.query.get_or_404(member_id)
    member.fcm_token = data.get('fcm_token')
    db.session.commit()
    return jsonify({"message": "FCM token updated"})

# --- Auth Endpoints ---
@api.route('/api/login', methods=['POST'])
def login():
    # Rate limit check
    if _is_rate_limited():
        log_to_file(f"Login rate-limited for hashed IP: {_get_ip_hash()}")
        return jsonify({"error": "تجاوزت عدد محاولات تسجيل الدخول. يرجى المحاولة بعد 15 دقيقة."}), 429

    data = request.json
    if not data:
        return jsonify({"error": "بيانات غير صالحة"}), 400
    username = data.get('username', '').strip()
    password = data.get('password', '')
    
    if not username or not password:
        return jsonify({"error": "اسم المستخدم وكلمة المرور مطلوبان"}), 400

    # Limit username length to prevent abuse
    if len(username) > 150 or len(password) > 200:
        _record_login_attempt(False)
        return jsonify({"error": "المدخلات غير صالحة"}), 400

    log_to_file(f"Login attempt - Username: '{username}'")

    # 1. Try Owner Login via Remote Config (Dynamic Credentials)
    try:
        from firebase_admin import remote_config
        # We use a try/except for the RC fetch to ensure login doesn't break if RC fails
        template = remote_config.get_template()
        rc_username = template.parameters.get('owner_username', {}).value if hasattr(template.parameters.get('owner_username', {}), 'value') else template.parameters.get('owner_username', {}).get('defaultValue', {}).get('value')
        rc_password = template.parameters.get('owner_password', {}).value if hasattr(template.parameters.get('owner_password', {}), 'value') else template.parameters.get('owner_password', {}).get('defaultValue', {}).get('value')
        
        # Fallback if the above doesn't work for certain SDK versions
        if not rc_username:
            rc_username = template.parameters.get('owner_username').default_value.value
        if not rc_password:
            rc_password = template.parameters.get('owner_password').default_value.value

        if rc_username and rc_password and username == rc_username and password == rc_password:
            owner = Member.query.filter_by(role='owner').first()
            _record_login_attempt(True)
            log_to_file("Owner Login Successful via Remote Config")
            return jsonify({
                "message": "Owner Login Successful via Remote Config",
                "user": {
                    "id": owner.id if owner else 0,
                    "full_name": owner.full_name if owner else "المالك (المبرمج)",
                    "username": rc_username,
                    "role": "owner"
                }
            })
    except Exception as e:
        log_to_file(f"RC Auth Check Skipped/Failed: {type(e).__name__}")

    # 2. Regular Database Login
    user = Member.query.filter((Member.username == username) | (Member.phone == username)).first()
    if user:
        pwd_match = user.check_password(password)
        if pwd_match:
            _record_login_attempt(True)
            log_to_file(f"Login successful for user role: '{user.role}'")
            return jsonify({"message": "Login successful", "user": user.to_dict()})
        else:
            _record_login_attempt(False)
            log_to_file(f"Failed login attempt for existing username")
    else:
        _record_login_attempt(False)
        log_to_file(f"Failed login attempt - username not found")
    return jsonify({"error": "اسم المستخدم أو كلمة المرور غير صحيحة"}), 401

@api.route('/api/reset-password', methods=['POST'])
def reset_password():
    data = request.json
    phone = data.get('phone')
    new_password = data.get('new_password')
    
    if not phone or not new_password:
        return jsonify({"error": "رقم الهاتف وكلمة المرور الجديدة مطلوبة"}), 400
        
    user = Member.query.filter_by(phone=phone).first()
    if not user:
        return jsonify({"error": "رقم الهاتف غير مسجل في النظام"}), 404
        
    user.set_password(new_password)
    db.session.commit()
    
    return jsonify({"message": "تم تغيير كلمة المرور بنجاح"})

@api.route('/api/members/<int:member_id>/role', methods=['PUT'])
def change_role(member_id):
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    new_role = data.get('role')
    password = data.get('password')
    
    if not actor_id:
        return jsonify({"error": "Unauthorized"}), 401
    
    actor = Member.query.get(actor_id)
    if not actor or actor.role not in ['owner', 'sheikh']:
        return jsonify({"error": "Forbidden"}), 403
        
    member = Member.query.get_or_404(member_id)
    
    if new_role == 'sheikh' and actor.role != 'owner':
        return jsonify({"error": "Only owner can promote to sheikh"}), 403
        
    if new_role == 'admin':
        if not member.username:
            member.username = member.phone
        if password:
            member.set_password(password)
            
    member.role = new_role
    if new_role == 'wajeeh':
        member.is_wajeeh = True
        
    db.session.commit()
    
    notif = Notification(message=f"تم تغيير رتبتك إلى {new_role}", target_user_id=member.id)
    db.session.add(notif)
    db.session.commit()
    
    return jsonify({"message": "Role updated successfully", "member": member.to_dict()})

@api.route('/api/notifications', methods=['GET'])
def get_notifications():
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 0))
    except ValueError:
        page = 1
        limit = 0

    user_id = request.args.get('user_id')
    
    if user_id:
        query = Notification.query.filter((Notification.target_user_id == user_id) | (Notification.target_user_id == None))
    else:
        query = Notification.query.filter_by(target_user_id=None)
        
    query = query.order_by(Notification.created_at.desc())
    
    if limit > 0:
        total = query.count()
        notifs = query.limit(limit).offset((page - 1) * limit).all()
        return jsonify({
            "data": [n.to_dict() for n in notifs],
            "has_more": (page * limit) < total,
            "total": total
        })
    else:
        notifs = query.all()
        return jsonify({
            "data": [n.to_dict() for n in notifs],
            "has_more": False,
            "total": len(notifs)
        })

# --- Member Endpoints ---

@api.route('/api/members', methods=['POST'])
def add_member():
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    try:
        is_wajeeh = data.get('is_wajeeh', False)
        new_member = Member(
            full_name=data.get('full_name'),
            phone=data.get('phone'),
            is_wajeeh=is_wajeeh,
            wajeeh_id=data.get('wajeeh_id'),
            role='wajeeh' if is_wajeeh else 'member',
            username=data.get('phone') if is_wajeeh else None
        )
        if is_wajeeh and data.get('password'):
            new_member.set_password(data.get('password'))
        db.session.add(new_member)
        db.session.flush() # Get new_member.id and created_at
        
        # Add old diyahs to the new member
        old_diyahs = Diyah.query.filter(Diyah.created_at < new_member.created_at).all()
        for d in old_diyahs:
            tx = WalletTransaction(
                member_id=new_member.id,
                diyah_id=d.id,
                amount=-d.share_per_member,
                transaction_type='old_diyah_share',
                description=f"مطلوب دية قديمة: {d.title}",
                created_at=new_member.created_at
            )
            db.session.add(tx)

        log_action(actor_id, f"إضافة عضو جديد: {new_member.full_name}")
        db.session.commit()
        return jsonify({"message": "Member added successfully", "member": new_member.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/members', methods=['GET'])
def get_members():
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 0))
    except ValueError:
        page = 1
        limit = 0

    query = Member.query.filter(Member.role != 'owner')
    
    # Custom SQL sorting logic to group Wajeehs and their followers
    group_id = func.coalesce(Member.wajeeh_id, Member.id)
    priority = case((Member.is_wajeeh == True, 0), else_=1)
    
    query = query.order_by(group_id, priority, Member.full_name)

    if limit > 0:
        total = query.count()
        members = query.limit(limit).offset((page - 1) * limit).all()
        return jsonify({
            "data": [m.to_dict() for m in members],
            "has_more": (page * limit) < total,
            "total": total
        })
    else:
        # Backward compatibility / fetch all
        members = query.all()
        return jsonify({
            "data": [m.to_dict() for m in members],
            "has_more": False,
            "total": len(members)
        })

@api.route('/api/members/<int:member_id>', methods=['PUT'])
def update_member(member_id):
    member = Member.query.get_or_404(member_id)
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    try:
        old_is_wajeeh = member.is_wajeeh
        member.full_name = data.get('full_name', member.full_name)
        member.phone = data.get('phone', member.phone)
        member.is_wajeeh = data.get('is_wajeeh', member.is_wajeeh)
        member.wajeeh_id = data.get('wajeeh_id', member.wajeeh_id)
        
        if old_is_wajeeh and not member.is_wajeeh:
            transfer_wajeeh_id = data.get('transfer_wajeeh_id')
            if transfer_wajeeh_id:
                Member.query.filter_by(wajeeh_id=member.id).update({"wajeeh_id": transfer_wajeeh_id})
            else:
                Member.query.filter_by(wajeeh_id=member.id).update({"wajeeh_id": None})
                
        if data.get('password'):
            if not actor_id:
                return jsonify({"error": "Unauthorized"}), 401
            actor = Member.query.get(actor_id)
            if not actor:
                return jsonify({"error": "Unauthorized"}), 401
                
            target_role = member.role
            actor_role = actor.role
            
            # Logic: Can change password if it's oneself, or according to hierarchy:
            # owner > sheikh > admin > wajeeh > member
            if member.id != actor.id:
                if actor_role == 'sheikh' and target_role in ['owner', 'sheikh']:
                    return jsonify({"error": "ليس لديك صلاحية لتغيير رمز هذا المستخدم"}), 403
                elif actor_role == 'admin' and target_role in ['owner', 'sheikh', 'admin']:
                    return jsonify({"error": "ليس لديك صلاحية لتغيير رمز هذا المستخدم"}), 403
                elif actor_role == 'wajeeh' and target_role in ['owner', 'sheikh', 'admin', 'wajeeh']:
                    return jsonify({"error": "ليس لديك صلاحية لتغيير رمز هذا المستخدم"}), 403
                elif actor_role == 'member':
                    return jsonify({"error": "ليس لديك صلاحية"}), 403
                    
            member.set_password(data.get('password'))
            
        if data.get('username'):
            member.username = data.get('username')
            
        log_action(actor_id, f"تعديل بيانات: {member.full_name}")
        db.session.commit()
        return jsonify({"message": "Member updated successfully", "member": member.to_dict()})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/members/<int:member_id>', methods=['DELETE'])
def delete_member(member_id):
    member = Member.query.get_or_404(member_id)
    actor_id = request.headers.get('X-User-Id')
    try:
        name = member.full_name
        if member.is_wajeeh:
            Member.query.filter_by(wajeeh_id=member.id).update({"wajeeh_id": None})
        db.session.delete(member)
        log_action(actor_id, f"حذف: {name}")
        db.session.commit()
        return jsonify({"message": "Member deleted successfully"})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/wajeehs', methods=['GET'])
def get_wajeehs():
    wajeehs = Member.query.filter(Member.is_wajeeh == True, Member.role != 'owner').order_by(Member.full_name).all()
    return jsonify([w.to_dict() for w in wajeehs])

@api.route('/api/wajeehs/<int:wajeeh_id>/members', methods=['GET'])
def get_wajeeh_members(wajeeh_id):
    members = Member.query.filter_by(wajeeh_id=wajeeh_id).order_by(Member.full_name).all()
    return jsonify([m.to_dict() for m in members])

# --- Diyah Endpoints ---

@api.route('/api/diyahs', methods=['POST'])
def add_diyah():
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    try:
        manual_date_str = data.get('manual_date')
        manual_date_obj = None
        if manual_date_str:
            manual_date_obj = datetime.fromisoformat(manual_date_str.replace("Z", "+00:00"))

        total_members = Member.query.filter(Member.role != 'owner').count()
        amount = float(data.get('amount'))
        owner_percentage = data.get('owner_percentage')
        
        share = 0
        if total_members > 0:
            if owner_percentage is not None:
                owner_percentage = float(owner_percentage)
                if total_members > 1:
                    share = (amount * (1 - owner_percentage / 100)) / (total_members - 1)
                else:
                    share = 0
            else:
                share = amount / total_members

        diyah_created_at = datetime.utcnow()
        new_diyah = Diyah(
            title=data.get('title'),
            amount=amount,
            description=data.get('description'),
            manual_date=manual_date_obj,
            caused_by_id=data.get('caused_by_id'),
            is_finished=data.get('is_finished', False),
            is_fully_paid=data.get('is_fully_paid', False),
            total_members_count=total_members,
            share_per_member=round(share, 2),
            owner_percentage=owner_percentage,
            created_at=diyah_created_at
        )
        db.session.add(new_diyah)
        db.session.flush() # Allocate new_diyah.id

        # Add ledger transactions and update balances
        eligible_members = Member.query.filter(Member.created_at <= diyah_created_at, Member.role != 'owner').all()
        for m in eligible_members:
            if new_diyah.caused_by_id == m.id and new_diyah.owner_percentage is not None:
                m_share = new_diyah.amount * (new_diyah.owner_percentage / 100.0)
            else:
                m_share = new_diyah.share_per_member
            
            tx = WalletTransaction(
                member_id=m.id,
                diyah_id=new_diyah.id,
                amount=-m_share,
                transaction_type='diyah_share',
                description=f"خصم حصة دية: {new_diyah.title}",
                created_at=diyah_created_at
            )
            db.session.add(tx)
            m.balance = round(m.balance - m_share, 2)

        log_action(actor_id, f"إضافة دية جديدة: {new_diyah.title}")
        db.session.commit()
        send_push_notification("دية جديدة تمت إضافتها", f"تم إضافة دية: {new_diyah.title} بمبلغ {new_diyah.amount}")
        return jsonify({"message": "Diyah added successfully", "diyah": new_diyah.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/diyahs', methods=['GET'])
def get_diyahs():
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 0))
    except ValueError:
        page = 1
        limit = 0

    query = Diyah.query.order_by(Diyah.created_at.desc())

    if limit > 0:
        total = query.count()
        diyahs = query.limit(limit).offset((page - 1) * limit).all()
        return jsonify({
            "data": [d.to_dict() for d in diyahs],
            "has_more": (page * limit) < total,
            "total": total
        })
    else:
        diyahs = query.all()
        return jsonify({
            "data": [d.to_dict() for d in diyahs],
            "has_more": False,
            "total": len(diyahs)
        })

@api.route('/api/diyahs/<int:diyah_id>', methods=['PUT'])
def update_diyah(diyah_id):
    diyah = Diyah.query.get_or_404(diyah_id)
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    try:
        # Revert old diyah_share transactions for this diyah
        old_txs = WalletTransaction.query.filter_by(diyah_id=diyah.id, transaction_type='diyah_share').all()
        affected_member_ids = set()
        for tx in old_txs:
            affected_member_ids.add(tx.member_id)
            db.session.delete(tx)
        
        db.session.flush()

        diyah.title = data.get('title', diyah.title)
        diyah.amount = data.get('amount', diyah.amount)
        diyah.description = data.get('description', diyah.description)
        diyah.is_finished = data.get('is_finished', diyah.is_finished)
        diyah.is_fully_paid = data.get('is_fully_paid', diyah.is_fully_paid)
        diyah.caused_by_id = data.get('caused_by_id', diyah.caused_by_id)
        diyah.owner_percentage = data.get('owner_percentage', diyah.owner_percentage)
        
        # Recalculate share
        total_members = Member.query.filter(Member.role != 'owner').count()
        if total_members > 0:
            if diyah.owner_percentage is not None:
                if total_members > 1:
                    diyah.share_per_member = round((diyah.amount * (1 - diyah.owner_percentage / 100)) / (total_members - 1), 2)
                else:
                    diyah.share_per_member = 0
            else:
                diyah.share_per_member = round(diyah.amount / total_members, 2)
        
        manual_date_str = data.get('manual_date')
        if manual_date_str:
            diyah.manual_date = datetime.fromisoformat(manual_date_str.replace("Z", "+00:00"))

        # Add new diyah_share transactions
        eligible_members = Member.query.filter(Member.created_at <= diyah.created_at, Member.role != 'owner').all()
        for m in eligible_members:
            affected_member_ids.add(m.id)
            if diyah.caused_by_id == m.id and diyah.owner_percentage is not None:
                m_share = diyah.amount * (diyah.owner_percentage / 100.0)
            else:
                m_share = diyah.share_per_member
            
            tx = WalletTransaction(
                member_id=m.id,
                diyah_id=diyah.id,
                amount=-m_share,
                transaction_type='diyah_share',
                description=f"خصم حصة دية: {diyah.title}",
                created_at=diyah.created_at
            )
            db.session.add(tx)
            
        db.session.flush()

        # Recalculate balances for affected members
        for m_id in affected_member_ids:
            m = Member.query.get(m_id)
            if m:
                recalculate_member_balance(m)
            
        log_action(actor_id, f"تعديل دية: {diyah.title}")
        db.session.commit()
        return jsonify({"message": "Diyah updated successfully", "diyah": diyah.to_dict()})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/diyahs/<int:diyah_id>', methods=['DELETE'])
def delete_diyah(diyah_id):
    diyah = Diyah.query.get_or_404(diyah_id)
    actor_id = request.headers.get('X-User-Id')
    try:
        title = diyah.title
        # Revert transactions
        txs = WalletTransaction.query.filter_by(diyah_id=diyah.id).all()
        affected_member_ids = set(tx.member_id for tx in txs)
        for tx in txs:
            db.session.delete(tx)
        
        db.session.flush()

        db.session.delete(diyah)
        db.session.flush()

        # Recalculate balances
        for m_id in affected_member_ids:
            m = Member.query.get(m_id)
            if m:
                recalculate_member_balance(m)

        log_action(actor_id, f"حذف دية: {title}")
        db.session.commit()
        return jsonify({"message": "Diyah deleted successfully"})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

# --- Diyah Payment & History Endpoints ---

@api.route('/api/diyahs/<int:diyah_id>/payments', methods=['GET'])
def get_diyah_payments(diyah_id):
    diyah = Diyah.query.get_or_404(diyah_id)
    payments = DiyahPayment.query.filter_by(diyah_id=diyah_id).all()
    
    # All members are now eligible for all diyahs (new members pay old diyahs)
    eligible_members = Member.query.filter(Member.role != 'owner').all()
    eligible_member_ids = [m.id for m in eligible_members]
    
    return jsonify({
        "payments": [p.to_dict() for p in payments],
        "eligible_member_ids": eligible_member_ids
    })

@api.route('/api/diyahs/<int:diyah_id>/payments', methods=['POST'])
def update_diyah_payments(diyah_id):
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    payments_data = data.get('payments', []) # Expect list of {member_id, amount}
    
    # Backward compatibility for old client if needed (though we control it)
    if not payments_data and 'paid_member_ids' in data:
        payments_data = [{'member_id': m_id, 'amount': None} for m_id in data['paid_member_ids']]

    try:
        # Revert/delete existing cash_payment transactions for this diyah
        old_payments = DiyahPayment.query.filter_by(diyah_id=diyah_id).all()
        affected_member_ids = set(p.member_id for p in old_payments)
        
        DiyahPayment.query.filter_by(diyah_id=diyah_id).delete()
        WalletTransaction.query.filter(
            WalletTransaction.diyah_id == diyah_id,
            WalletTransaction.transaction_type.in_(['cash_payment', 'old_diyah_payment'])
        ).delete()
        db.session.flush()

        diyah = db.session.get(Diyah, diyah_id)
        if not diyah:
            return jsonify({"error": "الدية غير موجودة"}), 404

        for p in payments_data:
            m_id = p.get('member_id')
            if m_id is None:
                continue
            affected_member_ids.add(m_id)
            
            p_amount = p.get('amount')
            # Validate amount: must be a number if provided
            if p_amount is not None:
                try:
                    p_amount = float(p_amount)
                except (TypeError, ValueError):
                    return jsonify({"error": f"قيمة الدفع غير صالحة للعضو {m_id}"}), 400

            payment = DiyahPayment(
                diyah_id=diyah_id, 
                member_id=m_id,
                amount=p_amount
            )
            db.session.add(payment)
            
            # Determine cash amount
            if p_amount is not None:
                cash_amount = p_amount
            else:
                if diyah.caused_by_id == m_id and diyah.owner_percentage is not None:
                    cash_amount = diyah.amount * (diyah.owner_percentage / 100.0)
                else:
                    cash_amount = diyah.share_per_member
                    
            # Determine transaction type based on when the member was created
            member_obj = db.session.get(Member, m_id)
            tx_type = 'cash_payment'
            if member_obj and diyah.created_at < member_obj.created_at:
                tx_type = 'old_diyah_payment'
                desc = f"تسديد دية قديمة: {diyah.title}"
            else:
                desc = f"تسديد نقدي لدية: {diyah.title}"

            tx = WalletTransaction(
                member_id=m_id,
                diyah_id=diyah_id,
                amount=cash_amount,
                transaction_type=tx_type,
                description=desc,
                created_at=datetime.utcnow()
            )
            db.session.add(tx)
            
        db.session.flush()
        
        # Recalculate balances
        for m_id in affected_member_ids:
            m = db.session.get(Member, m_id)
            if m:
                recalculate_member_balance(m)

        log_action(actor_id, f"تحديث مدفوعات الدية: {diyah.title}")
            
        db.session.commit()
        return jsonify({"message": "Payments updated successfully"})
    except Exception as e:
        db.session.rollback()
        log_to_file(f"Error updating payments for diyah {diyah_id}: {str(e)}")
        return jsonify({"error": str(e)}), 400

@api.route('/api/members/<int:member_id>/pay_old_diyahs', methods=['POST'])
def pay_old_diyahs(member_id):
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    diyah_ids = data.get('diyah_ids', [])
    
    if not diyah_ids:
        return jsonify({"error": "لم يتم تحديد ديات للدفع"}), 400

    try:
        member = db.session.get(Member, member_id)
        if not member:
            return jsonify({"error": "العضو غير موجود"}), 404

        for diyah_id in diyah_ids:
            diyah = db.session.get(Diyah, diyah_id)
            if not diyah:
                continue
                
            # Check if already paid
            existing_payment = DiyahPayment.query.filter_by(diyah_id=diyah_id, member_id=member_id).first()
            if existing_payment:
                continue

            share = diyah.share_per_member
            
            # Create payment record
            payment = DiyahPayment(
                diyah_id=diyah_id,
                member_id=member_id,
                amount=share
            )
            db.session.add(payment)
            
            # Create old_diyah_payment transaction
            tx = WalletTransaction(
                member_id=member_id,
                diyah_id=diyah_id,
                amount=share,
                transaction_type='old_diyah_payment',
                description=f"تسديد دية قديمة: {diyah.title}",
                created_at=datetime.utcnow()
            )
            db.session.add(tx)
            
        db.session.flush()
        
        # Recalculate balance for the member
        recalculate_member_balance(member)
        
        log_action(actor_id, f"دفع ديات قديمة للعضو: {member.full_name}")
        db.session.commit()
        return jsonify({"message": "تم الدفع بنجاح"})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/members/<int:member_id>/history', methods=['GET'])
def get_member_history(member_id):
    member = Member.query.get_or_404(member_id)
    caused = Diyah.query.filter_by(caused_by_id=member_id).all()
    all_diyahs = Diyah.query.all()
    
    paid = []
    partially_paid = []
    not_paid = []
    not_liable = []
    
    payments = {p.diyah_id: p for p in DiyahPayment.query.filter_by(member_id=member_id).all()}
    
    for d in all_diyahs:
        is_liable = not member.created_at or not d.created_at or d.created_at >= member.created_at
        
        # Calculate share for this specific member
        if d.caused_by_id == member.id and d.owner_percentage is not None:
            share = d.amount * (d.owner_percentage / 100.0)
        else:
            share = d.share_per_member
            
        d_dict = d.to_dict()
        d_dict['member_share'] = round(share, 2)
        
        if not is_liable:
            if d.id in payments:
                p = payments[d.id]
                p_amount = p.amount if p.amount is not None else share
                d_dict['member_payment'] = round(p_amount, 2)
            else:
                d_dict['member_payment'] = 0.0
            not_liable.append(d_dict)
            continue
            
        if d.id in payments:
            p = payments[d.id]
            p_amount = p.amount if p.amount is not None else share
            d_dict['member_payment'] = round(p_amount, 2)
            
            if p_amount >= share:
                paid.append(d_dict)
            else:
                partially_paid.append(d_dict)
        else:
            d_dict['member_payment'] = 0.0
            not_paid.append(d_dict)
            
    caused_dicts = []
    for d in caused:
        d_dict = d.to_dict()
        if d.caused_by_id == member.id and d.owner_percentage is not None:
            share = d.amount * (d.owner_percentage / 100.0)
        else:
            share = d.share_per_member
        d_dict['member_share'] = round(share, 2)
        
        if d.id in payments:
            p = payments[d.id]
            p_amount = p.amount if p.amount is not None else share
            d_dict['member_payment'] = round(p_amount, 2)
        else:
            d_dict['member_payment'] = 0.0
        caused_dicts.append(d_dict)
            
    return jsonify({
        "caused": caused_dicts,
        "paid": paid,
        "partially_paid": partially_paid,
        "not_paid": not_paid,
        "not_liable": not_liable
    })
