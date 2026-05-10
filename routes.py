from flask import Blueprint, jsonify, request, send_from_directory, abort
import os
from models import db, Member, Diyah, DiyahPayment, Notification
from datetime import datetime
from firebase_admin import messaging, remote_config

api = Blueprint('api', __name__)

APP_TOKEN = "Tribal_Secure_App_Token_2026_X77"

@api.before_request
def check_app_token():
    # Skip for simple public status, public downloads, and home
    if request.path == '/api/status' or request.path.startswith('/api/download/') or request.path == '/':
        return
        
    if request.method == 'OPTIONS':
        return # Allow CORS preflight
        
    app_token = request.headers.get('X-App-Token')
    if app_token != APP_TOKEN:
        print(f"Security Block! Received Token: '{app_token}', Expected: '{APP_TOKEN}'")
        print(f"Headers received: {dict(request.headers)}")
        return jsonify({'error': 'Unauthorized! Invalid App Fingerprint.'}), 403

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

def log_action(actor_id, action_text, target_user_id=None):
    if not actor_id: return
    actor = Member.query.get(actor_id)
    if not actor: return
    
    if actor.role in ['admin', 'sheikh']:
        msg = f"قام {actor.full_name} ({actor.phone}) بـ: {action_text}"
        notif = Notification(message=msg, target_user_id=target_user_id)
        db.session.add(notif)
        send_push_notification("تنبيه من النظام", msg, target_user_id)

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
    data = request.json
    username = data.get('username')
    password = data.get('password')

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
        print(f"RC Auth Check Skipped/Failed: {e}")

    # 2. Regular Database Login
    user = Member.query.filter((Member.username == username) | (Member.phone == username)).first()
    
    if user and user.check_password(password):
        return jsonify({"message": "Login successful", "user": user.to_dict()})
    return jsonify({"error": "اليوزر نيم أو كلمة المرور غير صحيحة"}), 401

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
    user_id = request.args.get('user_id')
    if user_id:
        notifs = Notification.query.filter((Notification.target_user_id == user_id) | (Notification.target_user_id == None)).order_by(Notification.created_at.desc()).all()
    else:
        notifs = Notification.query.filter_by(target_user_id=None).order_by(Notification.created_at.desc()).all()
    return jsonify([n.to_dict() for n in notifs])

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
        log_action(actor_id, f"إضافة عضو جديد: {new_member.full_name}")
        db.session.commit()
        return jsonify({"message": "Member added successfully", "member": new_member.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/members', methods=['GET'])
def get_members():
    members = Member.query.filter(Member.role != 'owner').all()
    def sort_key(m):
        group_id = m.wajeeh_id if m.wajeeh_id else m.id
        priority = 0 if m.is_wajeeh else 1
        return (group_id, priority, m.full_name)
    
    sorted_members = sorted(members, key=sort_key)
    return jsonify([m.to_dict() for m in sorted_members])

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
        share = amount / total_members if total_members > 0 else 0

        new_diyah = Diyah(
            title=data.get('title'),
            amount=amount,
            description=data.get('description'),
            manual_date=manual_date_obj,
            caused_by_id=data.get('caused_by_id'),
            is_finished=data.get('is_finished', False),
            total_members_count=total_members,
            share_per_member=round(share, 2)
        )
        db.session.add(new_diyah)
        log_action(actor_id, f"إضافة دية جديدة: {new_diyah.title}")
        db.session.commit()
        send_push_notification("دية جديدة تمت إضافتها", f"تم إضافة دية: {new_diyah.title} بمبلغ {new_diyah.amount}")
        return jsonify({"message": "Diyah added successfully", "diyah": new_diyah.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/diyahs', methods=['GET'])
def get_diyahs():
    diyahs = Diyah.query.order_by(Diyah.created_at.desc()).all()
    return jsonify([d.to_dict() for d in diyahs])

@api.route('/api/diyahs/<int:diyah_id>', methods=['PUT'])
def update_diyah(diyah_id):
    diyah = Diyah.query.get_or_404(diyah_id)
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    try:
        diyah.title = data.get('title', diyah.title)
        diyah.amount = data.get('amount', diyah.amount)
        diyah.description = data.get('description', diyah.description)
        diyah.is_finished = data.get('is_finished', diyah.is_finished)
        diyah.caused_by_id = data.get('caused_by_id', diyah.caused_by_id)
        
        manual_date_str = data.get('manual_date')
        if manual_date_str:
            diyah.manual_date = datetime.fromisoformat(manual_date_str.replace("Z", "+00:00"))
            
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
        db.session.delete(diyah)
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
    paid_member_ids = [p.member_id for p in payments]
    
    # Eligible members = those created before or at the same time as the diyah
    # We exclude the owner as requested
    eligible_members = Member.query.filter(Member.created_at <= diyah.created_at, Member.role != 'owner').all()
    eligible_member_ids = [m.id for m in eligible_members]
    
    return jsonify({
        "paid_member_ids": paid_member_ids,
        "eligible_member_ids": eligible_member_ids
    })

@api.route('/api/diyahs/<int:diyah_id>/payments', methods=['POST'])
def update_diyah_payments(diyah_id):
    data = request.json
    actor_id = request.headers.get('X-User-Id')
    paid_member_ids = data.get('paid_member_ids', [])
    try:
        DiyahPayment.query.filter_by(diyah_id=diyah_id).delete()
        for m_id in paid_member_ids:
            payment = DiyahPayment(diyah_id=diyah_id, member_id=m_id)
            db.session.add(payment)
            
        diyah = Diyah.query.get(diyah_id)
        if diyah:
            log_action(actor_id, f"تحديث مدفوعات الدية: {diyah.title}")
            
        db.session.commit()
        return jsonify({"message": "Payments updated successfully"})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400

@api.route('/api/members/<int:member_id>/history', methods=['GET'])
def get_member_history(member_id):
    member = Member.query.get_or_404(member_id)
    caused = Diyah.query.filter_by(caused_by_id=member_id).all()
    
    payments = DiyahPayment.query.filter_by(member_id=member_id).all()
    paid_ids = [p.diyah_id for p in payments]
    paid = Diyah.query.filter(Diyah.id.in_(paid_ids)).all() if paid_ids else []
    
    # Base query for diyahs the member hasn't paid
    query = Diyah.query.filter(Diyah.is_finished == False)
    if paid_ids:
        query = query.filter(~Diyah.id.in_(paid_ids))
    
    all_unpaid = query.all()
    
    not_paid = []    # Liable but not paid
    not_liable = []  # Not liable due to join date
    
    for d in all_unpaid:
        # If diyah created_at >= member created_at (or diyah has no date, though unlikely), member is liable
        if not member.created_at or not d.created_at or d.created_at >= member.created_at:
            not_paid.append(d)
        else:
            not_liable.append(d)
            
    return jsonify({
        "caused": [d.to_dict() for d in caused],
        "paid": [d.to_dict() for d in paid],
        "not_paid": [d.to_dict() for d in not_paid],
        "not_liable": [d.to_dict() for d in not_liable]
    })
