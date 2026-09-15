from flask import Blueprint, request, session, redirect, url_for, jsonify
from supabase_db import get, insert

reports_bp = Blueprint("reports", __name__)

def current_user():
    user_id = session.get("user_id")
    if not user_id:
        return None

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    return users[0] if users else None


@reports_bp.route("/report/<int:user_id>", methods=["POST"])
def report_user(user_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    if me["id"] == user_id:
        return jsonify({
            "ok": False,
            "error": "نمی‌توانید خودتان را گزارش کنید."
        }), 400

    target = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    if not target:
        return jsonify({
            "ok": False,
            "error": "کاربر پیدا نشد."
        }), 404

    reason = request.form.get("reason", "").strip()

    if not reason:
        return jsonify({
            "ok": False,
            "error": "دلیل گزارش را وارد کنید."
        }), 400

    created = insert(
        "reports",
        {
            "reporter_id": me["id"],
            "reported_user_id": user_id,
            "reason": reason
        }
    )

    return jsonify({
        "ok": True,
        "report": created[0] if created else None
    })


@reports_bp.route("/report", methods=["POST"])
def report_from_form():
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    user_id = request.form.get("user_id", "").strip()
    reason = request.form.get("reason", "").strip()

    try:
        user_id = int(user_id)
    except ValueError:
        return "شناسه کاربر نامعتبر است.", 400

    if user_id == me["id"]:
        return "نمی‌توانید خودتان را گزارش کنید.", 400

    target = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    if not target:
        return "کاربر پیدا نشد.", 404

    if not reason:
        return "دلیل گزارش را وارد کنید.", 400

    insert(
        "reports",
        {
            "reporter_id": me["id"],
            "reported_user_id": user_id,
            "reason": reason
        }
    )

    return redirect(url_for("users.public_profile", user_id=user_id))

