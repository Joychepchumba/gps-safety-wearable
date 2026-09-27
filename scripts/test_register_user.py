import os
import sys
import json
import hashlib
import time
import urllib.request
import urllib.error

def load_env(env_path):
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env_vars[k.strip()] = v.strip().strip("'\"")
    return env_vars

def hash_emergency_password(raw_password: str, salt: str) -> str:
    combined = (salt + raw_password).encode("utf-8")
    digest = hashlib.sha256(combined).hexdigest()
    return f"{salt}${digest}"

def test_registration():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    env = load_env(os.path.join(root_dir, ".env"))

    supabase_url = env.get("SUPABASE_URL")
    supabase_key = env.get("SUPABASE_ANON_KEY")
    service_key = env.get("SUPABASE_SERVICE_KEY")

    if not supabase_url or not supabase_key:
        print("[ERROR] SUPABASE_URL or SUPABASE_ANON_KEY missing in .env")
        sys.exit(1)

    print(f"Connecting to Supabase at: {supabase_url}")

    timestamp = int(time.time())
    test_email = f"safeguard.user.{timestamp}@gmail.com"
    test_password = "SecurePassword123!"
    full_name = "Amina Wanjiku"
    phone_number = f"+25470{timestamp % 10000000:07d}"
    emergency_pin = "9999"
    salt = str(timestamp * 1000)
    emergency_hash = hash_emergency_password(emergency_pin, salt)

    user_meta = {
        "full_name": full_name,
        "phone_number": phone_number,
        "is_community_responder": True,
        "emergency_password_hash": emergency_hash
    }

    print("\n--- 1. Registering New User ---")
    print(f"Full Name:           {full_name}")
    print(f"Email:               {test_email}")
    print(f"Phone Number:        {phone_number}")
    print(f"Community Responder: True")
    print(f"Emergency Duress PIN:{emergency_pin}")

    # If service role key is available, use Admin API (bypasses email confirmation)
    if service_key and service_key != "your_service_key_here":
        print("\n[INFO] Using SUPABASE_SERVICE_KEY via Admin API (bypasses email rate limits)")
        admin_url = f"{supabase_url}/auth/v1/admin/users"
        admin_payload = {
            "email": test_email,
            "password": test_password,
            "email_confirm": True,
            "user_metadata": user_meta
        }
        req = urllib.request.Request(
            admin_url,
            data=json.dumps(admin_payload).encode("utf-8"),
            headers={
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
                "Content-Type": "application/json"
            },
            method="POST"
        )
    else:
        print("\n[INFO] Using SUPABASE_ANON_KEY via Public Signup API")
        signup_payload = {
            "email": test_email,
            "password": test_password,
            "data": user_meta
        }
        req = urllib.request.Request(
            f"{supabase_url}/auth/v1/signup",
            data=json.dumps(signup_payload).encode("utf-8"),
            headers={
                "apikey": supabase_key,
                "Content-Type": "application/json"
            },
            method="POST"
        )

    user_id = None
    access_token = None
    try:
        with urllib.request.urlopen(req) as resp:
            resp_data = json.loads(resp.read().decode("utf-8"))
            user = resp_data.get("user") or resp_data
            user_id = user.get("id")
            access_token = resp_data.get("access_token")
            print(f"\n[SUCCESS] User created in auth.users! ID: {user_id}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        print(f"\n[FAILED] HTTP {e.code}: {e.reason}")
        print(f"Details: {err_body}")
        if "over_email_send_rate_limit" in err_body:
            print("\n" + "="*60)
            print("RATE LIMIT FIX:")
            print("1. Open Supabase Dashboard: https://supabase.com/dashboard/project/afagwdhpjnnbueiyjmde/auth/providers")
            print("2. Click 'Email' provider.")
            print("3. Toggle OFF 'Confirm email'.")
            print("4. Click 'Save' and re-run this script!")
            print("   (Or add SUPABASE_SERVICE_KEY=... to your .env file)")
            print("="*60)
        return

    # 2. Check if user profile was created in public.users
    print("\n--- 2. Verifying public.users Database Profile ---")
    auth_header = f"Bearer {service_key}" if (service_key and service_key != "your_service_key_here") else (f"Bearer {access_token}" if access_token else f"Bearer {supabase_key}")
    profile_url = f"{supabase_url}/rest/v1/users?id=eq.{user_id}&select=*"
    
    prof_req = urllib.request.Request(
        profile_url,
        headers={
            "apikey": service_key if (service_key and service_key != "your_service_key_here") else supabase_key,
            "Authorization": auth_header
        },
        method="GET"
    )

    try:
        with urllib.request.urlopen(prof_req) as resp:
            prof_data = json.loads(resp.read().decode("utf-8"))
            if prof_data:
                print("[SUCCESS] Profile found in public.users table:")
                print(json.dumps(prof_data[0], indent=2))
            else:
                print("[WARNING] User registered in auth.users, but no profile row found in public.users yet.")
                print("Tip: If the SQL trigger 'on_auth_user_created' has not been applied yet, run docs/schema.sql in Supabase SQL Editor.")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        print(f"[HTTP ERROR when querying public.users]: {e.code} - {err_body}")

if __name__ == "__main__":
    test_registration()
