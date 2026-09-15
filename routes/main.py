from flask import Blueprint, render_template, session, redirect, url_for
from supabase_db import get

main_bp = Blueprint("main", __name__)


@main_bp.route("/")
def home():
    user_id = session.get("user_id")

    if not user_id:
        return redirect(url_for("auth.login"))

    users = get("users", {
        "id": f"eq.{user_id}",
        "limit": 1
    })

    if not users:
        session.clear()
        return redirect(url_for("auth.login"))

    me = users[0]

    # پیام‌های ارسال‌شده
    sent = get("messages", {
        "sender_id": f"eq.{user_id}",
        "order": "created_at.desc"
    })

    # پیام‌های دریافت‌شده
    received = get("messages", {
        "receiver_id": f"eq.{user_id}",
        "order": "created_at.desc"
    })

    # ساخت لیست چت‌ها
    chat_users = {}

    for message in sent:
        other_id = message.get("receiver_id")

        if other_id and other_id != user_id:
            if other_id not in chat_users:
                chat_users[other_id] = message

    for message in received:
        other_id = message.get("sender_id")

        if other_id and other_id != user_id:
            if other_id not in chat_users:
                chat_users[other_id] = message

    chats = []

    for other_id, last_message in chat_users.items():
        other_users = get("users", {
            "id": f"eq.{other_id}",
            "limit": 1
        })

        if not other_users:
            continue

        other = other_users[0]

        unread_messages = get("messages", {
            "sender_id": f"eq.{other_id}",
            "receiver_id": f"eq.{user_id}",
            "is_read": "eq.false"
        })

        chats.append({
            "user": other,
            "last_message": last_message,
            "unread": len(unread_messages)
        })

    # مرتب‌سازی چت‌ها بر اساس آخرین پیام
    chats.sort(
        key=lambda x: x["last_message"].get("created_at", ""),
        reverse=True
    )

    # گروه‌هایی که کاربر عضو آنهاست
    memberships = get("group_members", {
        "user_id": f"eq.{user_id}"
    })

    groups = []

    for membership in memberships:
        group_id = membership.get("group_id")

        if not group_id:
            continue

        group_result = get("groups", {
            "id": f"eq.{group_id}",
            "limit": 1
        })

        if group_result:
            groups.append(group_result[0])

    # اعلان‌های خوانده‌نشده
    notifications = get("notifications", {
        "user_id": f"eq.{user_id}",
        "is_read": "eq.false"
    })

    unread = len(notifications)

    return render_template(
        "home.html",
        me=me,
        chats=chats,
        groups=groups,
        unread=unread
    )
