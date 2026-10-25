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
VALUES ('backend_url', 'https://unpaved-coherent-encroach.ngrok-free.dev', now())
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value, updated_at = now();


-- 4. EMERGENCY CONTACTS PERMISSIONS (Fixes Error 42501 when adding contacts)
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS emergency_contacts_policy ON public.emergency_contacts;
DROP POLICY IF EXISTS emergency_contacts_all ON public.emergency_contacts;
DROP POLICY IF EXISTS emergency_contacts_insert ON public.emergency_contacts;
DROP POLICY IF EXISTS emergency_contacts_select ON public.emergency_contacts;
DROP POLICY IF EXISTS emergency_contacts_update ON public.emergency_contacts;
DROP POLICY IF EXISTS emergency_contacts_delete ON public.emergency_contacts;

-- Allow reading, inserting, updating, and deleting emergency contacts
CREATE POLICY emergency_contacts_all ON public.emergency_contacts 
    FOR ALL USING (true) WITH CHECK (true);


-- 5. WEARABLE DEVICES PERMISSIONS (Allows ESP32 & App to register & see wearable)
ALTER TABLE public.wearable_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS wearable_devices_policy ON public.wearable_devices;
DROP POLICY IF EXISTS wearable_devices_all ON public.wearable_devices;
CREATE POLICY wearable_devices_all ON public.wearable_devices 
    FOR ALL USING (true) WITH CHECK (true);


-- 6. PANIC EVENTS PERMISSIONS (Allows ESP32 pendant to log all SOS alerts)
ALTER TABLE public.panic_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS panic_events_policy ON public.panic_events;
DROP POLICY IF EXISTS panic_events_all ON public.panic_events;
CREATE POLICY panic_events_all ON public.panic_events 
    FOR ALL USING (true) WITH CHECK (true);


-- 7. SEED JOY CHEPCHUMBA USER & EMERGENCY CONTACT
INSERT INTO public.users (id, full_name, phone_number, email)
VALUES (
    '7426cae6-d358-4a02-9e2f-c7839a864e93',
    'Joy Chepchumba',
    '+254740034499',
    'chepchumbajr@gmail.com'
)
ON CONFLICT (id) DO UPDATE
SET full_name = EXCLUDED.full_name,
    phone_number = EXCLUDED.phone_number,
    email = EXCLUDED.email,
    updated_at = now();

-- Seed initial emergency contacts
INSERT INTO public.emergency_contacts (user_id, contact_name, phone_number, consent_status)
VALUES 
    ('7426cae6-d358-4a02-9e2f-c7839a864e93', 'Joy (Primary)', '+254740034499', 'accepted')
ON CONFLICT (user_id, phone_number) DO UPDATE
SET contact_name = EXCLUDED.contact_name,
    consent_status = 'accepted',
    updated_at = now();

SELECT 'SafeLink database configuration completed successfully!' AS status;
