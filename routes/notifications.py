from flask import Blueprint, render_template, session, redirect, url_for, jsonify
from supabase_db import get, update

notifications_bp = Blueprint("notifications", __name__)


def current_user():
    user_id = session.get("user_id")

    if not user_id:
        return None

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    return users[0] if users else None


@notifications_bp.route("/notifications")
def notifications():
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    items = get("notifications", {
        "user_id": f"eq.{me['id']}",
        "order": "created_at.desc"
    })

    return render_template(
        "notifications.html",
        me=me,
        notifications=items
    )


@notifications_bp.route("/api/notifications/read", methods=["POST"])
def mark_notifications_read():
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    items = get("notifications", {
        "user_id": f"eq.{me['id']}",
        "is_read": "eq.false"
    })

    for item in items:
        update(
            "notifications",
            {"id": f"eq.{item['id']}"},
            {"is_read": True}
        )

    return jsonify({
        "ok": True
    })
