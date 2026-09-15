import os
import requests

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
}


def _url(table):
    return f"{SUPABASE_URL}/rest/v1/{table}"


def get(table, params=None):
    response = requests.get(
        _url(table),
        headers=HEADERS,
        params=params or {},
        timeout=20,
    )
    response.raise_for_status()
    return response.json()


def insert(table, data):
    headers = {
        **HEADERS,
        "Prefer": "return=representation",
    }

    response = requests.post(
        _url(table),
        headers=headers,
        json=data,
        timeout=20,
    )
    response.raise_for_status()
    return response.json()


def update(table, filters, data):
    params = filters.copy()

    headers = {
        **HEADERS,
        "Prefer": "return=representation",
    }

    response = requests.patch(
        _url(table),
        headers=headers,
        params=params,
        json=data,
        timeout=20,
    )
    response.raise_for_status()
    return response.json()


def delete(table, filters):
    response = requests.delete(
        _url(table),
        headers=HEADERS,
        params=filters,
        timeout=20,
    )
    response.raise_for_status()

    if response.text:
        return response.json()

    return True


def upload_file(bucket, path, file_data, content_type="application/octet-stream"):
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}"

    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": content_type,
    }

    response = requests.post(
        url,
        headers=headers,
        data=file_data,
        timeout=120,
    )

    response.raise_for_status()
    return response.json()


def delete_file(bucket, path):
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}"

    response = requests.delete(
        url,
        headers=HEADERS,
        timeout=30,
    )

    response.raise_for_status()
    return True


def download_file(bucket, path):
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}"

    response = requests.get(
        url,
        headers=HEADERS,
        timeout=120,
    )

    response.raise_for_status()
    return response
