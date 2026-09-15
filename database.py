import sqlite3
import os
from config import Config

def connect():
    db = sqlite3.connect(Config.DATABASE)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    return db

def init_db():
    os.makedirs(Config.UPLOAD_FOLDER, exist_ok=True)

    for folder in ["images", "videos", "audio", "files", "avatars"]:
        os.makedirs(os.path.join(Config.UPLOAD_FOLDER, folder), exist_ok=True)

    db = connect()

    db.executescript("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        public_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        username TEXT UNIQUE COLLATE NOCASE NOT NULL,
        avatar TEXT,
        bio TEXT DEFAULT '',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender_id INTEGER NOT NULL,
        receiver_id INTEGER,
        group_id INTEGER,
        message TEXT DEFAULT '',
        file_name TEXT,
        original_name TEXT,
        file_type TEXT,
        reply_to INTEGER,
        forwarded_from INTEGER,
        edited INTEGER DEFAULT 0,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        read_at TEXT,
        FOREIGN KEY(sender_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS reactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        emoji TEXT NOT NULL,
        UNIQUE(message_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS blocks (
        blocker_id INTEGER NOT NULL,
        blocked_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY(blocker_id, blocked_id)
    );

    CREATE TABLE IF NOT EXISTS reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reporter_id INTEGER NOT NULL,
        reported_id INTEGER NOT NULL,
        reason TEXT NOT NULL,
        status TEXT DEFAULT 'open',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        avatar TEXT,
        owner_id INTEGER,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS group_members (
        group_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY(group_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        message TEXT NOT NULL,
        link TEXT,
        is_read INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_messages_private
    ON messages(sender_id, receiver_id, created_at);

    CREATE INDEX IF NOT EXISTS idx_messages_group
    ON messages(group_id, created_at);
    """)

    group = db.execute(
        "SELECT id FROM groups WHERE is_default=1 LIMIT 1"
    ).fetchone()

    if not group:
        db.execute(
            """
            INSERT INTO groups(name, description, is_default)
            VALUES (?, ?, 1)
            """,
            (
                "گروه چت سایت ABKAM",
                "گروه عمومی کاربران سایت ABKAM"
            )
        )

    db.commit()
    db.close()

def default_group(db):
    return db.execute(
        "SELECT id FROM groups WHERE is_default=1 LIMIT 1"
    ).fetchone()
