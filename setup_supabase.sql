-- ==============================================================================
-- SafeLink / SafeGuard Supabase Database Quick Fix & Configuration
-- Run this in your Supabase Project -> SQL Editor -> Click 'Run'
-- Project URL: https://afagwdhpjnnbueiyjmde.supabase.co
-- ==============================================================================

-- 1. ALLOW APP & BACKEND TO INSERT / SYNC USER PROFILES (Fixes Error 42501)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_self_policy ON public.users;
DROP POLICY IF EXISTS users_insert_policy ON public.users;
DROP POLICY IF EXISTS users_all_policy ON public.users;

-- Allow user insertion during sign up
CREATE POLICY users_insert_policy ON public.users 
    FOR INSERT WITH CHECK (true);

-- Allow users and responders to read and update
CREATE POLICY users_all_policy ON public.users 
    FOR ALL USING (true) WITH CHECK (true);


-- 2. AUTOMATIC PROFILE CREATION TRIGGER (auth.users -> public.users)
-- Every time a user signs up via email/password or Google, this instantly
-- creates or updates their corresponding row in public.users.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, full_name, phone_number, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'SafeLink User'),
        COALESCE(NEW.raw_user_meta_data->>'phone', ''),
        NEW.email
    )
    ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        phone_number = EXCLUDED.phone_number,
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 3. APP CONFIG TABLE (For Automatic ngrok Tunnel Sync)
-- When the backend runs, it saves the current ngrok URL here.
-- The mobile app dynamically reads it so you never have to reconfigure URLs.
CREATE TABLE IF NOT EXISTS public.app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS allow_all_app_config ON public.app_config;
CREATE POLICY allow_all_app_config ON public.app_config 
    FOR ALL USING (true) WITH CHECK (true);

-- Seed initial ngrok URL if active
INSERT INTO public.app_config (key, value, updated_at)
VALUES ('backend_url', 'https://cb04-102-208-82-115.ngrok-free.app', now())
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value, updated_at = now();


-- 4. EMERGENCY CONTACTS PERMISSIONS (Fixes Error 42501 when adding contacts)
ALTER TABLE public.emergency_contacts DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.emergency_contacts TO anon, authenticated, service_role;

-- 5. PANIC EVENTS & GPS LOGS PERMISSIONS (Fixes Error 42501 on Alert Creation)
ALTER TABLE public.panic_events DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.panic_events TO anon, authenticated, service_role;

ALTER TABLE public.realtime_gps_logs DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.realtime_gps_logs TO anon, authenticated, service_role;

ALTER TABLE public.responder_alerts DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.responder_alerts TO anon, authenticated, service_role;

ALTER TABLE public.wearable_devices DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.wearable_devices TO anon, authenticated, service_role;

ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.users TO anon, authenticated, service_role;

SELECT 'SafeLink database configuration completed successfully! All RLS barriers lifted.' AS status;
