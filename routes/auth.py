from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from supabase_db import get, insert, update
from datetime import datetime, timezone
from werkzeug.security import generate_password_hash, check_password_hash
import re

auth_bp = Blueprint("auth", __name__)


def valid_username(username):
    return bool(re.fullmatch(r"[A-Za-z0-9_]{3,32}", username or ""))


def now_utc():
    return datetime.now(timezone.utc).isoformat()


@auth_bp.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        username = request.form.get("username", "").strip().lstrip("@")
        password = request.form.get("password", "")
        password_confirm = request.form.get("password_confirm", "")

        if not name:
            flash("نام را وارد کنید.")
            return redirect(url_for("auth.register"))

        if not valid_username(username):
            flash("آیدی باید 3 تا 32 کاراکتر و فقط شامل حروف انگلیسی، عدد و _ باشد.")
            return redirect(url_for("auth.register"))

        if len(password) < 8:
            flash("رمز عبور باید حداقل 8 کاراکتر باشد.")
            return redirect(url_for("auth.register"))

        if password != password_confirm:
            flash("تکرار رمز عبور با رمز اصلی یکسان نیست.")
            return redirect(url_for("auth.register"))

        exists = get("users", {
            "username": f"ilike.{username}",
            "limit": 1
        })

        if exists:
            flash("این آیدی قبلاً گرفته شده است.")
            return redirect(url_for("auth.register"))

        password_hash = generate_password_hash(password)

        created = insert(
            "users",
            {
                "name": name,
                "username": username,
                "password_hash": password_hash,
                "last_seen": now_utc()
            }
        )

        if not created:
            flash("ثبت‌نام انجام نشد. دوباره تلاش کنید.")
            return redirect(url_for("auth.register"))

        user = created[0]

        default_groups = get("groups", {
            "name": "eq.گروه چت سایت ABKAM",
            "limit": 1
        })

        if default_groups:
            group_id = default_groups[0]["id"]

            already_member = get("group_members", {
                "group_id": f"eq.{group_id}",
                "user_id": f"eq.{user['id']}",
                "limit": 1
            })

            if not already_member:
                insert(
                    "group_members",
                    {
                        "group_id": group_id,
                        "user_id": user["id"]
                    }
                )

        session.clear()
        session["user_id"] = user["id"]

        return redirect(url_for("main.home"))

    return render_template("register.html")


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip().lstrip("@")
        password = request.form.get("password", "")

        if not valid_username(username):
            flash("آیدی واردشده معتبر نیست.")
            return redirect(url_for("auth.login"))

        if not password:
            flash("رمز عبور را وارد کنید.")
            return redirect(url_for("auth.login"))

        users = get("users", {
            "username": f"ilike.{username}",
            "limit": 1
        })

        if not users:
            flash("آیدی یا رمز عبور اشتباه است.")
            return redirect(url_for("auth.login"))

        user = users[0]

        password_hash = user.get("password_hash")

        if not password_hash:
            flash("این حساب هنوز رمز عبور ندارد. لطفاً دوباره ثبت‌نام کنید.")
            return redirect(url_for("auth.login"))

        if not check_password_hash(password_hash, password):
            flash("آیدی یا رمز عبور اشتباه است.")
            return redirect(url_for("auth.login"))

        update(
            "users",
            {"id": f"eq.{user['id']}"},
            {"last_seen": now_utc()}
        )

        session.clear()
        session["user_id"] = user["id"]

        return redirect(url_for("main.home"))

    return render_template("login.html")


@auth_bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
