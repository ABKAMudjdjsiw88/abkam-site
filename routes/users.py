from flask import Blueprint, render_template, request, session, redirect, url_for
from supabase_db import get

users_bp = Blueprint("users", __name__)


@users_bp.route("/users")
def users():

    user_id = session.get("user_id")

    if not user_id:
        return redirect(url_for("auth.login"))

    q = request.args.get("q", "").strip()

    if q.startswith("@"):
        q = q[1:]

    results = []

    if q:

        # جستجو بر اساس نام، آیدی عددی یا username
        by_username = get(
            "users",
            {
                "username": f"ilike.*{q}*",
                "limit": 50
            }
        )

        by_name = get(
            "users",
            {
                "name": f"ilike.*{q}*",
                "limit": 50
            }
        )

        by_id = []

        if q.isdigit():
            by_id = get(
                "users",
                {
                    "id": f"eq.{q}",
                    "limit": 50
                }
            )

        seen = set()

        for user in by_username + by_name + by_id:

            if user["id"] == user_id:
                continue

            if user["id"] in seen:
                continue

            seen.add(user["id"])
            results.append(user)

    return render_template(
        "search.html",
        results=results,
        q=q
    )


@users_bp.route("/profile/<int:user_id>")
def public_profile(user_id):

    current_user = session.get("user_id")

    if not current_user:
        return redirect(url_for("auth.login"))

    users = get(
        "users",
        {
            "id": f"eq.{user_id}",
            "limit": 1
        }
    )

    if not users:
        return "کاربر پیدا نشد.", 404

    user = users[0]

    return render_template(
        "profile.html",
        user=user
    )


@users_bp.route("/u/<public_id>")
def public_profile_link(public_id):

    current_user = session.get("user_id")

    if not current_user:
        return redirect(url_for("auth.login"))

    users = get(
        "users",
        {
            "public_id": f"eq.{public_id}",
            "limit": 1
        }
    )

    if not users:
        return "کاربر پیدا نشد.", 404

    user = users[0]

    return render_template(
        "profile.html",
        user=user
    )
