--
-- PostgreSQL database dump
--

-- Dumped from database version 15.13
-- Dumped by pg_dump version 15.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE anagram_game;
--
-- Name: anagram_game; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE anagram_game WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'en_US.utf8';


ALTER DATABASE anagram_game OWNER TO postgres;

\connect anagram_game

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: calculate_phrase_score(integer, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_phrase_score(difficulty_score integer, player_uuid uuid, phrase_uuid uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    hints_used INTEGER;
    final_score NUMERIC;
BEGIN
    -- Count hints used by this player for this phrase
    SELECT COUNT(*) INTO hints_used
    FROM hint_usage
    WHERE player_id = player_uuid AND phrase_id = phrase_uuid;
    
    -- Apply scoring formula: 100%, 90%, 70%, 50%
    final_score := difficulty_score;
    
    IF hints_used >= 1 THEN
        final_score := difficulty_score * 0.90;
    END IF;
    
    IF hints_used >= 2 THEN
        final_score := difficulty_score * 0.70;
    END IF;
    
    IF hints_used >= 3 THEN
        final_score := difficulty_score * 0.50;
    END IF;
    
    -- Return rounded whole number
    RETURN ROUND(final_score);
END;
$$;


ALTER FUNCTION public.calculate_phrase_score(difficulty_score integer, player_uuid uuid, phrase_uuid uuid) OWNER TO postgres;

--
-- Name: calculate_player_total_score(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_player_total_score(player_uuid uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO total_score
    FROM completed_phrases 
    WHERE player_id = player_uuid;
    
    RETURN total_score;
END;
$$;


ALTER FUNCTION public.calculate_player_total_score(player_uuid uuid) OWNER TO postgres;

--
-- Name: complete_phrase_for_player(uuid, uuid, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_phrase_for_player(player_uuid uuid, phrase_uuid uuid, completion_score integer DEFAULT 0, completion_time integer DEFAULT 0) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
BEGIN
    -- Check if phrase and player exist
    SELECT EXISTS(SELECT 1 FROM phrases WHERE id = phrase_uuid) INTO phrase_exists;
    SELECT EXISTS(SELECT 1 FROM players WHERE id = player_uuid) INTO player_exists;
    
    IF NOT phrase_exists OR NOT player_exists THEN
        RETURN FALSE;
    END IF;
    
    -- Mark phrase as completed (ignore conflicts)
    INSERT INTO completed_phrases (player_id, phrase_id, score, completion_time_ms)
    VALUES (player_uuid, phrase_uuid, completion_score, completion_time)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    -- Update phrase usage count
    UPDATE phrases SET usage_count = usage_count + 1 WHERE id = phrase_uuid;
    
    -- Update player completion count
    UPDATE players SET phrases_completed = phrases_completed + 1 WHERE id = player_uuid;
    
    -- Mark targeted phrase as delivered if applicable
    UPDATE player_phrases 
    SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP 
    WHERE phrase_id = phrase_uuid AND target_player_id = player_uuid;
    
    RETURN TRUE;
END;
$$;


ALTER FUNCTION public.complete_phrase_for_player(player_uuid uuid, phrase_uuid uuid, completion_score integer, completion_time integer) OWNER TO postgres;

--
-- Name: complete_phrase_for_player_with_hints(uuid, uuid, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_phrase_for_player_with_hints(player_uuid uuid, phrase_uuid uuid, completion_time integer DEFAULT 0) RETURNS TABLE(success boolean, final_score integer, hints_used integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
    difficulty_score INTEGER;
    hint_count INTEGER;
    calculated_score INTEGER;
BEGIN
    -- Check if phrase and player exist
    SELECT EXISTS(SELECT 1 FROM phrases WHERE id = phrase_uuid) INTO phrase_exists;
    SELECT EXISTS(SELECT 1 FROM players WHERE id = player_uuid) INTO player_exists;
    
    IF NOT phrase_exists OR NOT player_exists THEN
        RETURN QUERY SELECT FALSE, 0, 0;
        RETURN;
    END IF;
    
    -- Get phrase difficulty
    SELECT difficulty_level INTO difficulty_score FROM phrases WHERE id = phrase_uuid;
    
    -- Count hints used
    SELECT COUNT(*) INTO hint_count FROM hint_usage 
    WHERE player_id = player_uuid AND phrase_id = phrase_uuid;
    
    -- Calculate final score with hint penalties
    calculated_score := calculate_phrase_score(difficulty_score, player_uuid, phrase_uuid);
    
    -- Insert completion record
    INSERT INTO completed_phrases (player_id, phrase_id, score, completed_at, completion_time)
    VALUES (player_uuid, phrase_uuid, calculated_score, CURRENT_TIMESTAMP, completion_time)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    -- Mark as delivered if in player_phrases
    UPDATE player_phrases 
    SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP
    WHERE phrase_id = phrase_uuid AND target_player_id = player_uuid;
    
    RETURN QUERY SELECT TRUE, calculated_score, hint_count;
END;
$$;


ALTER FUNCTION public.complete_phrase_for_player_with_hints(player_uuid uuid, phrase_uuid uuid, completion_time integer) OWNER TO postgres;

--
-- Name: generate_contribution_token(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_contribution_token() RETURNS character varying
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN encode(gen_random_bytes(32), 'base64url');
END;
$$;


ALTER FUNCTION public.generate_contribution_token() OWNER TO postgres;

--
-- Name: get_next_phrase_for_player(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_next_phrase_for_player(player_uuid uuid) RETURNS TABLE(phrase_id uuid, content character varying, hint character varying, difficulty_level integer, phrase_type text, priority integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- First, try to get targeted phrases (highest priority)
    RETURN QUERY
    SELECT 
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'targeted'::TEXT,
        pp.priority
    FROM phrases p
    INNER JOIN player_phrases pp ON p.id = pp.phrase_id
    WHERE pp.target_player_id = player_uuid
        AND pp.is_delivered = false
        AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = player_uuid)
        AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = player_uuid)
    ORDER BY pp.priority ASC, pp.assigned_at ASC
    LIMIT 1;
    
    -- If found, return early
    IF FOUND THEN
        RETURN;
    END IF;
    
    -- If no targeted phrases, get random global phrase
    RETURN QUERY
    SELECT 
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'global'::TEXT,
        1 as priority
    FROM phrases p
    WHERE p.is_global = true
        AND p.is_approved = true
        AND p.created_by_player_id != player_uuid  -- Don't give players their own phrases
        AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = player_uuid)
        AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = player_uuid)
    ORDER BY RANDOM()
    LIMIT 1;
END;
$$;


ALTER FUNCTION public.get_next_phrase_for_player(player_uuid uuid) OWNER TO postgres;

--
-- Name: get_player_score_summary(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_player_score_summary(player_uuid uuid) RETURNS TABLE(daily_score integer, daily_rank integer, weekly_score integer, weekly_rank integer, total_score integer, total_rank integer, total_phrases integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(ps_daily.total_score, 0) as daily_score,
        COALESCE(ps_daily.rank_position, 0) as daily_rank,
        COALESCE(ps_weekly.total_score, 0) as weekly_score,
        COALESCE(ps_weekly.rank_position, 0) as weekly_rank,
        COALESCE(ps_total.total_score, 0) as total_score,
        COALESCE(ps_total.rank_position, 0) as total_rank,
        COALESCE(ps_total.phrases_completed, 0) as total_phrases
    FROM players p
    LEFT JOIN player_scores ps_daily ON p.id = ps_daily.player_id AND ps_daily.score_period = 'daily' AND ps_daily.period_start = CURRENT_DATE
    LEFT JOIN player_scores ps_weekly ON p.id = ps_weekly.player_id AND ps_weekly.score_period = 'weekly' AND ps_weekly.period_start = date_trunc('week', CURRENT_DATE)::date
    LEFT JOIN player_scores ps_total ON p.id = ps_total.player_id AND ps_total.score_period = 'total' AND ps_total.period_start = '1970-01-01'
    WHERE p.id = player_uuid;
END;
$$;


ALTER FUNCTION public.get_player_score_summary(player_uuid uuid) OWNER TO postgres;

--
-- Name: skip_phrase_for_player(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.skip_phrase_for_player(player_uuid uuid, phrase_uuid uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Add to skipped phrases (ignore conflicts)
    INSERT INTO skipped_phrases (player_id, phrase_id)
    VALUES (player_uuid, phrase_uuid)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    RETURN TRUE;
END;
$$;


ALTER FUNCTION public.skip_phrase_for_player(player_uuid uuid, phrase_uuid uuid) OWNER TO postgres;

--
-- Name: update_leaderboard_rankings(character varying, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_leaderboard_rankings(score_period_param character varying, period_start_param date DEFAULT NULL::date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    updated_count INTEGER := 0;
    target_period_start DATE;
BEGIN
    -- Determine period start if not provided
    IF period_start_param IS NULL THEN
        IF score_period_param = 'daily' THEN
            target_period_start := CURRENT_DATE;
        ELSIF score_period_param = 'weekly' THEN
            target_period_start := date_trunc('week', CURRENT_DATE)::date;
        ELSE
            target_period_start := '1970-01-01';
        END IF;
    ELSE
        target_period_start := period_start_param;
    END IF;
    
    -- Update rankings based on scores
    WITH ranked_scores AS (
        SELECT 
            player_id,
            total_score,
            phrases_completed,
            ROW_NUMBER() OVER (ORDER BY total_score DESC, phrases_completed DESC) as new_rank
        FROM player_scores
        WHERE score_period = score_period_param AND period_start = target_period_start
    )
    UPDATE player_scores ps
    SET rank_position = rs.new_rank,
        last_updated = CURRENT_TIMESTAMP
    FROM ranked_scores rs
    WHERE ps.player_id = rs.player_id 
      AND ps.score_period = score_period_param 
      AND ps.period_start = target_period_start;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;


ALTER FUNCTION public.update_leaderboard_rankings(score_period_param character varying, period_start_param date) OWNER TO postgres;

--
-- Name: update_player_score_aggregations(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_player_score_aggregations(player_uuid uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update daily scores
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed)
    SELECT 
        player_uuid,
        'daily',
        CURRENT_DATE,
        COALESCE(SUM(score), 0),
        COUNT(*)
    FROM completed_phrases
    WHERE player_id = player_uuid AND DATE(completed_at) = CURRENT_DATE
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = CASE WHEN EXCLUDED.phrases_completed > 0 THEN EXCLUDED.total_score::numeric / EXCLUDED.phrases_completed ELSE 0 END,
        last_updated = CURRENT_TIMESTAMP;
        
    -- Update weekly scores  
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed)
    SELECT 
        player_uuid,
        'weekly', 
        date_trunc('week', CURRENT_DATE)::date,
        COALESCE(SUM(score), 0),
        COUNT(*)
    FROM completed_phrases
    WHERE player_id = player_uuid AND completed_at >= date_trunc('week', CURRENT_DATE)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = CASE WHEN EXCLUDED.phrases_completed > 0 THEN EXCLUDED.total_score::numeric / EXCLUDED.phrases_completed ELSE 0 END,
        last_updated = CURRENT_TIMESTAMP;
        
    -- Update total scores
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed)
    SELECT 
        player_uuid,
        'total',
        '1970-01-01',
        COALESCE(SUM(score), 0),
        COUNT(*)
    FROM completed_phrases
    WHERE player_id = player_uuid
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = CASE WHEN EXCLUDED.phrases_completed > 0 THEN EXCLUDED.total_score::numeric / EXCLUDED.phrases_completed ELSE 0 END,
        last_updated = CURRENT_TIMESTAMP;
END;
$$;


ALTER FUNCTION public.update_player_score_aggregations(player_uuid uuid) OWNER TO postgres;

--
-- Name: update_player_scores_all_periods(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_player_scores_all_periods(player_uuid uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update aggregations
    PERFORM update_player_score_aggregations(player_uuid);
    
    -- Update rankings for all periods
    PERFORM update_leaderboard_rankings('daily');
    PERFORM update_leaderboard_rankings('weekly'); 
    PERFORM update_leaderboard_rankings('total');
    
    RETURN TRUE;
EXCEPTION 
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


ALTER FUNCTION public.update_player_scores_all_periods(player_uuid uuid) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: completed_phrases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.completed_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    completed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    score integer DEFAULT 0,
    completion_time_ms integer DEFAULT 0
);


ALTER TABLE public.completed_phrases OWNER TO postgres;

--
-- Name: phrases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    content character varying(200) NOT NULL,
    hint character varying(300) NOT NULL,
    difficulty_level integer DEFAULT 1,
    is_global boolean DEFAULT false,
    created_by_player_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_approved boolean DEFAULT false,
    usage_count integer DEFAULT 0,
    phrase_type character varying(50) DEFAULT 'custom'::character varying,
    language character varying(10) DEFAULT 'en'::character varying,
    theme character varying(100),
    contributor_name character varying(100),
    source character varying(20) DEFAULT 'app'::character varying,
    contribution_link_id uuid,
    sender_name character varying(100)
);


ALTER TABLE public.phrases OWNER TO postgres;

--
-- Name: player_phrases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.player_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phrase_id uuid,
    target_player_id uuid,
    assigned_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    priority integer DEFAULT 1,
    is_delivered boolean DEFAULT false,
    delivered_at timestamp without time zone
);


ALTER TABLE public.player_phrases OWNER TO postgres;

--
-- Name: skipped_phrases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.skipped_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    skipped_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.skipped_phrases OWNER TO postgres;

--
-- Name: available_phrases_for_player; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.available_phrases_for_player AS
 SELECT p.id,
    p.content,
    p.hint,
    p.difficulty_level,
    p.is_global,
    p.created_by_player_id,
        CASE
            WHEN (pp.target_player_id IS NOT NULL) THEN 'targeted'::text
            WHEN p.is_global THEN 'global'::text
            ELSE 'other'::text
        END AS phrase_type,
    pp.priority,
    pp.assigned_at
   FROM (public.phrases p
     LEFT JOIN public.player_phrases pp ON ((p.id = pp.phrase_id)))
  WHERE ((p.is_approved = true) AND (NOT (p.id IN ( SELECT completed_phrases.phrase_id
           FROM public.completed_phrases
          WHERE (completed_phrases.player_id = COALESCE(pp.target_player_id, '00000000-0000-0000-0000-000000000000'::uuid))))) AND (NOT (p.id IN ( SELECT skipped_phrases.phrase_id
           FROM public.skipped_phrases
          WHERE (skipped_phrases.player_id = COALESCE(pp.target_player_id, '00000000-0000-0000-0000-000000000000'::uuid))))));


ALTER TABLE public.available_phrases_for_player OWNER TO postgres;

--
-- Name: contribution_links; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contribution_links (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token character varying(255) NOT NULL,
    requesting_player_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone NOT NULL,
    used_at timestamp without time zone,
    contributor_name character varying(100),
    contributor_ip character varying(45),
    is_active boolean DEFAULT true,
    max_uses integer DEFAULT 1,
    current_uses integer DEFAULT 0
);


ALTER TABLE public.contribution_links OWNER TO postgres;

--
-- Name: emoji_catalog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.emoji_catalog (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    emoji_character character varying(10) NOT NULL,
    name character varying(100) NOT NULL,
    rarity_tier character varying(20) NOT NULL,
    drop_rate_percentage numeric(5,3) NOT NULL,
    points_reward integer NOT NULL,
    unicode_version character varying(10),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT emoji_catalog_drop_rate_percentage_check CHECK (((drop_rate_percentage > (0)::numeric) AND (drop_rate_percentage <= (100)::numeric))),
    CONSTRAINT emoji_catalog_points_reward_check CHECK ((points_reward > 0)),
    CONSTRAINT emoji_catalog_rarity_tier_check CHECK (((rarity_tier)::text = ANY ((ARRAY['legendary'::character varying, 'mythic'::character varying, 'epic'::character varying, 'rare'::character varying, 'uncommon'::character varying, 'common'::character varying])::text[])))
);


ALTER TABLE public.emoji_catalog OWNER TO postgres;

--
-- Name: emoji_global_discoveries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.emoji_global_discoveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    emoji_id uuid,
    first_discoverer_id uuid,
    discovered_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.emoji_global_discoveries OWNER TO postgres;

--
-- Name: hint_usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.hint_usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    hint_level integer NOT NULL,
    used_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT hint_usage_hint_level_check CHECK (((hint_level >= 1) AND (hint_level <= 3)))
);


ALTER TABLE public.hint_usage OWNER TO postgres;

--
-- Name: leaderboards; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.leaderboards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    score_period character varying(10) NOT NULL,
    period_start date NOT NULL,
    player_id uuid,
    player_name character varying(50) NOT NULL,
    total_score integer NOT NULL,
    phrases_completed integer NOT NULL,
    rank_position integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT leaderboards_score_period_check CHECK (((score_period)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'total'::character varying])::text[])))
);


ALTER TABLE public.leaderboards OWNER TO postgres;

--
-- Name: offline_phrases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.offline_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    downloaded_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_used boolean DEFAULT false,
    used_at timestamp without time zone
);


ALTER TABLE public.offline_phrases OWNER TO postgres;

--
-- Name: player_emoji_collections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.player_emoji_collections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    emoji_id uuid,
    discovered_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_first_global_discovery boolean DEFAULT false
);


ALTER TABLE public.player_emoji_collections OWNER TO postgres;

--
-- Name: player_scores; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.player_scores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    score_period character varying(10) NOT NULL,
    period_start date NOT NULL,
    total_score integer DEFAULT 0,
    phrases_completed integer DEFAULT 0,
    avg_score numeric(5,2) DEFAULT 0.00,
    rank_position integer DEFAULT 0,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT player_scores_score_period_check CHECK (((score_period)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'total'::character varying])::text[])))
);


ALTER TABLE public.player_scores OWNER TO postgres;

--
-- Name: players; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.players (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL,
    device_id character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    last_seen timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    phrases_completed integer DEFAULT 0,
    socket_id character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    total_emoji_points integer DEFAULT 0
);


ALTER TABLE public.players OWNER TO postgres;

--
-- Data for Name: completed_phrases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.completed_phrases (id, player_id, phrase_id, completed_at, score, completion_time_ms) FROM stdin;
\.


--
-- Data for Name: contribution_links; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.contribution_links (id, token, requesting_player_id, created_at, expires_at, used_at, contributor_name, contributor_ip, is_active, max_uses, current_uses) FROM stdin;
684cd898-5fd5-414b-b1c7-9f0ce4baab12	HE6x9sY_pvTnWNLa7wTg6-8EHBBjIwj7kqU4-D92UNU	bf9157db-a987-4696-9e57-b2f9b29fa378	2025-08-12 07:50:21.629469	2025-08-14 07:50:21.627	\N	\N	\N	t	3	0
45d59d64-6762-4db0-8ba5-8a9641ad8720	-YBufE7sPF1mDFTm5e1CkVY35lMTR4VdrEfDGNycLio	bf9157db-a987-4696-9e57-b2f9b29fa378	2025-08-12 08:00:36.798017	2025-08-14 08:00:36.796	\N	\N	\N	t	3	0
e6ee3216-93d3-4f6d-a146-e0a6294b9f62	DdkWloxOIRuVASY5it5jZsFYGA15fhrP1xcO5eqtO9Y	bf9157db-a987-4696-9e57-b2f9b29fa378	2025-08-12 08:22:51.827668	2025-08-14 08:22:51.826	\N	\N	\N	t	3	0
\.


--
-- Data for Name: emoji_catalog; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.emoji_catalog (id, emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version, is_active, created_at) FROM stdin;
019118c6-e8eb-419a-aa46-89cabee6f7fd	🫩	Face with Bags Under Eyes	legendary	0.100	500	16.0	t	2025-08-12 07:35:25.883986
39da2c39-c5de-46cf-be70-9d13390337a7	🎨	Paint Splatter	legendary	0.150	500	16.0	t	2025-08-12 07:35:25.883986
33121604-40bd-4bad-b189-2f900a9204b2	🫴	Fingerprint	legendary	0.200	500	16.0	t	2025-08-12 07:35:25.883986
f54113e3-c86b-4845-9054-d437caa02b46	🇨🇶	Flag for Sark	legendary	0.250	500	16.0	t	2025-08-12 07:35:25.883986
0bf4af05-2f33-4975-8628-ed0ae5fc5f7d	🦄	Unicorn	legendary	0.300	500	14.0	t	2025-08-12 07:35:25.883986
d175dcfc-1580-47bb-b5fd-cf55aa86988b	👑	Crown	legendary	0.350	500	6.0	t	2025-08-12 07:35:25.883986
6a29cc4e-a0ec-47e6-8b9b-e72e68971376	💎	Diamond	legendary	0.400	500	6.0	t	2025-08-12 07:35:25.883986
c6126aa1-61ff-4188-876d-b802f50c6d71	⚡	Lightning Bolt	legendary	0.450	500	6.0	t	2025-08-12 07:35:25.883986
89938bd8-0a7f-4563-b674-0141dc93e252	🌟	Glowing Star	legendary	0.500	500	6.0	t	2025-08-12 07:35:25.883986
4efa3725-7d5f-4050-8a19-3bf2200d8a6f	🪐	Ringed Planet	mythic	0.600	200	12.0	t	2025-08-12 07:35:25.889064
5e97869e-6d7b-4a8e-9bc4-27bc1fe57346	🧿	Nazar Amulet	mythic	0.800	200	11.0	t	2025-08-12 07:35:25.889064
81cafca6-1712-4e82-8d59-3e53785ca499	🎭	Performing Arts	mythic	1.000	200	6.0	t	2025-08-12 07:35:25.889064
55c3594a-9f12-43a8-b004-7ea18cff1a39	🏆	Trophy	mythic	1.200	200	6.0	t	2025-08-12 07:35:25.889064
f34a4e41-edd5-43a2-8b8b-34e7e9cd4d8c	🌌	Milky Way	mythic	1.400	200	6.0	t	2025-08-12 07:35:25.889064
d4916dfc-5951-4325-8736-865254bf9fe8	🔥	Fire	mythic	1.600	200	6.0	t	2025-08-12 07:35:25.889064
914c05aa-f861-48d5-b7e9-f09c5cabfb96	✨	Sparkles	mythic	1.800	200	6.0	t	2025-08-12 07:35:25.889064
9760cc3a-4dc8-419e-b01b-c41b3a8948d8	🎆	Fireworks	mythic	2.000	200	6.0	t	2025-08-12 07:35:25.889064
f9ae8999-7bad-4964-9209-cdc724c50b6e	🎯	Direct Hit	epic	2.500	100	6.0	t	2025-08-12 07:35:25.893144
03f77127-6710-42cd-8590-b1d5eea98e48	🎪	Circus Tent	epic	3.000	100	6.0	t	2025-08-12 07:35:25.893144
96b30a76-2f92-45b0-bd6c-1a7a1044797b	🎰	Slot Machine	epic	3.500	100	6.0	t	2025-08-12 07:35:25.893144
a63e0524-69be-4f08-bd65-cea8b26a8183	🚀	Rocket	epic	4.000	100	6.0	t	2025-08-12 07:35:25.893144
e7854caf-ab98-465e-ae8d-2a7a782e8145	🛸	Flying Saucer	epic	4.500	100	7.0	t	2025-08-12 07:35:25.893144
c26e314e-d872-45ff-998f-79cbb1d32d2f	🏁	Chequered Flag	epic	5.000	100	6.0	t	2025-08-12 07:35:25.893144
459202de-9ad4-4edc-b026-6edd7c763556	🎁	Gift	rare	6.000	25	6.0	t	2025-08-12 07:35:25.896196
a488aff8-cead-48a6-b564-65925a489b8f	🎈	Balloon	rare	7.000	25	6.0	t	2025-08-12 07:35:25.896196
a6c177d2-23ef-4644-ab17-b27745a1c761	🎀	Ribbon	rare	8.000	25	6.0	t	2025-08-12 07:35:25.896196
25454eed-b5ac-4098-9f01-a205f5dcf49a	🥇	Gold Medal	rare	9.000	25	9.0	t	2025-08-12 07:35:25.896196
97cfb582-fd9c-4dae-b531-ca142a8a9011	🥈	Silver Medal	rare	10.000	25	9.0	t	2025-08-12 07:35:25.896196
af8e4d36-1231-4599-87f3-3af8cf8db1ea	🥉	Bronze Medal	rare	11.000	25	9.0	t	2025-08-12 07:35:25.896196
7f8f986b-244e-4cf3-98df-1a96ad599602	🎖️	Military Medal	rare	12.000	25	7.0	t	2025-08-12 07:35:25.896196
d6ed0f03-61b3-4be7-ad64-6ab0766f4453	🏅	Sports Medal	rare	13.000	25	7.0	t	2025-08-12 07:35:25.896196
381c52d4-4c00-46cf-9c51-d48173b70785	🎗️	Reminder Ribbon	rare	14.000	25	7.0	t	2025-08-12 07:35:25.896196
fee2b42e-82eb-4e6f-ab0f-8974e43c3a03	🌈	Rainbow	rare	15.000	25	6.0	t	2025-08-12 07:35:25.896196
859f551c-4f5e-4419-88c1-d600dd88722e	🎵	Musical Note	uncommon	16.000	5	6.0	t	2025-08-12 07:35:25.899558
f40687ea-2850-42d8-b6c0-c23229b77f93	🎶	Musical Notes	uncommon	17.000	5	6.0	t	2025-08-12 07:35:25.899558
544a8da6-50e2-42f9-8a4b-fbb2f1248bac	🎼	Musical Score	uncommon	18.000	5	6.0	t	2025-08-12 07:35:25.899558
634d9adc-827b-46f6-b23a-9efe5d166800	🎤	Microphone	uncommon	19.000	5	6.0	t	2025-08-12 07:35:25.899558
d750fe80-7d17-4b22-b399-229b6263fe40	🎧	Headphone	uncommon	20.000	5	6.0	t	2025-08-12 07:35:25.899558
fa16131e-0a55-4d72-bdb4-01f4cc2f71b1	🎺	Trumpet	uncommon	21.000	5	6.0	t	2025-08-12 07:35:25.899558
cd9776f6-bbad-41da-a1f6-6463942b9096	🎷	Saxophone	uncommon	22.000	5	6.0	t	2025-08-12 07:35:25.899558
ae13f978-aa92-4791-8214-4e70ec385548	🎸	Guitar	uncommon	23.000	5	6.0	t	2025-08-12 07:35:25.899558
74f84b8c-d24b-4d46-a724-01b95958d0f2	🎻	Violin	uncommon	24.000	5	6.0	t	2025-08-12 07:35:25.899558
9f79540f-8099-40cc-b2d8-562d763562b6	🎹	Musical Keyboard	uncommon	25.000	5	6.0	t	2025-08-12 07:35:25.899558
9185bc31-d1b8-448b-92b7-ccce66883670	🥁	Drum	uncommon	26.000	5	9.0	t	2025-08-12 07:35:25.899558
ab35ae6d-7692-4e53-8c0c-0a97f38f11ee	💫	Dizzy	uncommon	27.000	5	6.0	t	2025-08-12 07:35:25.899558
d1831114-8abc-4611-a7c3-44454964334f	⭐	Star	uncommon	28.000	5	5.1	t	2025-08-12 07:35:25.899558
7e06e949-ef2a-4ea7-a70c-56828552bb11	🌠	Shooting Star	uncommon	29.000	5	6.0	t	2025-08-12 07:35:25.899558
bd0cf4bd-079a-4dca-a01d-82edd7647076	☄️	Comet	uncommon	30.000	5	7.0	t	2025-08-12 07:35:25.899558
16818411-bb35-44a4-aa06-e701cb708a0a	🌙	Crescent Moon	uncommon	31.000	5	6.0	t	2025-08-12 07:35:25.899558
8f44fb2a-490a-4411-a05d-e64a7cae4ae0	☀️	Sun	uncommon	32.000	5	6.0	t	2025-08-12 07:35:25.899558
7772d7c2-2233-4e07-9072-769bc3b3c291	🌞	Sun with Face	uncommon	33.000	5	6.0	t	2025-08-12 07:35:25.899558
0ca2daaa-3e6e-42a1-b67d-7fcbcc94f703	🌛	First Quarter Moon Face	uncommon	34.000	5	6.0	t	2025-08-12 07:35:25.899558
662123cf-0dec-4042-8447-06ccab2024c7	🌜	Last Quarter Moon Face	uncommon	35.000	5	6.0	t	2025-08-12 07:35:25.899558
\.


--
-- Data for Name: emoji_global_discoveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.emoji_global_discoveries (id, emoji_id, first_discoverer_id, discovered_at) FROM stdin;
\.


--
-- Data for Name: hint_usage; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.hint_usage (id, player_id, phrase_id, hint_level, used_at) FROM stdin;
\.


--
-- Data for Name: leaderboards; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.leaderboards (id, score_period, period_start, player_id, player_name, total_score, phrases_completed, rank_position, created_at) FROM stdin;
\.


--
-- Data for Name: offline_phrases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.offline_phrases (id, player_id, phrase_id, downloaded_at, is_used, used_at) FROM stdin;
\.


--
-- Data for Name: phrases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.phrases (id, content, hint, difficulty_level, is_global, created_by_player_id, created_at, is_approved, usage_count, phrase_type, language, theme, contributor_name, source, contribution_link_id, sender_name) FROM stdin;
e954e8ab-bb0e-4997-8515-dd9b4c61af8c	be kind	A simple act of compassion	1	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
04ac597e-0f95-474d-bca5-e9ffdb4ed852	hello world	The classic first program greeting	1	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
4a6cdfb5-02b1-4a1f-8559-ccbe5ffbf09d	time flies	What happens when you're having fun	2	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
225ef548-b587-4e75-9cad-6167fa2202c9	open door	Access point that's not closed	1	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
3df6b7b4-ef0b-4eaa-96f0-1aeb59279c46	quick brown fox jumps	Famous typing test animal in motion	3	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
95e443ac-4788-47d9-8586-c9c94798362f	make it count	Ensure your effort has value	2	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
a133a55e-fb58-4164-aa99-fb7aeb492359	lost keys	Common household frustration	2	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
4851c988-e329-40ff-b2f9-912b1525b568	coffee break	Mid-day caffeine pause	2	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
94cea02c-5432-4e9d-a3ff-2d702e510479	bright sunny day	Perfect weather for outdoor activities	2	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
b7e5f5e0-4663-448d-9db0-d11d9a86c112	code works	Developer's dream outcome	2	t	\N	2025-08-12 07:35:25.462711	t	0	custom	en	\N	\N	app	\N	\N
1dfa7c66-fadb-4d4c-9090-4eccc0042da5	good morning	Daily greeting when you wake up	2	t	\N	2025-08-12 08:21:32.827258	t	0	custom	en	\N	\N	app	\N	\N
4331d6c6-1c42-4738-8f77-41b0ae246bc0	happy birthday	Special celebration day	3	t	\N	2025-08-12 08:21:32.827258	t	0	custom	en	\N	\N	app	\N	\N
1a2cc1b2-fbe1-4e8d-8984-6b6b32fb38ac	nice work	Compliment for a job well done	2	t	\N	2025-08-12 08:21:32.827258	t	0	custom	en	\N	\N	app	\N	\N
5b377bef-e1e6-4575-90bb-214d36aad177	thank you	Expression of gratitude	2	t	\N	2025-08-12 08:21:32.827258	t	0	custom	en	\N	\N	app	\N	\N
f4e08189-4236-4bfc-9300-82660d130cda	good luck	Wish for success	2	t	\N	2025-08-12 08:21:32.827258	t	0	custom	en	\N	\N	app	\N	\N
\.


--
-- Data for Name: player_emoji_collections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.player_emoji_collections (id, player_id, emoji_id, discovered_at, is_first_global_discovery) FROM stdin;
\.


--
-- Data for Name: player_phrases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.player_phrases (id, phrase_id, target_player_id, assigned_at, priority, is_delivered, delivered_at) FROM stdin;
\.


--
-- Data for Name: player_scores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.player_scores (id, player_id, score_period, period_start, total_score, phrases_completed, avg_score, rank_position, last_updated) FROM stdin;
\.


--
-- Data for Name: players; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.players (id, name, device_id, is_active, last_seen, phrases_completed, socket_id, created_at, total_emoji_points) FROM stdin;
bf9157db-a987-4696-9e57-b2f9b29fa378	Bruno	1754955446_ABBAF2C0	f	2025-08-12 08:48:06.084192	0	\N	2025-08-12 07:50:19.141881	0
b202ab20-95f0-4614-913d-d8d518450676	Bruce	1754988516_7F0EF25A	f	2025-08-12 08:54:34.123611	0	\N	2025-08-12 08:48:36.700584	0
\.


--
-- Data for Name: skipped_phrases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.skipped_phrases (id, player_id, phrase_id, skipped_at) FROM stdin;
58223f1d-7226-4222-afc0-e8ac04bc8e33	bf9157db-a987-4696-9e57-b2f9b29fa378	225ef548-b587-4e75-9cad-6167fa2202c9	2025-08-12 08:22:04.470757
001f068a-fd8f-4911-bd36-d56e55c728c1	bf9157db-a987-4696-9e57-b2f9b29fa378	4851c988-e329-40ff-b2f9-912b1525b568	2025-08-12 08:31:11.525493
be7704f8-c088-4211-a0da-91431aec3964	bf9157db-a987-4696-9e57-b2f9b29fa378	1a2cc1b2-fbe1-4e8d-8984-6b6b32fb38ac	2025-08-12 08:42:41.73401
b3837072-a8ba-4122-9347-dd67e854a828	bf9157db-a987-4696-9e57-b2f9b29fa378	4a6cdfb5-02b1-4a1f-8559-ccbe5ffbf09d	2025-08-12 08:42:45.62998
8ed108d5-c132-46eb-b2c1-826a94ef1e4d	bf9157db-a987-4696-9e57-b2f9b29fa378	1dfa7c66-fadb-4d4c-9090-4eccc0042da5	2025-08-12 08:42:48.556405
13849e2a-93ee-4fb0-8c93-f835ec4b5a43	bf9157db-a987-4696-9e57-b2f9b29fa378	04ac597e-0f95-474d-bca5-e9ffdb4ed852	2025-08-12 08:42:51.011283
c0069dbd-5c6a-4745-9ccd-9419636736fb	bf9157db-a987-4696-9e57-b2f9b29fa378	a133a55e-fb58-4164-aa99-fb7aeb492359	2025-08-12 08:42:53.493577
f7df13df-6816-4cd0-9943-18946d0cfffa	bf9157db-a987-4696-9e57-b2f9b29fa378	e954e8ab-bb0e-4997-8515-dd9b4c61af8c	2025-08-12 08:42:55.901396
67e7f8e3-9131-4b08-bd76-7ae1fc492a3d	bf9157db-a987-4696-9e57-b2f9b29fa378	94cea02c-5432-4e9d-a3ff-2d702e510479	2025-08-12 08:42:58.904238
72e792f8-f912-4501-a749-e3e2b72214d1	bf9157db-a987-4696-9e57-b2f9b29fa378	95e443ac-4788-47d9-8586-c9c94798362f	2025-08-12 08:43:01.333122
2053d2b8-e515-4cfb-98f0-6749a0f8241a	bf9157db-a987-4696-9e57-b2f9b29fa378	3df6b7b4-ef0b-4eaa-96f0-1aeb59279c46	2025-08-12 08:43:03.653183
2b4f1e5c-e22c-4deb-acde-6e80652bab92	bf9157db-a987-4696-9e57-b2f9b29fa378	4331d6c6-1c42-4738-8f77-41b0ae246bc0	2025-08-12 08:43:06.01198
bec4ac98-e0a5-4ca0-be75-af4fc6b34e46	bf9157db-a987-4696-9e57-b2f9b29fa378	5b377bef-e1e6-4575-90bb-214d36aad177	2025-08-12 08:43:08.501693
0c9376ca-b54b-4f28-92e2-a97dddaa56fa	bf9157db-a987-4696-9e57-b2f9b29fa378	f4e08189-4236-4bfc-9300-82660d130cda	2025-08-12 08:43:11.071193
025becc4-82cf-4fbf-a33c-e74d0cb1bc02	bf9157db-a987-4696-9e57-b2f9b29fa378	b7e5f5e0-4663-448d-9db0-d11d9a86c112	2025-08-12 08:43:13.560037
d79bfaeb-061f-42dc-8c5c-a726e241f4d3	b202ab20-95f0-4614-913d-d8d518450676	a133a55e-fb58-4164-aa99-fb7aeb492359	2025-08-12 08:48:43.40789
4c80fb16-8f00-4244-a89f-ceb3e99d41b4	b202ab20-95f0-4614-913d-d8d518450676	1dfa7c66-fadb-4d4c-9090-4eccc0042da5	2025-08-12 08:48:46.616906
a5e5d2fe-f622-40fd-80da-ded294acc760	b202ab20-95f0-4614-913d-d8d518450676	04ac597e-0f95-474d-bca5-e9ffdb4ed852	2025-08-12 08:48:49.484851
d7b50ab1-aa24-4024-95bc-4d0da3091062	b202ab20-95f0-4614-913d-d8d518450676	e954e8ab-bb0e-4997-8515-dd9b4c61af8c	2025-08-12 08:48:52.382129
cf7149cc-3795-44bd-89b6-6da625568c26	b202ab20-95f0-4614-913d-d8d518450676	4a6cdfb5-02b1-4a1f-8559-ccbe5ffbf09d	2025-08-12 08:48:54.986342
90fa31d5-3db3-4190-b1f5-0df84687c078	b202ab20-95f0-4614-913d-d8d518450676	1a2cc1b2-fbe1-4e8d-8984-6b6b32fb38ac	2025-08-12 08:49:03.884577
157fe363-32d4-478b-a171-ef21e5fdcb34	b202ab20-95f0-4614-913d-d8d518450676	f4e08189-4236-4bfc-9300-82660d130cda	2025-08-12 08:49:07.666246
05a930be-ca65-4293-be37-d6f982df8f1f	b202ab20-95f0-4614-913d-d8d518450676	4331d6c6-1c42-4738-8f77-41b0ae246bc0	2025-08-12 08:49:11.274844
c5f11cdb-bee0-4088-8686-fe3cd426e918	b202ab20-95f0-4614-913d-d8d518450676	4851c988-e329-40ff-b2f9-912b1525b568	2025-08-12 08:49:14.444838
6b9d94b6-e99a-4203-af48-51fa66b6a7f1	b202ab20-95f0-4614-913d-d8d518450676	b7e5f5e0-4663-448d-9db0-d11d9a86c112	2025-08-12 08:49:17.708568
61a98a19-e3df-4b7c-b76e-ca79b4a8e64a	b202ab20-95f0-4614-913d-d8d518450676	225ef548-b587-4e75-9cad-6167fa2202c9	2025-08-12 08:49:20.868122
25a3faf3-0ab2-449f-8ee5-a915358dc699	b202ab20-95f0-4614-913d-d8d518450676	3df6b7b4-ef0b-4eaa-96f0-1aeb59279c46	2025-08-12 08:49:24.695331
1255a895-a35a-497f-80c8-2c297ccd0c5a	b202ab20-95f0-4614-913d-d8d518450676	94cea02c-5432-4e9d-a3ff-2d702e510479	2025-08-12 08:49:27.370442
b9070e91-b6fa-421c-b743-5f206b3dd989	b202ab20-95f0-4614-913d-d8d518450676	95e443ac-4788-47d9-8586-c9c94798362f	2025-08-12 08:49:30.004228
f1c213d5-227b-4bd6-a3e1-752c5e420b13	b202ab20-95f0-4614-913d-d8d518450676	5b377bef-e1e6-4575-90bb-214d36aad177	2025-08-12 08:49:32.596333
\.


--
-- Name: completed_phrases completed_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_pkey PRIMARY KEY (id);


--
-- Name: completed_phrases completed_phrases_player_id_phrase_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_player_id_phrase_id_key UNIQUE (player_id, phrase_id);


--
-- Name: contribution_links contribution_links_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contribution_links
    ADD CONSTRAINT contribution_links_pkey PRIMARY KEY (id);


--
-- Name: contribution_links contribution_links_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contribution_links
    ADD CONSTRAINT contribution_links_token_key UNIQUE (token);


--
-- Name: emoji_catalog emoji_catalog_emoji_character_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.emoji_catalog
    ADD CONSTRAINT emoji_catalog_emoji_character_key UNIQUE (emoji_character);


--
-- Name: emoji_catalog emoji_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.emoji_catalog
    ADD CONSTRAINT emoji_catalog_pkey PRIMARY KEY (id);


--
-- Name: emoji_global_discoveries emoji_global_discoveries_emoji_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.emoji_global_discoveries
    ADD CONSTRAINT emoji_global_discoveries_emoji_id_key UNIQUE (emoji_id);


--
-- Name: emoji_global_discoveries emoji_global_discoveries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.emoji_global_discoveries
    ADD CONSTRAINT emoji_global_discoveries_pkey PRIMARY KEY (id);


--
-- Name: hint_usage hint_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_pkey PRIMARY KEY (id);


--
-- Name: hint_usage hint_usage_player_id_phrase_id_hint_level_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_player_id_phrase_id_hint_level_key UNIQUE (player_id, phrase_id, hint_level);


--
-- Name: leaderboards leaderboards_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_pkey PRIMARY KEY (id);


--
-- Name: leaderboards leaderboards_score_period_period_start_player_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_score_period_period_start_player_id_key UNIQUE (score_period, period_start, player_id);


--
-- Name: offline_phrases offline_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offline_phrases
    ADD CONSTRAINT offline_phrases_pkey PRIMARY KEY (id);


--
-- Name: phrases phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phrases
    ADD CONSTRAINT phrases_pkey PRIMARY KEY (id);


--
-- Name: player_emoji_collections player_emoji_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_emoji_collections
    ADD CONSTRAINT player_emoji_collections_pkey PRIMARY KEY (id);


--
-- Name: player_emoji_collections player_emoji_collections_player_id_emoji_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_emoji_collections
    ADD CONSTRAINT player_emoji_collections_player_id_emoji_id_key UNIQUE (player_id, emoji_id);


--
-- Name: player_phrases player_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_phrases
    ADD CONSTRAINT player_phrases_pkey PRIMARY KEY (id);


--
-- Name: player_scores player_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_scores
    ADD CONSTRAINT player_scores_pkey PRIMARY KEY (id);


--
-- Name: player_scores player_scores_player_id_score_period_period_start_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_scores
    ADD CONSTRAINT player_scores_player_id_score_period_period_start_key UNIQUE (player_id, score_period, period_start);


--
-- Name: players players_name_device_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_name_device_key UNIQUE (name, device_id);


--
-- Name: players players_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_pkey PRIMARY KEY (id);


--
-- Name: skipped_phrases skipped_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_pkey PRIMARY KEY (id);


--
-- Name: skipped_phrases skipped_phrases_player_id_phrase_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_player_id_phrase_id_key UNIQUE (player_id, phrase_id);


--
-- Name: players unique_player_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT unique_player_name UNIQUE (name);


--
-- Name: idx_completed_phrases_player; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_completed_phrases_player ON public.completed_phrases USING btree (player_id, completed_at);


--
-- Name: idx_contribution_links_expires_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contribution_links_expires_at ON public.contribution_links USING btree (expires_at);


--
-- Name: idx_contribution_links_requesting_player; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contribution_links_requesting_player ON public.contribution_links USING btree (requesting_player_id);


--
-- Name: idx_contribution_links_token; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contribution_links_token ON public.contribution_links USING btree (token);


--
-- Name: idx_emoji_catalog_drop_rate; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_emoji_catalog_drop_rate ON public.emoji_catalog USING btree (drop_rate_percentage);


--
-- Name: idx_emoji_catalog_rarity; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_emoji_catalog_rarity ON public.emoji_catalog USING btree (rarity_tier);


--
-- Name: idx_emoji_global_discoveries_emoji; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_emoji_global_discoveries_emoji ON public.emoji_global_discoveries USING btree (emoji_id);


--
-- Name: idx_hint_usage_phrase; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_hint_usage_phrase ON public.hint_usage USING btree (phrase_id, hint_level);


--
-- Name: idx_hint_usage_player_phrase; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_hint_usage_player_phrase ON public.hint_usage USING btree (player_id, phrase_id, hint_level);


--
-- Name: idx_leaderboards_period_rank; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_leaderboards_period_rank ON public.leaderboards USING btree (score_period, period_start, rank_position);


--
-- Name: idx_leaderboards_period_score; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_leaderboards_period_score ON public.leaderboards USING btree (score_period, period_start, total_score DESC);


--
-- Name: idx_offline_phrases_player; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_offline_phrases_player ON public.offline_phrases USING btree (player_id, is_used);


--
-- Name: idx_phrases_difficulty; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phrases_difficulty ON public.phrases USING btree (difficulty_level, is_global, is_approved);


--
-- Name: idx_phrases_global; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_phrases_global ON public.phrases USING btree (is_global, is_approved) WHERE ((is_global = true) AND (is_approved = true));


--
-- Name: idx_player_emoji_collections_emoji; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_emoji_collections_emoji ON public.player_emoji_collections USING btree (emoji_id);


--
-- Name: idx_player_emoji_collections_player; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_emoji_collections_player ON public.player_emoji_collections USING btree (player_id);


--
-- Name: idx_player_phrases_delivered; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_phrases_delivered ON public.player_phrases USING btree (target_player_id, delivered_at) WHERE (is_delivered = true);


--
-- Name: idx_player_phrases_target; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_phrases_target ON public.player_phrases USING btree (target_player_id, priority, is_delivered) WHERE (is_delivered = false);


--
-- Name: idx_player_scores_period_rank; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_scores_period_rank ON public.player_scores USING btree (score_period, rank_position);


--
-- Name: idx_player_scores_period_score; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_scores_period_score ON public.player_scores USING btree (score_period, total_score DESC);


--
-- Name: idx_player_scores_player_period; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_player_scores_player_period ON public.player_scores USING btree (player_id, score_period);


--
-- Name: idx_players_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_players_active ON public.players USING btree (is_active, last_seen) WHERE (is_active = true);


--
-- Name: idx_skipped_phrases_player; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_skipped_phrases_player ON public.skipped_phrases USING btree (player_id, skipped_at);


--
-- Name: completed_phrases completed_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: completed_phrases completed_phrases_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: contribution_links contribution_links_requesting_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contribution_links
    ADD CONSTRAINT contribution_links_requesting_player_id_fkey FOREIGN KEY (requesting_player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: emoji_global_discoveries emoji_global_discoveries_emoji_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.emoji_global_discoveries
    ADD CONSTRAINT emoji_global_discoveries_emoji_id_fkey FOREIGN KEY (emoji_id) REFERENCES public.emoji_catalog(id) ON DELETE CASCADE;


--
-- Name: emoji_global_discoveries emoji_global_discoveries_first_discoverer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.emoji_global_discoveries
    ADD CONSTRAINT emoji_global_discoveries_first_discoverer_id_fkey FOREIGN KEY (first_discoverer_id) REFERENCES public.players(id) ON DELETE SET NULL;


--
-- Name: hint_usage hint_usage_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: hint_usage hint_usage_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: leaderboards leaderboards_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: offline_phrases offline_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offline_phrases
    ADD CONSTRAINT offline_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: offline_phrases offline_phrases_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offline_phrases
    ADD CONSTRAINT offline_phrases_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: phrases phrases_created_by_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.phrases
    ADD CONSTRAINT phrases_created_by_player_id_fkey FOREIGN KEY (created_by_player_id) REFERENCES public.players(id) ON DELETE SET NULL;


--
-- Name: player_emoji_collections player_emoji_collections_emoji_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_emoji_collections
    ADD CONSTRAINT player_emoji_collections_emoji_id_fkey FOREIGN KEY (emoji_id) REFERENCES public.emoji_catalog(id) ON DELETE CASCADE;


--
-- Name: player_emoji_collections player_emoji_collections_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_emoji_collections
    ADD CONSTRAINT player_emoji_collections_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: player_phrases player_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_phrases
    ADD CONSTRAINT player_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: player_phrases player_phrases_target_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_phrases
    ADD CONSTRAINT player_phrases_target_player_id_fkey FOREIGN KEY (target_player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: player_scores player_scores_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_scores
    ADD CONSTRAINT player_scores_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: skipped_phrases skipped_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: skipped_phrases skipped_phrases_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

