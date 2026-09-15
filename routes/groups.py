from flask import Blueprint, render_template, request, redirect, url_for, session, jsonify
from supabase_db import get, insert, update

groups_bp = Blueprint("groups", __name__)


def current_user():
    user_id = session.get("user_id")

    if not user_id:
        return None

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    return users[0] if users else None


def get_group(group_id):
    groups = get("groups", {
        "id": f"eq.{group_id}",
        "limit": 1
    })

    return groups[0] if groups else None


def is_member(group_id, user_id):
    members = get("group_members", {
        "group_id": f"eq.{group_id}",
        "user_id": f"eq.{user_id}",
        "limit": 1
    })

    return bool(members)


@groups_bp.route("/groups")
def groups():
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    memberships = get("group_members", {
        "user_id": f"eq.{me['id']}"
    })

    result = []

    for membership in memberships:
        group_id = membership.get("group_id")

        if not group_id:
            continue

        group = get_group(group_id)

        if group:
            result.append(group)

    return render_template(
        "groups.html",
        me=me,
        groups=result
    )


@groups_bp.route("/group/<int:group_id>")
def group(group_id):
    me = current_user()

    if not me:
        return redirect(url_for("auth.login"))

    group_data = get_group(group_id)

    if not group_data:
        return "گروه پیدا نشد.", 404

    if not is_member(group_id, me["id"]):
        return "شما عضو این گروه نیستید.", 403

    messages = get("messages", {
        "group_id": f"eq.{group_id}",
        "order": "created_at.asc"
    })

    members = get("group_members", {
        "group_id": f"eq.{group_id}"
    })

    member_users = []

    for member in members:
        user_id = member.get("user_id")

        if not user_id:
            continue

        users = get("users", {
            "id": f"eq.{user_id}",
            "limit": 1
        })

        if users:
            member_users.append(users[0])

    return render_template(
        "group.html",
        me=me,
        group=group_data,
        messages=messages,
        members=member_users
    )


@groups_bp.route("/api/group/<int:group_id>/join", methods=["POST"])
def join_group(group_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    group_data = get_group(group_id)

    if not group_data:
        return jsonify({
            "ok": False,
            "error": "گروه پیدا نشد."
        }), 404

    if is_member(group_id, me["id"]):
        return jsonify({
            "ok": True,
            "message": "شما قبلاً عضو این گروه هستید."
        })

    created = insert(
        "group_members",
        {
            "group_id": group_id,
            "user_id": me["id"]
        }
    )

    return jsonify({
        "ok": True,
        "member": created[0] if created else None
    })


@groups_bp.route("/api/group/<int:group_id>/leave", methods=["POST"])
def leave_group(group_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    members = get("group_members", {
        "group_id": f"eq.{group_id}",
        "user_id": f"eq.{me['id']}",
        "limit": 1
    })

    if not members:
        return jsonify({
            "ok": True,
            "message": "شما عضو این گروه نیستید."
        })

    from supabase_db import delete

    delete(
        "group_members",
        {
            "id": f"eq.{members[0]['id']}"
        }
    )

    return jsonify({
        "ok": True
    })


@groups_bp.route("/api/group/<int:group_id>/send", methods=["POST"])
def send_group_message(group_id):
    me = current_user()

    if not me:
        return jsonify({
            "ok": False,
            "error": "ابتدا وارد حساب شوید."
        }), 401

    group_data = get_group(group_id)

    if not group_data:
        return jsonify({
            "ok": False,
            "error": "گروه پیدا نشد."
        }), 404

    if not is_member(group_id, me["id"]):
        return jsonify({
            "ok": False,
            "error": "شما عضو این گروه نیستید."
        }), 403

    message = request.form.get("message", "").strip()

    if not message:
        return jsonify({
            "ok": False,
            "error": "پیام خالی است."
        }), 400

    created = insert(
        "messages",
        {
            "sender_id": me["id"],
            "receiver_id": None,
            "group_id": group_id,
            "message": message,
            "edited": False,
            "is_read": False
        }
    )

    return jsonify({
        "ok": True,
        "message": created[0] if created else None
    })
