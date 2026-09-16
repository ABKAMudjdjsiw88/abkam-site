from flask import Blueprint, render_template, request, redirect, url_for, session, jsonify
from supabase_db import get, insert, update
from config import MAX_FILE_SIZE, FILES_BUCKET, SUPABASE_URL
from werkzeug.utils import secure_filename
from datetime import datetime, timezone
import uuid
import os

chat_bp = Blueprint("chat", __name__)


def current_user():
    user_id = session.get("user_id")

    if not user_id:
        return None

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    return users[0] if users else None


def get_user(user_id):
    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    return users[0] if users else None


def are_blocked(a, b):
    first = get("blocks", {
        "blocker_id": f"eq.{a}",
        "blocked_id": f"eq.{b}",
        "limit": 1
    })

    if first:
        return True

    second = get("blocks", {
        "blocker_id": f"eq.{b}",
        "blocked_id": f"eq.{a}",
        "limit": 1
    })

    return bool(second)


def public_file_url(filename):
    return (
        f"{SUPABASE_URL.rstrip('/')}"
        f"/storage/v1/object/public/{FILES_BUCKET}/{filename}"
    )


def load_conversation(me_id, other_id, limit=200):
    sent = get("messages", {
        "sender_id": f"eq.{me_id}",
        "receiver_id": f"eq.{other_id}",
        "order": "created_at.asc",
        "limit": str(limit)
    })

    received = get("messages", {
        "sender_id": f"eq.{other_id}",
        "receiver_id": f"eq.{me_id}",
        "order": "created_at.asc",
        "limit": str(limit)
    })

    messages = sent + received
    messages.sort(key=lambda x: x.get("created_at", ""))

    result = []

    for message in messages:
        reactions = get("reactions", {
            "message_id": f"eq.{message['id']}",
            "limit": "50"
        })

        message["reactions"] = reactions
        result.append(message)

    return result


def mark_messages_read(me_id, other_id):
    unread = get("messages", {
        "sender_id": f"eq.{other_id}",
        "receiver_id": f"eq.{me_id}",
        "is_read": "eq.false",
        "limit": "200"
    })

    for message in unread:
        update(
            "messages",
            {"id": f"eq.{message['id']}"},
            {"is_read": True}
        )


@chat_bp.route("/chat/<int:user_id>")
def chat(user_id):
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    if me["id"] == user_id:
        return redirect(url_for("profile.profile"))

    other = get_user(user_id)

    if not other:
        return "کاربر پیدا نشد.", 404

    messages = load_conversation(me["id"], user_id)

    mark_messages_read(me["id"], user_id)

    update(
        "users",
        {"id": f"eq.{me['id']}"},
        {
            "last_seen": datetime.now(timezone.utc).isoformat()
        }
    )

    return render_template(
        "chat.html",
        me=me,
        other=other,
        messages=messages
    )


@chat_bp.route("/api/chat/<int:user_id>")
def chat_updates(user_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    other = get_user(user_id)

    if not other:
        return jsonify({
            "ok": False,
            "error": "کاربر پیدا نشد."
        }), 404

    messages = load_conversation(me["id"], user_id)

    mark_messages_read(me["id"], user_id)

    return jsonify({
        "ok": True,
        "messages": messages
    })


@chat_bp.route("/api/send/<int:user_id>", methods=["POST"])
def send_message(user_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    other = get_user(user_id)

    if not other:
        return jsonify({
            "ok": False,
            "error": "کاربر پیدا نشد."
        }), 404

    if me["id"] == user_id:
        return jsonify({
            "ok": False,
            "error": "نمی‌توانید برای خودتان پیام بفرستید."
        }), 400

    if are_blocked(me["id"], user_id):
        return jsonify({
            "ok": False,
            "error": "این گفتگو به دلیل بلاک بودن قابل استفاده نیست."
        }), 403

    message_text = request.form.get("message", "").strip()

    reply_to = request.form.get("reply_to", "").strip() or None
    forwarded_from = request.form.get("forwarded_from", "").strip() or None

    if reply_to:
        try:
            reply_to = int(reply_to)
        except ValueError:
            reply_to = None

    if forwarded_from:
        try:
            forwarded_from = int(forwarded_from)
        except ValueError:
            forwarded_from = None

    uploaded = request.files.get("file")

    file_name = None
    original_name = None
    file_type = None

    if uploaded and uploaded.filename:
        uploaded.seek(0, os.SEEK_END)
        file_size = uploaded.tell()
        uploaded.seek(0)

        if file_size > MAX_FILE_SIZE:
            return jsonify({
                "ok": False,
                "error": "حجم فایل بیشتر از 50MB است."
            }), 413

        original_name = uploaded.filename
        safe_name = secure_filename(original_name)

        if not safe_name:
            safe_name = "file"

        extension = os.path.splitext(safe_name)[1]

        unique_name = (
            f"{datetime.now(timezone.utc).strftime('%Y%m%d')}_"
            f"{uuid.uuid4().hex}{extension}"
        )

        file_type = uploaded.content_type or "application/octet-stream"

        from supabase_db import upload_file

        upload_file(
            FILES_BUCKET,
            unique_name,
            uploaded.read(),
            file_type
        )

        file_name = unique_name

    if not message_text and not file_name:
        return jsonify({
            "ok": False,
            "error": "پیام یا فایل را وارد کنید."
        }), 400

    data = {
        "sender_id": me["id"],
        "receiver_id": user_id,
        "message": message_text or None,
        "file_name": file_name,
        "original_name": original_name,
        "file_type": file_type,
        "edited": False,
        "is_read": False,
        "reply_to": reply_to,
        "forwarded_from": forwarded_from,
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    created = insert("messages", data)

    if not created:
        return jsonify({
            "ok": False,
            "error": "ارسال پیام انجام نشد."
        }), 500

    try:
        insert(
            "notifications",
            {
                "user_id": user_id,
                "type": "message",
                "message": "پیام جدید دریافت کردید.",
                "link": f"/chat/{me['id']}",
                "is_read": False,
                "created_at": datetime.now(timezone.utc).isoformat()
            }
        )
    except Exception:
        pass

    message = created[0]

    message["reactions"] = []

    if file_name:
        message["file_url"] = public_file_url(file_name)
    else:
        message["file_url"] = None

    return jsonify({
        "ok": True,
        "message": message
    })


@chat_bp.route("/api/message/<int:message_id>", methods=["PUT", "DELETE"])
def message_action(message_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    messages = get("messages", {
        "id": f"eq.{message_id}",
        "limit": "1"
    })

    if not messages:
        return jsonify({
            "ok": False,
            "error": "پیام پیدا نشد."
        }), 404

    message = messages[0]

    if message["sender_id"] != me["id"]:
        return jsonify({
            "ok": False,
            "error": "دسترسی ندارید."
        }), 403

    if request.method == "DELETE":
        updated = update(
            "messages",
            {"id": f"eq.{message_id}"},
            {
                "message": None,
                "file_name": None,
                "original_name": None,
                "file_type": None
            }
        )

        return jsonify({
            "ok": True,
            "message": updated[0] if updated else None
        })

    text = request.form.get("message", "").strip()

    if not text:
        return jsonify({
            "ok": False,
            "error": "متن پیام خالی است."
        }), 400

    updated = update(
        "messages",
        {"id": f"eq.{message_id}"},
        {
            "message": text,
            "edited": True
        }
    )

    return jsonify({
        "ok": True,
        "message": updated[0] if updated else None
    })


@chat_bp.route("/api/message/<int:message_id>/react", methods=["POST"])
def react(message_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    reaction = request.form.get("emoji", "").strip()

    allowed = ["👍", "❤️", "😂", "😮", "😢", "🔥"]

    if reaction not in allowed:
        return jsonify({
            "ok": False,
            "error": "ری‌اکشن نامعتبر است."
        }), 400

    messages = get("messages", {
        "id": f"eq.{message_id}",
        "limit": "1"
    })

    if not messages:
        return jsonify({
            "ok": False,
            "error": "پیام پیدا نشد."
        }), 404

    existing = get("reactions", {
        "message_id": f"eq.{message_id}",
        "user_id": f"eq.{me['id']}",
        "limit": "1"
    })

    if existing:
        updated = update(
            "reactions",
            {"id": f"eq.{existing[0]['id']}"},
            {"reaction": reaction}
        )

        return jsonify({
            "ok": True,
            "reaction": updated[0] if updated else None
        })

    created = insert(
        "reactions",
        {
            "message_id": message_id,
            "user_id": me["id"],
            "reaction": reaction
        }
    )

    return jsonify({
        "ok": True,
        "reaction": created[0] if created else None
    })


@chat_bp.route("/api/search-chat/<int:user_id>")
def search_chat(user_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    q = request.args.get("q", "").strip()

    if not q:
        return jsonify({
            "ok": True,
            "messages": []
        })

    sent = get("messages", {
        "sender_id": f"eq.{me['id']}",
        "receiver_id": f"eq.{user_id}",
        "message": f"ilike.*{q}*",
        "order": "created_at.asc",
        "limit": "50"
    })

    received = get("messages", {
        "sender_id": f"eq.{user_id}",
        "receiver_id": f"eq.{me['id']}",
        "message": f"ilike.*{q}*",
        "order": "created_at.asc",
        "limit": "50"
    })

    messages = sent + received
    messages.sort(key=lambda x: x.get("created_at", ""))

    return jsonify({
        "ok": True,
        "messages": messages
    })


@chat_bp.route("/api/block/<int:user_id>", methods=["POST"])
def block_user(user_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    if me["id"] == user_id:
        return jsonify({
            "ok": False,
            "error": "نمی‌توانید خودتان را بلاک کنید."
        }), 400

    other = get_user(user_id)

    if not other:
        return jsonify({
            "ok": False,
            "error": "کاربر پیدا نشد."
        }), 404

    existing = get("blocks", {
        "blocker_id": f"eq.{me['id']}",
        "blocked_id": f"eq.{user_id}",
        "limit": "1"
    })

    if not existing:
        insert(
            "blocks",
            {
                "blocker_id": me["id"],
                "blocked_id": user_id,
                "created_at": datetime.now(timezone.utc).isoformat()
            }
        )

    return jsonify({
        "ok": True
    })


@chat_bp.route("/uploads/<path:filename>")
def uploaded_file(filename):
    return jsonify({
        "ok": False,
        "error": "فایل‌های جدید در Supabase Storage ذخیره می‌شوند."
    }), 404
