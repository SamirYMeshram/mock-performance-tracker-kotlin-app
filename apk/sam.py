from pathlib import Path
import re
import shutil
import base64
import json

# ============================================================
# REQUIRED STUDY PULSE PRO VALUES
# ============================================================

PROJECT_ID = "bcljjhoazecxiqrllbkx"
BASE_URL = "https://bcljjhoazecxiqrllbkx.supabase.co"
PUBLISHABLE_KEY = "sb_publishable_mgXuAxdSad-QnJTewuyVDA_Q_lhV06B"

# Correct anon public key.
# Important: this key payload contains "iss": "supabase", not "iss": "HS256".
ANON_PUBLIC_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjbGpqaG9hemVjeGlxcmxsYmt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3Njg5NDksImV4cCI6MjA5MjM0NDk0OX0."
    "Bwb3VYqY2_WPRaJeRxgujmQQ9BB7vW7i7goHcOzfrdY"
)

DEFAULT_EMAIL = "sam@gmail.com"

# Do NOT put the sbp_ access token in this file.
FORBIDDEN_ACCESS_TOKEN_PREFIX = "sbp_"

# ============================================================
# PATHS
# ============================================================

ROOT = Path.cwd()

CORE_FILE = ROOT / "app/src/main/java/com/liquidglass/study/core/Core.kt"
SCREENS_FILE = ROOT / "app/src/main/java/com/liquidglass/study/ui/Screens.kt"


def backup_file(path: Path):
    backup = path.with_suffix(path.suffix + ".bak")
    if not backup.exists():
        shutil.copy2(path, backup)
        print(f"Backup created: {backup}")


def decode_jwt_payload(token: str) -> dict:
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return {}
        payload = parts[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    except Exception:
        return {}


def is_valid_service_role_key(token: str) -> bool:
    payload = decode_jwt_payload(token)
    return (
        payload.get("role") == "service_role"
        and payload.get("ref") == PROJECT_ID
    )


def is_valid_anon_key(token: str) -> bool:
    payload = decode_jwt_payload(token)
    return (
        payload.get("role") == "anon"
        and payload.get("ref") == PROJECT_ID
        and payload.get("iss") == "supabase"
    )


def get_study_block(text: str) -> str:
    match = re.search(
        r'val\s+Study\s*=\s*SupabaseProjectConfig\s*\((.*?)\n\s*\)',
        text,
        flags=re.DOTALL
    )
    if not match:
        raise RuntimeError("Could not find Study SupabaseProjectConfig block in Core.kt")
    return match.group(0)


def get_value_from_block(block: str, key: str):
    match = re.search(rf'{key}\s*=\s*"([^"]*)"', block)
    return match.group(1) if match else None


def patch_core_file():
    if not CORE_FILE.exists():
        raise FileNotFoundError(f"Missing file: {CORE_FILE}")

    text = CORE_FILE.read_text(encoding="utf-8")
    original_text = text

    if FORBIDDEN_ACCESS_TOKEN_PREFIX in text:
        raise RuntimeError(
            "Found sbp_ access token in Core.kt. Remove it first. "
            "The Supabase access token must not be inside the Android app."
        )

    old_study_block = get_study_block(text)

    existing_service_role_key = get_value_from_block(old_study_block, "serviceRoleKey")

    if not existing_service_role_key or not is_valid_service_role_key(existing_service_role_key):
        raise RuntimeError(
            "Study serviceRoleKey is missing or invalid.\n"
            "Open Core.kt and put your real service_role JWT in the Study block first.\n"
            "Do NOT use the sbp_ access token."
        )

    if not is_valid_anon_key(ANON_PUBLIC_KEY):
        raise RuntimeError("The ANON_PUBLIC_KEY inside this script is invalid.")

    new_study_block = f'''val Study = SupabaseProjectConfig(
        moduleKey = "Study",
        appName = "Study Pulse Pro",
        projectId = "{PROJECT_ID}",
        baseUrl = "{BASE_URL}",
        anonKey = "{ANON_PUBLIC_KEY}",
        source = "projects/Mock-Performance-Tracker/assets/js/config.js",
        publishableKey = "{PUBLISHABLE_KEY}",
        serviceRoleKey = "{existing_service_role_key}"
    )'''

    text = text.replace(old_study_block, new_study_block)

    if text != original_text:
        backup_file(CORE_FILE)
        CORE_FILE.write_text(text, encoding="utf-8")
        print("Changed Core.kt")
    else:
        print("Core.kt already correct")


def patch_screens_file():
    if not SCREENS_FILE.exists():
        raise FileNotFoundError(f"Missing file: {SCREENS_FILE}")

    text = SCREENS_FILE.read_text(encoding="utf-8")
    original_text = text

    text = re.sub(
        r'var\s+email\s+by\s+rememberSaveable\s*\{\s*mutableStateOf\("[^"]*"\)\s*\}',
        f'var email by rememberSaveable {{ mutableStateOf("{DEFAULT_EMAIL}") }}',
        text
    )

    if text != original_text:
        backup_file(SCREENS_FILE)
        SCREENS_FILE.write_text(text, encoding="utf-8")
        print("Changed Screens.kt")
    else:
        print("Screens.kt already correct")


def verify_final_files():
    core_text = CORE_FILE.read_text(encoding="utf-8")
    study_block = get_study_block(core_text)

    project_id = get_value_from_block(study_block, "projectId")
    base_url = get_value_from_block(study_block, "baseUrl")
    anon_key = get_value_from_block(study_block, "anonKey")
    publishable_key = get_value_from_block(study_block, "publishableKey")
    service_role_key = get_value_from_block(study_block, "serviceRoleKey")

    checks = [
        ("Study projectId", project_id == PROJECT_ID),
        ("Study baseUrl", base_url == BASE_URL),
        ("Study publishableKey", publishable_key == PUBLISHABLE_KEY),
        ("Study anonKey role/ref/issuer", is_valid_anon_key(anon_key or "")),
        ("Study serviceRoleKey role/ref", is_valid_service_role_key(service_role_key or "")),
        ("No sbp_ access token in Core.kt", FORBIDDEN_ACCESS_TOKEN_PREFIX not in core_text),
    ]

    print()
    print("Verification:")
    all_ok = True

    for name, ok in checks:
        if ok:
            print(f"PASS: {name}")
        else:
            print(f"FAIL: {name}")
            all_ok = False

    print()

    if all_ok:
        print("RESULT: Everything looks correct.")
    else:
        print("RESULT: Some checks failed. Check the FAIL lines above.")


def main():
    print("Project root:")
    print(ROOT)
    print()

    patch_core_file()
    patch_screens_file()
    verify_final_files()


if __name__ == "__main__":
    main()