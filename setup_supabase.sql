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
    ('7426cae6-d358-4a02-9e2f-c7839a864e93', 'Joy (Primary)', '+254740034499', 'accepted'),
    ('7426cae6-d358-4a02-9e2f-c7839a864e93', 'National Police Helpline', '+254709570000', 'accepted')
ON CONFLICT (user_id, phone_number) DO UPDATE
SET contact_name = EXCLUDED.contact_name,
    consent_status = 'accepted',
    updated_at = now();

-- 8. SEED WEARABLE DEVICE & LINK TO USER
INSERT INTO public.wearable_devices (id, user_id, device_mac, device_name, firmware_version, is_active, last_seen_at)
VALUES (
    '69e529ae-6af0-4328-8ca1-2dabdd2a6f75',
    '7426cae6-d358-4a02-9e2f-c7839a864e93',
    '7C:DF:A1:00:11:22',
    'SafeLink Smart Pendant',
    '2.2.0',
    true,
    now()
)
ON CONFLICT (device_mac) DO UPDATE
SET user_id = EXCLUDED.user_id,
    device_name = EXCLUDED.device_name,
    firmware_version = EXCLUDED.firmware_version,
    is_active = true,
    last_seen_at = now();

UPDATE public.users 
SET has_wearable = true, updated_at = now() 
WHERE id = '7426cae6-d358-4a02-9e2f-c7839a864e93';


-- 9. LOCATIONS TABLE (For GPS Location Logging & Tracking History)
-- Stores all GPS tracks, responder location pings, and incident coordinates.
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    panic_event_id UUID REFERENCES public.panic_events(id) ON DELETE SET NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy_m REAL,
    is_anonymised BOOLEAN DEFAULT false NOT NULL,
    anonymised_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    recorded_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_locations_user_time ON public.locations(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_panic ON public.locations(panic_event_id);
CREATE INDEX IF NOT EXISTS idx_locations_anonymised ON public.locations(is_anonymised, recorded_at);

ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS locations_all ON public.locations;
CREATE POLICY locations_all ON public.locations 
    FOR ALL USING (true) WITH CHECK (true);


-- 10. USER LOCATION COLUMNS & DROP NOT-NULL CONSTRAINTS ON GPS LOGS
-- Allows coordinates to be set to NULL upon 24-hour anonymisation
ALTER TABLE public.realtime_gps_logs ALTER COLUMN latitude DROP NOT NULL;
ALTER TABLE public.realtime_gps_logs ALTER COLUMN longitude DROP NOT NULL;

-- Adds location tracking and 24h anonymisation metadata directly to public.users
ALTER TABLE public.users 
    ADD COLUMN IF NOT EXISTS last_latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS last_longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS last_location_updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS is_location_anonymised BOOLEAN DEFAULT false NOT NULL,
    ADD COLUMN IF NOT EXISTS anonymised_at TIMESTAMPTZ;


-- 11. 24-HOUR AUTOMATED LOCATION ANONYMISATION FUNCTION (REQ-F10 Privacy Standard)
-- Automatically anonymises location data across:
--   1. public.panic_events (resolutions or triggers older than 24h)
--   2. public.locations (GPS history points older than 24h)
--   3. public.realtime_gps_logs (real-time breadcrumbs older than 24h)
--   4. public.users (last known user/responder coordinates older than 24h)
CREATE OR REPLACE FUNCTION public.anonymise_24h_location_data()
RETURNS jsonb AS $$
DECLARE
    v_panic_count INT := 0;
    v_locations_count INT := 0;
    v_gps_count INT := 0;
    v_users_count INT := 0;
BEGIN
    -- 1. Anonymise panic_events older than 24 hours
    UPDATE public.panic_events
    SET 
        latitude = NULL,
        longitude = NULL,
        location_accuracy_m = NULL,
        is_location_anonymised = true,
        anonymised_at = now()
    WHERE (
        (resolved_at IS NOT NULL AND resolved_at < now() - INTERVAL '24 hours')
        OR (triggered_at < now() - INTERVAL '24 hours')
    )
    AND (is_location_anonymised = false OR latitude IS NOT NULL);
    GET DIAGNOSTICS v_panic_count = ROW_COUNT;

    -- 2. Anonymise locations table older than 24 hours
    UPDATE public.locations
    SET 
        latitude = NULL,
        longitude = NULL,
        accuracy_m = NULL,
        is_anonymised = true,
        anonymised_at = now()
    WHERE (recorded_at < now() - INTERVAL '24 hours' OR created_at < now() - INTERVAL '24 hours')
      AND (is_anonymised = false OR latitude IS NOT NULL);
    GET DIAGNOSTICS v_locations_count = ROW_COUNT;

    -- 3. Anonymise realtime_gps_logs older than 24 hours
    UPDATE public.realtime_gps_logs
    SET 
        latitude = NULL,
        longitude = NULL,
        accuracy_m = NULL,
        is_anonymised = true
    WHERE recorded_at < now() - INTERVAL '24 hours' 
      AND (is_anonymised = false OR latitude IS NOT NULL);
    GET DIAGNOSTICS v_gps_count = ROW_COUNT;

    -- 4. Anonymise users table last known locations older than 24 hours
    UPDATE public.users
    SET 
        last_latitude = NULL,
        last_longitude = NULL,
        is_location_anonymised = true,
        anonymised_at = now()
    WHERE (
        (last_location_updated_at IS NOT NULL AND last_location_updated_at < now() - INTERVAL '24 hours')
        OR (last_location_updated_at IS NULL AND updated_at < now() - INTERVAL '24 hours')
    )
    AND (last_latitude IS NOT NULL OR last_longitude IS NOT NULL);
    GET DIAGNOSTICS v_users_count = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'anonymised_at', now(),
        'panic_events_anonymised', v_panic_count,
        'locations_anonymised', v_locations_count,
        'realtime_gps_logs_anonymised', v_gps_count,
        'users_anonymised', v_users_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Backward compatibility alias for existing callers
CREATE OR REPLACE FUNCTION public.anonymise_old_panic_locations()
RETURNS void AS $$
BEGIN
    PERFORM public.anonymise_24h_location_data();
END;
$$ LANGUAGE plpgsql;

-- Schedule cron job for periodic hourly anonymisation if pg_cron extension is available
DO $$
BEGIN
    PERFORM cron.unschedule('anonymise_old_panic_locations_cron');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    PERFORM cron.schedule(
        'anonymise_24h_location_data_cron',
        '0 * * * *', -- Runs every hour at minute 0
        'SELECT public.anonymise_24h_location_data()'
    );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not enabled; backend Python scheduler/API will execute anonymise_24h_location_data periodically.';
END $$;

-- Trigger immediate anonymisation of all existing eligible data right now
SELECT public.anonymise_24h_location_data();

SELECT 'SafeLink database configuration & 24h location anonymisation completed successfully!' AS status;
