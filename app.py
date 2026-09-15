
import os

from flask import Flask

from config import SECRET_KEY, MAX_FILE_SIZE

from routes.main import main_bp
from routes.auth import auth_bp
from routes.users import users_bp
from routes.chat import chat_bp
from routes.groups import groups_bp
from routes.profile import profile_bp
from routes.notifications import notifications_bp
from routes.reports import reports_bp
from routes.owner import owner_bp


app = Flask(__name__)

app.secret_key = SECRET_KEY

# حداکثر حجم درخواست فایل: 50MB
app.config["MAX_CONTENT_LENGTH"] = MAX_FILE_SIZE

# Session
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

# در Render از HTTPS استفاده می‌شود
if os.getenv("RENDER"):
    app.config["SESSION_COOKIE_SECURE"] = True


app.register_blueprint(main_bp)
app.register_blueprint(auth_bp)
app.register_blueprint(users_bp)
app.register_blueprint(chat_bp)
app.register_blueprint(groups_bp)
app.register_blueprint(profile_bp)
app.register_blueprint(notifications_bp)
app.register_blueprint(reports_bp)
app.register_blueprint(owner_bp)


@app.errorhandler(413)
def too_large(error):
    return "حجم فایل بیشتر از 50MB است.", 413


@app.route("/health")
def health():
    return {
        "ok": True,
        "service": "ABKAM"
    }


if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    app.run(
        host="0.0.0.0",
        port=port,
        debug=False
    )
