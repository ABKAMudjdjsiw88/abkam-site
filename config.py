import os

SUPABASE_URL = os.getenv(
    "SUPABASE_URL",
    "https://vxvepvvgrtelmgarrgkc.supabase.co"
)

SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")

OWNER_USERNAME = os.getenv("OWNER_USERNAME", "")
OWNER_PASSWORD = os.getenv("OWNER_PASSWORD", "")

SECRET_KEY = os.getenv("FLASK_SECRET_KEY", "")

MAX_FILE_SIZE = 50 * 1024 * 1024

FILES_BUCKET = "abkam-files"
AVATARS_BUCKET = "abkam-avatars"
