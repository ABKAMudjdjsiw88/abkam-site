from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from supabase_db import get
from config import OWNER_USERNAME, OWNER_PASSWORD

owner_bp = Blueprint("owner", __name__, url_prefix="/owner")


def owner_logged_in():
    return session.get("owner_logged_in") is True


@owner_bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        if username == OWNER_USERNAME and password == OWNER_PASSWORD:
            session["owner_logged_in"] = True
            return redirect(url_for("owner.panel"))

        flash("نام کاربری یا رمز عبور اشتباه است.")

    return render_template("owner/login.html")


@owner_bp.route("/logout")
def logout():
    session.pop("owner_logged_in", None)
    return redirect(url_for("owner.login"))


@owner_bp.route("/")
def panel():
    if not owner_logged_in():
        return redirect(url_for("owner.login"))

    users = get("users", {
        "order": "created_at.desc"
    })

    reports = get("reports", {
        "order": "created_at.desc"
    })

    return render_template(
        "owner/panel.html",
        users=users,
        reports=reports
    )


@owner_bp.route("/chat/<int:user1>/<int:user2>")
def private_chat(user1, user2):
    if not owner_logged_in():
        return redirect(url_for("owner.login"))

    first = get("users", {
        "id": f"eq.{user1}",
        "limit": 1
    })

    second = get("users", {
        "id": f"eq.{user2}",
        "limit": 1
    })

    if not first or not second:
        return "کاربر پیدا نشد.", 404

    sent = get("messages", {
        "sender_id": f"eq.{user1}",
        "receiver_id": f"eq.{user2}",
        "order": "created_at.asc"
    })

    received = get("messages", {
        "sender_id": f"eq.{user2}",
        "receiver_id": f"eq.{user1}",
        "order": "created_at.asc"
    })

    messages = sent + received
    messages.sort(key=lambda x: x.get("created_at", ""))

    return render_template(
        "owner/chat.html",
        user1=first[0],
        user2=second[0],
        messages=messages
    )


@owner_bp.route("/user/<int:user_id>")
def user_details(user_id):
    if not owner_logged_in():
        return redirect(url_for("owner.login"))

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    if not users:
        return "کاربر پیدا نشد.", 404

    user = users[0]

    sent = get("messages", {
        "sender_id": f"eq.{user_id}",
        "order": "created_at.desc"
    })

    received = get("messages", {
        "receiver_id": f"eq.{user_id}",
        "order": "created_at.desc"
    })

    return render_template(
        "owner/panel.html",
        users=[user],
        reports=[],
        selected_user=user,
        sent_messages=sent,
        received_messages=received
    )
