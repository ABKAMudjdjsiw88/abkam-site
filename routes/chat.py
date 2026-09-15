from flask import Blueprint, render_template, request, redirect, url_for, session, jsonify
from supabase_db import get, insert, update
from config import MAX_FILE_SIZE
from datetime import datetime, timezone
import uuid

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


@chat_bp.route("/chat/<int:user_id>")
def chat(user_id):
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    other = get_user(user_id)

    if not other:
        return "کاربر پیدا نشد.", 404

    sent = get("messages", {
        "sender_id": f"eq.{me['id']}",
        "receiver_id": f"eq.{user_id}",
        "order": "created_at.asc"
    })

    received = get("messages", {
        "sender_id": f"eq.{user_id}",
        "receiver_id": f"eq.{me['id']}",
        "order": "created_at.asc"
    })

    messages = sent + received
    messages.sort(key=lambda x: x.get("created_at", ""))

    unread = [
        m for m in received
        if not m.get("is_read", False)
    ]

    for message in unread:
        update(
            "messages",
            {"id": f"eq.{message['id']}"},
            {"is_read": True}
        )

    return render_template(
        "chat.html",
        me=me,
        other=other,
        messages=messages
    )


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

    message_text = request.form.get("message", "").strip()
    reply_to = request.form.get("reply_to")

    file = request.files.get("file")

    file_name = None
    original_name = None
    file_type = None

    if file and file.filename:
        file.seek(0, 2)
        file_size = file.tell()
        file.seek(0)

        if file_size > MAX_FILE_SIZE:
            return jsonify({
                "ok": False,
                "error": "حجم فایل بیشتر از 50MB است."
            }), 413

        original_name = file.filename
        file_name = f"{uuid.uuid4()}_{original_name}"
        file_type = file.content_type or "application/octet-stream"

    if not message_text and not file:
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
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    if reply_to:
        try:
            data["reply_to"] = int(reply_to)
        except ValueError:
            pass

    created = insert("messages", data)

    if not created:
        return jsonify({
            "ok": False,
            "error": "ارسال پیام انجام نشد."
        }), 500

    return jsonify({
        "ok": True,
        "message": created[0]
    })


@chat_bp.route("/api/edit/<int:message_id>", methods=["POST"])
def edit_message(message_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    messages = get("messages", {
        "id": f"eq.{message_id}",
        "sender_id": f"eq.{me['id']}",
        "limit": 1
    })

    if not messages:
        return jsonify({
            "ok": False,
            "error": "پیام پیدا نشد."
        }), 404

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


@chat_bp.route("/api/delete/<int:message_id>", methods=["POST"])
def delete_message(message_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    messages = get("messages", {
        "id": f"eq.{message_id}",
        "sender_id": f"eq.{me['id']}",
        "limit": 1
    })

    if not messages:
        return jsonify({
            "ok": False,
            "error": "پیام پیدا نشد."
        }), 404

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


@chat_bp.route("/api/react/<int:message_id>", methods=["POST"])
def react_message(message_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    reaction = request.form.get("reaction", "").strip()

    if not reaction:
        return jsonify({
            "ok": False,
            "error": "واکنش مشخص نشده."
        }), 400

    existing = get("reactions", {
        "message_id": f"eq.{message_id}",
        "user_id": f"eq.{me['id']}",
        "limit": 1
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


@chat_bp.route("/api/search/<int:user_id>")
def search_messages(user_id):
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
        "order": "created_at.asc"
    })

    received = get("messages", {
        "sender_id": f"eq.{user_id}",
        "receiver_id": f"eq.{me['id']}",
        "message": f"ilike.*{q}*",
        "order": "created_at.asc"
    })

    messages = sent + received
    messages.sort(key=lambda x: x.get("created_at", ""))

    return jsonify({
        "ok": True,
        "messages": messages
    })
