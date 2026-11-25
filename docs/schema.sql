

-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- ENUM TYPES
DO $$ BEGIN
    CREATE TYPE trigger_method AS ENUM ('pendant_touch', 'pendant_voice', 'app_shake', 'app_button', 'app_voice');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE panic_status AS ENUM ('active', 'acknowledged', 'resolved', 'false_alarm');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE responder_status AS ENUM ('available', 'responding', 'unavailable');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE consent_status AS ENUM ('pending', 'accepted', 'declined');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE notification_status AS ENUM ('sent', 'failed', 'pending');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE notification_channel AS ENUM ('sms', 'push', 'email');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─── USERS PROFILE TABLE ──────────────────────────────────
-- Directly linked to Supabase Auth auth.users
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name VARCHAR(120) NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    avatar_url TEXT,
    
    -- Emergency / Duress Password Hash
    emergency_password_hash TEXT,
    
    -- Community Responder Opt-in & Status
    is_community_responder BOOLEAN DEFAULT false NOT NULL,
    responder_status responder_status DEFAULT 'available',
    responder_opted_in_at TIMESTAMPTZ,
    responder_opted_out_at TIMESTAMPTZ,
    
    has_wearable BOOLEAN DEFAULT false NOT NULL,
    push_token TEXT,
    
    -- Last Known Location & Anonymisation (REQ-F10)
    last_latitude DOUBLE PRECISION,
    last_longitude DOUBLE PRECISION,
    last_location_updated_at TIMESTAMPTZ,
    is_location_anonymised BOOLEAN DEFAULT false NOT NULL,
    anonymised_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ─── WEARABLE DEVICES ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wearable_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    device_mac VARCHAR(17) UNIQUE NOT NULL,
    device_name VARCHAR(80),
    firmware_version VARCHAR(20),
    sim_iccid VARCHAR(22),
    paired_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    last_seen_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true NOT NULL
);

COMMENT ON COLUMN public.wearable_devices.device_mac IS 'BLE MAC address e.g. AA:BB:CC:DD:EE:FF';
COMMENT ON COLUMN public.wearable_devices.sim_iccid IS 'SIM card ICCID in the SIM800L module';

CREATE UNIQUE INDEX IF NOT EXISTS one_active_wearable_per_user 
ON public.wearable_devices(user_id) 
WHERE is_active = true AND user_id IS NOT NULL;

-- ─── EMERGENCY CONTACTS ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    contact_name VARCHAR(120) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    consent_status consent_status DEFAULT 'pending' NOT NULL,
    consented_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(user_id, phone_number)
);

-- ─── PANIC EVENTS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.panic_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT NOT NULL,
    wearable_device_id UUID REFERENCES public.wearable_devices(id) ON DELETE SET NULL,
    triggered_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    trigger_method trigger_method NOT NULL,
    status panic_status DEFAULT 'active' NOT NULL,
    resolved_at TIMESTAMPTZ,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_accuracy_m REAL,
    is_location_anonymised BOOLEAN DEFAULT false NOT NULL,
    anonymised_at TIMESTAMPTZ,
    emergency_contacts_notified BOOLEAN DEFAULT false NOT NULL,
    hotline_notified BOOLEAN DEFAULT false NOT NULL,
    community_responders_alerted INT DEFAULT 0 NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ─── RESPONDER ALERTS ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.responder_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    panic_event_id UUID REFERENCES public.panic_events(id) ON DELETE CASCADE NOT NULL,
    responder_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    alerted_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    acknowledged_at TIMESTAMPTZ,
    arrived_at TIMESTAMPTZ,
    distance_m REAL,
    UNIQUE(panic_event_id, responder_id)
);

COMMENT ON COLUMN public.responder_alerts.distance_m IS 'distance from responder to victim at time of alert';

-- ─── NOTIFICATIONS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    panic_event_id UUID REFERENCES public.panic_events(id) ON DELETE CASCADE NOT NULL,
    recipient_phone VARCHAR(20),
    recipient_email VARCHAR(255),
    recipient_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    channel notification_channel NOT NULL,
    message_body TEXT,
    status notification_status DEFAULT 'pending' NOT NULL,
    sent_at TIMESTAMPTZ,
    error_detail TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ─── REALTIME GPS LOGS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.realtime_gps_logs (
    id BIGSERIAL PRIMARY KEY,
    panic_event_id UUID REFERENCES public.panic_events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy_m REAL,
    recorded_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    is_anonymised BOOLEAN DEFAULT false NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_gps_logs_user_time ON public.realtime_gps_logs(user_id, recorded_at DESC);

-- ─── LOCATIONS (HISTORICAL & REALTIME TRACKING) ───────────
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
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

-- ─── LOCATION SHARING SESSIONS ───────────────────────────
CREATE TABLE IF NOT EXISTS public.location_sharing_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    session_token VARCHAR(64) UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32),'hex'),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sharing_session_contacts (
    session_id UUID REFERENCES public.location_sharing_sessions(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.emergency_contacts(id) ON DELETE CASCADE,
    PRIMARY KEY(session_id, contact_id)
);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (
        id,
        full_name,
        phone_number,
        email,
        emergency_password_hash,
        is_community_responder,
        responder_status,
        responder_opted_in_at,
        created_at,
        updated_at
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'User'),
        COALESCE(NULLIF(NEW.raw_user_meta_data->>'phone_number', ''), NULLIF(NEW.raw_user_meta_data->>'phone', ''), '+254700' || substring(replace(NEW.id::text, '-', ''), 1, 6)),
        NEW.email,
        NEW.raw_user_meta_data->>'emergency_password_hash',
        COALESCE((NEW.raw_user_meta_data->>'is_community_responder')::boolean, false),
        CASE WHEN COALESCE((NEW.raw_user_meta_data->>'is_community_responder')::boolean, false) THEN 'available'::responder_status ELSE NULL END,
        CASE WHEN COALESCE((NEW.raw_user_meta_data->>'is_community_responder')::boolean, false) THEN now() ELSE NULL END,
        now(),
        now()
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone_number = EXCLUDED.phone_number,
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS update_emergency_contacts_updated_at ON public.emergency_contacts;
CREATE TRIGGER update_emergency_contacts_updated_at BEFORE UPDATE ON public.emergency_contacts FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS update_panic_events_updated_at ON public.panic_events;
CREATE TRIGGER update_panic_events_updated_at BEFORE UPDATE ON public.panic_events FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();


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

-- Backward compatibility alias
CREATE OR REPLACE FUNCTION public.anonymise_old_panic_locations()
RETURNS void AS $$
BEGIN
    PERFORM public.anonymise_24h_location_data();
END;
$$ LANGUAGE plpgsql;

-- Schedule cron job for periodic hourly anonymisation if pg_cron is active
DO $$
BEGIN
    PERFORM cron.unschedule('anonymise_old_panic_locations_cron');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    PERFORM cron.schedule(
        'anonymise_24h_location_data_cron',
        '0 * * * *',
        'SELECT public.anonymise_24h_location_data()'
    );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available; function can be triggered via backend scheduler or API endpoint.';
END $$;

-- ROW LEVEL SECURITY (RLS)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wearable_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.panic_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.responder_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.realtime_gps_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_sharing_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sharing_session_contacts ENABLE ROW LEVEL SECURITY;

-- Locations policy
DROP POLICY IF EXISTS locations_all ON public.locations;
CREATE POLICY locations_all ON public.locations FOR ALL USING (true) WITH CHECK (true);

-- Users policies
DROP POLICY IF EXISTS users_self_policy ON public.users;
CREATE POLICY users_self_policy ON public.users FOR ALL USING (auth.uid() = id);

DROP POLICY IF EXISTS responders_discoverable_policy ON public.users;
CREATE POLICY responders_discoverable_policy ON public.users FOR SELECT 
USING (is_community_responder = true AND responder_status = 'available');

-- Wearable devices policies
DROP POLICY IF EXISTS wearable_devices_policy ON public.wearable_devices;
CREATE POLICY wearable_devices_policy ON public.wearable_devices FOR ALL USING (auth.uid() = user_id);

-- Emergency contacts policies
DROP POLICY IF EXISTS emergency_contacts_policy ON public.emergency_contacts;
CREATE POLICY emergency_contacts_policy ON public.emergency_contacts FOR ALL USING (auth.uid() = user_id);

-- Panic events policies
DROP POLICY IF EXISTS panic_events_policy ON public.panic_events;
CREATE POLICY panic_events_policy ON public.panic_events FOR ALL 
USING (auth.uid() = user_id OR EXISTS (
    SELECT 1 FROM public.responder_alerts 
    WHERE panic_event_id = panic_events.id AND responder_id = auth.uid()
));

-- Responder alerts policies
DROP POLICY IF EXISTS responder_alerts_policy ON public.responder_alerts;
CREATE POLICY responder_alerts_policy ON public.responder_alerts FOR ALL USING (auth.uid() = responder_id);

-- Realtime GPS logs policies
DROP POLICY IF EXISTS realtime_gps_logs_policy ON public.realtime_gps_logs;
CREATE POLICY realtime_gps_logs_policy ON public.realtime_gps_logs FOR ALL USING (auth.uid() = user_id);

-- Notifications policies
DROP POLICY IF EXISTS notifications_policy ON public.notifications;
CREATE POLICY notifications_policy ON public.notifications FOR ALL USING (auth.uid() = recipient_user_id);

-- Location sharing sessions policies
DROP POLICY IF EXISTS location_sharing_sessions_policy ON public.location_sharing_sessions;
CREATE POLICY location_sharing_sessions_policy ON public.location_sharing_sessions FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS sharing_session_contacts_policy ON public.sharing_session_contacts;
CREATE POLICY sharing_session_contacts_policy ON public.sharing_session_contacts FOR ALL 
USING (EXISTS (
    SELECT 1 FROM public.location_sharing_sessions s 
    WHERE s.id = sharing_session_contacts.session_id AND s.user_id = auth.uid()
));
