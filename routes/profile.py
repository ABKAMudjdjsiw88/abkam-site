from flask import Blueprint, render_template, request, redirect, url_for, session, jsonify
from supabase_db import get, update

profile_bp = Blueprint("profile", __name__)


def current_user():
    user_id = session.get("user_id")

    if not user_id:
        return None

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    return users[0] if users else None


@profile_bp.route("/profile")
def profile():
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    return render_template(
        "profile.html",
        me=me
    )


@profile_bp.route("/api/profile/update", methods=["POST"])
def update_profile():
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    name = request.form.get("name", "").strip()
    username = request.form.get("username", "").strip().lstrip("@")
    bio = request.form.get("bio", "").strip()

    data = {}

    if name:
        data["name"] = name

    if username and username != me.get("username"):
        existing = get("users", {
            "username": f"ilike.{username}",
            "limit": 1
        })

        if existing and existing[0]["id"] != me["id"]:
            return jsonify({
                "ok": False,
                "error": "این آیدی قبلاً گرفته شده است."
            }), 400

        data["username"] = username

    data["bio"] = bio

    updated = update(
        "users",
        {"id": f"eq.{me['id']}"},
        data
    )

    return jsonify({
        "ok": True,
        "user": updated[0] if updated else None
    })


@profile_bp.route("/api/profile/avatar", methods=["POST"])
def update_avatar():
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    file = request.files.get("avatar")

    if not file or not file.filename:
        return jsonify({
            "ok": False,
            "error": "عکس انتخاب نشده است."
        }), 400

    from config import MAX_FILE_SIZE, AVATARS_BUCKET
    from supabase_db import upload_file

    file.seek(0, 2)
    size = file.tell()
    file.seek(0)

    if size > MAX_FILE_SIZE:
        return jsonify({
            "ok": False,
            "error": "حجم عکس بیشتر از 50MB است."
        }), 413

    filename = f"{me['id']}_{file.filename}"

    upload_file(
        AVATARS_BUCKET,
        filename,
        file.read(),
        file.content_type or "image/jpeg"
    )

    avatar_url = (
        f"{__import__('os').getenv('SUPABASE_URL')}"
        f"/storage/v1/object/public/{AVATARS_BUCKET}/{filename}"
    )

    updated = update(
        "users",
        {"id": f"eq.{me['id']}"},
        {"avatar": avatar_url}
    )

    return jsonify({
        "ok": True,
        "user": updated[0] if updated else None
    })
