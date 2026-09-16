from flask import Blueprint, render_template, request, redirect, url_for, session
from supabase_db import get, delete
from config import OWNER_USERNAME, OWNER_PASSWORD

owner_bp = Blueprint("owner", __name__, url_prefix="/owner")


def owner_logged_in():
    return session.get("owner_logged_in") is True


def owner_required():
    if not owner_logged_in():
        return redirect(url_for("owner.login"))
    return None


@owner_bp.route("/login", methods=["GET", "POST"])
def login():
    if owner_logged_in():
        return redirect(url_for("owner.panel"))

    error = None

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        if username == OWNER_USERNAME and password == OWNER_PASSWORD:
            session.clear()
            session["owner_logged_in"] = True
            return redirect(url_for("owner.panel"))

        error = "نام کاربری یا رمز عبور اشتباه است."

    return render_template("owner/login.html", error=error)


@owner_bp.route("/logout")
def logout():
    session.pop("owner_logged_in", None)
    return redirect(url_for("owner.login"))


@owner_bp.route("/")
@owner_bp.route("/panel")
def panel():
    check = owner_required()
    if check:
        return check

    users = get("users", {
        "order": "created_at.desc"
    }) or []

    messages = get("messages", {
        "order": "created_at.desc"
    }) or []

    groups = get("groups", {
        "order": "created_at.desc"
    }) or []

    reports = get("reports", {
        "order": "created_at.desc"
    }) or []

    stats = {
        "users": len(users),
        "messages": len(messages),
        "groups": len(groups),
        "reports": len(reports),
    }

    return render_template(
        "owner/panel.html",
        users=users,
        reports=reports,
        stats=stats
    )


@owner_bp.route("/delete-user/<int:user_id>", methods=["POST"])
def delete_user(user_id):
    check = owner_required()
    if check:
        return check

    try:
        users = get("users", {
            "id": f"eq.{user_id}",
            "limit": 1
        }) or []

        if not users:
            return "کاربر پیدا نشد.", 404

        print(f"[OWNER DELETE] شروع حذف کاربر {user_id}")

        # موارد وابسته؛ اگر یکی از جدول‌های اختیاری مشکل داشت،
        # حذف بقیه موارد متوقف نمی‌شود.
        delete_tasks = [
            ("messages - sender", "messages", {"sender_id": f"eq.{user_id}"}),
            ("messages - receiver", "messages", {"receiver_id": f"eq.{user_id}"}),
            ("group_members", "group_members", {"user_id": f"eq.{user_id}"}),
            ("notifications", "notifications", {"user_id": f"eq.{user_id}"}),
            ("reports reported", "reports", {"reported_user_id": f"eq.{user_id}"}),
            ("reports reporter", "reports", {"reporter_id": f"eq.{user_id}"})
        ]

        for name, table, filters in delete_tasks:
            try:
                delete(table, filters)
                print(f"[OWNER DELETE] {name}: OK")
            except Exception as e:
                print(f"[OWNER DELETE] {name}: SKIPPED -> {e}")

        # حذف خود حساب؛ این قسمت باید موفق شود.
        print("[OWNER DELETE] deleting user...")
        delete("users", {"id": f"eq.{user_id}"})

        print(f"[OWNER DELETE] user {user_id} deleted successfully")

        return redirect(url_for("owner.panel"))

    except Exception as e:
        print("[OWNER DELETE ERROR]", repr(e))

        return (
            "<h2>خطا هنگام حذف کاربر</h2>"
            "<p>خود حساب حذف نشد.</p>"
            "<pre>"
            + str(e)
            + "</pre>",
            500
        )


@owner_bp.route("/chat/<int:user_id>")
def user_chat(user_id):
    check = owner_required()
    if check:
        return check

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    }) or []

    if not users:
        return "کاربر پیدا نشد.", 404

    user = users[0]

    sent = get("messages", {
        "sender_id": f"eq.{user_id}",
        "order": "created_at.asc"
    }) or []

    received = get("messages", {
        "receiver_id": f"eq.{user_id}",
        "order": "created_at.asc"
    }) or []

    messages = sent + received
    messages.sort(key=lambda x: x.get("created_at", ""))

    user_ids = set()

    for message in messages:
        if message.get("sender_id"):
            user_ids.add(message["sender_id"])

        if message.get("receiver_id"):
            user_ids.add(message["receiver_id"])

    user_map = {}

    for uid in user_ids:
        result = get("users", {
            "id": f"eq.{uid}",
            "limit": 1
        }) or []

        if result:
            user_map[uid] = result[0]

    for message in messages:
        sender = user_map.get(message.get("sender_id"))
        receiver = user_map.get(message.get("receiver_id"))

        message["sender_username"] = (
            sender.get("username")
            if sender else "نامشخص"
        )

        message["receiver_username"] = (
            receiver.get("username")
            if receiver else None
        )

    return render_template(
        "owner/chat.html",
        u=user,
        messages=messages
    )
