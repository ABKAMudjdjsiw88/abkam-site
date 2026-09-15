#!/data/data/com.termux/files/usr/bin/bash

cat > requirements.txt <<'PY'
Flask
Werkzeug
PY

cat > config.py <<'PY'
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

class Config:
    SECRET_KEY = os.environ.get("ABKAM_SECRET", "abkam-secret-2026")
    DATABASE = os.path.join(BASE_DIR, "chat.db")
    UPLOAD_FOLDER = os.path.join(BASE_DIR, "uploads")

    MAX_CONTENT_LENGTH = 100 * 1024 * 1024

    OWNER_USERNAME = "ABKAM"
PY

cat > database.py <<'PY'
import sqlite3
import os
from config import Config

def connect():
    db = sqlite3.connect(Config.DATABASE)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    return db

def init_db():
    os.makedirs(Config.UPLOAD_FOLDER, exist_ok=True)

    for folder in ["images", "videos", "audio", "files", "avatars"]:
        os.makedirs(os.path.join(Config.UPLOAD_FOLDER, folder), exist_ok=True)

    db = connect()

    db.executescript("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        public_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        username TEXT UNIQUE COLLATE NOCASE NOT NULL,
        avatar TEXT,
        bio TEXT DEFAULT '',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender_id INTEGER NOT NULL,
        receiver_id INTEGER,
        group_id INTEGER,
        message TEXT DEFAULT '',
        file_name TEXT,
        original_name TEXT,
        file_type TEXT,
        reply_to INTEGER,
        forwarded_from INTEGER,
        edited INTEGER DEFAULT 0,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        read_at TEXT,
        FOREIGN KEY(sender_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS reactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        emoji TEXT NOT NULL,
        UNIQUE(message_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS blocks (
        blocker_id INTEGER NOT NULL,
        blocked_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY(blocker_id, blocked_id)
    );

    CREATE TABLE IF NOT EXISTS reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reporter_id INTEGER NOT NULL,
        reported_id INTEGER NOT NULL,
        reason TEXT NOT NULL,
        status TEXT DEFAULT 'open',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        avatar TEXT,
        owner_id INTEGER,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS group_members (
        group_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY(group_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        message TEXT NOT NULL,
        link TEXT,
        is_read INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_messages_private
    ON messages(sender_id, receiver_id, created_at);

    CREATE INDEX IF NOT EXISTS idx_messages_group
    ON messages(group_id, created_at);
    """)

    group = db.execute(
        "SELECT id FROM groups WHERE is_default=1 LIMIT 1"
    ).fetchone()

    if not group:
        db.execute(
            """
            INSERT INTO groups(name, description, is_default)
            VALUES (?, ?, 1)
            """,
            (
                "گروه چت سایت ABKAM",
                "گروه عمومی کاربران سایت ABKAM"
            )
        )

    db.commit()
    db.close()

def default_group(db):
    return db.execute(
        "SELECT id FROM groups WHERE is_default=1 LIMIT 1"
    ).fetchone()
PY

cat > app.py <<'PY'
from flask import Flask
from config import Config
from database import init_db

from routes.main import main_bp
from routes.auth import auth_bp
from routes.users import users_bp
from routes.chat import chat_bp
from routes.groups import groups_bp
from routes.profile import profile_bp
from routes.notifications import notifications_bp
from routes.reports import reports_bp
from routes.owner import owner_bp

app = Flask(__name__)
app.config.from_object(Config)
app.secret_key = Config.SECRET_KEY

init_db()

app.register_blueprint(main_bp)
app.register_blueprint(auth_bp)
app.register_blueprint(users_bp)
app.register_blueprint(chat_bp)
app.register_blueprint(groups_bp)
app.register_blueprint(profile_bp)
app.register_blueprint(notifications_bp)
app.register_blueprint(reports_bp)
app.register_blueprint(owner_bp)

@app.errorhandler(413)
def too_large(error):
    return "حجم فایل بیشتر از 100MB است.", 413

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
PY

cat > routes/__init__.py <<'PY'
PY

cat > routes/main.py <<'PY'
from flask import Blueprint, render_template, session, redirect, url_for
from database import connect

main_bp = Blueprint("main", __name__)

@main_bp.route("/")
def home():
    if not session.get("user_id"):
        return redirect(url_for("auth.login"))

    db = connect()

    me = db.execute(
        "SELECT * FROM users WHERE id=?",
        (session["user_id"],)
    ).fetchone()

    chats = db.execute("""
        SELECT
            u.*,
            MAX(m.created_at) AS last_chat,
            (
                SELECT COUNT(*)
                FROM messages x
                WHERE x.sender_id=u.id
                  AND x.receiver_id=?
                  AND x.read_at IS NULL
                  AND x.deleted=0
            ) AS unread
        FROM users u
        JOIN messages m
          ON (
            (m.sender_id=u.id AND m.receiver_id=?)
            OR
            (m.receiver_id=u.id AND m.sender_id=?)
          )
        WHERE u.id<>?
        GROUP BY u.id
        ORDER BY last_chat DESC
    """, (
        session["user_id"],
        session["user_id"],
        session["user_id"],
        session["user_id"]
    )).fetchall()

    groups = db.execute("""
        SELECT * FROM groups
        ORDER BY is_default DESC, id DESC
    """).fetchall()

    unread = db.execute("""
        SELECT COUNT(*) AS c
        FROM notifications
        WHERE user_id=? AND is_read=0
    """, (session["user_id"],)).fetchone()["c"]

    db.close()

    return render_template(
        "home.html",
        me=me,
        chats=chats,
        groups=groups,
        unread=unread
    )
PY

cat > routes/auth.py <<'PY'
from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from database import connect, default_group
import re
import secrets

auth_bp = Blueprint("auth", __name__)

def valid_username(username):
    return bool(re.fullmatch(r"[A-Za-z0-9_]{3,32}", username or ""))

@auth_bp.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        username = request.form.get("username", "").strip().lstrip("@")

        if not name:
            flash("نام را وارد کنید.")
            return redirect(url_for("auth.register"))

        if not valid_username(username):
            flash("آیدی باید 3 تا 32 کاراکتر و فقط شامل حروف انگلیسی، عدد و _ باشد.")
            return redirect(url_for("auth.register"))

        db = connect()

        exists = db.execute(
            "SELECT id FROM users WHERE username=?",
            (username,)
        ).fetchone()

        if exists:
            db.close()
            flash("این آیدی قبلاً گرفته شده است.")
            return redirect(url_for("auth.register"))

        public_id = secrets.token_hex(6).upper()

        cur = db.execute("""
            INSERT INTO users(public_id,name,username)
            VALUES(?,?,?)
        """, (public_id, name, username))

        user_id = cur.lastrowid

        group = default_group(db)

        if group:
            db.execute("""
                INSERT OR IGNORE INTO group_members(group_id,user_id)
                VALUES(?,?)
            """, (group["id"], user_id))

        db.commit()
        db.close()

        session["user_id"] = user_id

        return redirect(url_for("main.home"))

    return render_template("register.html")

@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip().lstrip("@")

        db = connect()

        user = db.execute(
            "SELECT * FROM users WHERE username=?",
            (username,)
        ).fetchone()

        if not user:
            db.close()
            flash("کاربری با این آیدی پیدا نشد.")
            return redirect(url_for("auth.login"))

        db.execute(
            "UPDATE users SET last_seen=CURRENT_TIMESTAMP WHERE id=?",
            (user["id"],)
        )

        db.commit()
        db.close()

        session["user_id"] = user["id"]

        return redirect(url_for("main.home"))

    return render_template("login.html")

@auth_bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
PY

cat > routes/users.py <<'PY'
from flask import Blueprint, render_template, request, session
from database import connect

users_bp = Blueprint("users", __name__)

@users_bp.route("/users")
def users():
    q = request.args.get("q", "").strip()

    if q.startswith("@"):
        q = q[1:]

    db = connect()

    if q:
        rows = db.execute("""
            SELECT *
            FROM users
            WHERE id<>?
              AND (
                    username LIKE ? COLLATE NOCASE
                    OR name LIKE ?
                  )
            ORDER BY
                CASE
                    WHEN username=? COLLATE NOCASE THEN 0
                    WHEN name=? THEN 1
                    ELSE 2
                END,
                name
            LIMIT 50
        """, (
            session["user_id"],
            f"%{q}%",
            f"%{q}%",
            q,
            q
        )).fetchall()
    else:
        rows = []

    db.close()

    return render_template(
        "search.html",
        results=rows,
        q=q
    )

@users_bp.route("/profile/<int:user_id>")
def public_profile(user_id):
    db = connect()

    user = db.execute(
        "SELECT * FROM users WHERE id=?",
        (user_id,)
    ).fetchone()

    db.close()

    if not user:
        return "کاربر پیدا نشد", 404

    return render_template(
        "public_profile.html",
        u=user
    )
PY

cat > routes/chat.py <<'PY'
from flask import Blueprint, request, jsonify, render_template, session, send_from_directory
from database import connect
from config import Config
import os
import uuid

chat_bp = Blueprint("chat", __name__)

def are_blocked(db, a, b):
    one = db.execute("""
        SELECT 1 FROM blocks
        WHERE blocker_id=? AND blocked_id=?
    """, (a, b)).fetchone()

    two = db.execute("""
        SELECT 1 FROM blocks
        WHERE blocker_id=? AND blocked_id=?
    """, (b, a)).fetchone()

    return bool(one or two)

@chat_bp.route("/chat/<int:user_id>")
def chat(user_id):
    db = connect()

    me = db.execute(
        "SELECT * FROM users WHERE id=?",
        (session["user_id"],)
    ).fetchone()

    other = db.execute(
        "SELECT * FROM users WHERE id=?",
        (user_id,)
    ).fetchone()

    if not other:
        db.close()
        return "کاربر پیدا نشد", 404

    messages = db.execute("""
        SELECT
            m.*,
            u.name AS sender_name,
            u.username AS sender_username,
            u.avatar AS sender_avatar,
            (
                SELECT GROUP_CONCAT(r.emoji)
                FROM reactions r
                WHERE r.message_id=m.id
            ) AS reactions
        FROM messages m
        JOIN users u ON u.id=m.sender_id
        WHERE m.deleted=0
          AND (
              (m.sender_id=? AND m.receiver_id=?)
              OR
              (m.sender_id=? AND m.receiver_id=?)
          )
        ORDER BY m.id
    """, (
        session["user_id"],
        user_id,
        user_id,
        session["user_id"]
    )).fetchall()

    db.execute("""
        UPDATE messages
        SET read_at=CURRENT_TIMESTAMP
        WHERE sender_id=?
          AND receiver_id=?
          AND read_at IS NULL
    """, (
        user_id,
        session["user_id"]
    ))

    db.execute(
        "UPDATE users SET last_seen=CURRENT_TIMESTAMP WHERE id=?",
        (session["user_id"],)
    )

    db.commit()
    db.close()

    return render_template(
        "chat.html",
        me=me,
        other=other,
        messages=messages
    )

@chat_bp.route("/api/send/<int:user_id>", methods=["POST"])
def send_message(user_id):
    me = session["user_id"]

    db = connect()

    other = db.execute(
        "SELECT id FROM users WHERE id=?",
        (user_id,)
    ).fetchone()

    if not other:
        db.close()
        return jsonify(error="کاربر پیدا نشد"), 404

    if are_blocked(db, me, user_id):
        db.close()
        return jsonify(error="این کاربر بلاک شده است."), 403

    message = request.form.get("message", "").strip()
    reply_to = request.form.get("reply_to") or None
    forwarded_from = request.form.get("forwarded_from") or None

    uploaded = request.files.get("file")

    file_name = None
    original_name = None
    file_type = None

    if uploaded and uploaded.filename:
        original_name = uploaded.filename
        extension = os.path.splitext(original_name)[1].lower()

        unique = uuid.uuid4().hex + extension
        mime = uploaded.mimetype or "application/octet-stream"

        if mime.startswith("image/"):
            folder = "images"
        elif mime.startswith("video/"):
            folder = "videos"
        elif mime.startswith("audio/"):
            folder = "audio"
        else:
            folder = "files"

        uploaded.save(
            os.path.join(
                Config.UPLOAD_FOLDER,
                folder,
                unique
            )
        )

        file_name = folder + "/" + unique
        file_type = mime

    if not message and not file_name:
        db.close()
        return jsonify(error="پیام خالی است."), 400

    cur = db.execute("""
        INSERT INTO messages(
            sender_id,
            receiver_id,
            message,
            file_name,
            original_name,
            file_type,
            reply_to,
            forwarded_from
        )
        VALUES(?,?,?,?,?,?,?,?)
    """, (
        me,
        user_id,
        message,
        file_name,
        original_name,
        file_type,
        reply_to,
        forwarded_from
    ))

    db.execute("""
        INSERT INTO notifications(
            user_id,
            kind,
            message,
            link
        )
        VALUES(?,?,?,?)
    """, (
        user_id,
        "message",
        "پیام جدید دریافت کردید.",
        f"/chat/{me}"
    ))

    db.commit()

    message_id = cur.lastrowid

    db.close()

    return jsonify(
        ok=True,
        id=message_id
    )

@chat_bp.route("/api/message/<int:message_id>", methods=["PUT", "DELETE"])
def message_action(message_id):
    db = connect()

    msg = db.execute(
        "SELECT * FROM messages WHERE id=?",
        (message_id,)
    ).fetchone()

    if not msg or msg["sender_id"] != session["user_id"]:
        db.close()
        return jsonify(error="دسترسی ندارید."), 403

    if request.method == "DELETE":
        db.execute("""
            UPDATE messages
            SET deleted=1,
                message='',
                file_name=NULL,
                original_name=NULL
            WHERE id=?
        """, (message_id,))
    else:
        text = request.form.get("message", "").strip()

        if not text:
            db.close()
            return jsonify(error="متن خالی است."), 400

        db.execute("""
            UPDATE messages
            SET message=?, edited=1
            WHERE id=?
        """, (
            text,
            message_id
        ))

    db.commit()
    db.close()

    return jsonify(ok=True)

@chat_bp.route("/api/message/<int:message_id>/react", methods=["POST"])
def react(message_id):
    emoji = request.form.get("emoji", "").strip()

    if emoji not in ["👍", "❤️", "😂", "😮", "😢", "🔥"]:
        return jsonify(error="ری‌اکشن نامعتبر"), 400

    db = connect()

    db.execute("""
        INSERT INTO reactions(message_id,user_id,emoji)
        VALUES(?,?,?)
        ON CONFLICT(message_id,user_id)
        DO UPDATE SET emoji=excluded.emoji
    """, (
        message_id,
        session["user_id"],
        emoji
    ))

    db.commit()
    db.close()

    return jsonify(ok=True)

@chat_bp.route("/api/search-chat/<int:user_id>")
def search_chat(user_id):
    q = request.args.get("q", "").strip()

    db = connect()

    rows = db.execute("""
        SELECT id,message,created_at
        FROM messages
        WHERE deleted=0
          AND (
              (sender_id=? AND receiver_id=?)
              OR
              (sender_id=? AND receiver_id=?)
          )
          AND message LIKE ?
        ORDER BY id DESC
        LIMIT 50
    """, (
        session["user_id"],
        user_id,
        user_id,
        session["user_id"],
        f"%{q}%"
    )).fetchall()

    db.close()

    return jsonify([dict(row) for row in rows])

@chat_bp.route("/uploads/<path:filename>")
def uploaded_file(filename):
    return send_from_directory(
        Config.UPLOAD_FOLDER,
        filename
    )
PY

cat > routes/groups.py <<'PY'
from flask import Blueprint, request, jsonify, render_template, session
from database import connect

groups_bp = Blueprint("groups", __name__)

def is_member(db, group_id, user_id):
    return bool(db.execute("""
        SELECT 1
        FROM group_members
        WHERE group_id=? AND user_id=?
    """, (group_id, user_id)).fetchone())

@groups_bp.route("/groups")
def groups():
    db = connect()

    groups = db.execute("""
        SELECT * FROM groups
        ORDER BY is_default DESC, id DESC
    """).fetchall()

    db.close()

    return render_template(
        "groups.html",
        groups=groups
    )

@groups_bp.route("/api/groups", methods=["POST"])
def create_group():
    name = request.form.get("name", "").strip()
    description = request.form.get("description", "").strip()

    if not name:
        return jsonify(error="نام گروه لازم است."), 400

    db = connect()

    cur = db.execute("""
        INSERT INTO groups(
            name,
            description,
            owner_id
        )
        VALUES(?,?,?)
    """, (
        name,
        description,
        session["user_id"]
    ))

    group_id = cur.lastrowid

    db.execute("""
        INSERT INTO group_members(group_id,user_id)
        VALUES(?,?)
    """, (
        group_id,
        session["user_id"]
    ))

    db.commit()
    db.close()

    return jsonify(
        ok=True,
        id=group_id
    )

@groups_bp.route("/group/<int:group_id>")
def group(group_id):
    db = connect()

    group = db.execute(
        "SELECT * FROM groups WHERE id=?",
        (group_id,)
    ).fetchone()

    if not group:
        db.close()
        return "گروه پیدا نشد", 404

    if not is_member(db, group_id, session["user_id"]):
        db.execute("""
            INSERT OR IGNORE INTO group_members(
                group_id,
                user_id
            )
            VALUES(?,?)
        """, (
            group_id,
            session["user_id"]
        ))
        db.commit()

    messages = db.execute("""
        SELECT
            m.*,
            u.name AS sender_name,
            u.username AS sender_username,
            u.avatar AS sender_avatar
        FROM messages m
        JOIN users u ON u.id=m.sender_id
        WHERE m.group_id=?
          AND m.deleted=0
        ORDER BY m.id
    """, (group_id,)).fetchall()

    members = db.execute("""
        SELECT u.*
        FROM users u
        JOIN group_members gm
          ON gm.user_id=u.id
        WHERE gm.group_id=?
    """, (group_id,)).fetchall()

    db.close()

    return render_template(
        "group.html",
        group=group,
        messages=messages,
        members=members
    )

@groups_bp.route("/api/group/<int:group_id>/send", methods=["POST"])
def group_send(group_id):
    db = connect()

    if not is_member(db, group_id, session["user_id"]):
        db.close()
        return jsonify(error="عضو گروه نیستید."), 403

    text = request.form.get("message", "").strip()

    if not text:
        db.close()
        return jsonify(error="پیام خالی است."), 400

    db.execute("""
        INSERT INTO messages(
            sender_id,
            group_id,
            message
        )
        VALUES(?,?,?)
    """, (
        session["user_id"],
        group_id,
        text
    ))

    db.commit()
    db.close()

    return jsonify(ok=True)
PY

cat > routes/profile.py <<'PY'
from flask import Blueprint, render_template, request, redirect, url_for, session
from database import connect
from config import Config
import os
import uuid

profile_bp = Blueprint("profile", __name__)

@profile_bp.route("/profile")
def profile():
    db = connect()

    user = db.execute(
        "SELECT * FROM users WHERE id=?",
        (session["user_id"],)
    ).fetchone()

    db.close()

    return render_template(
        "profile.html",
        u=user
    )

@profile_bp.route("/profile/update", methods=["POST"])
def update_profile():
    name = request.form.get("name", "").strip()
    bio = request.form.get("bio", "").strip()

    if not name:
        name = "کاربر"

    db = connect()

    avatar = request.files.get("avatar")

    if avatar and avatar.filename:
        extension = os.path.splitext(
            avatar.filename
        )[1].lower()

        filename = uuid.uuid4().hex + extension

        avatar.save(
            os.path.join(
                Config.UPLOAD_FOLDER,
                "avatars",
                filename
            )
        )

        db.execute("""
            UPDATE users
            SET name=?, bio=?, avatar=?
            WHERE id=?
        """, (
            name,
            bio,
            filename,
            session["user_id"]
        ))
    else:
        db.execute("""
            UPDATE users
            SET name=?, bio=?
            WHERE id=?
        """, (
            name,
            bio,
            session["user_id"]
        ))

    db.commit()
    db.close()

    return redirect(url_for("profile.profile"))

@profile_bp.route("/api/block/<int:user_id>", methods=["POST", "DELETE"])
def block_user(user_id):
    db = connect()

    if request.method == "POST":
        db.execute("""
            INSERT OR IGNORE INTO blocks(
                blocker_id,
                blocked_id
            )
            VALUES(?,?)
        """, (
            session["user_id"],
            user_id
        ))
    else:
        db.execute("""
            DELETE FROM blocks
            WHERE blocker_id=? AND blocked_id=?
        """, (
            session["user_id"],
            user_id
        ))

    db.commit()
    db.close()

    return {"ok": True}
PY

cat > routes/notifications.py <<'PY'
from flask import Blueprint, render_template, session
from database import connect

notifications_bp = Blueprint(
    "notifications",
    __name__
)

@notifications_bp.route("/notifications")
def notifications():
    db = connect()

    rows = db.execute("""
        SELECT *
        FROM notifications
        WHERE user_id=?
        ORDER BY id DESC
        LIMIT 100
    """, (
        session["user_id"],
    )).fetchall()

    db.execute("""
        UPDATE notifications
        SET is_read=1
        WHERE user_id=?
    """, (
        session["user_id"],
    ))

    db.commit()
    db.close()

    return render_template(
        "notifications.html",
        notifications=rows
    )
PY

cat > routes/reports.py <<'PY'
from flask import Blueprint, request, jsonify, session
from database import connect

reports_bp = Blueprint(
    "reports",
    __name__
)

@reports_bp.route(
    "/api/report/<int:user_id>",
    methods=["POST"]
)
def report_user(user_id):
    reason = request.form.get(
        "reason",
        "گزارش کاربر"
    ).strip()

    if not reason:
        reason = "گزارش کاربر"

    db = connect()

    db.execute("""
        INSERT INTO reports(
            reporter_id,
            reported_id,
            reason
        )
        VALUES(?,?,?)
    """, (
        session["user_id"],
        user_id,
        reason
    ))

    db.commit()
    db.close()

    return jsonify(ok=True)
PY

cat > routes/owner.py <<'PY'
from flask import Blueprint, render_template, request, redirect, url_for, session
from database import connect
from config import Config

owner_bp = Blueprint(
    "owner",
    __name__
)

def owner():
    return session.get("owner") is True

@owner_bp.route(
    "/owner",
    methods=["GET", "POST"]
)
def owner_login():
    if owner():
        return redirect(url_for("owner.panel"))

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")

        if (
            username == Config.OWNER_USERNAME
            and password == Config.OWNER_PASSWORD
        ):
            session["owner"] = True
            return redirect(url_for("owner.panel"))

        return render_template(
            "owner/login.html",
            error="اطلاعات مالک اشتباه است."
        )

    return render_template(
        "owner/login.html"
    )

@owner_bp.route("/owner/logout")
def owner_logout():
    session.pop("owner", None)
    return redirect(url_for("owner.owner_login"))

@owner_bp.route("/owner/panel")
def panel():
    if not owner():
        return redirect(url_for("owner.owner_login"))

    db = connect()

    users = db.execute("""
        SELECT *
        FROM users
        ORDER BY id DESC
    """).fetchall()

    reports = db.execute("""
        SELECT
            r.*,
            a.username AS reporter_username,
            b.username AS reported_username
        FROM reports r
        JOIN users a ON a.id=r.reporter_id
        JOIN users b ON b.id=r.reported_id
        ORDER BY r.id DESC
    """).fetchall()

    stats = {
        "users": db.execute(
            "SELECT COUNT(*) c FROM users"
        ).fetchone()["c"],

        "messages": db.execute(
            "SELECT COUNT(*) c FROM messages"
        ).fetchone()["c"],

        "groups": db.execute(
            "SELECT COUNT(*) c FROM groups"
        ).fetchone()["c"],

        "reports": db.execute(
            "SELECT COUNT(*) c FROM reports"
        ).fetchone()["c"]
    }

    db.close()

    return render_template(
        "owner/panel.html",
        users=users,
        reports=reports,
        stats=stats
    )

@owner_bp.route("/owner/chat/<int:user_id>")
def owner_chat(user_id):
    if not owner():
        return redirect(url_for("owner.owner_login"))

    db = connect()

    user = db.execute(
        "SELECT * FROM users WHERE id=?",
        (user_id,)
    ).fetchone()

    messages = db.execute("""
        SELECT
            m.*,
            a.username AS sender_username,
            b.username AS receiver_username
        FROM messages m
        JOIN users a ON a.id=m.sender_id
        LEFT JOIN users b
          ON b.id=m.receiver_id
        WHERE
            m.sender_id=?
            OR m.receiver_id=?
        ORDER BY m.id ASC
        LIMIT 1000
    """, (
        user_id,
        user_id
    )).fetchall()

    db.close()

    return render_template(
        "owner/chat.html",
        u=user,
        messages=messages
    )
PY

cat > templates/base.html <<'HTML'
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>{% block title %}ABKAM{% endblock %}</title>
<link rel="stylesheet" href="/static/css/style.css">
</head>

<body>

<header class="topbar">
    <a class="brand" href="/">ABKAM</a>

    {% if session.get("user_id") %}
    <nav>
        <a href="/">خانه</a>
        <a href="/groups">گروه‌ها</a>
        <a href="/notifications">🔔</a>
        <a href="/profile">پروفایل</a>
        <a href="/logout">خروج</a>
    </nav>
    {% endif %}
</header>

<main class="container">

{% with messages = get_flashed_messages() %}
{% if messages %}
<div class="flash">
{% for m in messages %}
{{ m }}
{% endfor %}
</div>
{% endif %}
{% endwith %}

{% block content %}{% endblock %}

</main>

<script src="/static/js/app.js"></script>
{% block scripts %}{% endblock %}

</body>
</html>
HTML

cat > templates/login.html <<'HTML'
{% extends "base.html" %}
{% block title %}ورود | ABKAM{% endblock %}

{% block content %}
<div class="auth-card">
<h1>ورود به ABKAM</h1>
<p class="muted">با آیدی خود وارد شوید</p>

<form method="post">
<input name="username" placeholder="@username" required>
<button>ورود</button>
</form>

<a class="secondary" href="/register">ساخت حساب جدید</a>
</div>
{% endblock %}
HTML

cat > templates/register.html <<'HTML'
{% extends "base.html" %}
{% block title %}ثبت نام | ABKAM{% endblock %}

{% block content %}
<div class="auth-card">
<h1>ساخت حساب</h1>

<form method="post">
<input name="name" placeholder="نام شما" required>
<input name="username" placeholder="آیدی انگلیسی، مثل alireza" required>

<p class="hint">
هر آیدی فقط یک بار قابل استفاده است.
</p>

<button>ثبت نام</button>
</form>

<a class="secondary" href="/login">قبلاً حساب دارم</a>
</div>
{% endblock %}
HTML

cat > templates/home.html <<'HTML'
{% extends "base.html" %}
{% block title %}ABKAM{% endblock %}

{% block content %}

<div class="hero">
    <h1>سلام {{ me.name }} 👋</h1>
    <p>برای پیدا کردن افراد، نام یا آیدی را جستجو کنید.</p>
</div>

<form class="search-box" action="/users">
    <input name="q" placeholder="🔎 جستجوی نام یا آیدی">
    <button>جستجو</button>
</form>

<section>
<h2>گروه‌ها</h2>

{% for g in groups %}
<a class="list-item" href="/group/{{ g.id }}">
    <div class="avatar group-avatar">👥</div>
    <div>
        <b>{{ g.name }}</b>
        <small>{{ g.description }}</small>
    </div>
</a>
{% endfor %}
</section>

<section>
<h2>گفتگوهای من</h2>

{% if chats %}
{% for c in chats %}
<a class="list-item" href="/chat/{{ c.id }}">
    {% if c.avatar %}
    <img class="avatar" src="/uploads/avatars/{{ c.avatar }}">
    {% else %}
    <div class="avatar">👤</div>
    {% endif %}

    <div class="grow">
        <b>{{ c.name }}</b>
        <small>@{{ c.username }}</small>
    </div>

    {% if c.unread %}
    <span class="badge">{{ c.unread }}</span>
    {% endif %}
</a>
{% endfor %}
{% else %}
<div class="empty">
هنوز گفتگویی ندارید.<br>
از قسمت جستجو یک نفر را پیدا کنید.
</div>
{% endif %}

</section>

{% endblock %}
HTML

cat > templates/search.html <<'HTML'
{% extends "base.html" %}
{% block title %}جستجو | ABKAM{% endblock %}

{% block content %}

<h1>جستجو</h1>

<form class="search-box" action="/users">
<input name="q" value="{{ q }}" placeholder="نام یا آیدی">
<button>جستجو</button>
</form>

{% if q %}

{% if results %}

{% for u in results %}
<a class="list-item" href="/profile/{{ u.id }}">

{% if u.avatar %}
<img class="avatar" src="/uploads/avatars/{{ u.avatar }}">
{% else %}
<div class="avatar">👤</div>
{% endif %}

<div>
<b>{{ u.name }}</b>
<small>@{{ u.username }}</small>
</div>

</a>
{% endfor %}

{% else %}
<div class="empty">
کاربری پیدا نشد.
</div>
{% endif %}

{% else %}

<div class="empty">
نام یا آیدی را وارد کنید.
</div>

{% endif %}

{% endblock %}
HTML

cat > templates/public_profile.html <<'HTML'
{% extends "base.html" %}
{% block title %}پروفایل{% endblock %}

{% block content %}

<div class="profile-card">

{% if u.avatar %}
<img class="big-avatar" src="/uploads/avatars/{{ u.avatar }}">
{% else %}
<div class="big-avatar">👤</div>
{% endif %}

<h1>{{ u.name }}</h1>
<p>@{{ u.username }}</p>

{% if u.bio %}
<p class="bio">{{ u.bio }}</p>
{% endif %}

<p class="muted">
لینک پروفایل: /profile/{{ u.id }}
</p>

<a class="button" href="/chat/{{ u.id }}">💬 شروع چت</a>

</div>

{% endblock %}
HTML

cat > templates/profile.html <<'HTML'
{% extends "base.html" %}
{% block title %}پروفایل من{% endblock %}

{% block content %}

<div class="profile-card">

{% if u.avatar %}
<img class="big-avatar" src="/uploads/avatars/{{ u.avatar }}">
{% else %}
<div class="big-avatar">👤</div>
{% endif %}

<h1>{{ u.name }}</h1>
<p>@{{ u.username }}</p>

<p class="idbox">
ID: {{ u.public_id }}
</p>

<form method="post" action="/profile/update" enctype="multipart/form-data">

<input name="name" value="{{ u.name }}" placeholder="نام">

<textarea name="bio" placeholder="بیو">{{ u.bio }}</textarea>

<label class="file-label">
عکس پروفایل
<input type="file" name="avatar" accept="image/*">
</label>

<button>ذخیره تغییرات</button>

</form>

</div>

{% endblock %}
HTML

cat > templates/chat.html <<'HTML'
{% extends "base.html" %}
{% block title %}چت با {{ other.name }}{% endblock %}

{% block content %}

<div class="chat-page">

<div class="chat-head">

<a href="/" class="back">‹</a>

{% if other.avatar %}
<img class="avatar" src="/uploads/avatars/{{ other.avatar }}">
{% else %}
<div class="avatar">👤</div>
{% endif %}

<div class="grow">
<b>{{ other.name }}</b>
<small id="online">
@{{ other.username }}
</small>
</div>

<button onclick="blockUser({{ other.id }})" class="icon-btn">🚫</button>

</div>

<div class="chat-search">
<input id="chatSearch" placeholder="🔎 جستجو در گفتگو">
</div>

<div id="messages" class="messages">

{% for m in messages %}

<div class="message {% if m.sender_id == me.id %}mine{% else %}theirs{% endif %}"
     data-id="{{ m.id }}">

<div class="bubble">

{% if m.reply_to %}
<div class="reply-mini">
پاسخ به پیام
</div>
{% endif %}

{% if m.forwarded_from %}
<div class="forward-mini">
↪ پیام فوروارد شده
</div>
{% endif %}

{% if m.message %}
<div class="message-text">{{ m.message }}</div>
{% endif %}

{% if m.file_name %}

{% if m.file_type and m.file_type.startswith("image/") %}
<img class="media-image" src="/uploads/{{ m.file_name }}">
{% elif m.file_type and m.file_type.startswith("video/") %}
<video class="media" controls src="/uploads/{{ m.file_name }}"></video>
{% elif m.file_type and m.file_type.startswith("audio/") %}
<audio class="audio" controls src="/uploads/{{ m.file_name }}"></audio>
{% else %}
<a class="file-link" href="/uploads/{{ m.file_name }}" download>
📎 {{ m.original_name }}
</a>
{% endif %}

{% endif %}

<div class="message-actions">
<button onclick="replyMessage({{ m.id }})">↩</button>

{% if m.sender_id == me.id %}
<button onclick="editMessage({{ m.id }})">✏️</button>
<button onclick="deleteMessage({{ m.id }})">🗑</button>
{% endif %}

<button onclick="reactMessage({{ m.id }}, '❤️')">❤️</button>
<button onclick="reactMessage({{ m.id }}, '👍')">👍</button>
<button onclick="reactMessage({{ m.id }}, '😂')">😂</button>
<button onclick="forwardMessage({{ m.id }})">↪</button>
</div>

{% if m.reactions %}
<div class="reactions">{{ m.reactions }}</div>
{% endif %}

<div class="time">
{{ m.created_at }}
{% if m.edited %} · ویرایش شد{% endif %}
{% if m.sender_id == me.id %}
{% if m.read_at %} ✓✓ {% else %} ✓ {% endif %}
{% endif %}
</div>

</div>
</div>

{% endfor %}

</div>

<div id="replyBox" class="reply-box hidden">
پاسخ به پیام
<button onclick="cancelReply()">×</button>
</div>

<div id="uploadProgress" class="upload-progress hidden">
<div id="progressBar"></div>
<span id="progressText">0%</span>
</div>

<form id="sendForm" class="composer" enctype="multipart/form-data">

<input type="hidden" id="replyTo" name="reply_to">
<input type="hidden" id="forwardedFrom" name="forwarded_from">

<label class="attach">
📎
<input type="file" name="file" id="fileInput">
</label>

<input
    id="messageInput"
    name="message"
    autocomplete="off"
    placeholder="پیام..."
>

<button type="submit" class="send">➤</button>

</form>

</div>

{% endblock %}

{% block scripts %}
<script>

const CHAT_USER = {{ other.id }};

function scrollBottom(){
    const box = document.getElementById("messages");
    box.scrollTop = box.scrollHeight;
}

scrollBottom();

document.getElementById("sendForm").addEventListener("submit", function(e){

    e.preventDefault();

    const form = this;
    const input = document.getElementById("messageInput");
    const file = document.getElementById("fileInput").files[0];

    if(!input.value.trim() && !file){
        return;
    }

    const data = new FormData(form);

    const xhr = new XMLHttpRequest();

    xhr.open("POST", "/api/send/" + CHAT_USER);

    if(file){
        document.getElementById("uploadProgress").classList.remove("hidden");

        xhr.upload.onprogress = function(e){

            if(e.lengthComputable){

                const percent = Math.round(
                    (e.loaded / e.total) * 100
                );

                document.getElementById("progressBar").style.width =
                    percent + "%";

                document.getElementById("progressText").innerText =
                    percent + "%";
            }
        };
    }

    xhr.onload = function(){

        document.getElementById("uploadProgress")
            .classList.add("hidden");

        if(xhr.status === 200){

            const result = JSON.parse(xhr.responseText);

            if(result.ok){
                location.reload();
            }else{
                alert(result.error || "خطا");
            }

        }else{

            try{
                const result = JSON.parse(xhr.responseText);
                alert(result.error || "خطا");
            }catch{
                alert("خطا در ارسال");
            }

        }
    };

    xhr.send(data);
});

function replyMessage(id){

    document.getElementById("replyTo").value = id;

    document.getElementById("replyBox")
        .classList.remove("hidden");

    document.getElementById("messageInput").focus();
}

function cancelReply(){

    document.getElementById("replyTo").value = "";

    document.getElementById("replyBox")
        .classList.add("hidden");
}

function editMessage(id){

    const text = prompt("متن جدید پیام:");

    if(!text) return;

    const data = new FormData();

    data.append("message", text);

    fetch("/api/message/" + id, {
        method:"PUT",
        body:data
    }).then(() => location.reload());
}

function deleteMessage(id){

    if(!confirm("پیام حذف شود؟")) return;

    fetch("/api/message/" + id, {
        method:"DELETE"
    }).then(() => location.reload());
}

function reactMessage(id, emoji){

    const data = new FormData();

    data.append("emoji", emoji);

    fetch("/api/message/" + id + "/react", {
        method:"POST",
        body:data
    }).then(() => location.reload());
}

function forwardMessage(id){

    document.getElementById("forwardedFrom").value = id;

    alert("حالا متن یا فایل را برای فوروارد ارسال کنید.");

    document.getElementById("messageInput").focus();
}

function blockUser(id){

    if(!confirm("این کاربر بلاک شود؟")) return;

    fetch("/api/block/" + id, {
        method:"POST"
    }).then(() => {
        alert("کاربر بلاک شد.");
        location.href="/";
    });
}

document.getElementById("chatSearch")
.addEventListener("input", function(){

    const q = this.value.toLowerCase();

    document.querySelectorAll(".message")
    .forEach(function(message){

        message.style.display =
            message.innerText.toLowerCase().includes(q)
            ? ""
            : "none";

    });

});

</script>
{% endblock %}
HTML

cat > templates/groups.html <<'HTML'
{% extends "base.html" %}
{% block title %}گروه‌ها{% endblock %}

{% block content %}

<h1>گروه‌ها</h1>

{% for g in groups %}
<a class="list-item" href="/group/{{ g.id }}">

<div class="avatar group-avatar">👥</div>

<div>
<b>{{ g.name }}</b>
<small>{{ g.description }}</small>
</div>

</a>
{% endfor %}

<div class="card">

<h2>ساخت گروه</h2>

<form id="groupForm">

<input name="name" placeholder="نام گروه" required>
<input name="description" placeholder="توضیحات">

<button>ساخت گروه</button>

</form>

</div>

<script>

document.getElementById("groupForm")
.addEventListener("submit", function(e){

e.preventDefault();

fetch("/api/groups", {
method:"POST",
body:new FormData(this)
})
.then(r=>r.json())
.then(result=>{

if(result.ok){
location.href="/group/"+result.id;
}else{
alert(result.error);
}

});

});

</script>

{% endblock %}
HTML

cat > templates/group.html <<'HTML'
{% extends "base.html" %}
{% block title %}{{ group.name }}{% endblock %}

{% block content %}

<div class="chat-page">

<div class="chat-head">

<a href="/groups" class="back">‹</a>

<div class="avatar group-avatar">👥</div>

<div class="grow">
<b>{{ group.name }}</b>
<small>{{ members|length }} عضو</small>
</div>

</div>

<div id="messages" class="messages">

{% for m in messages %}

<div class="message {% if m.sender_id == session.get('user_id') %}mine{% else %}theirs{% endif %}">

<div class="bubble">

<small class="sender">
{{ m.sender_name }} · @{{ m.sender_username }}
</small>

{% if m.message %}
<div class="message-text">
{{ m.message }}
</div>
{% endif %}

<div class="time">
{{ m.created_at }}
</div>

</div>

</div>

{% endfor %}

</div>

<form id="groupForm" class="composer">

<input
name="message"
id="groupMessage"
placeholder="پیام در گروه..."
autocomplete="off"
>

<button>➤</button>

</form>

</div>

<script>

const groupId = {{ group.id }};

document.getElementById("groupForm")
.addEventListener("submit", function(e){

e.preventDefault();

const input = document.getElementById("groupMessage");

if(!input.value.trim()) return;

const data = new FormData(this);

fetch("/api/group/"+groupId+"/send",{
method:"POST",
body:data
})
.then(r=>r.json())
.then(result=>{

if(result.ok){
location.reload();
}else{
alert(result.error);
}

});

});

const box = document.getElementById("messages");
box.scrollTop = box.scrollHeight;

</script>

{% endblock %}
HTML

cat > templates/notifications.html <<'HTML'
{% extends "base.html" %}
{% block title %}اعلان‌ها{% endblock %}

{% block content %}

<h1>اعلان‌ها</h1>

{% for n in notifications %}

<a class="notification" href="{{ n.link or '#' }}">
<b>{{ n.message }}</b>
<small>{{ n.created_at }}</small>
</a>

{% else %}

<div class="empty">
اعلانی ندارید.
</div>

{% endfor %}

{% endblock %}
HTML

cat > templates/owner/login.html <<'HTML'
{% extends "base.html" %}
{% block title %}ورود مالک{% endblock %}

{% block content %}

<div class="auth-card">

<h1>پنل مالک ABKAM</h1>

{% if error %}
<div class="error">{{ error }}</div>
{% endif %}

<form method="post">

<input name="username" placeholder="نام کاربری مالک">
<input name="password" type="password" placeholder="رمز عبور">

<button>ورود</button>

</form>

</div>

{% endblock %}
HTML

cat > templates/owner/panel.html <<'HTML'
{% extends "base.html" %}
{% block title %}پنل مالک{% endblock %}

{% block content %}

<div class="owner-head">

<div>
<h1>پنل مالک ABKAM</h1>
<p>مدیریت سایت</p>
</div>

<a class="danger" href="/owner/logout">خروج</a>

</div>

<div class="stats">

<div class="stat">
<b>{{ stats.users }}</b>
<small>کاربر</small>
</div>

<div class="stat">
<b>{{ stats.messages }}</b>
<small>پیام</small>
</div>

<div class="stat">
<b>{{ stats.groups }}</b>
<small>گروه</small>
</div>

<div class="stat">
<b>{{ stats.reports }}</b>
<small>گزارش</small>
</div>

</div>

<h2>کاربران</h2>

{% for u in users %}

<div class="list-item">

{% if u.avatar %}
<img class="avatar" src="/uploads/avatars/{{ u.avatar }}">
{% else %}
<div class="avatar">👤</div>
{% endif %}

<div class="grow">

<b>{{ u.name }}</b>
<small>@{{ u.username }}</small>

</div>

<a class="button small" href="/owner/chat/{{ u.id }}">
مشاهده پیام‌ها
</a>

</div>

{% endfor %}

<h2>گزارش‌ها</h2>

{% for r in reports %}

<div class="report">

<b>@{{ r.reported_username }}</b>

<p>{{ r.reason }}</p>

<small>
گزارش توسط @{{ r.reporter_username }}
· {{ r.created_at }}
</small>

</div>

{% else %}

<div class="empty">
گزارشی وجود ندارد.
</div>

{% endfor %}

{% endblock %}
HTML

cat > templates/owner/chat.html <<'HTML'
{% extends "base.html" %}
{% block title %}پیام‌های {{ u.name }}{% endblock %}

{% block content %}

<div class="owner-head">

<div>
<h1>{{ u.name }}</h1>
<p>@{{ u.username }}</p>
</div>

<a class="button" href="/owner/panel">
بازگشت
</a>

</div>

<div class="owner-messages">

{% for m in messages %}

<div class="owner-message">

<div>
<b>
@{{ m.sender_username }}
{% if m.receiver_username %}
→ @{{ m.receiver_username }}
{% else %}
→ گروه
{% endif %}
</b>
</div>

{% if m.message %}
<p>{{ m.message }}</p>
{% endif %}

{% if m.original_name %}
<p>📎 {{ m.original_name }}</p>
{% endif %}

<small>{{ m.created_at }}</small>

</div>

{% else %}

<div class="empty">
پیامی وجود ندارد.
</div>

{% endfor %}

</div>

{% endblock %}
HTML

cat > static/css/style.css <<'CSS'
*{
box-sizing:border-box;
}

:root{
--bg:#0f1115;
--card:#181b22;
--card2:#20242d;
--text:#f4f6f8;
--muted:#9aa3af;
--border:#292e38;
--accent:#4f8cff;
--mine:#2b6de0;
--danger:#e05252;
}

body{
margin:0;
background:var(--bg);
color:var(--text);
font-family:Tahoma,Arial,sans-serif;
font-size:15px;
}

a{
color:inherit;
text-decoration:none;
}

.topbar{
height:60px;
display:flex;
align-items:center;
justify-content:space-between;
padding:0 14px;
background:var(--card);
border-bottom:1px solid var(--border);
position:sticky;
top:0;
z-index:10;
}

.brand{
font-size:21px;
font-weight:bold;
}

.topbar nav{
display:flex;
gap:12px;
align-items:center;
font-size:13px;
}

.container{
width:100%;
max-width:650px;
margin:auto;
padding:15px;
padding-bottom:80px;
}

.hero{
padding:10px 2px 18px;
}

.hero h1{
margin:0 0 7px;
font-size:23px;
}

.hero p,
.muted,
small{
color:var(--muted);
}

.search-box{
display:flex;
gap:8px;
margin-bottom:20px;
}

input,
textarea{
width:100%;
background:var(--card);
border:1px solid var(--border);
border-radius:12px;
padding:13px;
color:var(--text);
outline:none;
font-family:inherit;
}

textarea{
min-height:100px;
resize:vertical;
}

input:focus,
textarea:focus{
border-color:var(--accent);
}

button,
.button{
border:0;
background:var(--accent);
color:white;
padding:12px 16px;
border-radius:12px;
font-family:inherit;
cursor:pointer;
font-weight:bold;
}

.secondary{
display:block;
text-align:center;
padding:12px;
margin-top:10px;
background:var(--card2);
border-radius:12px;
}

.auth-card,
.card,
.profile-card{
background:var(--card);
border:1px solid var(--border);
border-radius:18px;
padding:20px;
margin-top:30px;
}

.auth-card h1{
margin-top:0;
}

.auth-card form{
display:flex;
flex-direction:column;
gap:10px;
}

.hint{
font-size:12px;
color:var(--muted);
}

.flash{
background:#453b18;
padding:12px;
border-radius:12px;
margin-bottom:15px;
}

.error{
background:#4a2222;
padding:12px;
border-radius:12px;
margin-bottom:10px;
}

section{
margin-top:22px;
}

section h2{
font-size:17px;
}

.list-item{
display:flex;
align-items:center;
gap:12px;
background:var(--card);
border:1px solid var(--border);
border-radius:15px;
padding:12px;
margin:8px 0;
transition:.15s;
}

.list-item:active{
transform:scale(.98);
}

.list-item small{
display:block;
margin-top:5px;
}

.grow{
flex:1;
}

.avatar{
width:46px;
height:46px;
min-width:46px;
border-radius:50%;
object-fit:cover;
background:var(--card2);
display:flex;
align-items:center;
justify-content:center;
font-size:22px;
}

.group-avatar{
background:#26354d;
}

.big-avatar{
width:100px;
height:100px;
border-radius:50%;
object-fit:cover;
background:var(--card2);
display:flex;
align-items:center;
justify-content:center;
font-size:40px;
margin:auto;
}

.profile-card{
text-align:center;
}

.profile-card form{
display:flex;
flex-direction:column;
gap:10px;
margin-top:20px;
}

.bio{
white-space:pre-wrap;
}

.idbox{
background:var(--card2);
padding:10px;
border-radius:10px;
font-size:12px;
}

.file-label{
display:block;
background:var(--card2);
padding:12px;
border-radius:12px;
cursor:pointer;
}

.file-label input{
display:none;
}

.badge{
background:var(--accent);
border-radius:20px;
padding:4px 9px;
font-size:12px;
}

.empty{
background:var(--card);
border:1px dashed var(--border);
padding:25px;
border-radius:15px;
text-align:center;
color:var(--muted);
}

.notification{
display:block;
background:var(--card);
border:1px solid var(--border);
border-radius:14px;
padding:14px;
margin:8px 0;
}

.notification small{
display:block;
margin-top:7px;
}

.chat-page{
height:calc(100vh - 90px);
display:flex;
flex-direction:column;
}

.chat-head{
display:flex;
align-items:center;
gap:10px;
background:var(--card);
border:1px solid var(--border);
border-radius:15px;
padding:9px;
}

.back{
font-size:30px;
padding:0 7px;
}

.icon-btn{
background:transparent;
padding:8px;
font-size:17px;
}

.chat-search{
padding:8px 0;
}

.chat-search input{
padding:10px;
}

.messages{
flex:1;
overflow-y:auto;
padding:10px 2px;
scroll-behavior:smooth;
}

.message{
display:flex;
margin:6px 0;
}

.message.mine{
justify-content:flex-start;
}

.message.theirs{
justify-content:flex-end;
}

.bubble{
max-width:82%;
padding:9px 11px;
border-radius:16px;
background:var(--card2);
word-break:break-word;
}

.mine .bubble{
background:var(--mine);
border-bottom-right-radius:5px;
}

.theirs .bubble{
border-bottom-left-radius:5px;
}

.message-text{
white-space:pre-wrap;
line-height:1.65;
}

.time{
font-size:9px;
color:#c2c8d0;
margin-top:5px;
text-align:left;
}

.message-actions{
display:flex;
gap:3px;
margin-top:6px;
opacity:.7;
}

.message-actions button{
padding:3px 5px;
background:transparent;
font-size:11px;
}

.reactions{
font-size:12px;
margin-top:3px;
}

.reply-mini,
.forward-mini{
background:rgba(255,255,255,.08);
padding:6px;
border-radius:8px;
margin-bottom:5px;
font-size:11px;
}

.media-image,
.media{
max-width:100%;
max-height:350px;
border-radius:12px;
display:block;
}

.audio{
width:100%;
max-width:280px;
}

.file-link{
display:block;
background:rgba(0,0,0,.18);
padding:10px;
border-radius:10px;
}

.composer{
display:flex;
align-items:center;
gap:7px;
padding-top:8px;
background:var(--bg);
}

.composer input[name="message"]{
flex:1;
}

.attach{
width:42px;
height:42px;
border-radius:50%;
background:var(--card);
display:flex;
align-items:center;
justify-content:center;
cursor:pointer;
font-size:20px;
}

.attach input{
display:none;
}

.send{
width:45px;
height:45px;
border-radius:50%;
padding:0;
font-size:20px;
}

.reply-box{
background:var(--card2);
padding:9px;
border-radius:10px;
margin-top:5px;
}

.reply-box button{
float:left;
background:transparent;
padding:0;
}

.hidden{
display:none!important;
}

.upload-progress{
position:relative;
height:25px;
background:var(--card2);
border-radius:12px;
overflow:hidden;
margin-top:6px;
text-align:center;
}

#progressBar{
height:100%;
width:0;
background:var(--accent);
transition:.1s;
}

#progressText{
position:absolute;
left:0;
right:0;
top:4px;
font-size:11px;
}

.sender{
display:block;
margin-bottom:5px;
color:#9fc2ff;
}

.owner-head{
display:flex;
align-items:center;
justify-content:space-between;
margin-bottom:15px;
}

.owner-head h1{
margin-bottom:4px;
}

.danger{
background:var(--danger);
padding:10px 13px;
border-radius:10px;
}

.stats{
display:grid;
grid-template-columns:repeat(4,1fr);
gap:7px;
margin-bottom:20px;
}

.stat{
background:var(--card);
border:1px solid var(--border);
border-radius:13px;
padding:12px 5px;
text-align:center;
}

.stat b{
display:block;
font-size:20px;
}

.stat small{
font-size:10px;
}

.small{
padding:8px 10px;
font-size:11px;
}

.report,
.owner-message{
background:var(--card);
border:1px solid var(--border);
border-radius:14px;
padding:13px;
margin:8px 0;
}

.report p,
.owner-message p{
white-space:pre-wrap;
line-height:1.6;
}

.owner-messages{
margin-top:15px;
}

@media(max-width:480px){

.container{
padding:10px;
}

.topbar{
padding:0 10px;
}

.topbar nav{
gap:7px;
font-size:11px;
}

.bubble{
max-width:88%;
}

.stats{
grid-template-columns:repeat(2,1fr);
}

}
CSS

cat > static/js/app.js <<'JS'
console.log("ABKAM loaded");
JS

echo "ABKAM files created."
