--
-- PostgreSQL database dump
--

-- Dumped from database version 14.18 (Homebrew)
-- Dumped by pg_dump version 14.18 (Homebrew)

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
-- Name: calculate_phrase_score(integer, uuid, uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
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


ALTER FUNCTION public.calculate_phrase_score(difficulty_score integer, player_uuid uuid, phrase_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: calculate_player_daily_score(uuid, date); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.calculate_player_daily_score(player_uuid uuid, target_date date DEFAULT CURRENT_DATE) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    daily_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO daily_score
    FROM completed_phrases 
    WHERE player_id = player_uuid 
    AND DATE(completed_at) = target_date;
    
    RETURN daily_score;
END;
$$;


ALTER FUNCTION public.calculate_player_daily_score(player_uuid uuid, target_date date) OWNER TO fredriksafsten;

--
-- Name: calculate_player_total_score(uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
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


ALTER FUNCTION public.calculate_player_total_score(player_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: calculate_player_weekly_score(uuid, date); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.calculate_player_weekly_score(player_uuid uuid, week_start date DEFAULT date_trunc('week'::text, (CURRENT_DATE)::timestamp with time zone)) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    weekly_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO weekly_score
    FROM completed_phrases 
    WHERE player_id = player_uuid 
    AND DATE(completed_at) >= week_start 
    AND DATE(completed_at) < week_start + INTERVAL '7 days';
    
    RETURN weekly_score;
END;
$$;


ALTER FUNCTION public.calculate_player_weekly_score(player_uuid uuid, week_start date) OWNER TO fredriksafsten;

--
-- Name: complete_phrase_for_player(uuid, uuid, integer, integer); Type: FUNCTION; Schema: public; Owner: fredriksafsten
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


ALTER FUNCTION public.complete_phrase_for_player(player_uuid uuid, phrase_uuid uuid, completion_score integer, completion_time integer) OWNER TO fredriksafsten;

--
-- Name: complete_phrase_for_player_with_hints(uuid, uuid, integer); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.complete_phrase_for_player_with_hints(player_uuid uuid, phrase_uuid uuid, completion_time integer DEFAULT 0) RETURNS TABLE(success boolean, final_score integer, hints_used integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
    difficulty_score INTEGER;
    calculated_score INTEGER;
    hints_count INTEGER;
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
    
    -- Calculate score based on hints used
    SELECT calculate_phrase_score(difficulty_score, player_uuid, phrase_uuid) INTO calculated_score;
    
    -- Count hints used
    SELECT COUNT(*) INTO hints_count FROM hint_usage WHERE player_id = player_uuid AND phrase_id = phrase_uuid;
    
    -- Mark phrase as completed
    INSERT INTO completed_phrases (player_id, phrase_id, score, completion_time_ms)
    VALUES (player_uuid, phrase_uuid, calculated_score, completion_time)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    -- Update phrase usage count
    UPDATE phrases SET usage_count = usage_count + 1 WHERE id = phrase_uuid;
    
    -- Update player completion count
    UPDATE players SET phrases_completed = phrases_completed + 1 WHERE id = player_uuid;
    
    -- Mark targeted phrase as delivered if applicable
    UPDATE player_phrases 
    SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP 
    WHERE phrase_id = phrase_uuid AND target_player_id = player_uuid;
    
    RETURN QUERY SELECT TRUE, calculated_score, hints_count;
END;
$$;


ALTER FUNCTION public.complete_phrase_for_player_with_hints(player_uuid uuid, phrase_uuid uuid, completion_time integer) OWNER TO fredriksafsten;

--
-- Name: get_hint_status_for_player(uuid, uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.get_hint_status_for_player(player_uuid uuid, phrase_uuid uuid) RETURNS TABLE(hint_level integer, used_at timestamp without time zone, next_hint_level integer, hints_remaining integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        hu.hint_level,
        hu.used_at,
        CASE 
            WHEN MAX(hu.hint_level) < 3 THEN MAX(hu.hint_level) + 1
            ELSE NULL
        END as next_hint_level,
        CASE 
            WHEN MAX(hu.hint_level) IS NULL THEN 3
            ELSE 3 - MAX(hu.hint_level)
        END as hints_remaining
    FROM hint_usage hu
    WHERE hu.player_id = player_uuid AND hu.phrase_id = phrase_uuid
    GROUP BY hu.hint_level, hu.used_at
    ORDER BY hu.hint_level;
END;
$$;


ALTER FUNCTION public.get_hint_status_for_player(player_uuid uuid, phrase_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: get_next_phrase_for_player(uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.get_next_phrase_for_player(player_uuid uuid) RETURNS TABLE(phrase_id uuid, content character varying, hint character varying, difficulty_level integer, phrase_type text, language character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- First, try to get targeted phrases (no priority, just chronological)
    RETURN QUERY
    SELECT 
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'targeted'::TEXT,
        p.language
    FROM phrases p
    INNER JOIN player_phrases pp ON p.id = pp.phrase_id
    WHERE pp.target_player_id = player_uuid
        AND pp.is_delivered = false
        AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = player_uuid)
        AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = player_uuid)
    ORDER BY pp.assigned_at ASC
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
        p.language
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


ALTER FUNCTION public.get_next_phrase_for_player(player_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: get_player_score_summary(uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.get_player_score_summary(player_uuid uuid) RETURNS TABLE(daily_score integer, daily_rank integer, weekly_score integer, weekly_rank integer, total_score integer, total_rank integer, total_phrases integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(daily.total_score, 0) as daily_score,
        COALESCE(daily.rank_position, 0) as daily_rank,
        COALESCE(weekly.total_score, 0) as weekly_score,
        COALESCE(weekly.rank_position, 0) as weekly_rank,
        COALESCE(total.total_score, 0) as total_score,
        COALESCE(total.rank_position, 0) as total_rank,
        COALESCE(total.phrases_completed, 0) as total_phrases
    FROM (SELECT 1) as dummy
    LEFT JOIN player_scores daily ON daily.player_id = player_uuid 
        AND daily.score_period = 'daily' 
        AND daily.period_start = CURRENT_DATE
    LEFT JOIN player_scores weekly ON weekly.player_id = player_uuid 
        AND weekly.score_period = 'weekly' 
        AND weekly.period_start = DATE_TRUNC('week', CURRENT_DATE)
    LEFT JOIN player_scores total ON total.player_id = player_uuid 
        AND total.score_period = 'total' 
        AND total.period_start = '1970-01-01';
END;
$$;


ALTER FUNCTION public.get_player_score_summary(player_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: skip_phrase_for_player(uuid, uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
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


ALTER FUNCTION public.skip_phrase_for_player(player_uuid uuid, phrase_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: update_leaderboard_rankings(character varying, date); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.update_leaderboard_rankings(score_period_param character varying, period_start_param date DEFAULT NULL::date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    target_period_start DATE;
    records_updated INTEGER := 0;
BEGIN
    -- Set default period start based on period type
    IF period_start_param IS NULL THEN
        CASE score_period_param
            WHEN 'daily' THEN target_period_start := CURRENT_DATE;
            WHEN 'weekly' THEN target_period_start := DATE_TRUNC('week', CURRENT_DATE);
            WHEN 'total' THEN target_period_start := '1970-01-01';
            ELSE RAISE EXCEPTION 'Invalid score period: %', score_period_param;
        END CASE;
    ELSE
        target_period_start := period_start_param;
    END IF;
    
    -- Update rankings in player_scores table
    WITH ranked_players AS (
        SELECT 
            player_id,
            ROW_NUMBER() OVER (ORDER BY total_score DESC, phrases_completed DESC, last_updated ASC) as new_rank
        FROM player_scores 
        WHERE score_period = score_period_param 
        AND period_start = target_period_start
        AND total_score > 0
    )
    UPDATE player_scores 
    SET rank_position = ranked_players.new_rank
    FROM ranked_players 
    WHERE player_scores.player_id = ranked_players.player_id
    AND player_scores.score_period = score_period_param
    AND player_scores.period_start = target_period_start;
    
    GET DIAGNOSTICS records_updated = ROW_COUNT;
    
    -- Delete and recreate leaderboard snapshot
    DELETE FROM leaderboards 
    WHERE score_period = score_period_param 
    AND period_start = target_period_start;
    
    -- Insert new leaderboard snapshot
    INSERT INTO leaderboards (score_period, period_start, player_id, player_name, total_score, phrases_completed, rank_position)
    SELECT 
        ps.score_period,
        ps.period_start,
        ps.player_id,
        p.name,
        ps.total_score,
        ps.phrases_completed,
        ps.rank_position
    FROM player_scores ps
    JOIN players p ON ps.player_id = p.id
    WHERE ps.score_period = score_period_param 
    AND ps.period_start = target_period_start
    AND ps.total_score > 0
    ORDER BY ps.rank_position;
    
    RETURN records_updated;
END;
$$;


ALTER FUNCTION public.update_leaderboard_rankings(score_period_param character varying, period_start_param date) OWNER TO fredriksafsten;

--
-- Name: update_player_score_aggregations(uuid); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.update_player_score_aggregations(player_uuid uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    current_date DATE := CURRENT_DATE;
    week_start DATE := DATE_TRUNC('week', CURRENT_DATE);
    daily_score INTEGER;
    weekly_score INTEGER;
    total_score INTEGER;
    daily_count INTEGER;
    weekly_count INTEGER;
    total_count INTEGER;
BEGIN
    -- Calculate scores
    daily_score := calculate_player_daily_score(player_uuid, current_date);
    weekly_score := calculate_player_weekly_score(player_uuid, week_start);
    total_score := calculate_player_total_score(player_uuid);
    
    -- Calculate phrase counts
    SELECT COUNT(*) INTO daily_count
    FROM completed_phrases 
    WHERE player_id = player_uuid AND DATE(completed_at) = current_date;
    
    SELECT COUNT(*) INTO weekly_count
    FROM completed_phrases 
    WHERE player_id = player_uuid 
    AND DATE(completed_at) >= week_start 
    AND DATE(completed_at) < week_start + INTERVAL '7 days';
    
    SELECT COUNT(*) INTO total_count
    FROM completed_phrases 
    WHERE player_id = player_uuid;
    
    -- Update or insert daily score
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed, avg_score, last_updated)
    VALUES (player_uuid, 'daily', current_date, daily_score, daily_count, 
            CASE WHEN daily_count > 0 THEN daily_score::DECIMAL / daily_count ELSE 0 END, 
            CURRENT_TIMESTAMP)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = EXCLUDED.avg_score,
        last_updated = CURRENT_TIMESTAMP;
    
    -- Update or insert weekly score
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed, avg_score, last_updated)
    VALUES (player_uuid, 'weekly', week_start, weekly_score, weekly_count,
            CASE WHEN weekly_count > 0 THEN weekly_score::DECIMAL / weekly_count ELSE 0 END,
            CURRENT_TIMESTAMP)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = EXCLUDED.avg_score,
        last_updated = CURRENT_TIMESTAMP;
    
    -- Update or insert total score
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed, avg_score, last_updated)
    VALUES (player_uuid, 'total', '1970-01-01', total_score, total_count,
            CASE WHEN total_count > 0 THEN total_score::DECIMAL / total_count ELSE 0 END,
            CURRENT_TIMESTAMP)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = EXCLUDED.avg_score,
        last_updated = CURRENT_TIMESTAMP;
END;
$$;


ALTER FUNCTION public.update_player_score_aggregations(player_uuid uuid) OWNER TO fredriksafsten;

--
-- Name: use_hint_for_player(uuid, uuid, integer); Type: FUNCTION; Schema: public; Owner: fredriksafsten
--

CREATE FUNCTION public.use_hint_for_player(player_uuid uuid, phrase_uuid uuid, hint_level_int integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
    previous_hint_exists BOOLEAN;
BEGIN
    -- Validate inputs
    IF hint_level_int < 1 OR hint_level_int > 3 THEN
        RETURN FALSE;
    END IF;
    
    -- Check if phrase and player exist
    SELECT EXISTS(SELECT 1 FROM phrases WHERE id = phrase_uuid) INTO phrase_exists;
    SELECT EXISTS(SELECT 1 FROM players WHERE id = player_uuid) INTO player_exists;
    
    IF NOT phrase_exists OR NOT player_exists THEN
        RETURN FALSE;
    END IF;
    
    -- Check if previous hint level was used (except for hint level 1)
    IF hint_level_int > 1 THEN
        SELECT EXISTS(
            SELECT 1 FROM hint_usage 
            WHERE player_id = player_uuid 
                AND phrase_id = phrase_uuid 
                AND hint_level = hint_level_int - 1
        ) INTO previous_hint_exists;
        
        IF NOT previous_hint_exists THEN
            RETURN FALSE; -- Must use hints in order
        END IF;
    END IF;
    
    -- Record hint usage (ignore if already exists)
    INSERT INTO hint_usage (player_id, phrase_id, hint_level)
    VALUES (player_uuid, phrase_uuid, hint_level_int)
    ON CONFLICT (player_id, phrase_id, hint_level) DO NOTHING;
    
    RETURN TRUE;
END;
$$;


ALTER FUNCTION public.use_hint_for_player(player_uuid uuid, phrase_uuid uuid, hint_level_int integer) OWNER TO fredriksafsten;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: completed_phrases; Type: TABLE; Schema: public; Owner: fredriksafsten
--

CREATE TABLE public.completed_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    completed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    score integer DEFAULT 0,
    completion_time_ms integer DEFAULT 0
);


ALTER TABLE public.completed_phrases OWNER TO fredriksafsten;

--
-- Name: phrases; Type: TABLE; Schema: public; Owner: fredriksafsten
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
    phrase_type character varying(20) DEFAULT 'custom'::character varying,
    language character varying(5) DEFAULT 'en'::character varying NOT NULL,
    CONSTRAINT check_language CHECK (((language)::text = ANY ((ARRAY['en'::character varying, 'sv'::character varying])::text[]))),
    CONSTRAINT phrases_difficulty_level_check CHECK (((difficulty_level >= 1) AND (difficulty_level <= 100)))
);


ALTER TABLE public.phrases OWNER TO fredriksafsten;

--
-- Name: COLUMN phrases.difficulty_level; Type: COMMENT; Schema: public; Owner: fredriksafsten
--

COMMENT ON COLUMN public.phrases.difficulty_level IS 'Statistical difficulty score (1-100) calculated using letter rarity and structural complexity analysis';


--
-- Name: player_phrases; Type: TABLE; Schema: public; Owner: fredriksafsten
--

CREATE TABLE public.player_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phrase_id uuid,
    target_player_id uuid,
    assigned_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_delivered boolean DEFAULT false,
    delivered_at timestamp without time zone
);


ALTER TABLE public.player_phrases OWNER TO fredriksafsten;

--
-- Name: skipped_phrases; Type: TABLE; Schema: public; Owner: fredriksafsten
--

CREATE TABLE public.skipped_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    skipped_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.skipped_phrases OWNER TO fredriksafsten;

--
-- Name: available_phrases_for_player; Type: VIEW; Schema: public; Owner: fredriksafsten
--

CREATE VIEW public.available_phrases_for_player AS
 SELECT p.id,
    p.content,
    p.hint,
    p.difficulty_level,
    p.is_global,
    p.created_by_player_id,
    p.language,
        CASE
            WHEN (pp.target_player_id IS NOT NULL) THEN 'targeted'::text
            WHEN p.is_global THEN 'global'::text
            ELSE 'other'::text
        END AS phrase_type,
    pp.assigned_at
   FROM (public.phrases p
     LEFT JOIN public.player_phrases pp ON ((p.id = pp.phrase_id)))
  WHERE ((p.is_approved = true) AND (NOT (p.id IN ( SELECT completed_phrases.phrase_id
           FROM public.completed_phrases
          WHERE (completed_phrases.player_id = COALESCE(pp.target_player_id, '00000000-0000-0000-0000-000000000000'::uuid))))) AND (NOT (p.id IN ( SELECT skipped_phrases.phrase_id
           FROM public.skipped_phrases
          WHERE (skipped_phrases.player_id = COALESCE(pp.target_player_id, '00000000-0000-0000-0000-000000000000'::uuid))))));


ALTER TABLE public.available_phrases_for_player OWNER TO fredriksafsten;

--
-- Name: hint_usage; Type: TABLE; Schema: public; Owner: fredriksafsten
--

CREATE TABLE public.hint_usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    hint_level integer NOT NULL,
    used_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT hint_usage_hint_level_check CHECK (((hint_level >= 1) AND (hint_level <= 3)))
);


ALTER TABLE public.hint_usage OWNER TO fredriksafsten;

--
-- Name: leaderboards; Type: TABLE; Schema: public; Owner: fredriksafsten
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


ALTER TABLE public.leaderboards OWNER TO fredriksafsten;

--
-- Name: offline_phrases; Type: TABLE; Schema: public; Owner: fredriksafsten
--

CREATE TABLE public.offline_phrases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid,
    phrase_id uuid,
    downloaded_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_used boolean DEFAULT false,
    used_at timestamp without time zone
);


ALTER TABLE public.offline_phrases OWNER TO fredriksafsten;

--
-- Name: player_scores; Type: TABLE; Schema: public; Owner: fredriksafsten
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


ALTER TABLE public.player_scores OWNER TO fredriksafsten;

--
-- Name: players; Type: TABLE; Schema: public; Owner: fredriksafsten
--

CREATE TABLE public.players (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL,
    is_active boolean DEFAULT true,
    last_seen timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    phrases_completed integer DEFAULT 0,
    socket_id character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.players OWNER TO fredriksafsten;

--
-- Data for Name: completed_phrases; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.completed_phrases (id, player_id, phrase_id, completed_at, score, completion_time_ms) FROM stdin;
51feb682-3668-49bb-8bc8-f1aeefe0cef5	b82e1b95-7ee3-4475-b1d8-46edf4fd60cf	b9200606-efb5-4dc4-9a90-8acc07e26207	2025-07-07 18:28:08.367107	100	5000
04927d16-956c-4a4d-974f-35f117b01519	b82e1b95-7ee3-4475-b1d8-46edf4fd60cf	579833ef-7c25-4869-8f3d-a4420518e630	2025-07-07 18:58:38.107201	100	5000
91e94489-9144-44a0-b9ed-a58507a62492	b10c80be-b76f-4182-b18b-26495c71700c	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:53:24.902104	0	0
3c7a931e-a662-4537-8cc1-b9aecc1e6af8	b10c80be-b76f-4182-b18b-26495c71700c	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:53:24.917205	0	0
01f11396-44da-4d3e-8a4b-dc762efcfe8e	b10c80be-b76f-4182-b18b-26495c71700c	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:53:24.921549	0	0
15205101-d07a-416d-91cd-147a30091501	b10c80be-b76f-4182-b18b-26495c71700c	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:53:24.924273	0	0
3db3239c-1358-48e0-9e11-1b8f093f8e6e	b10c80be-b76f-4182-b18b-26495c71700c	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:53:24.927203	0	0
1c92b89e-7b81-4432-87bc-5f2148a5666e	b10c80be-b76f-4182-b18b-26495c71700c	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:53:24.930716	0	0
1f329a04-aab5-4cfe-b9b3-f26364d35b8a	b10c80be-b76f-4182-b18b-26495c71700c	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:53:24.933052	0	0
d85107ab-958c-4e4a-9b86-df15f2c197ee	b10c80be-b76f-4182-b18b-26495c71700c	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:53:24.935059	0	0
5602a134-f25d-4006-ba88-08886cf05298	39981124-6a61-421f-912f-6dbee57849eb	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:55:31.51257	0	0
838c7fb6-3acc-43ab-bb84-8955f1d5f77f	39981124-6a61-421f-912f-6dbee57849eb	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:55:31.594307	0	0
f639a68b-451c-4154-be4c-9cdb08e2cea0	39981124-6a61-421f-912f-6dbee57849eb	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:55:31.653473	0	0
1a08dd84-2fdc-4cc0-a1ad-5a2cbf3a5025	39981124-6a61-421f-912f-6dbee57849eb	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:55:31.70817	0	0
3d9bf2c2-cbb1-4236-80cb-b7c3de66990a	39981124-6a61-421f-912f-6dbee57849eb	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:55:46.823614	0	0
6cf6a599-9e8b-4667-bb5d-d304868b9260	39981124-6a61-421f-912f-6dbee57849eb	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:55:46.907029	0	0
bd129232-bb66-424b-bd8b-87f587a313ba	39981124-6a61-421f-912f-6dbee57849eb	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:55:46.927186	0	0
35668c4e-2824-4d55-a211-604f5b34e7d6	39981124-6a61-421f-912f-6dbee57849eb	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:55:46.956411	0	0
bf4688b4-0075-4031-a922-20c6742fcb68	3d01c53d-593b-4053-8004-63f33daece6c	9209c2c3-bd7f-4480-aca3-fb24fc8ad4a1	2025-07-08 10:53:33.854916	23	5000
d73ac73f-9d85-42f4-84b1-d2f2dcbe1352	3d01c53d-593b-4053-8004-63f33daece6c	890fef27-b06e-4017-bab6-5e12272e85bb	2025-07-08 10:56:08.210099	23	5000
3ea6f484-eaf4-46b4-bfcb-b8faf2b762c0	6611542b-d5be-441d-ba28-287b5b79903e	9373b647-6778-42ab-a0df-3c51d4daf120	2025-07-08 14:03:47.79457	38	0
d4e71adf-ece0-41bc-820e-7f9ed1351339	8f43e562-9d44-4b54-8025-20824d3975af	45809dbd-6adb-43e0-b445-897a908ce827	2025-07-08 14:18:54.777602	42	0
2d2a995d-1f4b-44c3-8f93-757d98f5a8b0	6611542b-d5be-441d-ba28-287b5b79903e	08740e0e-06c0-41dd-a61b-afd73b2471d7	2025-07-08 14:31:08.650995	25	0
2abddb2a-96cd-4c2f-975c-e104c2c3f33a	6611542b-d5be-441d-ba28-287b5b79903e	224517ff-9833-4684-bd20-31bcb5ac160a	2025-07-08 14:58:06.27372	30	0
83d5d012-9e8d-4195-844c-c4460658c853	3d01c53d-593b-4053-8004-63f33daece6c	2f4afe5f-a586-4075-a99b-d7c9b7b87683	2025-07-08 15:05:24.860521	23	5000
e0d0d3e8-5147-4f34-b779-ec47f3873723	3d01c53d-593b-4053-8004-63f33daece6c	1037447e-28dd-4dc3-9d96-3a5572f4cecb	2025-07-08 15:09:53.165326	23	5000
861b7cd5-52a9-4a5f-87b2-e2b7733b531e	3d01c53d-593b-4053-8004-63f33daece6c	1f38cc22-3ca6-46f2-b427-75ac2c846694	2025-07-08 15:12:28.764937	23	5000
e28c6e7b-bfe7-457e-a09f-3a05995cce0b	3d01c53d-593b-4053-8004-63f33daece6c	78b79d72-90ab-4dc9-be8c-a074e8018868	2025-07-08 15:22:13.374017	23	5000
bbb66a6c-4649-4101-b870-37683ced7234	3d01c53d-593b-4053-8004-63f33daece6c	b07a5fb6-9c1d-4544-bb05-303219d34dcc	2025-07-08 15:27:45.906817	23	5000
220d4645-ee3f-4146-90bd-b9fae7336182	3d01c53d-593b-4053-8004-63f33daece6c	9dda1183-9207-48a5-9fad-36441667b57c	2025-07-08 15:27:46.894382	23	5000
f56a7696-e6d9-4e97-a73d-926bbea50848	842d0a5c-a025-4485-90c4-540ff3cfaaae	c7458654-b9b4-4b13-a17d-ddc83d6ad0d8	2025-07-08 15:48:40.175545	34	8000
235c5f75-3635-4db6-b013-7263fc54564a	3d01c53d-593b-4053-8004-63f33daece6c	51d4492c-465b-4b9d-ad93-3b543fcecf7a	2025-07-08 15:50:56.654674	23	5000
c962c86e-7f82-43c5-b780-c8411be17152	3d01c53d-593b-4053-8004-63f33daece6c	53c0c34a-7eb2-4486-a74d-0fffba5cd70d	2025-07-08 15:50:57.706376	23	5000
521b3023-8821-4568-9794-ec50814d9b1f	842d0a5c-a025-4485-90c4-540ff3cfaaae	7ed53066-a8b0-40ee-a6bb-976989f2bf32	2025-07-08 15:50:59.562646	34	8000
4f524b84-c6f1-4532-9a3f-902f74f30292	842d0a5c-a025-4485-90c4-540ff3cfaaae	019807f3-a2f3-425d-8852-dc11e1d4146f	2025-07-08 16:01:40.494451	34	8000
4af10f3b-c046-4aec-ae93-f56c8897eb1c	3d01c53d-593b-4053-8004-63f33daece6c	2fcfa332-4519-4a9d-a8d3-cfbaf0dc6830	2025-07-08 16:02:00.869676	23	5000
74e2160b-7dfe-4c98-8d52-85020de50a8d	842d0a5c-a025-4485-90c4-540ff3cfaaae	7de1e91d-9448-4dbd-ad46-27abb8aa2089	2025-07-08 16:02:02.734376	34	8000
9dcbc38a-3b10-4c11-964e-8a59637ee477	8f43e562-9d44-4b54-8025-20824d3975af	ce78667b-f0af-49a7-8d10-78da1bf66805	2025-07-08 19:04:01.360941	53	0
132da290-9e15-493c-87b4-fc6ea52fec0c	842d0a5c-a025-4485-90c4-540ff3cfaaae	51fd5f22-a2d7-43a0-a849-5edf13ebf2bd	2025-07-09 15:47:37.437962	34	8000
e3cb5b58-e9e6-482a-9886-b904a0620bc2	989d493b-42ec-489f-b25f-c4700e8ee735	b87aaedb-e8f5-4774-92c9-5ae5b852e2b0	2025-07-09 15:54:15.818798	100	0
\.


--
-- Data for Name: hint_usage; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.hint_usage (id, player_id, phrase_id, hint_level, used_at) FROM stdin;
142ef67a-b0cc-474c-a427-e63afb18d0bc	3d01c53d-593b-4053-8004-63f33daece6c	9209c2c3-bd7f-4480-aca3-fb24fc8ad4a1	1	2025-07-08 10:53:33.778678
c0cacfb4-fe6b-4366-9459-37fb4baff584	3d01c53d-593b-4053-8004-63f33daece6c	9209c2c3-bd7f-4480-aca3-fb24fc8ad4a1	2	2025-07-08 10:53:33.805309
73d2d007-25b0-4e05-a5cb-7deba8fa0f34	3d01c53d-593b-4053-8004-63f33daece6c	9209c2c3-bd7f-4480-aca3-fb24fc8ad4a1	3	2025-07-08 10:53:33.831568
23b0dc59-1374-479a-a22d-a681c5a61f41	3d01c53d-593b-4053-8004-63f33daece6c	890fef27-b06e-4017-bab6-5e12272e85bb	1	2025-07-08 10:56:08.162698
84236ff6-925a-4282-9f2e-07cba1551d86	3d01c53d-593b-4053-8004-63f33daece6c	890fef27-b06e-4017-bab6-5e12272e85bb	2	2025-07-08 10:56:08.183408
89bb5618-352f-4921-b8e8-0373cd387229	3d01c53d-593b-4053-8004-63f33daece6c	890fef27-b06e-4017-bab6-5e12272e85bb	3	2025-07-08 10:56:08.189624
519e0256-88b3-470b-bb40-bf478b0b190e	989d493b-42ec-489f-b25f-c4700e8ee735	15a1e19b-63da-431a-975c-81b4e255dc1c	1	2025-07-08 13:57:46.461983
83854e83-6bd1-4058-932e-84541d7a0ffc	989d493b-42ec-489f-b25f-c4700e8ee735	15a1e19b-63da-431a-975c-81b4e255dc1c	2	2025-07-08 13:57:47.667742
eac5dfc8-c429-43e5-a902-df1eaa5c5776	989d493b-42ec-489f-b25f-c4700e8ee735	15a1e19b-63da-431a-975c-81b4e255dc1c	3	2025-07-08 13:57:48.426619
7a53f0dc-bc92-4d87-a298-8cad10aa908d	6611542b-d5be-441d-ba28-287b5b79903e	ce537516-568f-4f11-98fb-e49bcafbb173	1	2025-07-08 13:58:16.948182
ad22ffd0-a566-4213-b2f1-abc3dccf706c	6611542b-d5be-441d-ba28-287b5b79903e	ce537516-568f-4f11-98fb-e49bcafbb173	2	2025-07-08 13:58:17.795832
19806321-bb01-4703-8181-806b41a83e87	6611542b-d5be-441d-ba28-287b5b79903e	ce537516-568f-4f11-98fb-e49bcafbb173	3	2025-07-08 13:58:18.468446
70b0aefa-b716-411a-b74b-f5e4b61d1163	989d493b-42ec-489f-b25f-c4700e8ee735	5900f572-f4ec-4094-8b91-194d1137ce51	1	2025-07-08 14:04:23.711346
b2e992b9-5579-4bed-81e2-2fdb260e26d7	989d493b-42ec-489f-b25f-c4700e8ee735	5900f572-f4ec-4094-8b91-194d1137ce51	2	2025-07-08 14:04:24.491157
55749caa-18b8-4983-aa92-a732107895f5	989d493b-42ec-489f-b25f-c4700e8ee735	5900f572-f4ec-4094-8b91-194d1137ce51	3	2025-07-08 14:04:25.532088
48d5ecea-293f-4288-8193-583d91ebbc6a	6611542b-d5be-441d-ba28-287b5b79903e	9734aee3-d8f4-489b-9750-1be4ad374afe	1	2025-07-08 14:04:53.313488
c95811f7-4943-42de-a83f-1532c18958c8	6611542b-d5be-441d-ba28-287b5b79903e	9734aee3-d8f4-489b-9750-1be4ad374afe	2	2025-07-08 14:04:54.685455
e2fef2eb-4048-451a-bce6-550d467aff77	6611542b-d5be-441d-ba28-287b5b79903e	9734aee3-d8f4-489b-9750-1be4ad374afe	3	2025-07-08 14:04:55.872046
f9424f0c-e666-4d7b-9c7b-a7023fc884ea	8f43e562-9d44-4b54-8025-20824d3975af	9a1d95e0-471a-4c56-b8db-0ad800c29ae3	1	2025-07-08 14:14:59.944237
be78b44e-fc12-493b-9603-a9b302c6b830	8f43e562-9d44-4b54-8025-20824d3975af	9a1d95e0-471a-4c56-b8db-0ad800c29ae3	2	2025-07-08 14:15:01.243065
ee85477e-0768-4790-b1e7-071ab5241b59	8f43e562-9d44-4b54-8025-20824d3975af	9a1d95e0-471a-4c56-b8db-0ad800c29ae3	3	2025-07-08 14:15:02.998354
f3d37bc2-bee8-4351-9ba3-a2d2a0816491	8f43e562-9d44-4b54-8025-20824d3975af	45809dbd-6adb-43e0-b445-897a908ce827	1	2025-07-08 14:18:31.093712
28625233-bee3-4d95-979d-fa3f3cc38764	8f43e562-9d44-4b54-8025-20824d3975af	45809dbd-6adb-43e0-b445-897a908ce827	2	2025-07-08 14:18:32.863889
2d4d74db-43bc-4faf-b434-6bb18e13070c	8f43e562-9d44-4b54-8025-20824d3975af	45809dbd-6adb-43e0-b445-897a908ce827	3	2025-07-08 14:18:36.995346
74f346ba-542d-46ba-a9db-313e2719e657	989d493b-42ec-489f-b25f-c4700e8ee735	bea8e03d-196f-4171-9b6b-5491f4c3717f	1	2025-07-08 14:26:15.664117
e3b080b5-2ebf-45c1-9690-bbcfbac9fb3f	989d493b-42ec-489f-b25f-c4700e8ee735	bea8e03d-196f-4171-9b6b-5491f4c3717f	2	2025-07-08 14:26:16.717706
4c2138ec-36c1-40d5-b9d4-b059e7d97867	989d493b-42ec-489f-b25f-c4700e8ee735	bea8e03d-196f-4171-9b6b-5491f4c3717f	3	2025-07-08 14:26:21.639985
30ef81a7-476c-4fe6-9ddf-50766486b318	6611542b-d5be-441d-ba28-287b5b79903e	08740e0e-06c0-41dd-a61b-afd73b2471d7	1	2025-07-08 14:30:40.580516
71c09463-0d8f-4577-9400-3030ce10411b	6611542b-d5be-441d-ba28-287b5b79903e	08740e0e-06c0-41dd-a61b-afd73b2471d7	2	2025-07-08 14:30:41.318039
5fd7eca5-805d-4a8d-80ca-c4062539c89b	6611542b-d5be-441d-ba28-287b5b79903e	08740e0e-06c0-41dd-a61b-afd73b2471d7	3	2025-07-08 14:30:42.259183
8ceafa89-ca7b-4256-b3df-f0b7d2a545e9	6611542b-d5be-441d-ba28-287b5b79903e	224517ff-9833-4684-bd20-31bcb5ac160a	1	2025-07-08 14:57:55.785383
6e9c472a-fffb-4a3b-9957-92174048bbe2	6611542b-d5be-441d-ba28-287b5b79903e	224517ff-9833-4684-bd20-31bcb5ac160a	2	2025-07-08 14:57:56.571273
2b5fd60d-7d16-4238-aaa8-caf03e317aac	6611542b-d5be-441d-ba28-287b5b79903e	224517ff-9833-4684-bd20-31bcb5ac160a	3	2025-07-08 14:57:58.692255
3a46201d-0e3c-4fc1-8aa7-7e261e726c56	6611542b-d5be-441d-ba28-287b5b79903e	a2b44fb9-0fc2-4fc9-a165-f1c7a673b272	1	2025-07-08 14:58:56.257366
9703931b-9df7-4929-963a-8962acca38e8	6611542b-d5be-441d-ba28-287b5b79903e	a2b44fb9-0fc2-4fc9-a165-f1c7a673b272	2	2025-07-08 14:58:57.471873
96537a84-5110-4411-a8a9-f5caffa9f486	6611542b-d5be-441d-ba28-287b5b79903e	a2b44fb9-0fc2-4fc9-a165-f1c7a673b272	3	2025-07-08 14:59:04.990723
2dc61325-7595-440a-93c9-007f3bc5d7dc	3d01c53d-593b-4053-8004-63f33daece6c	2f4afe5f-a586-4075-a99b-d7c9b7b87683	1	2025-07-08 15:05:24.701389
fb414301-f8f4-4b34-968a-9b27a4b5044a	3d01c53d-593b-4053-8004-63f33daece6c	2f4afe5f-a586-4075-a99b-d7c9b7b87683	2	2025-07-08 15:05:24.745901
d4c4dd68-f76d-4b5d-accc-e1e608cd480d	3d01c53d-593b-4053-8004-63f33daece6c	2f4afe5f-a586-4075-a99b-d7c9b7b87683	3	2025-07-08 15:05:24.762832
3e0784bd-dfaf-4755-a8fb-da60d12c56be	0f9c0fc2-cf0b-4207-bb69-47988110b74a	0a442428-89b3-443e-842b-a33b2bbc9d94	1	2025-07-08 15:09:25.070356
dc4f28b6-d513-4eb2-ab82-0c87ea964417	0f9c0fc2-cf0b-4207-bb69-47988110b74a	0a442428-89b3-443e-842b-a33b2bbc9d94	2	2025-07-08 15:09:25.113581
e4373383-a989-4be5-9bee-2344fc903746	0f9c0fc2-cf0b-4207-bb69-47988110b74a	0a442428-89b3-443e-842b-a33b2bbc9d94	3	2025-07-08 15:09:25.133129
067854ea-bd0d-4df0-b421-3b5b556173c1	3d01c53d-593b-4053-8004-63f33daece6c	1037447e-28dd-4dc3-9d96-3a5572f4cecb	1	2025-07-08 15:09:53.109956
fa4ce47b-88b6-4334-90b1-238222a2547d	3d01c53d-593b-4053-8004-63f33daece6c	1037447e-28dd-4dc3-9d96-3a5572f4cecb	2	2025-07-08 15:09:53.116239
4fc80732-cd7a-4042-8264-b345e1d77dce	3d01c53d-593b-4053-8004-63f33daece6c	1037447e-28dd-4dc3-9d96-3a5572f4cecb	3	2025-07-08 15:09:53.133555
895a29a2-4968-47eb-9fa7-6de27e9e62b2	3d01c53d-593b-4053-8004-63f33daece6c	1f38cc22-3ca6-46f2-b427-75ac2c846694	1	2025-07-08 15:12:28.584977
d6beb06b-c2b8-4905-8200-6d7b58f37d9d	3d01c53d-593b-4053-8004-63f33daece6c	1f38cc22-3ca6-46f2-b427-75ac2c846694	2	2025-07-08 15:12:28.664771
ce640d03-a80c-4dc7-8c3b-20b84e25db39	3d01c53d-593b-4053-8004-63f33daece6c	1f38cc22-3ca6-46f2-b427-75ac2c846694	3	2025-07-08 15:12:28.715806
67c372a0-7aff-47e3-9c66-c0c35699e7f1	3d01c53d-593b-4053-8004-63f33daece6c	78b79d72-90ab-4dc9-be8c-a074e8018868	1	2025-07-08 15:22:13.281057
1681b86e-e3e5-4cdb-af64-f9c322d33e79	3d01c53d-593b-4053-8004-63f33daece6c	78b79d72-90ab-4dc9-be8c-a074e8018868	2	2025-07-08 15:22:13.317653
d2b718e5-696f-4d2e-833c-69c899a4ed27	3d01c53d-593b-4053-8004-63f33daece6c	78b79d72-90ab-4dc9-be8c-a074e8018868	3	2025-07-08 15:22:13.337173
ac648a48-2107-4f5d-9ae1-de1f4a02b2f0	3d01c53d-593b-4053-8004-63f33daece6c	b07a5fb6-9c1d-4544-bb05-303219d34dcc	1	2025-07-08 15:27:45.867139
c656a8dc-2722-4247-ac86-4d7be25ee88f	3d01c53d-593b-4053-8004-63f33daece6c	b07a5fb6-9c1d-4544-bb05-303219d34dcc	2	2025-07-08 15:27:45.885773
93531975-2797-4744-94ed-6c439f337898	3d01c53d-593b-4053-8004-63f33daece6c	b07a5fb6-9c1d-4544-bb05-303219d34dcc	3	2025-07-08 15:27:45.888925
7e45c844-2c87-495c-8023-bb11eb586f76	3d01c53d-593b-4053-8004-63f33daece6c	9dda1183-9207-48a5-9fad-36441667b57c	1	2025-07-08 15:27:46.866569
3ed7cdf6-8d18-44aa-b6cf-97f7d3134920	3d01c53d-593b-4053-8004-63f33daece6c	9dda1183-9207-48a5-9fad-36441667b57c	2	2025-07-08 15:27:46.873962
c58c2059-4ca8-473e-a385-4465a3f6d354	3d01c53d-593b-4053-8004-63f33daece6c	9dda1183-9207-48a5-9fad-36441667b57c	3	2025-07-08 15:27:46.881731
41c5690b-a270-4985-90d3-31aa3abf6e5a	aee5986b-3fc2-40d7-a55e-2df9872efdd2	c9dfca9d-fa18-4703-bd19-4dfe041ba400	1	2025-07-08 15:42:39.313706
b3a0de79-3633-470c-99f7-b8e1a35092d0	aee5986b-3fc2-40d7-a55e-2df9872efdd2	7887a3bb-25df-4b6c-b375-8b99db7e5835	1	2025-07-08 15:42:39.359532
104f1a76-5ec3-4a9c-a41f-6ebb028a444b	aee5986b-3fc2-40d7-a55e-2df9872efdd2	07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	1	2025-07-08 15:42:39.365314
20bb0447-04f8-4287-b767-227ad1ba42b3	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	c9dfca9d-fa18-4703-bd19-4dfe041ba400	1	2025-07-08 15:42:39.38395
a577e5a1-03a8-490a-b092-14b8587b9031	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	c9dfca9d-fa18-4703-bd19-4dfe041ba400	2	2025-07-08 15:42:39.38826
fd313473-59aa-4ea8-8261-353a95b1ee2b	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	7887a3bb-25df-4b6c-b375-8b99db7e5835	1	2025-07-08 15:42:39.393186
4179b956-33c5-4ce3-9abd-b69b6c5eaf91	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	7887a3bb-25df-4b6c-b375-8b99db7e5835	2	2025-07-08 15:42:39.396482
5c74e4ee-b39c-4610-abaa-c41de2df721a	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	1	2025-07-08 15:42:39.403549
44f99835-fb52-4b86-b09a-edcda83516ce	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	2	2025-07-08 15:42:39.408172
97e03d87-1a30-442f-9ded-9b4b6f64eb5e	158da148-407d-4b08-8390-650692fccc6a	c9dfca9d-fa18-4703-bd19-4dfe041ba400	1	2025-07-08 15:42:39.414025
5fb5f62a-e086-475c-9d71-0b3891dc0ad4	158da148-407d-4b08-8390-650692fccc6a	c9dfca9d-fa18-4703-bd19-4dfe041ba400	2	2025-07-08 15:42:39.417499
27a453e4-7c8b-4da5-b1f2-b5f9261ec60b	158da148-407d-4b08-8390-650692fccc6a	c9dfca9d-fa18-4703-bd19-4dfe041ba400	3	2025-07-08 15:42:39.41981
bd92a5b5-bd15-42c6-9a95-cdbc351499d8	158da148-407d-4b08-8390-650692fccc6a	7887a3bb-25df-4b6c-b375-8b99db7e5835	1	2025-07-08 15:42:39.422902
915cdb2d-98b5-4449-aeec-47261e4755c7	158da148-407d-4b08-8390-650692fccc6a	7887a3bb-25df-4b6c-b375-8b99db7e5835	2	2025-07-08 15:42:39.425893
e41653db-5b5b-422a-8c17-6d285334d710	158da148-407d-4b08-8390-650692fccc6a	7887a3bb-25df-4b6c-b375-8b99db7e5835	3	2025-07-08 15:42:39.427666
124469cd-084b-45c8-b5dc-3d9dc353a2f2	158da148-407d-4b08-8390-650692fccc6a	07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	1	2025-07-08 15:42:39.444959
d84f0bda-c21c-4c86-b66f-20af374842e8	158da148-407d-4b08-8390-650692fccc6a	07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	2	2025-07-08 15:42:39.44883
31a658b3-9b3b-40ed-871e-222fa2e81ba4	158da148-407d-4b08-8390-650692fccc6a	07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	3	2025-07-08 15:42:39.450403
98eaf94b-ed5d-4339-851a-4de95e33c842	aee5986b-3fc2-40d7-a55e-2df9872efdd2	e1f3a24c-4db6-4314-b822-b59e407e9f75	1	2025-07-08 15:48:38.623376
2a14c7d7-18e5-4415-b525-6651761e2b38	aee5986b-3fc2-40d7-a55e-2df9872efdd2	596025a8-8b2c-41a0-89e5-60ee0ae852b7	1	2025-07-08 15:48:38.659047
76e1a11e-a37c-4757-b83d-c51a133374f6	aee5986b-3fc2-40d7-a55e-2df9872efdd2	836b23a1-5ae4-471b-8d5b-ccd8836042ef	1	2025-07-08 15:48:38.725182
cea90c97-f2f9-4e35-be33-f1f4539e8cad	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	e1f3a24c-4db6-4314-b822-b59e407e9f75	1	2025-07-08 15:48:38.761731
2cdfc0a5-b5de-4037-807c-4f6c33477da5	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	e1f3a24c-4db6-4314-b822-b59e407e9f75	2	2025-07-08 15:48:38.77552
69228992-1f87-459e-a40a-ac03cba44f4d	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	596025a8-8b2c-41a0-89e5-60ee0ae852b7	1	2025-07-08 15:48:38.794793
d3cd7c10-31ea-4830-a1f8-81f9c50b0ca9	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	596025a8-8b2c-41a0-89e5-60ee0ae852b7	2	2025-07-08 15:48:38.798951
bd1d699e-d9e7-443f-9cfb-4d9e9c17431c	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	836b23a1-5ae4-471b-8d5b-ccd8836042ef	1	2025-07-08 15:48:38.806898
7380ad35-2491-466b-b6b3-5824fcf040e6	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	836b23a1-5ae4-471b-8d5b-ccd8836042ef	2	2025-07-08 15:48:38.810959
ab95d3a7-3a5a-4613-bd0b-b2289087237c	158da148-407d-4b08-8390-650692fccc6a	e1f3a24c-4db6-4314-b822-b59e407e9f75	1	2025-07-08 15:48:38.838703
c43ad79b-11d8-4ec8-927c-eaaf6f3ab000	158da148-407d-4b08-8390-650692fccc6a	e1f3a24c-4db6-4314-b822-b59e407e9f75	2	2025-07-08 15:48:38.843207
41fdf90d-dcb8-42bd-8f81-827bb6d83fed	158da148-407d-4b08-8390-650692fccc6a	e1f3a24c-4db6-4314-b822-b59e407e9f75	3	2025-07-08 15:48:38.845128
f2ae74cd-3ddd-4a0b-b741-53156bbe9d92	158da148-407d-4b08-8390-650692fccc6a	596025a8-8b2c-41a0-89e5-60ee0ae852b7	1	2025-07-08 15:48:38.869122
c4cbabc6-c7f0-401b-a159-3dd82b3d9608	158da148-407d-4b08-8390-650692fccc6a	596025a8-8b2c-41a0-89e5-60ee0ae852b7	2	2025-07-08 15:48:38.886465
4f674024-8b62-40a3-9eaa-2a4bafa55f4f	158da148-407d-4b08-8390-650692fccc6a	596025a8-8b2c-41a0-89e5-60ee0ae852b7	3	2025-07-08 15:48:38.891755
73b83377-83b0-42e9-9fbc-ab9e6d7d21d7	158da148-407d-4b08-8390-650692fccc6a	836b23a1-5ae4-471b-8d5b-ccd8836042ef	1	2025-07-08 15:48:38.909425
ac1c677c-7f60-4817-ae61-991b8b4f0dd2	158da148-407d-4b08-8390-650692fccc6a	836b23a1-5ae4-471b-8d5b-ccd8836042ef	2	2025-07-08 15:48:38.914515
9361bb9f-d7a4-47b3-8376-833588e96c1d	158da148-407d-4b08-8390-650692fccc6a	836b23a1-5ae4-471b-8d5b-ccd8836042ef	3	2025-07-08 15:48:38.917082
f58d9518-c6c3-44e6-8253-c0923205b78b	842d0a5c-a025-4485-90c4-540ff3cfaaae	c7458654-b9b4-4b13-a17d-ddc83d6ad0d8	1	2025-07-08 15:48:40.125854
1305238f-181d-43a2-b87e-e341dfa21611	842d0a5c-a025-4485-90c4-540ff3cfaaae	c7458654-b9b4-4b13-a17d-ddc83d6ad0d8	2	2025-07-08 15:48:40.17002
107288fe-f4cc-4067-917a-b3bbb9044a07	3d01c53d-593b-4053-8004-63f33daece6c	51d4492c-465b-4b9d-ad93-3b543fcecf7a	1	2025-07-08 15:50:56.591003
b81c75b4-6cfc-4ead-aefd-15add36a9172	3d01c53d-593b-4053-8004-63f33daece6c	51d4492c-465b-4b9d-ad93-3b543fcecf7a	2	2025-07-08 15:50:56.598484
695974d3-3373-4e4a-8797-888ce75945b4	3d01c53d-593b-4053-8004-63f33daece6c	51d4492c-465b-4b9d-ad93-3b543fcecf7a	3	2025-07-08 15:50:56.640702
8805420c-2420-4263-b071-c6a52bdb833e	3d01c53d-593b-4053-8004-63f33daece6c	53c0c34a-7eb2-4486-a74d-0fffba5cd70d	1	2025-07-08 15:50:57.641791
dd412f88-9a8c-4750-8950-46276c17c18e	3d01c53d-593b-4053-8004-63f33daece6c	53c0c34a-7eb2-4486-a74d-0fffba5cd70d	2	2025-07-08 15:50:57.651129
f3b282d4-cf8d-43c2-9f70-2eea2befe49c	3d01c53d-593b-4053-8004-63f33daece6c	53c0c34a-7eb2-4486-a74d-0fffba5cd70d	3	2025-07-08 15:50:57.673757
be10ff7e-acaf-4a8e-bb91-66cbb1cca0b9	aee5986b-3fc2-40d7-a55e-2df9872efdd2	1fde4dcb-5079-49a8-815c-ac09e6207616	1	2025-07-08 15:50:57.934566
272536ad-fbcf-45f2-8cf6-da8009e13cb5	aee5986b-3fc2-40d7-a55e-2df9872efdd2	0cf77938-9161-4773-abe4-2412d9e9656d	1	2025-07-08 15:50:57.948915
63be73d0-3124-4ab8-8e36-232caed34e77	aee5986b-3fc2-40d7-a55e-2df9872efdd2	c0048f24-e8cc-4724-ad13-3605ff71edc7	1	2025-07-08 15:50:57.95926
3235da3b-1420-4b16-8b2f-5a2a843d1218	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	1fde4dcb-5079-49a8-815c-ac09e6207616	1	2025-07-08 15:50:58.006922
3b2baa2b-f292-4294-b422-76ee43f20e33	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	1fde4dcb-5079-49a8-815c-ac09e6207616	2	2025-07-08 15:50:58.019444
7342cc88-aa43-4c74-a6bd-ea3410023a1d	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	0cf77938-9161-4773-abe4-2412d9e9656d	1	2025-07-08 15:50:58.02636
4a77c68a-5efe-40f1-b923-105034ca38a4	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	0cf77938-9161-4773-abe4-2412d9e9656d	2	2025-07-08 15:50:58.030434
367f742f-5c8d-4f27-870f-e5180427f67e	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	c0048f24-e8cc-4724-ad13-3605ff71edc7	1	2025-07-08 15:50:58.03849
c05919ba-dbe9-423c-8e2f-0c67d613a3c7	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	c0048f24-e8cc-4724-ad13-3605ff71edc7	2	2025-07-08 15:50:58.042547
777b9594-e7b5-4a97-b66c-9163d6634a48	158da148-407d-4b08-8390-650692fccc6a	1fde4dcb-5079-49a8-815c-ac09e6207616	1	2025-07-08 15:50:58.051892
5fa06553-af8a-48c2-bcc3-65824556bb47	158da148-407d-4b08-8390-650692fccc6a	1fde4dcb-5079-49a8-815c-ac09e6207616	2	2025-07-08 15:50:58.055932
761404a0-2fab-4d70-9fdd-e68230a0163b	158da148-407d-4b08-8390-650692fccc6a	1fde4dcb-5079-49a8-815c-ac09e6207616	3	2025-07-08 15:50:58.057488
f39be421-466c-4575-8f57-2782683ef57d	158da148-407d-4b08-8390-650692fccc6a	0cf77938-9161-4773-abe4-2412d9e9656d	1	2025-07-08 15:50:58.104771
a8d38487-7e6c-46e8-ad8c-a6cdedc57143	158da148-407d-4b08-8390-650692fccc6a	0cf77938-9161-4773-abe4-2412d9e9656d	2	2025-07-08 15:50:58.126167
8d0f7232-a2b5-4b1d-9a1c-08c922603e6e	158da148-407d-4b08-8390-650692fccc6a	0cf77938-9161-4773-abe4-2412d9e9656d	3	2025-07-08 15:50:58.128201
1b3a6af6-e207-419a-b4fd-139668fe3593	158da148-407d-4b08-8390-650692fccc6a	c0048f24-e8cc-4724-ad13-3605ff71edc7	1	2025-07-08 15:50:58.172964
415f3fe1-f0bb-4d78-a4ec-800c952c4d83	158da148-407d-4b08-8390-650692fccc6a	c0048f24-e8cc-4724-ad13-3605ff71edc7	2	2025-07-08 15:50:58.219461
b098f6e9-d4bb-43ec-9392-9b2f3405f9df	158da148-407d-4b08-8390-650692fccc6a	c0048f24-e8cc-4724-ad13-3605ff71edc7	3	2025-07-08 15:50:58.223664
97dbbae5-821c-4c5f-915e-aa6628c1e35d	842d0a5c-a025-4485-90c4-540ff3cfaaae	7ed53066-a8b0-40ee-a6bb-976989f2bf32	1	2025-07-08 15:50:59.538702
45cbda41-8f71-4f04-87da-e641239467d0	842d0a5c-a025-4485-90c4-540ff3cfaaae	7ed53066-a8b0-40ee-a6bb-976989f2bf32	2	2025-07-08 15:50:59.543091
9f369385-0cd1-47f8-91aa-d22e8471553f	aee5986b-3fc2-40d7-a55e-2df9872efdd2	618a10f3-7561-4343-b5b9-7c9ee4470e2c	1	2025-07-08 16:01:39.092989
8e9ff14d-3cce-4cff-a48c-4851608bf662	aee5986b-3fc2-40d7-a55e-2df9872efdd2	a7677c21-24d1-428a-aee4-9f592241caec	1	2025-07-08 16:01:39.106085
eb77e801-35c8-4e5b-9daa-a7ac7785620f	aee5986b-3fc2-40d7-a55e-2df9872efdd2	5f6bc012-cd13-496b-9089-8afcf4b5db58	1	2025-07-08 16:01:39.115681
227a7166-949c-45f1-896d-1032993874af	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	618a10f3-7561-4343-b5b9-7c9ee4470e2c	1	2025-07-08 16:01:39.135778
1afc1443-553d-4298-bd12-93828f7f36ee	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	618a10f3-7561-4343-b5b9-7c9ee4470e2c	2	2025-07-08 16:01:39.145498
42eebf8d-abec-4d4a-90e6-d478a8f8927d	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	a7677c21-24d1-428a-aee4-9f592241caec	1	2025-07-08 16:01:39.152372
311f40d8-6cdf-4e95-b814-e0349695a204	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	a7677c21-24d1-428a-aee4-9f592241caec	2	2025-07-08 16:01:39.156578
188e204a-2c31-4171-a797-53be4e5c09e9	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	5f6bc012-cd13-496b-9089-8afcf4b5db58	1	2025-07-08 16:01:39.169676
e782a5a9-769a-4f21-b672-ae086008d8b3	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	5f6bc012-cd13-496b-9089-8afcf4b5db58	2	2025-07-08 16:01:39.174723
d48c4b74-0c7c-4d80-8b83-44d31f47c74c	158da148-407d-4b08-8390-650692fccc6a	618a10f3-7561-4343-b5b9-7c9ee4470e2c	1	2025-07-08 16:01:39.190308
e3b87fd9-f29f-4331-aef8-db6fd23bbcc2	158da148-407d-4b08-8390-650692fccc6a	618a10f3-7561-4343-b5b9-7c9ee4470e2c	2	2025-07-08 16:01:39.20866
519a99df-f930-4b69-8c7c-7d7df1a98835	158da148-407d-4b08-8390-650692fccc6a	618a10f3-7561-4343-b5b9-7c9ee4470e2c	3	2025-07-08 16:01:39.213721
22768bf8-8541-4cd1-8690-0f39b308ea28	158da148-407d-4b08-8390-650692fccc6a	a7677c21-24d1-428a-aee4-9f592241caec	1	2025-07-08 16:01:39.22358
7795ce15-eb61-42bd-85b1-f4d0e5db25e8	158da148-407d-4b08-8390-650692fccc6a	a7677c21-24d1-428a-aee4-9f592241caec	2	2025-07-08 16:01:39.232248
8cd03caa-e44f-48a1-8b2b-dae1ffc508ca	158da148-407d-4b08-8390-650692fccc6a	a7677c21-24d1-428a-aee4-9f592241caec	3	2025-07-08 16:01:39.23449
9a4e45be-5456-48ea-ba8e-f8d40a550288	158da148-407d-4b08-8390-650692fccc6a	5f6bc012-cd13-496b-9089-8afcf4b5db58	1	2025-07-08 16:01:39.239568
ffb969bc-050c-44cf-8bad-e9f6d9e5f05f	158da148-407d-4b08-8390-650692fccc6a	5f6bc012-cd13-496b-9089-8afcf4b5db58	2	2025-07-08 16:01:39.247716
08f2a3a1-783c-4525-84f3-fa8c968c7d29	158da148-407d-4b08-8390-650692fccc6a	5f6bc012-cd13-496b-9089-8afcf4b5db58	3	2025-07-08 16:01:39.252206
5b24d8a7-8219-4ead-97bb-9bf7a3370525	842d0a5c-a025-4485-90c4-540ff3cfaaae	019807f3-a2f3-425d-8852-dc11e1d4146f	1	2025-07-08 16:01:40.452839
c4f52932-f524-42ab-9a2d-ff68843fd712	842d0a5c-a025-4485-90c4-540ff3cfaaae	019807f3-a2f3-425d-8852-dc11e1d4146f	2	2025-07-08 16:01:40.484645
9b99cd09-5d6c-4102-9552-959c21082c41	3d01c53d-593b-4053-8004-63f33daece6c	2fcfa332-4519-4a9d-a8d3-cfbaf0dc6830	1	2025-07-08 16:02:00.840475
3d505a7b-1ead-4f06-9c97-66067bf52241	3d01c53d-593b-4053-8004-63f33daece6c	2fcfa332-4519-4a9d-a8d3-cfbaf0dc6830	2	2025-07-08 16:02:00.856514
082bc0f1-66a8-4144-88ea-73ee9a4376f7	3d01c53d-593b-4053-8004-63f33daece6c	2fcfa332-4519-4a9d-a8d3-cfbaf0dc6830	3	2025-07-08 16:02:00.860983
510abdc2-6e78-4f15-865c-ea5066b9d136	aee5986b-3fc2-40d7-a55e-2df9872efdd2	23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	1	2025-07-08 16:02:01.397403
7ddcebfd-ab21-4fb4-a34b-9e6a1276683e	aee5986b-3fc2-40d7-a55e-2df9872efdd2	e67e95fd-ceb8-4e9f-915a-5fa5836bef54	1	2025-07-08 16:02:01.418429
8bbd85de-4d27-40d8-8171-89f836383604	aee5986b-3fc2-40d7-a55e-2df9872efdd2	a91b1efb-d21c-4ec8-a67f-b63e15fcd579	1	2025-07-08 16:02:01.430205
3861d95e-83d3-4a88-a36c-de6dbabcfa86	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	1	2025-07-08 16:02:01.439312
c6bc109b-b54b-4dc7-9577-668b3c2b89e4	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	2	2025-07-08 16:02:01.444921
4d68802e-4526-4a7a-aa8f-0ccc82f953ca	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	e67e95fd-ceb8-4e9f-915a-5fa5836bef54	1	2025-07-08 16:02:01.455194
2161a80c-fb61-4091-8914-410b32258047	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	e67e95fd-ceb8-4e9f-915a-5fa5836bef54	2	2025-07-08 16:02:01.460922
9147aa98-990d-498b-94f1-e2ac7a449d35	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	a91b1efb-d21c-4ec8-a67f-b63e15fcd579	1	2025-07-08 16:02:01.473222
545f87be-28e3-4c7e-bce8-5ba8c12b9f47	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	a91b1efb-d21c-4ec8-a67f-b63e15fcd579	2	2025-07-08 16:02:01.486474
97578f45-1ba9-4bc5-9e8f-109ffc9dcca6	158da148-407d-4b08-8390-650692fccc6a	23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	1	2025-07-08 16:02:01.511764
70cce800-ab01-42d3-a650-2f4262504753	158da148-407d-4b08-8390-650692fccc6a	23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	2	2025-07-08 16:02:01.516569
8397c5d7-b414-4d2e-a336-f0104dbca080	158da148-407d-4b08-8390-650692fccc6a	23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	3	2025-07-08 16:02:01.518667
3c40694e-40d3-43e2-bd65-a829e4bde001	158da148-407d-4b08-8390-650692fccc6a	e67e95fd-ceb8-4e9f-915a-5fa5836bef54	1	2025-07-08 16:02:01.524995
7ca9a445-562d-40ce-9cc9-36a5a647cd20	158da148-407d-4b08-8390-650692fccc6a	e67e95fd-ceb8-4e9f-915a-5fa5836bef54	2	2025-07-08 16:02:01.531302
8f333038-5ce8-419a-b91e-cb41391a8b17	158da148-407d-4b08-8390-650692fccc6a	e67e95fd-ceb8-4e9f-915a-5fa5836bef54	3	2025-07-08 16:02:01.533406
988bad6a-0f67-4d4d-ba6d-16e82be498ad	158da148-407d-4b08-8390-650692fccc6a	a91b1efb-d21c-4ec8-a67f-b63e15fcd579	1	2025-07-08 16:02:01.539543
031bcd9f-1aa9-446d-b80b-d1bd2255c0ec	158da148-407d-4b08-8390-650692fccc6a	a91b1efb-d21c-4ec8-a67f-b63e15fcd579	2	2025-07-08 16:02:01.543499
6c42d05e-f5fa-44b0-96fa-99960c85af73	158da148-407d-4b08-8390-650692fccc6a	a91b1efb-d21c-4ec8-a67f-b63e15fcd579	3	2025-07-08 16:02:01.545231
59cb6058-8425-483d-a8b8-7a94834a86e7	842d0a5c-a025-4485-90c4-540ff3cfaaae	7de1e91d-9448-4dbd-ad46-27abb8aa2089	1	2025-07-08 16:02:02.702416
3fd020ad-cb2f-43db-9c38-794552037679	842d0a5c-a025-4485-90c4-540ff3cfaaae	7de1e91d-9448-4dbd-ad46-27abb8aa2089	2	2025-07-08 16:02:02.718664
a34d4d38-8826-47c8-8b59-8358d9da6cc5	6611542b-d5be-441d-ba28-287b5b79903e	34a55d40-67b8-4c2a-95de-8ec4eb91c544	1	2025-07-08 19:02:35.816688
a0b82e87-4cd8-4162-a6a2-4d11b50fb569	6611542b-d5be-441d-ba28-287b5b79903e	34a55d40-67b8-4c2a-95de-8ec4eb91c544	2	2025-07-08 19:02:37.349825
fc6acb7e-ece1-424f-ab39-c5eb8de0262b	6611542b-d5be-441d-ba28-287b5b79903e	34a55d40-67b8-4c2a-95de-8ec4eb91c544	3	2025-07-08 19:02:37.926971
ee37295d-27fd-473b-bf40-207f4aeaf00d	989d493b-42ec-489f-b25f-c4700e8ee735	93718f8b-2d13-4736-b9c9-76465af58076	1	2025-07-08 19:02:44.349857
f5d2aa04-d49c-4544-919b-4f02bc809902	989d493b-42ec-489f-b25f-c4700e8ee735	93718f8b-2d13-4736-b9c9-76465af58076	2	2025-07-08 19:02:44.509399
c032a837-888d-45d2-9b97-5086e7c19f74	989d493b-42ec-489f-b25f-c4700e8ee735	93718f8b-2d13-4736-b9c9-76465af58076	3	2025-07-08 19:02:44.641204
6cb02391-0f65-4d11-a567-5b8584ceb293	8f43e562-9d44-4b54-8025-20824d3975af	24b52495-be3a-423c-adaf-94c205fd2c57	1	2025-07-08 20:40:13.039537
37259318-f274-4044-a7c3-c0840d6a6968	989d493b-42ec-489f-b25f-c4700e8ee735	a3a09e90-8329-468f-9bfa-c81619280bb7	1	2025-07-08 23:34:21.392197
b6a4c906-4e62-40d1-b260-77a39eee2fee	989d493b-42ec-489f-b25f-c4700e8ee735	a3a09e90-8329-468f-9bfa-c81619280bb7	2	2025-07-08 23:34:24.176497
83e6beb9-af3c-4e5d-a1e6-d7336c3bd81d	989d493b-42ec-489f-b25f-c4700e8ee735	a3a09e90-8329-468f-9bfa-c81619280bb7	3	2025-07-08 23:35:03.781994
ab600b17-e51d-4908-9bf4-22e17700ded3	6611542b-d5be-441d-ba28-287b5b79903e	041d4171-f15f-4671-9a91-64fa3a898688	1	2025-07-09 10:43:45.825424
cedd3182-af26-4ee6-a61d-19d39cc09afd	6611542b-d5be-441d-ba28-287b5b79903e	041d4171-f15f-4671-9a91-64fa3a898688	2	2025-07-09 10:43:47.693928
f8bea91b-9642-48de-af26-48c05bfba0a1	6611542b-d5be-441d-ba28-287b5b79903e	041d4171-f15f-4671-9a91-64fa3a898688	3	2025-07-09 10:43:50.499344
f4114590-1528-4586-991e-653e72448fdb	6611542b-d5be-441d-ba28-287b5b79903e	e2163f75-6b45-4623-8f5e-c71834c79cf8	1	2025-07-09 12:15:42.262515
112efe7a-14c7-4a1f-995f-eb2165c3ba1e	6611542b-d5be-441d-ba28-287b5b79903e	e2163f75-6b45-4623-8f5e-c71834c79cf8	2	2025-07-09 12:15:44.702294
a1c822da-48cf-4691-bc88-ed1067c4d8c4	6611542b-d5be-441d-ba28-287b5b79903e	e2163f75-6b45-4623-8f5e-c71834c79cf8	3	2025-07-09 12:15:46.596274
294a5a4d-7194-468e-a08f-f9a48eda4f06	6611542b-d5be-441d-ba28-287b5b79903e	b1355d07-d5b8-4bc4-a1c3-5908e3ce2169	1	2025-07-09 12:27:57.493532
7d8edb65-b2a9-4ebc-9fa8-04eac5ddca25	6611542b-d5be-441d-ba28-287b5b79903e	b1355d07-d5b8-4bc4-a1c3-5908e3ce2169	2	2025-07-09 12:27:58.518236
12dd6868-173b-41ad-9868-67c8c6236034	6611542b-d5be-441d-ba28-287b5b79903e	161daf73-a405-4511-9af4-a04de88578d4	1	2025-07-09 12:34:01.365616
5ea70818-50cc-4ad6-b4eb-65d28240d7b5	6611542b-d5be-441d-ba28-287b5b79903e	161daf73-a405-4511-9af4-a04de88578d4	2	2025-07-09 12:34:02.368909
4cb67d16-7d0c-4daa-882a-9b80860766f5	6611542b-d5be-441d-ba28-287b5b79903e	161daf73-a405-4511-9af4-a04de88578d4	3	2025-07-09 12:34:04.765587
b4e188bd-260c-469b-8fe5-e66d5991bae9	aee5986b-3fc2-40d7-a55e-2df9872efdd2	54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	1	2025-07-09 15:47:36.223812
8c75a476-6bbc-49d8-a3ba-3ff3cb534c3e	aee5986b-3fc2-40d7-a55e-2df9872efdd2	ab9d296b-4905-44b0-9485-ad469202120d	1	2025-07-09 15:47:36.237812
c1de96d4-751d-40c8-94f3-ee6c9dc2c196	aee5986b-3fc2-40d7-a55e-2df9872efdd2	40bf3ebb-46e5-4bc7-8c97-93c414d57545	1	2025-07-09 15:47:36.245727
53254a75-d642-4a14-9a96-7d4d69ab51ed	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	1	2025-07-09 15:47:36.254432
05febe95-cd73-4d38-a6df-e2afd6074a33	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	2	2025-07-09 15:47:36.258265
c82a3775-13a1-48c3-8910-cfd8b36abdd9	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	ab9d296b-4905-44b0-9485-ad469202120d	1	2025-07-09 15:47:36.263368
7a35025a-c5cd-46c7-aaa7-e8b01157cae3	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	ab9d296b-4905-44b0-9485-ad469202120d	2	2025-07-09 15:47:36.267692
0f50845a-4585-4b23-899c-55b98a3ced02	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	40bf3ebb-46e5-4bc7-8c97-93c414d57545	1	2025-07-09 15:47:36.284348
0eae83e3-34e1-4f6d-ba68-a6072325fdba	1a63a1c0-b3a7-4458-957e-8458d6d7ab54	40bf3ebb-46e5-4bc7-8c97-93c414d57545	2	2025-07-09 15:47:36.288762
41f776b5-cf31-4045-b0cd-0189948c610a	158da148-407d-4b08-8390-650692fccc6a	54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	1	2025-07-09 15:47:36.295748
1dc38f16-e17a-4509-8e2f-60acbe960e7a	158da148-407d-4b08-8390-650692fccc6a	54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	2	2025-07-09 15:47:36.301726
f9b1849d-12ef-4280-87c0-bc5ba02ba576	158da148-407d-4b08-8390-650692fccc6a	54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	3	2025-07-09 15:47:36.30363
3291a8a9-87af-4cee-8a64-54fee089499c	158da148-407d-4b08-8390-650692fccc6a	ab9d296b-4905-44b0-9485-ad469202120d	1	2025-07-09 15:47:36.316121
7d0ef7fa-cf2d-498c-bf67-053f7e118fc8	158da148-407d-4b08-8390-650692fccc6a	ab9d296b-4905-44b0-9485-ad469202120d	2	2025-07-09 15:47:36.320538
87e66e0d-7c4e-4fb0-b9ec-1595753a591c	158da148-407d-4b08-8390-650692fccc6a	ab9d296b-4905-44b0-9485-ad469202120d	3	2025-07-09 15:47:36.322406
41ee23d3-1142-42d9-bd20-e0ae8f23e6ca	158da148-407d-4b08-8390-650692fccc6a	40bf3ebb-46e5-4bc7-8c97-93c414d57545	1	2025-07-09 15:47:36.327209
b4d804bc-ec0e-4941-b671-686a510b0173	158da148-407d-4b08-8390-650692fccc6a	40bf3ebb-46e5-4bc7-8c97-93c414d57545	2	2025-07-09 15:47:36.331071
12a15cb3-1469-451f-8ba5-7ba7fcca4dcc	158da148-407d-4b08-8390-650692fccc6a	40bf3ebb-46e5-4bc7-8c97-93c414d57545	3	2025-07-09 15:47:36.332716
67547314-7749-4af4-a214-fe52e2ddb321	842d0a5c-a025-4485-90c4-540ff3cfaaae	51fd5f22-a2d7-43a0-a849-5edf13ebf2bd	1	2025-07-09 15:47:37.419939
d601fda7-a9d9-49cd-8966-254c62a4642a	842d0a5c-a025-4485-90c4-540ff3cfaaae	51fd5f22-a2d7-43a0-a849-5edf13ebf2bd	2	2025-07-09 15:47:37.43491
\.


--
-- Data for Name: leaderboards; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.leaderboards (id, score_period, period_start, player_id, player_name, total_score, phrases_completed, rank_position, created_at) FROM stdin;
81f3003f-7d5d-45f4-9883-e34a3d07daef	daily	2025-07-08	3d01c53d-593b-4053-8004-63f33daece6c	HintTestPlayer	253	11	1	2025-07-08 19:04:01.396933
4c9f1e36-1612-45c5-86e0-2dd893909762	daily	2025-07-08	842d0a5c-a025-4485-90c4-540ff3cfaaae	ScoringTestPlayer1	136	4	2	2025-07-08 19:04:01.396933
5e8d9f86-68d0-45f5-b1d1-e51485d310b1	daily	2025-07-08	8f43e562-9d44-4b54-8025-20824d3975af	Mmeee	95	2	3	2025-07-08 19:04:01.396933
05143428-74d2-4057-990f-3a898f232b69	daily	2025-07-09	989d493b-42ec-489f-b25f-c4700e8ee735	Harry	100	1	1	2025-07-09 15:54:15.875343
5675cefb-15ba-4525-a2df-afd36a1536dd	daily	2025-07-09	842d0a5c-a025-4485-90c4-540ff3cfaaae	ScoringTestPlayer1	34	1	2	2025-07-09 15:54:15.875343
c4d3a510-b9d1-4f26-911f-54bc1707dd96	weekly	2025-07-07	3d01c53d-593b-4053-8004-63f33daece6c	HintTestPlayer	253	11	1	2025-07-09 15:54:15.87885
25c32582-22c0-47c7-bbcd-6db4c1068964	weekly	2025-07-07	842d0a5c-a025-4485-90c4-540ff3cfaaae	ScoringTestPlayer1	170	5	2	2025-07-09 15:54:15.87885
ab530fae-8deb-4e83-bcc1-d40c44ab14b0	weekly	2025-07-07	989d493b-42ec-489f-b25f-c4700e8ee735	Harry	100	1	3	2025-07-09 15:54:15.87885
823e0d64-2de1-43b8-93bb-7f9030a89821	weekly	2025-07-07	8f43e562-9d44-4b54-8025-20824d3975af	Mmeee	95	2	4	2025-07-09 15:54:15.87885
686ac10e-2d2d-47d4-b376-76919be91f6c	total	1970-01-01	3d01c53d-593b-4053-8004-63f33daece6c	HintTestPlayer	253	11	1	2025-07-09 15:54:15.881412
06701984-6eaa-4abd-9787-0a0e213c4fea	total	1970-01-01	842d0a5c-a025-4485-90c4-540ff3cfaaae	ScoringTestPlayer1	170	5	2	2025-07-09 15:54:15.881412
2cdd7a09-16d0-4f8c-bd15-da41aafac89b	total	1970-01-01	989d493b-42ec-489f-b25f-c4700e8ee735	Harry	100	1	3	2025-07-09 15:54:15.881412
721396f2-65d4-4caf-bb77-0e01927fd861	total	1970-01-01	8f43e562-9d44-4b54-8025-20824d3975af	Mmeee	95	2	4	2025-07-09 15:54:15.881412
\.


--
-- Data for Name: offline_phrases; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.offline_phrases (id, player_id, phrase_id, downloaded_at, is_used, used_at) FROM stdin;
f453ea28-b5e9-4475-922f-bf1a966e8c3e	dd2064cd-8351-4fae-809c-171f0f59f7b5	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:31:10.926432	f	\N
7cb68f6f-c637-4eec-b75f-41c2ee9a1976	dd2064cd-8351-4fae-809c-171f0f59f7b5	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:31:10.926432	f	\N
f71ce152-b832-4807-8148-ab131affdd29	dd2064cd-8351-4fae-809c-171f0f59f7b5	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:31:10.926432	f	\N
53511679-aeb2-4738-bbef-2fb8d365da58	dd2064cd-8351-4fae-809c-171f0f59f7b5	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:31:10.926432	f	\N
fef4b66f-bbee-47c1-8cc1-4664c65c52e2	dd2064cd-8351-4fae-809c-171f0f59f7b5	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:31:10.926432	f	\N
fe68332a-b501-40dd-a113-3aa4c9e05751	dd2064cd-8351-4fae-809c-171f0f59f7b5	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:31:10.926432	f	\N
7f6c0277-a438-4fee-aa12-a02efd764d9f	dd2064cd-8351-4fae-809c-171f0f59f7b5	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:31:10.926432	f	\N
009c14aa-3f72-4778-b7af-90fcfa1fd6e7	dd2064cd-8351-4fae-809c-171f0f59f7b5	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:31:10.926432	f	\N
5bb6d058-d8eb-4e0f-8b2e-453646bbe8d8	4a67af66-246c-4fb4-ab15-1d23cc9724ed	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:31:18.394641	f	\N
cbf6738e-66f4-40c4-ab79-cf10370307ca	4a67af66-246c-4fb4-ab15-1d23cc9724ed	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:31:18.394641	f	\N
d70f0523-309f-4793-8916-17d937b002ae	4a67af66-246c-4fb4-ab15-1d23cc9724ed	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:31:18.394641	f	\N
f42c22cc-30ad-4acf-893f-79d2040d9ee6	4a67af66-246c-4fb4-ab15-1d23cc9724ed	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:31:18.394641	f	\N
c0e1fc03-7592-48da-aae6-c9f0dfa05f3f	4a67af66-246c-4fb4-ab15-1d23cc9724ed	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:31:18.394641	f	\N
3c1c0e86-3f17-4fb4-9aa9-564504ce7e1c	4a67af66-246c-4fb4-ab15-1d23cc9724ed	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:31:18.394641	f	\N
50d1db3b-19c7-4f0e-a9b5-df4f157282ca	4a67af66-246c-4fb4-ab15-1d23cc9724ed	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:31:18.394641	f	\N
1d4620e8-af1a-4e9f-8aeb-4bf3ed63608a	4a67af66-246c-4fb4-ab15-1d23cc9724ed	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:31:18.394641	f	\N
c042f360-3618-4b13-8506-c23516326a15	c722bd54-5717-4ed2-a311-ba47c32aff6a	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:31:18.47847	f	\N
2b57745c-afbf-42f6-8b7c-b4cdd27c87e5	c722bd54-5717-4ed2-a311-ba47c32aff6a	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:31:18.47847	f	\N
fc04a303-fc42-4cf6-af9f-1987a0b737e7	c722bd54-5717-4ed2-a311-ba47c32aff6a	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:31:18.47847	f	\N
a8448ea6-8fac-481c-be2a-56e91b90905b	c722bd54-5717-4ed2-a311-ba47c32aff6a	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:31:18.483733	f	\N
b5945ef8-7136-49cf-b55b-cfec72bec460	c722bd54-5717-4ed2-a311-ba47c32aff6a	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:31:18.483733	f	\N
41fb6258-4c2c-4390-819a-d8dcbfc7bf34	c722bd54-5717-4ed2-a311-ba47c32aff6a	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:31:18.483733	f	\N
a9d4f789-0af9-4673-9ffd-0ed78c56c235	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:31:18.493367	f	\N
de0456a3-31ec-459c-83f3-c46362b04359	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:31:18.493367	f	\N
5bc5caea-1329-4037-aeb1-adc2fe2d64b2	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:31:18.493367	f	\N
74560085-438c-43ad-b2fc-fb26c586e87a	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:31:18.493367	f	\N
72853c89-8701-4bb1-ae26-ebafe0cf5ff9	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:31:18.493367	f	\N
822ee9ef-1b8c-4655-8d45-2a7076a6bb36	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:31:18.493367	f	\N
b46fa3a4-f8fa-4139-8136-f5e98e1a3d78	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:31:18.493367	f	\N
df4086dd-1e77-4407-af10-dd07d0b22eae	9a9b4e2d-283f-4111-bed1-b5cfa62b6856	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:31:18.493367	f	\N
36124457-388e-4975-8376-a97cea105c8c	c722bd54-5717-4ed2-a311-ba47c32aff6a	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:31:18.542417	f	\N
f8d9c3ff-17f8-465d-a4b9-b7db3cb0d6cd	c722bd54-5717-4ed2-a311-ba47c32aff6a	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:31:18.542417	f	\N
a4773900-cb46-4a8f-9010-d50b5803f12e	901682b0-3c53-42af-b7af-c3787b52c306	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:36:04.891744	f	\N
3073c33b-c720-47e7-9a49-be644925c470	901682b0-3c53-42af-b7af-c3787b52c306	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:36:04.891744	f	\N
d7c7e9c1-0ec6-4a7d-858e-318a89c7834c	901682b0-3c53-42af-b7af-c3787b52c306	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:36:04.891744	f	\N
532afeb8-45c2-409d-9fee-89b1f862d433	901682b0-3c53-42af-b7af-c3787b52c306	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:36:04.891744	f	\N
7d547335-fe69-4241-b475-3f65a1fea489	901682b0-3c53-42af-b7af-c3787b52c306	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:36:04.891744	f	\N
fad42d13-6dcd-4672-b072-2badb0d80526	901682b0-3c53-42af-b7af-c3787b52c306	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:36:04.891744	f	\N
5f6a9975-a95f-4c31-b3d2-b0d46b0ff3ad	901682b0-3c53-42af-b7af-c3787b52c306	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:36:04.891744	f	\N
6f9b4aaa-d9cc-4699-a4c0-42301809c85d	901682b0-3c53-42af-b7af-c3787b52c306	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:36:04.891744	f	\N
586770c5-4690-4517-8244-b55a4bd6649e	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:36:04.912373	f	\N
46d095b8-4d74-41c7-a6a6-5d431212ad83	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:36:04.912373	f	\N
456cc01f-7248-470b-958b-d1374206ce4b	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:36:04.912373	f	\N
6ae3d5c1-b89d-4d87-87c6-d8375d9af710	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:36:04.917526	f	\N
bce3d2d2-3e4f-4048-baa4-e1f2b63fcc50	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:36:04.917526	f	\N
6ea3cbdb-40cc-4bd3-8d5b-486aef418c98	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:36:04.917526	f	\N
bfbe372b-c0dd-4bbb-8b9f-7b0e923b5d84	76cf776d-1d08-4cd2-b9da-e17db5beff33	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:36:04.927841	f	\N
f6bfc8c6-900d-4201-a5cc-99b3274be40a	76cf776d-1d08-4cd2-b9da-e17db5beff33	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:36:04.927841	f	\N
f1922e0f-f47e-4290-adcd-542fe7e8d33d	76cf776d-1d08-4cd2-b9da-e17db5beff33	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:36:04.927841	f	\N
4dbeb212-5f3f-4854-993e-44672a660782	76cf776d-1d08-4cd2-b9da-e17db5beff33	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:36:04.927841	f	\N
f38cb1c4-113a-4013-96b8-83973e0c309d	76cf776d-1d08-4cd2-b9da-e17db5beff33	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:36:04.927841	f	\N
3dec6416-c707-4b49-a979-d16b6aecb9a8	76cf776d-1d08-4cd2-b9da-e17db5beff33	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:36:04.927841	f	\N
6cde0964-3558-4652-84f8-e375b0b6eac9	76cf776d-1d08-4cd2-b9da-e17db5beff33	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:36:04.927841	f	\N
763b5265-8ea4-4fd2-a811-2e8588558f76	76cf776d-1d08-4cd2-b9da-e17db5beff33	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:36:04.927841	f	\N
fd87fbd5-6e73-4aa1-8ed9-d8a2b8cf201e	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:36:04.992866	f	\N
cea7701c-e94e-42fa-bc2f-07b6356553ad	b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:36:04.992866	f	\N
ebe85d09-9472-4b99-b80d-0e5b7dc1e436	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:41:55.711289	f	\N
3bb156d9-a316-413c-a899-94bb1a4ce496	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:41:55.711289	f	\N
4fc8d1d1-0692-4316-b82b-c9cf630a2674	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:41:55.711289	f	\N
672dde19-df21-4fef-8d8f-15affa152652	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:41:55.711289	f	\N
9f289bda-36ea-43b6-a6e7-d10b40fd4c70	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:41:55.711289	f	\N
10133f60-d41e-4bb1-ab22-98b1613d834f	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:41:55.711289	f	\N
bb9ba671-1326-4528-9cdc-087147dbf510	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:41:55.711289	f	\N
29966297-47fa-4f6d-9830-bd334d1879e9	5b8a6048-31c5-453a-a5c6-ad8a7660fa08	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:41:55.711289	f	\N
c2139bb3-712c-450b-bca7-798f655be6f7	40682e11-e7fc-4b84-9ad3-2c09298f67d5	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:42:39.842799	f	\N
2c398048-734c-4547-b05e-e0d6c4085482	40682e11-e7fc-4b84-9ad3-2c09298f67d5	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:42:39.842799	f	\N
30f89cee-376d-442f-aa7c-cacb2767c832	40682e11-e7fc-4b84-9ad3-2c09298f67d5	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:42:39.842799	f	\N
19725e8b-6cb6-4292-9c2b-7b5f2640da46	40682e11-e7fc-4b84-9ad3-2c09298f67d5	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:42:39.842799	f	\N
d30d422f-ef12-472a-add3-c79a5f61a295	40682e11-e7fc-4b84-9ad3-2c09298f67d5	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:42:39.842799	f	\N
4be6257f-6b09-460a-8006-02c57855ed34	40682e11-e7fc-4b84-9ad3-2c09298f67d5	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:42:39.842799	f	\N
2a1ece01-b6c9-4c5f-91be-8a222f64b145	40682e11-e7fc-4b84-9ad3-2c09298f67d5	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:42:39.842799	f	\N
6897ba23-8e25-4eec-9ed9-57c11afc4e2c	40682e11-e7fc-4b84-9ad3-2c09298f67d5	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:42:39.842799	f	\N
c311b2bf-806c-4855-ba9d-69568905e0da	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:42:39.897767	f	\N
dc42b154-7b11-4024-b19c-329c9788493f	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:42:39.897767	f	\N
d718da51-0aaf-409d-aa0a-b08c3620bd0a	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:42:39.897767	f	\N
5e7429f4-6779-436c-8bfa-4a7627bb2b2c	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:42:39.901635	f	\N
1fbee28b-db18-4d0e-a4cf-a8153ffbb9c6	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:42:39.901635	f	\N
6b9665a3-f11b-4c72-9754-0e3b14ce04e8	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:42:39.901635	f	\N
294647e2-5170-440a-8ed2-a59641fb2023	d0654012-742d-4e23-ab6c-5d921574a1c0	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:42:39.907236	f	\N
f66e133f-82fd-45d1-8333-8776a24a9b19	d0654012-742d-4e23-ab6c-5d921574a1c0	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:42:39.907236	f	\N
6b99dc65-abfb-4ed8-84d8-d1ec81822848	d0654012-742d-4e23-ab6c-5d921574a1c0	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:42:39.907236	f	\N
8e5d18ee-03cc-407d-aea4-8a9fdda1f62e	d0654012-742d-4e23-ab6c-5d921574a1c0	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:42:39.907236	f	\N
98dbfa6f-22a2-40cd-af93-bcf1fde3cfad	d0654012-742d-4e23-ab6c-5d921574a1c0	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:42:39.907236	f	\N
173501f0-2226-4f6d-b6ad-e6dc2784e93c	d0654012-742d-4e23-ab6c-5d921574a1c0	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:42:39.907236	f	\N
6618f119-c6dc-412b-a061-62df0d570a55	d0654012-742d-4e23-ab6c-5d921574a1c0	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:42:39.907236	f	\N
68744b2d-33b1-4692-9731-1110a08ee36c	d0654012-742d-4e23-ab6c-5d921574a1c0	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:42:39.907236	f	\N
2e5c0741-703a-4703-a5e9-68f37d5f6b42	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:42:39.983459	f	\N
a6bf52ba-5897-4be1-a42b-2abb9404bb43	03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:42:39.983459	f	\N
ae4281a4-3ed3-4e48-9f9f-d79d10869bf8	12bb186c-3aaf-428b-9182-5fea9984e1b3	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:44:00.514805	f	\N
5576369f-6db2-4d90-aef3-acb133f54217	12bb186c-3aaf-428b-9182-5fea9984e1b3	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:44:00.514805	f	\N
782bedd4-da69-4f07-af96-e14389861258	12bb186c-3aaf-428b-9182-5fea9984e1b3	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:44:00.514805	f	\N
ccd19b1c-8a79-4b3b-b068-2becf185b73d	12bb186c-3aaf-428b-9182-5fea9984e1b3	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:44:00.514805	f	\N
e648eef5-9be2-4936-aceb-18a792523fe2	12bb186c-3aaf-428b-9182-5fea9984e1b3	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:44:00.514805	f	\N
72987faa-a2c8-40cd-8987-5d85706feea5	12bb186c-3aaf-428b-9182-5fea9984e1b3	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:44:00.514805	f	\N
0b6ace7a-8d09-4ddc-a55b-1e84c192ba1e	12bb186c-3aaf-428b-9182-5fea9984e1b3	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:44:00.514805	f	\N
99c28b06-eb52-4c24-8fca-8dfb462f7eff	12bb186c-3aaf-428b-9182-5fea9984e1b3	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:44:00.514805	f	\N
95741379-782c-4c9a-85d1-7e88da0977e8	d238f9eb-6432-426f-969b-a394ae850893	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:44:00.546684	f	\N
a78c0369-08c1-488b-9903-11b731cc0dd2	d238f9eb-6432-426f-969b-a394ae850893	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:44:00.546684	f	\N
665f2b0e-e0eb-4ba4-bebe-402b5aefcbfc	d238f9eb-6432-426f-969b-a394ae850893	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:44:00.546684	f	\N
4d6999d0-8dd4-4074-be3a-3b3623c6d71d	d238f9eb-6432-426f-969b-a394ae850893	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:44:00.549864	f	\N
0e888a81-473f-4c1e-8372-e099545e775b	d238f9eb-6432-426f-969b-a394ae850893	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:44:00.549864	f	\N
d5220a24-5a6f-4b55-9fc5-0d62047c270d	d238f9eb-6432-426f-969b-a394ae850893	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:44:00.549864	f	\N
19de4582-3d67-4946-8faf-32e858847a0a	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:44:00.563644	f	\N
c13ab1a1-b782-4871-a19a-1d9f4fb7311f	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:44:00.563644	f	\N
7f919d8f-9d6d-4201-a3a7-0934cff5a69a	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:44:00.563644	f	\N
d58a49e0-6aa1-4765-831b-17ae32f42b2f	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:44:00.563644	f	\N
338b5067-1080-4279-affb-81d2ad139c7d	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:44:00.563644	f	\N
4580ed43-e8d9-4c66-b453-02bc6657f184	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:44:00.563644	f	\N
80a8427d-100a-42a1-a852-e43f87363208	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:44:00.563644	f	\N
1356b5d4-22f4-4f87-a6e1-ad04e5a3afe7	3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:44:00.563644	f	\N
b963d071-9d67-4009-8633-fdb031c1fa02	d238f9eb-6432-426f-969b-a394ae850893	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:44:00.610604	f	\N
a904a769-819e-4130-b94c-023f12763e77	d238f9eb-6432-426f-969b-a394ae850893	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:44:00.610604	f	\N
87740e29-9999-4259-9cb3-6b69e911e8fa	c9b235db-4309-4573-9800-db505f70274c	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:50:27.37138	f	\N
6e934019-8300-465b-9561-d0d603558754	c9b235db-4309-4573-9800-db505f70274c	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:50:27.37138	f	\N
f12069f2-c80e-4565-a405-914d3ae999fc	c9b235db-4309-4573-9800-db505f70274c	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:50:27.37138	f	\N
7c8d541a-068b-445e-ae9d-ff312b38e6a3	c9b235db-4309-4573-9800-db505f70274c	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:50:27.37138	f	\N
e6c50051-c697-4baa-bcb4-0a400a53d4f1	c9b235db-4309-4573-9800-db505f70274c	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:50:27.37138	f	\N
e30ab9ef-6af2-494c-bc24-87844f2808c2	c9b235db-4309-4573-9800-db505f70274c	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:50:27.37138	f	\N
0e521033-8567-48fd-97c3-86b4603112a0	c9b235db-4309-4573-9800-db505f70274c	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:50:27.37138	f	\N
1ae5a6ac-253c-41b1-8fa3-86c8341eb1f2	c9b235db-4309-4573-9800-db505f70274c	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:50:27.37138	f	\N
05a503b4-325e-4dc2-bc4b-1720998614cf	38b317b0-8468-4ef2-9ef2-e621233e4619	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:50:27.436798	f	\N
fa4b02cb-7f4e-4c05-99f9-0f2950b81629	38b317b0-8468-4ef2-9ef2-e621233e4619	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:50:27.436798	f	\N
9abf3475-c42f-4d8d-8bf5-785b1a2706ec	38b317b0-8468-4ef2-9ef2-e621233e4619	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:50:27.436798	f	\N
bd961dd7-6fc7-4d97-bc9d-76bc8799eb31	38b317b0-8468-4ef2-9ef2-e621233e4619	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:50:27.455848	f	\N
62bd8ff5-196d-4ff4-9940-bd8733e494f0	38b317b0-8468-4ef2-9ef2-e621233e4619	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:50:27.455848	f	\N
f0934bfe-107d-49e0-b2ac-9a0c0727672c	38b317b0-8468-4ef2-9ef2-e621233e4619	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:50:27.455848	f	\N
f04b2b1f-5f3e-4fad-bdc7-c4c44d429925	7934628e-6daa-4b73-857c-db4c5fdc9c3a	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:50:27.482785	f	\N
ea505a0b-dce5-449b-8620-532550e1c70d	7934628e-6daa-4b73-857c-db4c5fdc9c3a	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:50:27.482785	f	\N
937781e5-e73b-4a41-a626-2831ec69e55d	7934628e-6daa-4b73-857c-db4c5fdc9c3a	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:50:27.482785	f	\N
09ea5055-5cde-4f6c-ba2f-cc7218e336f5	7934628e-6daa-4b73-857c-db4c5fdc9c3a	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:50:27.482785	f	\N
711499f3-39ca-484d-ba67-1dcd84c3e0c3	7934628e-6daa-4b73-857c-db4c5fdc9c3a	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:50:27.482785	f	\N
e89724fe-76fd-406d-88f5-fab07e21a174	7934628e-6daa-4b73-857c-db4c5fdc9c3a	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:50:27.482785	f	\N
f933dca8-2f9e-49df-817f-10f8e661d06c	7934628e-6daa-4b73-857c-db4c5fdc9c3a	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:50:27.482785	f	\N
2b61817e-68fd-45d1-9946-52325ba6a255	7934628e-6daa-4b73-857c-db4c5fdc9c3a	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:50:27.482785	f	\N
839a4288-a67f-4bbb-a67a-96f2d103ba18	1203de34-904c-405f-97c0-00ae573062ff	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:50:27.563094	f	\N
8ef4eca7-dee3-48c5-9d76-9c00ce3beeb9	1203de34-904c-405f-97c0-00ae573062ff	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:50:27.563094	f	\N
7ec9721f-c012-4081-88ac-b5d6f842773d	1203de34-904c-405f-97c0-00ae573062ff	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:50:27.563094	f	\N
b5f30cb2-ad33-4e7b-9534-5f1f94383460	1203de34-904c-405f-97c0-00ae573062ff	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:50:27.563094	f	\N
2723b7ab-9d68-4c6a-81c4-ced6ac79e67b	1203de34-904c-405f-97c0-00ae573062ff	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:50:27.563094	f	\N
f5bc1587-1d7f-4616-826c-8986014384ce	1203de34-904c-405f-97c0-00ae573062ff	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:50:27.563094	f	\N
ebba2074-ea25-4ea3-884a-613a861f9c1e	1203de34-904c-405f-97c0-00ae573062ff	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:50:27.563094	f	\N
e63d2998-c550-49ee-b4ae-2dee6e5bbaa1	1203de34-904c-405f-97c0-00ae573062ff	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:50:27.563094	f	\N
545e118d-b506-42e2-854c-b1ddccf26ed8	38b317b0-8468-4ef2-9ef2-e621233e4619	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:50:27.669041	f	\N
2e4e0fc9-9f3f-4e7b-af89-15c208f75159	38b317b0-8468-4ef2-9ef2-e621233e4619	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:50:27.669041	f	\N
f19e3ad0-e291-4e69-9e90-bb63a366116b	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:53:24.755611	f	\N
80e22efb-7223-439d-84bd-4b365cea21c7	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:53:24.755611	f	\N
2c50b0c4-ed27-46cb-9bea-2b4161b33004	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:53:24.755611	f	\N
c47ac35d-68a2-44b2-be55-a9e1de89ecbc	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:53:24.755611	f	\N
550f0cfc-7ec0-48ed-abf9-fdec7f24b11f	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:53:24.755611	f	\N
dbd71c72-aa0d-442c-ae8e-ef4c28419836	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:53:24.755611	f	\N
1fa7d7d5-20f5-48d9-8b1e-988611741289	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:53:24.755611	f	\N
b3b6145a-28b9-4534-9581-a00ef9d1c3ea	9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:53:24.755611	f	\N
ff70e06a-3980-44b3-b949-c9653294a4e4	c987746c-1945-4170-a67d-19e8eabfbffc	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:53:24.803369	f	\N
eb55ab25-af0f-4a7b-8ad4-c663a833eb7e	c987746c-1945-4170-a67d-19e8eabfbffc	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:53:24.803369	f	\N
5ba64014-68fb-459d-a3f9-f1fd86a4529b	c987746c-1945-4170-a67d-19e8eabfbffc	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:53:24.803369	f	\N
ca597b43-666a-4abb-a959-5f79fde1e817	c987746c-1945-4170-a67d-19e8eabfbffc	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:53:24.807496	f	\N
b3b79e3d-33f8-4a59-8cc5-0b8828256d90	c987746c-1945-4170-a67d-19e8eabfbffc	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:53:24.807496	f	\N
b1c19137-9dea-47fa-a1d5-bce32db4aead	c987746c-1945-4170-a67d-19e8eabfbffc	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:53:24.807496	f	\N
ddb7ddb0-035b-4e32-a453-6fe5829c3b25	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:53:24.830749	f	\N
6e0f2ca2-a7e7-44d8-8590-fd9f02c9c580	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:53:24.830749	f	\N
edf04ac7-a09b-4953-8bd1-a37203c2daab	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:53:24.830749	f	\N
5e7d7d57-4279-40be-b6c5-75c752f47a29	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:53:24.830749	f	\N
f7f69b8d-3f34-4415-a1ff-9b62d5053ac5	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:53:24.830749	f	\N
c74e4045-d613-4738-bfef-d4314a7dfb56	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:53:24.830749	f	\N
7e36a5dc-c898-4405-b385-bdbcf37cef06	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:53:24.830749	f	\N
3b2c93e7-7989-46bf-8087-6b050fe9eaf5	a860abd6-2fee-4838-9e84-0f8ce4cf96c8	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:53:24.830749	f	\N
2c0de74b-21c4-4d4b-815e-0a6b0c110c53	b10c80be-b76f-4182-b18b-26495c71700c	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:53:24.890029	f	\N
2fc920b5-7d08-4a27-a91e-d9183d4c4188	b10c80be-b76f-4182-b18b-26495c71700c	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:53:24.890029	f	\N
da91795a-76f2-4055-94bb-17c65d860f3d	b10c80be-b76f-4182-b18b-26495c71700c	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:53:24.890029	f	\N
16d5a5f9-1355-483d-8cb6-9ae98fad4401	b10c80be-b76f-4182-b18b-26495c71700c	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:53:24.890029	f	\N
0f17c29d-e5d7-4488-9b03-639d5a446fe6	b10c80be-b76f-4182-b18b-26495c71700c	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:53:24.890029	f	\N
a5c1866b-52f6-449f-92ca-b53d4857b4e3	b10c80be-b76f-4182-b18b-26495c71700c	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:53:24.890029	f	\N
6ff1e237-a56e-4efc-b811-24ce68980b5d	b10c80be-b76f-4182-b18b-26495c71700c	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:53:24.890029	f	\N
b18c3cd7-6fc8-421f-a0a7-ac057252f318	b10c80be-b76f-4182-b18b-26495c71700c	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:53:24.890029	f	\N
9d3fd7de-8ff0-4e6d-8701-a4604a515c3f	c987746c-1945-4170-a67d-19e8eabfbffc	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:53:24.990083	f	\N
3b1f9397-f5af-4d05-8db4-1fd3c0998225	c987746c-1945-4170-a67d-19e8eabfbffc	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:53:24.990083	f	\N
b359f547-fe3c-458b-8308-980b9bf576f5	39981124-6a61-421f-912f-6dbee57849eb	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 22:55:03.084909	f	\N
a34a2e9c-6fa3-495f-8de4-adc29e5e0afe	39981124-6a61-421f-912f-6dbee57849eb	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 22:55:03.084909	f	\N
a36434bb-37a5-4409-9670-821cb4d30064	39981124-6a61-421f-912f-6dbee57849eb	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 22:55:03.084909	f	\N
9b92a87b-c152-444b-b4ba-03a8c6906d5c	39981124-6a61-421f-912f-6dbee57849eb	6ebd741f-cf0c-410d-8176-eb547c2aadef	2025-07-07 22:55:03.084909	f	\N
f9ca246e-b85b-444c-9211-0b15cc51d78d	39981124-6a61-421f-912f-6dbee57849eb	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 22:55:03.084909	f	\N
4d9a5fce-4ddd-402a-b32e-eb792ce5be62	39981124-6a61-421f-912f-6dbee57849eb	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 22:55:03.084909	f	\N
c8c8520b-ac90-4ad2-9880-21a1b0e696c1	39981124-6a61-421f-912f-6dbee57849eb	77cb0efd-7382-435d-9df0-95dd8ef7e4c7	2025-07-07 22:55:03.084909	f	\N
ddea18bd-1dac-40af-8c2d-65b04ab88d9b	39981124-6a61-421f-912f-6dbee57849eb	9ac4e667-a917-4378-8435-f739ef083de6	2025-07-07 22:55:03.084909	f	\N
101b81a8-fc55-408e-8fef-491d44983d18	57e87ec4-f54f-4b6a-bb8b-018a0d606b28	ec045c87-58b3-4fc9-a484-dd54ffa6c27d	2025-07-07 23:12:47.13384	f	\N
df6eb780-4872-4074-b76c-6a9cdc0ee4e5	57e87ec4-f54f-4b6a-bb8b-018a0d606b28	472246b4-dde0-4f65-8ac9-d5d72abb5072	2025-07-07 23:12:47.13384	f	\N
1c4fd0fb-cdfe-4aa9-90fe-47f77226da18	57e87ec4-f54f-4b6a-bb8b-018a0d606b28	05903b18-d7d7-4992-a248-cce08f5af93b	2025-07-07 23:12:47.13384	f	\N
9d818fbf-7dbe-4a73-9f92-8739fea13838	57e87ec4-f54f-4b6a-bb8b-018a0d606b28	9c9bb9ae-1d21-4337-a843-c5b09e6f361c	2025-07-07 23:12:47.13384	f	\N
8dbebf57-9a1f-48cc-9846-9f9d5b02aebd	57e87ec4-f54f-4b6a-bb8b-018a0d606b28	0ec333ea-ed6b-4624-92d1-bd1cad564e1a	2025-07-07 23:12:47.13384	f	\N
\.


--
-- Data for Name: phrases; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.phrases (id, content, hint, difficulty_level, is_global, created_by_player_id, created_at, is_approved, usage_count, phrase_type, language) FROM stdin;
85b901dc-1a3f-4d52-9953-3accb3f69680	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 09:41:36.220204	t	0	custom	en
bfbf6735-ca14-40b6-a3d8-3c9cc57e97fc	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 09:41:36.241518	t	0	custom	en
86e2d838-ce0b-43f7-97f6-99e3a2b90295	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 09:41:36.291112	t	0	custom	en
4180d35c-dba8-45c2-b448-7c72db212f8d	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 09:41:36.309998	t	0	custom	en
f9758961-a796-44fc-a23e-5c4d68d50179	Dsaf Ff	Unscramble these 2 words	46	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:27:13.136888	t	0	custom	en
e0934ec2-00db-4f1a-8cc2-d9f0cbb9c722	Sda Sdaf	Sadf	35	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:51:09.695739	t	0	custom	en
b0d80fe0-93a0-4504-b38d-0c8dada46a54	Asdf Asdfa Adsafads Adfsa Sd	Ffd	28	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:28:56.113609	t	0	custom	en
9a1d95e0-471a-4c56-b8db-0ad800c29ae3	fasd Dsfa	Fdsadf	43	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:14:00.177344	t	0	custom	en
224517ff-9833-4684-bd20-31bcb5ac160a	Burk Lurk	Bb	60	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:57:26.756665	t	1	custom	en
b091b3dc-6663-4aaf-b7b8-76fe84b5911a	integration test phrase	Unscramble these 3 words	37	f	bd2fc8a5-52db-46f0-9436-8d1ad8e09e2d	2025-07-08 15:10:58.246979	t	0	custom	en
9a85fce8-fb61-4717-9a2e-e67265709c8a	integration test phrase	Unscramble these 3 words	37	f	2bdfae9b-9aa1-4037-a50d-99815d4b3b98	2025-07-08 15:12:20.33748	t	0	custom	en
1f38cc22-3ca6-46f2-b427-75ac2c846694	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:12:28.562839	f	1	custom	en
105ec468-6d2a-4e39-899e-0ed3358425eb	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:20:33.736788	t	0	custom	en
0ac9db6d-7783-4870-b796-fa604239c760	sample validation message	This helps verify data structure correctness	45	t	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:20:33.841879	f	0	custom	en
78b79d72-90ab-4dc9-be8c-a074e8018868	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:22:13.264008	f	1	custom	en
e9f19d8a-d0a4-420d-bbf8-6f2bbde43f73	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:22:19.366247	t	0	custom	en
a2330fc3-f4cc-436a-aecf-2c24f2d00980	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:22:19.370231	t	0	custom	en
784bf70e-fcab-444c-a4d6-afcc350039ee	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:22:19.384844	t	0	custom	en
cdf2ceac-a0ff-488f-9453-ef09a877388d	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:22:19.398237	t	0	custom	en
0857b332-4967-41da-97fe-b5116a92667e	status test phrase	Unscramble these 3 words	38	f	efb1c13f-a7e1-47fc-968f-3f93723366e8	2025-07-08 15:22:31.522388	t	0	custom	en
cb17ef7d-581f-4bfe-a00a-bb9290d7bcba	hello world amazing test	Testing the new enhanced endpoint	77	f	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.8311	f	0	custom	en
ee27f4a3-bf4d-4c48-aaee-93e6d13578f2	global test phrase for everyone	Available to all participants	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.85644	f	0	community	en
756c998a-2708-46b0-93f6-03206241e6ce	multi target test phrase	Challenge for multiple recipients	43	f	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.861627	f	0	challenge	en
18aa2a27-21b6-4e8a-8424-0c6f8a3c93e1	validation test phrase	Unscramble this challenging message	44	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.880179	f	0	custom	en
d6af1639-a3c9-464f-bca2-9f07e2471dd6	level 1 sample words	Unscramble this level 1 message	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.883804	f	0	custom	en
80b1fea2-d477-451b-a2d6-72dff30cb92f	level 2 sample words	Unscramble this level 2 message	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.885203	f	0	custom	en
ac76522e-9981-47f4-b80d-02bf02c47d7f	level 3 sample words	Unscramble this level 3 message	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.887082	f	0	custom	en
b910b118-7849-4f44-b602-f19066d891bc	level 4 sample words	Unscramble this level 4 message	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.899772	f	0	custom	en
2e428131-81d2-4b19-adf1-339e364b41d5	level 5 sample words	Unscramble this level 5 message	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.901281	f	0	custom	en
63b11778-7458-4c89-8dfd-a3ec65a41c15	custom type test phrase	Testing custom phrase type	44	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.903744	f	0	custom	en
8e7e6249-7a53-47b1-a884-88c384549d40	global type test phrase	Testing global phrase type	47	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.905669	f	0	global	en
61214ca4-4445-4d33-8e9f-ff9749984600	community type test phrase	Testing community phrase type	45	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.908009	f	0	community	en
5d095fe2-7558-412e-a14a-d64b025d16d5	challenge type test phrase	Testing challenge phrase type	43	t	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.910408	f	0	challenge	en
5e694415-96ea-4577-b56a-bd9cefc7515a	sample output testing demo	Check the enhanced data format	45	f	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.914706	f	0	custom	en
49ddf61c-d338-4edd-a00c-83159d6e25a2	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:27:45.648372	t	0	custom	en
b07a5fb6-9c1d-4544-bb05-303219d34dcc	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:27:45.847408	f	1	custom	en
e1f3a24c-4db6-4314-b822-b59e407e9f75	hello world	A simple greeting	45	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:48:38.590821	f	0	custom	en
596025a8-8b2c-41a0-89e5-60ee0ae852b7	difficult anagram puzzle challenge	This is quite complex	91	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:48:38.596696	f	0	custom	en
836b23a1-5ae4-471b-8d5b-ccd8836042ef	quick brown fox jumps	Classic pangram phrase	100	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:48:38.601515	f	0	custom	en
bad18cad-dde0-47d5-a2d7-31aa4a1147ee	scoring system test	Testing our new feature	41	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:48:38.604372	f	0	custom	en
c7458654-b9b4-4b13-a17d-ddc83d6ad0d8	leaderboard ranking	Competition system	48	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:48:38.607107	f	1	custom	en
e5b1b135-f3af-4aed-836f-a8780793320a	hello world amazing test	Testing the new enhanced endpoint	77	f	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.470572	f	0	custom	en
479928e4-e4e9-4999-b313-9e133eb79931	global test phrase for everyone	Available to all participants	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.473212	f	0	community	en
9862b697-7931-42d2-b0cb-5d5fe1507014	multi target test phrase	Challenge for multiple recipients	43	f	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.47556	f	0	challenge	en
6f8ecdf0-c743-4a45-acd7-91d7591f5d29	validation test phrase	Unscramble this challenging message	44	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.485262	f	0	custom	en
8c1edd7f-fc50-4389-ae5f-fdcc6c6b8617	level 1 sample words	Unscramble this level 1 message	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.518346	f	0	custom	en
62fb29a4-fa65-4b99-8393-7875a94e17f1	level 2 sample words	Unscramble this level 2 message	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.520852	f	0	custom	en
3c34a7d7-151d-40d8-9bd4-fdcef55ec2a2	level 3 sample words	Unscramble this level 3 message	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.522884	f	0	custom	en
ab1f10a7-a5e9-46c6-a0ce-2dc3cda78827	level 4 sample words	Unscramble this level 4 message	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.531699	f	0	custom	en
ef4d014f-c45c-4bae-8797-87615ca5e9e6	level 5 sample words	Unscramble this level 5 message	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.5361	f	0	custom	en
9209c2c3-bd7f-4480-aca3-fb24fc8ad4a1	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 10:53:33.736747	f	1	custom	en
17224f05-9efb-4952-9170-146f227d9bee	Fralla Fin	Bröd gröt	46	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:36:25.86025	t	0	custom	en
64c06c75-dd75-4af2-ad66-4e49803cf957	Hej Banan	Frukt hojt	82	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:39:40.864083	t	0	custom	en
323556c4-b8dc-44f9-8fe5-fa116da2c488	asd Asdf	Sdaf	35	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:53:18.41053	t	0	custom	en
c46f5c1d-3e08-4df6-8340-7e0109e36b2c	Sadf Asdf	Sadf	43	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:55:02.458216	t	0	custom	en
5d555474-26e5-4a64-bc1a-cc2f9f86b548	Adsf Dfsa	Ff	47	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:39:38.68437	t	0	custom	en
45809dbd-6adb-43e0-b445-897a908ce827	Hej Tomte	Hello santa	83	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:17:31.69487	t	1	custom	en
a2b44fb9-0fc2-4fc9-a165-f1c7a673b272	Sdaf Dfsa Dfsa Dfs	Fds	35	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:58:42.735349	t	0	custom	en
cde0d416-d0f3-4f83-953a-a09e0583e3ab	hello world amazing test	Testing the new enhanced endpoint	77	f	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.285899	f	0	custom	en
47330fad-3226-41fe-99e3-6c97a2ad9c25	global test phrase for everyone	Available to all participants	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.314172	f	0	community	en
dfba3b62-02f3-4f8b-8a28-e6dc23ec69f0	multi target test phrase	Challenge for multiple recipients	43	f	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.317074	f	0	challenge	en
c0d5097d-fb64-4230-852f-272ac3a7758a	validation test phrase	Unscramble this challenging message	44	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.329482	f	0	custom	en
97627b31-10e8-447c-9ac7-7bd4a12b3c44	level 1 sample words	Unscramble this level 1 message	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.368219	f	0	custom	en
b4b46da4-35d8-451c-99dc-ed02d3055fb7	level 2 sample words	Unscramble this level 2 message	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.371023	f	0	custom	en
f134b2d6-a95d-4b44-b9ba-30c5b174c2ac	level 3 sample words	Unscramble this level 3 message	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.383636	f	0	custom	en
1364604e-b5d4-462b-b09c-eaac4abe0d7e	level 4 sample words	Unscramble this level 4 message	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.386505	f	0	custom	en
5941ac36-e47f-42c1-92be-5662431ce299	level 5 sample words	Unscramble this level 5 message	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.400339	f	0	custom	en
b80915a7-07e8-4c72-ab55-50a761354be4	custom type test phrase	Testing custom phrase type	44	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.404027	f	0	custom	en
d30050dd-196a-4397-84e7-09e01c92c174	global type test phrase	Testing global phrase type	47	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.411877	f	0	global	en
5b99dd82-2068-472f-b537-90c51a2af60d	community type test phrase	Testing community phrase type	45	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.415464	f	0	community	en
a2622ec7-3fb5-4df4-a90d-8e4ffe093807	challenge type test phrase	Testing challenge phrase type	43	t	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.417516	f	0	challenge	en
4509f9fc-3291-4af7-9a2b-aea29e92b22d	sample output testing demo	Check the enhanced data format	45	f	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.421891	f	0	custom	en
7cce2a2f-ffce-4e14-b12d-1a1f9c1d2c3f	hello world amazing test	Testing the new enhanced endpoint	77	f	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.439865	f	0	custom	en
64f3c057-31a0-4356-8318-81af72c61d56	global test phrase for everyone	Available to all participants	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.454392	f	0	community	en
5fb475f5-31b7-4dfd-997c-744b2557928e	multi target test phrase	Challenge for multiple recipients	43	f	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.457481	f	0	challenge	en
fcb8f932-b4f8-4edc-ae2b-c7bc89439b4d	validation test phrase	Unscramble this challenging message	44	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.482944	f	0	custom	en
791efcc6-05a0-4a31-befc-48883d87473d	level 1 sample words	Unscramble this level 1 message	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.488397	f	0	custom	en
024fcae6-31ee-4158-bcf3-e202e2a9c896	level 2 sample words	Unscramble this level 2 message	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.502669	f	0	custom	en
d6a875c1-62b8-45f2-89e8-1e20bfaffb0f	level 3 sample words	Unscramble this level 3 message	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.504533	f	0	custom	en
ce2ac171-b9ee-4cad-9f61-1d6a12ed1664	level 4 sample words	Unscramble this level 4 message	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.50638	f	0	custom	en
14a0005f-c5be-4bcf-97e6-c5e94db78d0d	level 5 sample words	Unscramble this level 5 message	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.511802	f	0	custom	en
35b2dbb9-8ad2-45da-907d-d30179e79e45	custom type test phrase	Testing custom phrase type	44	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.515572	f	0	custom	en
001b4c1c-69a4-46cf-a296-6c6b88991f48	global type test phrase	Testing global phrase type	47	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.518342	f	0	global	en
157d5d30-471b-4aba-b2d7-41af19d62c7f	community type test phrase	Testing community phrase type	45	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.520095	f	0	community	en
58d003d3-3bbb-4288-b5d3-cdd34af260a9	challenge type test phrase	Testing challenge phrase type	43	t	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.52166	f	0	challenge	en
c3547be5-5de2-450a-9d2f-f7a267ea95bd	sample output testing demo	Check the enhanced data format	45	f	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.5302	f	0	custom	en
ce89caf6-c0c6-4f0e-ba75-b03e8afa1565	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:16:48.098242	t	0	custom	en
b6cb542f-36bc-4c02-8b5b-d92a9f47f070	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:20:55.723408	f	0	custom	en
af3c4613-ce76-4985-ac9e-c7142e829348	integration test phrase	Unscramble these 3 words	37	f	8b162299-7933-4498-a8b9-a9f271f37fda	2025-07-08 15:22:30.89998	t	0	custom	en
f7c733fe-1463-41a8-91ec-6ec5043ef4e8	hello world amazing test	Testing the new enhanced endpoint	77	f	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.948627	f	0	custom	en
ac2b5126-cc89-4938-ae5e-3c8f8390e5b1	global test phrase for everyone	Available to all participants	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.951326	f	0	community	en
ddc9820d-fb26-4332-9d98-68de9e701238	multi target test phrase	Challenge for multiple recipients	43	f	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.954512	f	0	challenge	en
149b0b99-b9dc-4631-838a-a8521bbb7b72	validation test phrase	Unscramble this challenging message	44	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.969847	f	0	custom	en
be7133aa-bdff-486c-85d0-e54845482fe8	level 1 sample words	Unscramble this level 1 message	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.9826	f	0	custom	en
ad5f54d8-ec08-448c-b7b3-e124c5e284fd	level 2 sample words	Unscramble this level 2 message	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.985567	f	0	custom	en
0b57465d-3c0d-4cce-a1b2-91bd50ea0668	level 3 sample words	Unscramble this level 3 message	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.99331	f	0	custom	en
81252cd5-6a56-47dd-b103-c6b8f7ea0577	level 4 sample words	Unscramble this level 4 message	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.995643	f	0	custom	en
8bded731-fccb-46f3-980a-18c7f6603020	level 5 sample words	Unscramble this level 5 message	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.997559	f	0	custom	en
2c042189-8030-4da9-a4c3-46048a4ce7b8	custom type test phrase	Testing custom phrase type	44	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:31.000955	f	0	custom	en
ba9a232e-1966-42f8-b9d4-b6ba97ccd1ff	global type test phrase	Testing global phrase type	47	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:31.006376	f	0	global	en
34f677a1-0949-4c70-be16-1e9e630ac4e0	community type test phrase	Testing community phrase type	45	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:31.017775	f	0	community	en
890fef27-b06e-4017-bab6-5e12272e85bb	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 10:56:08.094774	f	1	custom	en
72a2b0bc-cfb2-4733-be2a-d7e47538184e	Kolla Balla	Stor	47	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:41:59.519845	t	0	custom	en
4fa027c3-df86-4f14-bab5-aaa7d56d136e	Sdaf Adsf	Asdf	47	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:11:24.936565	t	0	custom	en
ce537516-568f-4f11-98fb-e49bcafbb173	Dsf Ff D	Fd	47	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:57:26.372045	t	0	custom	en
15a1e19b-63da-431a-975c-81b4e255dc1c	ffdfs Fd	Fd	49	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:57:37.476895	t	0	custom	en
78aea051-45e7-4f78-afab-316743eb9670	Sfda Asfdf	Fsadf	41	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:24:17.319196	t	0	custom	en
6c4d0520-dda0-473e-8565-721215b6056e	integration test phrase	Unscramble these 3 words	37	f	d9938742-8ff0-4fff-9658-cdb081b44642	2025-07-08 15:03:47.706124	t	0	custom	en
95f0b122-e29a-4ed6-98aa-b2f64b0f59f5	approve this global phrase	Unscramble these words to solve the puzzle	49	t	90cb8121-5522-434d-bb56-4ed42e6dc46d	2025-07-08 15:10:58.616975	t	0	community	en
65f65708-79fa-44ac-9f88-38c242a3f23e	reject this targeted phrase	Solve this scrambled text puzzle	56	f	90cb8121-5522-434d-bb56-4ed42e6dc46d	2025-07-08 15:10:58.682754	f	0	custom	en
4065376d-53c9-48ba-884a-037d1c73160f	already approved phrase test	Unscramble these words to solve the puzzle	47	t	2d71cfee-9f20-4c61-a04e-6fff0c5db83c	2025-07-08 15:10:58.739086	t	0	community	en
018488fc-83fb-411e-9122-9085e8828941	response format test phrase	Unscramble these words to solve the puzzle	41	t	77f4b9eb-d615-4587-b7f0-23100eca9be4	2025-07-08 15:10:58.749063	t	0	community	en
fd6f9f08-c4e1-439c-a5d0-fedb6f5ba57e	visibility test global phrase	Unscramble these words to solve the puzzle	48	t	2a5c2de9-5dec-401e-8c8c-9ac4fa9b1ef5	2025-07-08 15:10:58.755422	t	0	community	en
8642657f-c655-4cda-9a5b-95a7e1b49b00	test phrase for skip validation	Unscramble these 5 words	48	f	ed0f1492-463e-4850-b920-48176cd9eb84	2025-07-08 15:10:58.856949	t	0	custom	en
123f1dfd-f0d1-49d9-b5ce-d4039319c2bf	test phrase for consume validation	Unscramble these 5 words	44	f	ed0f1492-463e-4850-b920-48176cd9eb84	2025-07-08 15:10:58.891807	t	0	custom	en
c33a52b9-1149-4a46-b6b7-a188070a002f	approve this global phrase	Unscramble these words to solve the puzzle	49	t	bb67393c-1a22-46ce-b4d1-c6553f908001	2025-07-08 15:12:20.58421	t	0	community	en
88712952-32a9-4ba6-a9e6-b42b2198f44b	reject this targeted phrase	Solve this scrambled text puzzle	56	f	bb67393c-1a22-46ce-b4d1-c6553f908001	2025-07-08 15:12:20.603952	f	0	custom	en
8dadaac3-eccc-49b5-83cb-7a6e29231669	already approved phrase test	Unscramble these words to solve the puzzle	47	t	de837188-65c0-4abe-8536-bc6b8d8e851b	2025-07-08 15:12:20.613687	t	0	community	en
9d728532-4336-4703-b53e-6376a5f30af3	response format test phrase	Unscramble these words to solve the puzzle	41	t	1e7fc343-667c-42fd-9c03-ac0b379e723e	2025-07-08 15:12:20.631185	t	0	community	en
2dd71308-ff9f-44ae-830f-97603806d77a	visibility test global phrase	Unscramble these words to solve the puzzle	48	t	81d6384f-1864-4204-89c8-1e83f1ab8cae	2025-07-08 15:12:20.639288	t	0	community	en
545bb838-f096-4126-85d5-a669f9fd4b9a	test phrase for skip validation	Unscramble these 5 words	48	f	6c9aa9d8-ddaf-4217-87ba-b751fc43721c	2025-07-08 15:12:20.658522	t	0	custom	en
53b583d7-0cf6-41a9-9fa4-8480c74d5f56	test phrase for consume validation	Unscramble these 5 words	44	f	6c9aa9d8-ddaf-4217-87ba-b751fc43721c	2025-07-08 15:12:20.68795	t	0	custom	en
cf772388-e002-4a1f-bee8-0f064b085d4a	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:18:59.23472	t	0	custom	en
8e55081a-558e-4df7-ac95-fd1c843b803b	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:21:04.805134	t	0	custom	en
9fa16656-d001-4989-8e12-92eed09aa275	sample validation message	This helps verify data structure correctness	45	t	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:21:04.832103	f	0	custom	en
434e0247-926c-43e4-b032-f95db636e050	challenge type test phrase	Testing challenge phrase type	43	t	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:31.019767	f	0	challenge	en
0d9ae418-452b-43b9-8c24-116d454c0c78	sample output testing demo	Check the enhanced data format	45	f	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:31.021894	f	0	custom	en
ef8e56f0-9aa2-4970-a538-58d2ffb45eff	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:27:33.114371	t	0	custom	en
6d30e99b-d717-470e-a0b5-26e73ee91412	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:27:33.137031	t	0	custom	en
83f175a0-f485-455c-a995-bbddc4b3d585	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:27:33.14913	t	0	custom	en
66c8aaab-6742-4377-b0b2-f158930f4db8	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:27:33.195767	t	0	custom	en
41b97d11-bead-4aa2-a823-fb531e6ab75d	approve this global phrase	Unscramble these words to solve the puzzle	49	t	984dfa6d-eb55-4031-b487-d71fd9789362	2025-07-08 15:27:44.989615	t	0	community	en
85e086b4-39e9-44f1-95a9-722295610449	reject this targeted phrase	Solve this scrambled text puzzle	56	f	984dfa6d-eb55-4031-b487-d71fd9789362	2025-07-08 15:27:44.995767	f	0	custom	en
0218fad3-90bc-4150-844a-2dc2794eb257	already approved phrase test	Unscramble these words to solve the puzzle	47	t	ad356dc5-9a40-4557-a27a-9f220d47ac29	2025-07-08 15:27:45.022873	t	0	community	en
85fc45d0-897b-4b69-bc6c-ca50637ef0e3	response format test phrase	Unscramble these words to solve the puzzle	41	t	3bfc2008-f6ec-45da-9de6-5d773fb39f67	2025-07-08 15:27:45.029592	t	0	community	en
1238d361-2c9e-4cd3-b535-4eda4b54ca01	visibility test global phrase	Unscramble these words to solve the puzzle	48	t	9b007f97-dc5c-47ae-878a-c8fc334e6d42	2025-07-08 15:27:45.039995	t	0	community	en
a9122e5c-bf60-40bd-8863-9b8f029164ca	test phrase for skip validation	Unscramble these 5 words	48	f	b26ea39c-b24f-4996-a041-6cdd08270c48	2025-07-08 15:27:45.062022	t	0	custom	en
94476c1d-448b-4250-9dbf-3aed567bc174	test phrase for consume validation	Unscramble these 5 words	44	f	b26ea39c-b24f-4996-a041-6cdd08270c48	2025-07-08 15:27:45.068793	t	0	custom	en
31885176-3611-4c19-b01f-343d625e94ff	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:27:45.716897	f	0	custom	en
115c22fd-e496-4bb1-b688-241e2f0b0d6d	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:27:46.592359	t	0	custom	en
a78425e5-c862-4035-9788-105c8a5b769c	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:27:46.682993	f	0	custom	en
583ef98d-4df3-43d6-8d85-0a3fc9365940	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:50:43.858463	t	0	custom	en
14cb84fe-e4a8-4c4d-a0b4-1197f5307494	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:50:43.865465	t	0	custom	en
7c208952-b16a-4ee7-ad2f-27b413d9171e	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:50:43.871458	t	0	custom	en
5526d3e7-9ea3-4800-8618-0e99a7d4e527	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:50:43.875271	t	0	custom	en
b14b643b-1491-45a7-bd38-2a3fd9d52a86	custom type test phrase	Testing custom phrase type	44	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.542973	f	0	custom	en
7be7cfb8-8756-44f9-a83f-65882c9b4d26	global type test phrase	Testing global phrase type	47	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.559068	f	0	global	en
9c6b9fcc-9d1c-4ca4-a362-c79135cba50d	community type test phrase	Testing community phrase type	45	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.562188	f	0	community	en
f32a8e07-5d92-4b45-89fe-d49be7e25079	challenge type test phrase	Testing challenge phrase type	43	t	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.567416	f	0	challenge	en
344af6d4-514e-47ef-8664-32ba327d266d	sample output testing demo	Check the enhanced data format	45	f	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.570435	f	0	custom	en
c65b7e36-f137-4828-a2aa-4b5a002849e4	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:50:56.433073	t	0	custom	en
613bf27a-468d-4f4f-9aa1-bb5b6e025a2d	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:50:56.525092	f	0	custom	en
97a9b7f5-d61f-42a9-983b-aa352cec8390	hello world	A common greeting phrase	45	f	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 11:19:43.774895	f	0	custom	en
8d31b54a-b320-4dfa-8305-0b97b186d6fc	hello world	Unscramble these 2 words	45	f	081ebacd-08a6-4ba8-b55a-914f88c8b7bd	2025-07-08 11:20:08.015631	t	0	custom	en
9f92f01f-9073-435d-a8b9-b4998abe5d17	Sadf Asdf	Sadf	43	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:44:59.749771	t	0	custom	en
84aa0fcb-19ac-4e36-89ec-ff980138a783	Asd Asdf	Sdaf	35	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:45:14.375294	t	0	custom	en
fbd1453e-406e-4afb-962d-1d74dd6dde78	sdf D	Sdaf	49	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:21:14.530883	t	0	custom	en
6159195f-45a9-4194-a9fc-fceebb8ea351	Sad Asdf	Dsfa	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:22:24.013043	t	0	custom	en
9373b647-6778-42ab-a0df-3c51d4daf120	Ff Ff Ff	Ss	38	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:03:43.965234	t	1	custom	en
9734aee3-d8f4-489b-9750-1be4ad374afe	Fasd Asdf	Dsfa	38	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:04:50.199998	t	0	custom	en
bea8e03d-196f-4171-9b6b-5491f4c3717f	AsD Ads	F	42	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:26:07.704222	t	0	custom	en
2f4afe5f-a586-4075-a99b-d7c9b7b87683	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:05:24.634699	f	1	custom	en
ec75d8f7-2d50-4e88-b8e6-6bdbbf31350e	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:06:48.614175	t	0	custom	en
4a9d504b-b56b-4afb-a038-89a9f11f4419	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:06:48.642598	t	0	custom	en
76f6a31d-fb49-484f-b2dd-6f8965f15f23	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:06:48.647689	t	0	custom	en
ae4a2ae8-dbe0-4938-a00c-27834e4c1c0e	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:06:48.663257	t	0	custom	en
e3292026-70d3-4274-9caa-e3ca66622b24	status test phrase	Unscramble these 3 words	38	f	ed0f1492-463e-4850-b920-48176cd9eb84	2025-07-08 15:10:58.916077	t	0	custom	en
cb46c8ec-e7e9-4319-9839-a6eda8afb0f8	status test phrase	Unscramble these 3 words	38	f	6c9aa9d8-ddaf-4217-87ba-b751fc43721c	2025-07-08 15:12:20.73946	t	0	custom	en
8e5b9816-95a6-4e06-a11b-47f44d593302	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:19:58.435402	f	0	custom	en
a7ba5832-5ca7-44ef-802b-e1c252d3969d	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:20:09.938645	f	0	custom	en
f5c59b42-3359-4acb-b734-208258e8a8b5	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:22:05.45523	t	0	custom	en
38173e98-b509-4f9b-8e17-8950ce841870	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:22:13.027102	t	0	custom	en
db2e707a-94fa-4a95-a6ed-cbf65c22e9e9	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:22:13.118749	f	0	custom	en
41947853-81b6-4e16-99f4-e6984cc56182	approve this global phrase	Unscramble these words to solve the puzzle	49	t	9184ce0e-f656-4070-8d6d-08e9fa748480	2025-07-08 15:22:31.123093	t	0	community	en
87bf3c51-6778-4b8b-9450-546b64ece630	reject this targeted phrase	Solve this scrambled text puzzle	56	f	9184ce0e-f656-4070-8d6d-08e9fa748480	2025-07-08 15:22:31.15576	f	0	custom	en
84a349a8-8cbe-4bc5-93dc-61cd4869fb99	already approved phrase test	Unscramble these words to solve the puzzle	47	t	747fcd7f-94b4-450f-8f4c-d656a89beda9	2025-07-08 15:22:31.200399	t	0	community	en
f4a32fea-a30d-4cef-ac5e-021ed9f02a99	response format test phrase	Unscramble these words to solve the puzzle	41	t	f564d20f-590c-4d35-a271-04e86d40518d	2025-07-08 15:22:31.295699	t	0	community	en
f0c549aa-4076-4849-8fa5-efe6d4ee8499	visibility test global phrase	Unscramble these words to solve the puzzle	48	t	46f7b5e0-cc46-4487-a983-d83755492142	2025-07-08 15:22:31.317919	t	0	community	en
0aafbe1e-33e2-48d4-bff5-f8374f9879fd	test phrase for skip validation	Unscramble these 5 words	48	f	efb1c13f-a7e1-47fc-968f-3f93723366e8	2025-07-08 15:22:31.456793	t	0	custom	en
ece2519a-3bdf-4e67-8310-6c05324e4ecb	test phrase for consume validation	Unscramble these 5 words	44	f	efb1c13f-a7e1-47fc-968f-3f93723366e8	2025-07-08 15:22:31.486436	t	0	custom	en
d4366ef0-c831-422c-a1f3-14790138ced3	integration test phrase	Unscramble these 3 words	37	f	bb6e5dff-0e61-4de4-9e9e-fc0997cd69f9	2025-07-08 15:27:44.688902	t	0	custom	en
5b4635d2-bce3-42a6-bb87-e456b7b6c38d	status test phrase	Unscramble these 3 words	38	f	b26ea39c-b24f-4996-a041-6cdd08270c48	2025-07-08 15:27:45.080994	t	0	custom	en
9dda1183-9207-48a5-9fad-36441667b57c	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:27:46.836554	f	1	custom	en
c9dfca9d-fa18-4703-bd19-4dfe041ba400	hello world	A simple greeting	45	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:42:39.179359	f	0	custom	en
7887a3bb-25df-4b6c-b375-8b99db7e5835	difficult anagram puzzle challenge	This is quite complex	91	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:42:39.193643	f	0	custom	en
07e1a595-7eba-4dbc-a1d7-ca6278e25fb0	quick brown fox jumps	Classic pangram phrase	100	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:42:39.214298	f	0	custom	en
f0560555-68d5-4ba4-83f9-98cfd7e43470	scoring system test	Testing our new feature	41	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:42:39.221622	f	0	custom	en
76176805-d34a-4610-a40d-265c96b22850	leaderboard ranking	Competition system	48	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:42:39.229967	f	0	custom	en
77fe1215-2c64-4a36-9d40-b1d984fb5bf4	integration test phrase	Unscramble these 3 words	37	f	c0c04d9a-bf94-40b0-9424-7f4157bde78c	2025-07-08 15:50:55.423709	t	0	custom	en
f35affbb-843f-4b39-8c69-68475e7c2c66	approve this global phrase	Unscramble these words to solve the puzzle	49	t	048c6b58-53e0-4b8d-ab7c-431304657dbc	2025-07-08 15:50:55.672622	t	0	community	en
ab3b1b83-9c55-48b9-b98c-298413df30f7	reject this targeted phrase	Solve this scrambled text puzzle	56	f	048c6b58-53e0-4b8d-ab7c-431304657dbc	2025-07-08 15:50:55.686942	f	0	custom	en
833bb935-d695-45a6-80b6-e886298e8b7f	already approved phrase test	Unscramble these words to solve the puzzle	47	t	66b92f69-887d-421e-8465-22537f5ddb14	2025-07-08 15:50:55.712267	t	0	community	en
4622c801-d8ca-4dc2-b679-b8e1f00e054b	response format test phrase	Unscramble these words to solve the puzzle	41	t	be77fd1d-53aa-4395-b3cd-57ed90d38e68	2025-07-08 15:50:55.717055	t	0	community	en
9800a4cb-4a80-48a6-8767-f80413e8aea7	visibility test global phrase	Unscramble these words to solve the puzzle	48	t	a79a6da1-fd72-4206-b4ae-6cdbbf8dd57c	2025-07-08 15:50:55.731546	t	0	community	en
76d33595-d58e-4f5a-9d24-ddf46c8674f6	test phrase for skip validation	Unscramble these 5 words	48	f	13b59552-1c34-45d8-b791-41c33fc2cd28	2025-07-08 15:50:55.806187	t	0	custom	en
f31bdf80-93de-4830-b3b7-2ff9bf7276e5	be kind	A simple act of compassion	20	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
cd4cc122-85ab-4f86-9439-0738f8aec3e3	hello world	The classic first program greeting	20	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
0f1dcebc-4b72-4c0b-a822-41e2c7f5b885	global test phrase for everyone	Available to all participants	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.128245	f	0	community	en
4763492f-5404-41cb-8067-26dfd7492bb7	open door	Access point that's not closed	20	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
30071440-4ab1-41b4-b817-71351faf197a	quick brown fox jumps	Famous typing test animal in motion	60	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
e15ccd29-2bb4-4d17-b21c-8768e404978e	make it count	Ensure your effort has value	40	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
61df6b38-75fc-4d64-92b7-9d2b389cb060	lost keys	Common household frustration	40	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
e3a08c5f-e191-470d-87ea-452a3031fb6d	coffee break	Mid-day caffeine pause	40	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
aacecda5-d93d-416a-8b63-a1e310fdbdcf	bright sunny day	Perfect weather for outdoor activities	40	t	\N	2025-07-07 18:23:03.822646	t	0	custom	en
c5243f0c-bee8-4b99-9702-95d92fdc7f03	test phrase for consume validation	Unscramble these 5 words	44	f	13b59552-1c34-45d8-b791-41c33fc2cd28	2025-07-08 15:50:55.833782	t	0	custom	en
b5bf74f4-f3b9-4e2e-b9b9-6bc840dbafb0	status test phrase	Unscramble these 3 words	38	f	13b59552-1c34-45d8-b791-41c33fc2cd28	2025-07-08 15:50:55.85886	t	0	custom	en
e57d19ed-75d7-46b3-a052-e38b59fa0538	multi target test phrase	Challenge for multiple recipients	80	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.133757	f	0	challenge	en
52643597-5000-4778-9b2f-f19134589f6d	cat dog run	Three animals and an action	40	t	b82e1b95-7ee3-4475-b1d8-46edf4fd60cf	2025-07-07 18:26:50.830207	f	0	custom	en
9168b8fc-853e-4456-bb6f-245f4670217c	cat dog run	Three animals and an action	40	t	b82e1b95-7ee3-4475-b1d8-46edf4fd60cf	2025-07-07 18:28:08.336073	f	0	custom	en
b9200606-efb5-4dc4-9a90-8acc07e26207	time flies	What happens when you're having fun	40	t	\N	2025-07-07 18:23:03.822646	t	1	custom	en
54a2c5a0-257b-4056-b62f-37e38f083711	cat dog run	Three animals and an action	40	t	b82e1b95-7ee3-4475-b1d8-46edf4fd60cf	2025-07-07 18:58:37.922057	f	0	custom	en
579833ef-7c25-4869-8f3d-a4420518e630	code works	Developer's dream outcome	40	t	\N	2025-07-07 18:23:03.822646	t	1	custom	en
a4065dd9-6438-4fa1-9c00-741753903746	restart test phrase	Unscramble these 3 words	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:06.766243	t	0	custom	en
b3878e04-4dd9-425d-b4d0-5d66c9c7c498	hello world test	Unscramble these 3 words	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:15.787159	t	0	custom	en
6bcb0525-de57-4fd2-8481-ea6ca5f5974e	quick brown fox	Famous typing test animal	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:15.792173	t	0	custom	en
1b2a5e3c-1771-4fec-a9f8-b6b78d105108	persistence test phrase	Testing database storage	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:15.80597	t	0	custom	en
b78fd268-c107-43cd-9850-e4b193275b42	targeted test phrase	This phrase is targeted	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:15.839279	t	0	custom	en
33a5d6d1-0a83-472f-b7f4-32d8daae82d3	websocket hint test	WebSocket test hint message	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:16.869433	t	0	custom	en
e3b63d3b-3bcf-48dc-a93b-bfc16f8fe1a0	lifecycle test phrase	Testing full phrase lifecycle	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:05:16.925501	t	0	custom	en
7f5805a4-f491-458f-976c-b6d990e7a964	hello world test	Unscramble these 3 words	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:06.408283	t	0	custom	en
57edc53f-049a-4c75-b635-2055c5a8b0da	quick brown fox	Famous typing test animal	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:06.425262	t	0	custom	en
8df536b9-7a91-4435-a675-a811fd3e8a65	hint response test	Test hint for response validation	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:06.439772	t	0	custom	en
408f906d-b77d-4a31-9d3b-87c14e60c9d9	persistence test phrase	Testing database storage	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:06.47472	t	0	custom	en
82a02934-6cd1-4cff-be1d-558c5c4d414d	targeted test phrase	This phrase is targeted	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:06.518883	t	0	custom	en
1bc015fa-623c-4a30-b572-f46282f4e5a8	websocket hint test	WebSocket test hint message	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:07.542579	t	0	custom	en
c5d09453-4eca-4191-a648-f9e2a546c544	lifecycle test phrase	Testing full phrase lifecycle	20	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:06:07.584227	t	0	custom	en
e21bca9d-fc26-439a-bf22-a4a81a3fba07	test phase four endpoint	Testing the new enhanced phrase creation	60	f	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:28:31.342438	f	0	custom	en
a4c86d4e-5bec-4d9c-9a92-adfb894375bd	global phrase test for community	Unscramble this message for everyone to enjoy	80	t	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:28:58.395221	f	0	community	en
6403f3ed-2ca8-4fc9-9014-3bc6ebc55535	global test phrase for everyone	Available to all participants	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:30:59.220051	f	0	community	en
5956f94c-71cd-4343-b9c8-ae1076376657	validation test phrase	Hi	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:30:59.228202	f	0	custom	en
ea896d64-86ae-4aa1-b886-a175d7268d6f	validation test phrase	Unscramble this challenging message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:30:59.239294	f	0	custom	en
24985e86-2591-4467-ba69-af9c240bdc07	global test phrase for everyone	Available to all participants	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.57663	f	0	community	en
643b57dc-ba7d-40c8-bb65-796df77f1f48	multi target test phrase	Challenge for multiple recipients	80	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.587534	f	0	challenge	en
7894b2e5-46d9-4a36-ba70-dbda835f4130	validation test phrase	Unscramble this challenging message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.612258	f	0	custom	en
51ff5741-e00b-46e6-a39e-fdda90381400	custom type test phrase	Testing custom phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.661911	f	0	custom	en
b046b6de-a74b-4f70-8f48-fa7a25909eea	global type test phrase	Testing global phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.676569	f	0	global	en
74f513b5-e65f-4f2b-b0d5-9c9d4c3e1f65	community type test phrase	Testing community phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.67921	f	0	community	en
0d7ef1f7-fc22-4132-bd3e-e34ba5c3b818	challenge type test phrase	Testing challenge phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:31:49.69541	f	0	challenge	en
f2331484-2050-412b-b025-e4612b616f88	hello world amazing test	Testing the new enhanced endpoint	40	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.11206	f	0	custom	en
4e8fe918-8e7e-4f63-b255-839bbaa6d9d7	validation test phrase	Unscramble this challenging message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.142426	f	0	custom	en
37d19b89-adfa-46e7-b847-e735745ff07c	level 1 sample words	Unscramble this level 1 message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.160408	f	0	custom	en
4b024d53-a55e-4aeb-ac12-2724bdec997e	level 2 sample words	Unscramble this level 2 message	40	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.172695	f	0	custom	en
ca2a948d-3ce3-41c1-a206-7f7bba9412ee	level 3 sample words	Unscramble this level 3 message	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.176448	f	0	custom	en
135ccd9c-2033-485a-a8fc-01e2af415a31	level 4 sample words	Unscramble this level 4 message	80	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.178922	f	0	custom	en
f2891908-1545-4340-8a68-3558984cf654	level 5 sample words	Unscramble this level 5 message	95	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.182648	f	0	custom	en
d64e29ea-d653-4e7c-8a17-c01bcfd61ed9	custom type test phrase	Testing custom phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.188858	f	0	custom	en
bd2d97c7-babe-48a1-8e28-073c88af092f	global type test phrase	Testing global phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.193008	f	0	global	en
54f9bf50-e095-429b-aab6-ad40b9ab3ed0	community type test phrase	Testing community phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.195112	f	0	community	en
acf32216-24b6-44fa-a0fb-2040c62ab0db	challenge type test phrase	Testing challenge phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:31.1974	f	0	challenge	en
7b774ae4-e2f2-4a79-bedf-bf7704bfae11	hello world amazing test	Testing the new enhanced endpoint	40	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.812333	f	0	custom	en
ef17f9ae-164b-4073-821e-45badceb8fa2	global test phrase for everyone	Available to all participants	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.827028	f	0	community	en
3a258e33-e1dd-4680-aeab-86eefdb10ede	multi target test phrase	Challenge for multiple recipients	80	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.841792	f	0	challenge	en
509a4fd0-6b64-439d-85a7-0ba19fb8a60e	validation test phrase	Unscramble this challenging message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.873038	f	0	custom	en
82a0fc80-401d-4a66-bba1-65f840c6fee6	level 1 sample words	Unscramble this level 1 message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.891923	f	0	custom	en
301354c1-8233-4de8-a0f9-2bd7ef3b175d	level 2 sample words	Unscramble this level 2 message	40	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.894501	f	0	custom	en
ff817481-4245-4786-8ea1-578ba3b44991	level 3 sample words	Unscramble this level 3 message	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.95853	f	0	custom	en
9dc6d306-bb0b-4c29-8444-f809a2dd00ff	level 4 sample words	Unscramble this level 4 message	80	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.96304	f	0	custom	en
1e8789b3-1653-4cb6-af79-c183b42b405a	level 5 sample words	Unscramble this level 5 message	95	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.965262	f	0	custom	en
2c71c3c8-bf14-46f9-8361-b828fefa1ea1	custom type test phrase	Testing custom phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.969255	f	0	custom	en
f71ebb7d-0a09-4ae9-a3e3-4015926075d8	global type test phrase	Testing global phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.971107	f	0	global	en
2b20fb64-88f1-4bc3-8642-e9b787e1a65b	community type test phrase	Testing community phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.976185	f	0	community	en
1d7360a1-0a2d-4215-935d-6f96d2037cfd	challenge type test phrase	Testing challenge phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:33:49.991959	f	0	challenge	en
90db795d-8f46-40cd-b4a8-1ba5ac1cdad6	hello world amazing test	Testing the new enhanced endpoint	40	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.291204	f	0	custom	en
0d4e8a5f-f05a-44fd-8c80-c02c5306e02e	global test phrase for everyone	Available to all participants	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.297073	f	0	community	en
528e1963-9f18-4525-af30-df5bdbcf441e	multi target test phrase	Challenge for multiple recipients	80	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.307117	f	0	challenge	en
c7bb72c4-ba1b-47d5-89f9-e36809f623e3	validation test phrase	Unscramble this challenging message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.314156	f	0	custom	en
bc45db55-d06c-427c-b0b9-07f44049243b	level 1 sample words	Unscramble this level 1 message	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.328419	f	0	custom	en
d20a368d-781d-409c-9cf2-9af88d7cfd71	level 2 sample words	Unscramble this level 2 message	40	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.344651	f	0	custom	en
985486c3-9e9d-4a4d-a5b8-8e2458e93da6	level 3 sample words	Unscramble this level 3 message	60	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.347461	f	0	custom	en
ae4997bf-9090-4d86-9026-bfcb3aeba460	level 4 sample words	Unscramble this level 4 message	80	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.360802	f	0	custom	en
fbd94000-ba6e-4ec7-88c1-77cdd5c2be5f	level 5 sample words	Unscramble this level 5 message	95	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.362857	f	0	custom	en
163773e7-0879-469c-bae7-46af18965111	custom type test phrase	Testing custom phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.374903	f	0	custom	en
af3bd04d-117f-4fd3-85a8-202c5f11816e	global type test phrase	Testing global phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.379198	f	0	global	en
669df701-aaa9-49b1-8727-965c2c0ecb4e	community type test phrase	Testing community phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.390251	f	0	community	en
cc5a5b10-9948-4b57-97b0-b62d2d2c7a2b	challenge type test phrase	Testing challenge phrase type	20	t	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.394069	f	0	challenge	en
7fb1438f-ba54-4324-a59b-da2b1803ce22	sample output testing demo	Check the enhanced data format	60	f	d2d3d95a-5a94-4cda-8b13-667e95388d84	2025-07-07 20:34:09.396292	f	0	custom	en
c8299493-e25e-4480-925e-38b278523b1e	hello world test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 20:47:13.555784	t	0	custom	en
4281bd47-0454-4fcd-8356-1e9328e9c6d1	quick brown fox	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 20:47:13.561252	t	0	custom	en
1c0908c3-852b-4457-b46c-5c3feb0e5178	sample phrase creation	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 20:47:13.564524	t	0	custom	en
0da606b5-0c37-4a90-8fa5-61eb48083a68	anagram game test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 20:47:13.573293	t	0	custom	en
e619cf1d-d9f1-4e83-810b-4cb51bda2ab3	hello world amazing test	Testing the new enhanced endpoint	40	f	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.931882	f	0	custom	en
23505cd8-47a1-4652-951b-c27b95a7827f	global test phrase for everyone	Available to all participants	60	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.935397	f	0	community	en
b9b8395b-c4a5-4ec1-9dc7-5e550bb08ce3	multi target test phrase	Challenge for multiple recipients	80	f	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.93821	f	0	challenge	en
20af9f3b-35a3-4fd2-b28f-9e5e5d1804b4	validation test phrase	Unscramble this challenging message	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.94383	f	0	custom	en
e00284ef-94e5-4381-b725-70fd39281c7d	level 1 sample words	Unscramble this level 1 message	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.947794	f	0	custom	en
114a440b-b164-432a-93a4-61731e5e2a53	level 2 sample words	Unscramble this level 2 message	40	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.958354	f	0	custom	en
593356b1-849f-4bce-b987-1c24555121c4	level 3 sample words	Unscramble this level 3 message	60	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.962539	f	0	custom	en
9619baf0-22b8-45d6-b70e-f67971c4c762	level 4 sample words	Unscramble this level 4 message	80	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.964888	f	0	custom	en
50774a29-0396-4580-a3db-aed89646f06b	level 5 sample words	Unscramble this level 5 message	95	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.983402	f	0	custom	en
56c8aae7-e185-4b81-bc80-ff324566aa5c	custom type test phrase	Testing custom phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.989742	f	0	custom	en
a53c9e3e-2c01-4a54-b353-52d764251b14	global type test phrase	Testing global phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.99242	f	0	global	en
54459f81-3752-4129-8a9a-6b6b1f2e5958	community type test phrase	Testing community phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:24.99466	f	0	community	en
ff543ad1-ab18-42d3-a6aa-02233a9731ca	challenge type test phrase	Testing challenge phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:25.000322	f	0	challenge	en
cec48ac7-97fe-45c5-8bb3-848cf9e50073	sample output testing demo	Check the enhanced data format	60	f	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 20:47:25.011982	f	0	custom	en
9f249ec2-3663-45c0-ab80-d5b257070a4d	hello world test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:00:28.130354	t	0	custom	en
360a8cd9-65f7-4b90-86a8-8c50f75ca7cf	quick brown fox	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:00:28.136826	t	0	custom	en
f88410af-2ef3-4664-b9fb-9275b9d34c4f	sample phrase creation	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:00:28.139117	t	0	custom	en
f7c001cc-8cd0-4d92-86f3-9bb2338987d0	anagram game test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:00:28.14991	t	0	custom	en
e7c16160-8be5-4ea0-ae7b-44ff09e391d4	hello world amazing test	Testing the new enhanced endpoint	40	f	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.620763	f	0	custom	en
e8291525-57e3-428e-a0bf-c3d4f9360e34	global test phrase for everyone	Available to all participants	60	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.637152	f	0	community	en
4b494875-dd5e-45b9-b930-40a4d3ad334e	multi target test phrase	Challenge for multiple recipients	80	f	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.640652	f	0	challenge	en
51a39c36-2218-4613-a2ab-9dea999a23d0	validation test phrase	Unscramble this challenging message	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.64825	f	0	custom	en
386db2d2-1b38-4fc6-97e2-1bf57682ff4f	level 1 sample words	Unscramble this level 1 message	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.659712	f	0	custom	en
e78ab08b-1d5c-4960-88e5-e7d4aabd0e9c	level 2 sample words	Unscramble this level 2 message	40	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.661152	f	0	custom	en
3b636077-7271-426d-9f4f-cc02f094d6b4	level 3 sample words	Unscramble this level 3 message	60	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.663243	f	0	custom	en
6716c690-733d-49aa-8a44-62f7737d181a	level 4 sample words	Unscramble this level 4 message	80	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.664911	f	0	custom	en
ecce4f32-17ec-4d3d-b836-a0c695af5e1e	level 5 sample words	Unscramble this level 5 message	95	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.666705	f	0	custom	en
59bb1f9f-eb12-4630-8918-4065a8e1adc2	custom type test phrase	Testing custom phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.672777	f	0	custom	en
e94b43d0-0ba0-4fd5-bd77-1fca5381ae9c	global type test phrase	Testing global phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.687006	f	0	global	en
e274758a-bfdb-4a5e-a704-a7d0d194db1b	community type test phrase	Testing community phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.688702	f	0	community	en
ea916a9e-1b67-459e-9c26-69f6261437fa	challenge type test phrase	Testing challenge phrase type	20	t	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.690547	f	0	challenge	en
cb9e3ecc-d69e-4d0a-a5fe-e249d84680c3	sample output testing demo	Check the enhanced data format	60	f	8299d480-659b-4e06-866a-7da36f85f389	2025-07-07 21:00:39.705565	f	0	custom	en
22c44c20-35f8-4991-9807-58b31749d2ef	hello world test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:01:57.784565	t	0	custom	en
048c6043-e79f-4377-bf9a-2a186e53b6aa	quick brown fox	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:01:57.787706	t	0	custom	en
6bcf9b43-cdee-4bb0-bb9d-a4c284ca5d6b	sample phrase creation	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:01:57.789918	t	0	custom	en
22ee7ff0-6959-4c0f-b955-54593c141139	anagram game test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:01:57.791806	t	0	custom	en
1cc93298-0031-4046-a1f1-3184a29e61c1	hello world test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:04:37.471937	t	0	custom	en
f8893c89-66dd-4dbc-88dc-2145f87b3370	quick brown fox	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:04:37.475585	t	0	custom	en
3a14415c-c06e-40b3-bb8b-59a801f4e4ca	sample phrase creation	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:04:37.487463	t	0	custom	en
70323597-e40d-4b4a-8967-7392c6fd86df	anagram game test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:04:37.490768	t	0	custom	en
c3ef1dad-f504-4f57-873f-13b43739bd2e	integration test phrase	Unscramble these 3 words	20	f	004a92bd-7600-44f3-959d-60e4b8f8d95e	2025-07-07 21:14:22.963768	t	0	custom	en
43287691-4a63-4d43-946a-ce9f1efc156c	integration test phrase	Unscramble these 3 words	20	f	c2cc4bb4-f035-4962-ba11-b4e72f50035a	2025-07-07 21:15:11.565406	t	0	custom	en
1cd4ee2a-cb4f-4e04-89b8-f05618583fa6	hello world test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:15:22.582691	t	0	custom	en
8ba8b674-28b7-459b-bf73-816e9ee0b0db	quick brown fox	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:15:22.59317	t	0	custom	en
398ff63f-9126-4036-959f-be6a2bae716a	sample phrase creation	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:15:22.600547	t	0	custom	en
a067a1f9-5ccf-4f90-81f2-05c0cb7d675f	anagram game test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-07 21:15:22.612378	t	0	custom	en
6ae58199-f644-4897-bac1-d51cf62c69e5	integration test phrase	Unscramble these 3 words	20	f	88e5d907-b590-4a04-adae-3ece35bf8240	2025-07-07 21:15:33.865815	t	0	custom	en
469ed4ad-83eb-4e37-afa2-a2f43cc9eae3	hello world amazing test	Testing the new enhanced endpoint	40	f	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.031638	f	0	custom	en
31aa4176-2529-494a-9f24-7512a0559706	global test phrase for everyone	Available to all participants	60	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.079911	f	0	community	en
bc8d05ee-1255-4800-8281-b4d9673aaaf0	multi target test phrase	Challenge for multiple recipients	80	f	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.104512	f	0	challenge	en
b310361c-4d41-4cee-a686-1a6a09fe5e49	validation test phrase	Unscramble this challenging message	20	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.133247	f	0	custom	en
6143d9c5-117e-4b26-ac7b-e4534b25ac3b	level 1 sample words	Unscramble this level 1 message	20	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.151638	f	0	custom	en
62cd2743-7501-4048-99db-046c84282bcf	level 2 sample words	Unscramble this level 2 message	40	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.154561	f	0	custom	en
36dfd3a5-b531-40c2-ba1a-dedd065a4bba	level 3 sample words	Unscramble this level 3 message	60	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.158892	f	0	custom	en
d1d9400a-9e09-45a8-b03c-9474fa2901d8	level 4 sample words	Unscramble this level 4 message	80	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.165197	f	0	custom	en
d19f4e8b-db18-49a4-b4a3-4802d35233ce	level 5 sample words	Unscramble this level 5 message	95	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.167491	f	0	custom	en
07891fab-c02c-4165-b2f5-b56ebe865b4a	custom type test phrase	Testing custom phrase type	20	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.182601	f	0	custom	en
96ea99df-6cd7-42ab-b09b-975855a9932b	global type test phrase	Testing global phrase type	20	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.188682	f	0	global	en
7a125798-01bf-445b-aef9-393ac250c5db	community type test phrase	Testing community phrase type	20	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.250553	f	0	community	en
e483aeb6-6279-4c45-b7e5-b568c591192a	challenge type test phrase	Testing challenge phrase type	20	t	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.259312	f	0	challenge	en
e27fa831-4575-4da9-bd89-449b0e3f2770	sample output testing demo	Check the enhanced data format	60	f	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:34.263005	f	0	custom	en
88126b19-d929-418c-ab72-fde6d0be8178	test phrase for skip validation	Unscramble these 5 words	20	f	f1e4411f-8b37-4185-9585-22e92a82a04c	2025-07-07 21:47:04.42086	t	0	custom	en
50fcf241-0488-442c-aa98-25218996b7a9	test phrase for consume validation	Unscramble these 5 words	20	f	f1e4411f-8b37-4185-9585-22e92a82a04c	2025-07-07 21:47:04.641167	t	0	custom	en
d25d3133-0b78-4f76-91d4-1b755184a141	status test phrase	Unscramble these 3 words	20	f	f1e4411f-8b37-4185-9585-22e92a82a04c	2025-07-07 21:47:04.905384	t	0	custom	en
20eb1933-d397-4650-a0e0-028cc1a059d4	test phrase for skip validation	Unscramble these 5 words	20	f	c61eaa45-aa2e-41d7-ac8e-c86970348466	2025-07-07 21:48:19.748579	t	0	custom	en
568f03e8-d71c-41e5-94c9-4b6017c4f92e	test phrase for consume validation	Unscramble these 5 words	20	f	c61eaa45-aa2e-41d7-ac8e-c86970348466	2025-07-07 21:48:19.784872	t	0	custom	en
4281438b-c37c-48f9-a7f3-b60000e4fba0	status test phrase	Unscramble these 3 words	20	f	c61eaa45-aa2e-41d7-ac8e-c86970348466	2025-07-07 21:48:19.887838	t	0	custom	en
bbc5454d-ecd6-45ac-894c-eb0e4709d23b	test phrase for skip validation	Unscramble these 5 words	20	f	4aa4ff17-5957-448e-bcd8-901b7c914287	2025-07-07 21:48:56.104376	t	0	custom	en
2f2cd57b-c80b-45c0-951f-532add7cf389	test phrase for consume validation	Unscramble these 5 words	20	f	4aa4ff17-5957-448e-bcd8-901b7c914287	2025-07-07 21:48:56.145364	t	0	custom	en
904d9a10-e048-4e13-b7fa-212f530b4946	status test phrase	Unscramble these 3 words	20	f	4aa4ff17-5957-448e-bcd8-901b7c914287	2025-07-07 21:48:56.290446	t	0	custom	en
8a0a2aa0-5221-4977-bed6-85845d7f5610	test phrase for skip validation	Unscramble these 5 words	20	f	76832a95-e644-4c49-8282-1879003166a4	2025-07-07 21:52:50.212449	t	0	custom	en
ef948f79-78b5-469e-a8a5-6b0e64f3f718	test phrase for consume validation	Unscramble these 5 words	20	f	76832a95-e644-4c49-8282-1879003166a4	2025-07-07 21:52:50.254961	t	0	custom	en
ceabb3c5-dd34-4428-9fa7-2188bc1ac58b	status test phrase	Unscramble these 3 words	20	f	76832a95-e644-4c49-8282-1879003166a4	2025-07-07 21:52:50.522237	t	0	custom	en
12edb476-2a79-42b3-9b44-4d74f7a1eec8	approve this global phrase	Test hint for global phrase	40	t	9eeddf1f-227b-485b-9ab7-c2aa43025593	2025-07-07 22:08:58.99903	f	0	community	en
d4df2b60-9072-4b1a-8a9d-15bf60d80467	approve this global phrase	Unscramble these words to solve the puzzle	40	t	c4b7d178-7c02-44e0-97fe-cb1f8108c7e1	2025-07-07 22:09:47.353902	f	0	community	en
833b6624-7d0e-4f4d-9801-e7068b3c22fa	reject this targeted phrase	Solve this scrambled text puzzle	20	f	c4b7d178-7c02-44e0-97fe-cb1f8108c7e1	2025-07-07 22:09:47.388248	f	0	custom	en
6a55f6fe-104e-480e-8533-5fbbf927040c	already approved phrase test	Unscramble these words to solve the puzzle	40	t	3abcdb2a-a750-4095-99e0-525443896f38	2025-07-07 22:09:47.434256	f	0	community	en
36ab288d-da97-48b6-ada5-7f8a6554d87f	response format test phrase	Unscramble these words to solve the puzzle	40	t	68f83f5d-c9f0-4822-801f-ca0a285a1349	2025-07-07 22:09:47.453923	f	0	community	en
c2ddefca-d0e2-45ea-9608-599a6843a6f7	visibility test global phrase	Unscramble these words to solve the puzzle	40	t	fe43ae0d-3310-4458-9279-c4f25ea79445	2025-07-07 22:09:47.486257	f	0	community	en
0ec333ea-ed6b-4624-92d1-bd1cad564e1a	approve this global phrase	Unscramble these words to solve the puzzle	40	t	53e405ad-4843-45da-b15e-a268c37a43f3	2025-07-07 22:10:43.19568	t	0	community	en
84605adc-5fd4-4fb1-9f0b-9f5c7727f059	reject this targeted phrase	Solve this scrambled text puzzle	20	f	53e405ad-4843-45da-b15e-a268c37a43f3	2025-07-07 22:10:43.232532	f	0	custom	en
9c9bb9ae-1d21-4337-a843-c5b09e6f361c	already approved phrase test	Unscramble these words to solve the puzzle	40	t	eb22082b-b283-4d06-8267-4de309582897	2025-07-07 22:10:43.266327	t	0	community	en
ec045c87-58b3-4fc9-a484-dd54ffa6c27d	response format test phrase	Unscramble these words to solve the puzzle	40	t	3371a4b3-aed8-43c6-b845-79db1c88592d	2025-07-07 22:10:43.284086	t	0	community	en
05903b18-d7d7-4992-a248-cce08f5af93b	visibility test global phrase	Unscramble these words to solve the puzzle	40	t	3839350a-9c43-4d15-8c41-bb060e8b5e74	2025-07-07 22:10:43.304069	t	0	community	en
9ac4e667-a917-4378-8435-f739ef083de6	approve this global phrase	Unscramble these words to solve the puzzle	40	t	44c0515e-c2d3-4145-8432-3f5e9f34a7a0	2025-07-07 22:13:00.527772	t	0	community	en
08941179-0945-42de-8055-6666969192fe	reject this targeted phrase	Solve this scrambled text puzzle	20	f	44c0515e-c2d3-4145-8432-3f5e9f34a7a0	2025-07-07 22:13:00.576322	f	0	custom	en
472246b4-dde0-4f65-8ac9-d5d72abb5072	already approved phrase test	Unscramble these words to solve the puzzle	40	t	a63e5ff9-f50b-430c-a4d5-57cebe8f4f15	2025-07-07 22:13:00.611869	t	0	community	en
77cb0efd-7382-435d-9df0-95dd8ef7e4c7	response format test phrase	Unscramble these words to solve the puzzle	40	t	ab48b17c-78bc-4453-89c8-3fdd5101bbeb	2025-07-07 22:13:00.648579	t	0	community	en
6ebd741f-cf0c-410d-8176-eb547c2aadef	visibility test global phrase	Unscramble these words to solve the puzzle	40	t	e77d7fa3-277c-4c5f-8e3d-271ac0ba1a0a	2025-07-07 22:13:00.685677	t	0	community	en
b48ff951-c8bb-45ef-8c3f-c8dc43f1167c	hello world test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 00:02:31.582154	t	0	custom	en
0ab1478b-05d7-4ad2-8f5a-0a7166b96e7f	quick brown fox	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 00:02:31.596429	t	0	custom	en
01265652-b8c3-47ad-a61a-4b4e277fa18f	sample phrase creation	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 00:02:31.602745	t	0	custom	en
3658f67c-54d8-4a65-bbbb-dff1448321da	anagram game test	Unscramble these 3 words	20	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 00:02:31.610321	t	0	custom	en
207efbe0-a868-4ea4-89c1-2d6675e66fda	integration test phrase	Unscramble these 3 words	20	f	f123666c-7101-42ff-9945-f0a80359edbf	2025-07-08 00:02:42.925972	t	0	custom	en
a61259f7-d065-421b-8c67-b24de665f0b2	hello world amazing test	Testing the new enhanced endpoint	40	f	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.976872	f	0	custom	en
b961b7de-8c61-4239-9852-30d1023c7932	global test phrase for everyone	Available to all participants	60	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.980605	f	0	community	en
cab1199a-4f95-4965-bd91-339b380b9c9a	multi target test phrase	Challenge for multiple recipients	80	f	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.982922	f	0	challenge	en
c2ae8753-2fe8-4db6-b479-ed85218b7bd9	validation test phrase	Unscramble this challenging message	20	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.988324	f	0	custom	en
839b3a50-4b83-4856-ae05-91186ee165ed	level 1 sample words	Unscramble this level 1 message	20	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.99471	f	0	custom	en
12675354-072a-4bd9-8336-b871af236efc	level 2 sample words	Unscramble this level 2 message	40	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.99698	f	0	custom	en
0e9a5918-8c56-4e51-8255-46d386e27b0a	level 3 sample words	Unscramble this level 3 message	60	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.999472	f	0	custom	en
1fc65d40-55a3-46cb-a818-49085f15ac83	level 4 sample words	Unscramble this level 4 message	80	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.001612	f	0	custom	en
0333500d-a987-4391-9f3d-f36b89b85cb5	level 5 sample words	Unscramble this level 5 message	95	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.00429	f	0	custom	en
10e28ab4-71f7-434e-9a4f-9864d721d2d6	custom type test phrase	Testing custom phrase type	20	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.021441	f	0	custom	en
647007d6-c778-4a1a-b603-a9d627a2a101	global type test phrase	Testing global phrase type	20	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.027956	f	0	global	en
278f96d8-ed87-4aa3-8b40-10714c21a2b3	community type test phrase	Testing community phrase type	20	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.030392	f	0	community	en
229aae34-b103-48ad-955a-56a33a581f10	challenge type test phrase	Testing challenge phrase type	20	t	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.032508	f	0	challenge	en
46c6482b-21bf-4968-b5e3-66b35ef2f8a8	sample output testing demo	Check the enhanced data format	60	f	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:43.035284	f	0	custom	en
5d96c171-854a-4e89-bb15-eed44b6e8956	approve this global phrase	Unscramble these words to solve the puzzle	40	t	5006b465-d0d3-4364-9d0f-8f79b10130fb	2025-07-08 00:02:43.106226	t	0	community	en
10666f64-b227-438d-ac50-1a935df71123	reject this targeted phrase	Solve this scrambled text puzzle	20	f	5006b465-d0d3-4364-9d0f-8f79b10130fb	2025-07-08 00:02:43.116647	f	0	custom	en
64bb8f3b-6e78-4901-bb09-d2e671edfa2d	already approved phrase test	Unscramble these words to solve the puzzle	40	t	44942768-c4a5-4327-ae8a-fbf6d7e89f29	2025-07-08 00:02:43.131351	t	0	community	en
013ad8f9-62a9-49c0-b3ad-6733bbcdebe6	response format test phrase	Unscramble these words to solve the puzzle	40	t	2417a2bd-3ee0-4bf4-bb22-78205d8b8429	2025-07-08 00:02:43.147041	t	0	community	en
0dd54738-ce32-438a-a4c9-b8ad2142a1d0	visibility test global phrase	Unscramble these words to solve the puzzle	40	t	525945c6-22bf-48c7-b58d-b4ddd0f1878b	2025-07-08 00:02:43.153699	t	0	community	en
00414a32-c3b5-4f33-ab4a-3e18598a7282	test phrase for skip validation	Unscramble these 5 words	20	f	57feef81-fae9-49c4-b9fa-e51121362589	2025-07-08 00:02:43.208475	t	0	custom	en
c790532b-b614-4f03-b5b3-b61408fa8af0	test phrase for consume validation	Unscramble these 5 words	20	f	57feef81-fae9-49c4-b9fa-e51121362589	2025-07-08 00:02:43.21854	t	0	custom	en
6bf151e4-1af5-4825-b916-52516afc4a2e	status test phrase	Unscramble these 3 words	20	f	57feef81-fae9-49c4-b9fa-e51121362589	2025-07-08 00:02:43.254302	t	0	custom	en
2c0dfc1a-14eb-48db-af44-458457279e9d	Din Mama	Unscramble these 2 words	41	f	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 11:52:38.494624	t	0	custom	en
da222535-14ba-4ca9-a019-b599ff6b4b29	Asdf Asdf	Sadf	34	f	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 12:48:45.078825	t	0	custom	en
443c459b-7ef4-4894-9e45-a30dcffd7dc2	sad Asdf Adsf	Asdf	43	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:26:46.782083	t	0	custom	en
5900f572-f4ec-4094-8b91-194d1137ce51	Ddfff F	Ddffdsad dfsa	45	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:04:11.385841	t	0	custom	en
08740e0e-06c0-41dd-a61b-afd73b2471d7	Aa Ff	Af	50	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:30:15.358502	t	1	custom	en
0a442428-89b3-443e-842b-a33b2bbc9d94	hello world	A greeting to the world	45	t	0f9c0fc2-cf0b-4207-bb69-47988110b74a	2025-07-08 15:09:25.065498	f	0	custom	en
1037447e-28dd-4dc3-9d96-3a5572f4cecb	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:09:53.084544	f	1	custom	en
10d0331f-59af-40d1-bccf-8aad48e55356	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:10:46.639596	t	0	custom	en
bc4c6d30-6e81-4400-8f01-afed1d9310da	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:10:46.651239	t	0	custom	en
9feb1685-e889-4794-abc1-b7f3bd6bcec0	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:10:46.654707	t	0	custom	en
9941b025-8367-4be7-80a9-53d725b173d5	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:10:46.681767	t	0	custom	en
c5d7d82a-6828-478d-b2ad-a9fbeed969b6	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:12:08.76733	t	0	custom	en
7c9fd074-8983-4ae9-9016-aad5f3978e09	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:12:08.783978	t	0	custom	en
c0c0c943-9123-44f0-9c99-38855eca7ced	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:12:08.787706	t	0	custom	en
d0a430f2-3acd-40c8-98a6-893c9227cbdb	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 15:12:08.800727	t	0	custom	en
51d4492c-465b-4b9d-ad93-3b543fcecf7a	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:50:56.569213	f	1	custom	en
8bfa62ae-4b2b-4db9-8253-7463ed00e054	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 15:50:57.356082	t	0	custom	en
938c6387-df6f-44b3-b41b-df7586dc531d	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 15:50:57.451899	f	0	custom	en
53c0c34a-7eb2-4486-a74d-0fffba5cd70d	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 15:50:57.625396	f	1	custom	en
1fde4dcb-5079-49a8-815c-ac09e6207616	hello world	A simple greeting	45	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:50:57.856259	f	0	custom	en
0cf77938-9161-4773-abe4-2412d9e9656d	difficult anagram puzzle challenge	This is quite complex	91	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:50:57.858629	f	0	custom	en
c0048f24-e8cc-4724-ad13-3605ff71edc7	quick brown fox jumps	Classic pangram phrase	100	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:50:57.865673	f	0	custom	en
bc9d6cee-a416-46df-ae46-567d68325c18	scoring system test	Testing our new feature	41	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:50:57.871538	f	0	custom	en
7ed53066-a8b0-40ee-a6bb-976989f2bf32	leaderboard ranking	Competition system	48	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 15:50:57.873013	f	1	custom	en
618a10f3-7561-4343-b5b9-7c9ee4470e2c	hello world	A simple greeting	45	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:01:39.030908	f	0	custom	en
a7677c21-24d1-428a-aee4-9f592241caec	difficult anagram puzzle challenge	This is quite complex	91	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:01:39.033847	f	0	custom	en
5f6bc012-cd13-496b-9089-8afcf4b5db58	quick brown fox jumps	Classic pangram phrase	100	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:01:39.036548	f	0	custom	en
dbc25846-1185-4d06-a9c3-45b62a246ad0	scoring system test	Testing our new feature	41	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:01:39.03834	f	0	custom	en
019807f3-a2f3-425d-8852-dc11e1d4146f	leaderboard ranking	Competition system	48	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:01:39.049629	f	1	custom	en
bf1df45d-3e8b-4175-855d-6ee9ba9d486c	hello world test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 16:01:48.281646	t	0	custom	en
73507da5-ebfb-4cc9-8eec-ae9531a0cc42	quick brown fox	Unscramble these 3 words	100	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 16:01:48.28685	t	0	custom	en
a1e7ff38-b89f-4da5-8199-b5c1a9bc23a7	sample phrase creation	Unscramble these 3 words	44	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 16:01:48.314806	t	0	custom	en
78b1fe8f-2b66-44bd-aae5-0335f3bd72d1	anagram game test	Unscramble these 3 words	43	f	ba9fcb00-3262-421e-a4a4-b297f2bfd098	2025-07-08 16:01:48.320575	t	0	custom	en
388f4d85-7090-4629-8ecf-6b959efb69fa	integration test phrase	Unscramble these 3 words	37	f	57b25b2f-9f26-4633-ba53-8dc70c17b6ec	2025-07-08 16:01:59.793994	t	0	custom	en
13e5e749-dc05-4f84-8c6d-b37ada41e1b1	hello world amazing test	Testing the new enhanced endpoint	77	f	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.910263	f	0	custom	en
5bf5b910-4cad-4b30-80a3-21bca6260fbc	global test phrase for everyone	Available to all participants	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.914052	f	0	community	en
d430887f-04b9-4950-9fec-138fe71d01ec	multi target test phrase	Challenge for multiple recipients	43	f	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.918023	f	0	challenge	en
4eae5976-3c21-4af5-bf70-42ec38b1fe67	validation test phrase	Unscramble this challenging message	44	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.923883	f	0	custom	en
a9b6698d-29e8-4819-a6b0-7ca2f9bdf605	level 1 sample words	Unscramble this level 1 message	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.929912	f	0	custom	en
d76ba8c3-89e8-46b8-9c51-8a7c875144f7	level 2 sample words	Unscramble this level 2 message	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.93246	f	0	custom	en
6c07a221-4ba8-4374-8fc4-75abda509558	level 3 sample words	Unscramble this level 3 message	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.934405	f	0	custom	en
e3ece760-6582-4dda-8e7f-2b51409d0b93	level 4 sample words	Unscramble this level 4 message	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.93676	f	0	custom	en
421a2a96-d7b4-41d9-85b9-fc2db26fd9e3	level 5 sample words	Unscramble this level 5 message	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.939007	f	0	custom	en
7f9ee47b-8f8d-4100-99b1-fffd61ba714a	custom type test phrase	Testing custom phrase type	44	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.942719	f	0	custom	en
50c11f0a-b038-44b5-8cd3-ed77a8ac06ff	global type test phrase	Testing global phrase type	47	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.94466	f	0	global	en
9a3122b1-8828-475b-99f9-c71ad8e684fe	community type test phrase	Testing community phrase type	45	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.946165	f	0	community	en
b4e4272b-5523-4eff-a79f-a339b843e919	challenge type test phrase	Testing challenge phrase type	43	t	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.947727	f	0	challenge	en
ffa9f28d-dc9d-44ad-891b-2399bef6ed1f	sample output testing demo	Check the enhanced data format	45	f	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.953117	f	0	custom	en
51dd77f3-aee2-47be-8b07-ba0edbfeba6b	approve this global phrase	Unscramble these words to solve the puzzle	49	t	d980f8f7-106e-4342-a4ab-283b00d17b9d	2025-07-08 16:02:00.039212	t	0	community	en
69d35357-1ae2-49c2-a7c8-140f902f2815	reject this targeted phrase	Solve this scrambled text puzzle	56	f	d980f8f7-106e-4342-a4ab-283b00d17b9d	2025-07-08 16:02:00.057495	f	0	custom	en
2f77b525-a273-4b81-9da5-820a0db2d072	already approved phrase test	Unscramble these words to solve the puzzle	47	t	256d1910-6906-4d96-8407-349f70a9178d	2025-07-08 16:02:00.079228	t	0	community	en
3c163fea-fc44-445a-b179-dd371c083aac	response format test phrase	Unscramble these words to solve the puzzle	41	t	efdbfea9-63ee-46e2-a089-cdff1a89329b	2025-07-08 16:02:00.098998	t	0	community	en
fab5fbba-0d6f-40d4-814b-743e0b0fe177	visibility test global phrase	Unscramble these words to solve the puzzle	48	t	1487b8f6-acef-4e10-ab65-3d2aa6de05b1	2025-07-08 16:02:00.11432	t	0	community	en
f24fdde3-9072-4edb-b557-df5a76aef8a6	test phrase for skip validation	Unscramble these 5 words	48	f	e9ee8f28-dc0b-40f7-a275-d619c20bc76c	2025-07-08 16:02:00.150546	t	0	custom	en
2aeb27e4-2375-4fe9-a9fc-b0288bca27e2	test phrase for consume validation	Unscramble these 5 words	44	f	e9ee8f28-dc0b-40f7-a275-d619c20bc76c	2025-07-08 16:02:00.171119	t	0	custom	en
f97b45d2-07fb-41d9-9fbd-15b978c1f441	status test phrase	Unscramble these 3 words	38	f	e9ee8f28-dc0b-40f7-a275-d619c20bc76c	2025-07-08 16:02:00.204032	t	0	custom	en
1d4bbaee-9fe4-4409-af12-730c26316a87	websocket data test phrase	Test hint for data validation	45	f	35bcd4cd-1663-42b5-b657-0ce99c85be33	2025-07-08 16:02:00.780542	t	0	custom	en
8d692dd8-fced-4cc0-98fa-2309a9049e58	hello world example	A simple greeting to everyone on the planet	65	t	b28c4c40-f9a4-4867-8296-7b63a645ef00	2025-07-08 16:02:00.803663	f	0	custom	en
2fcfa332-4519-4a9d-a8d3-cfbaf0dc6830	hello world	A greeting to the world	45	t	3d01c53d-593b-4053-8004-63f33daece6c	2025-07-08 16:02:00.826608	f	1	custom	en
23a0ef9e-c3bb-4b9b-b4dd-9bb01b9d839e	hello world	A simple greeting	45	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:02:01.347057	f	0	custom	en
e67e95fd-ceb8-4e9f-915a-5fa5836bef54	difficult anagram puzzle challenge	This is quite complex	91	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:02:01.351178	f	0	custom	en
a91b1efb-d21c-4ec8-a67f-b63e15fcd579	quick brown fox jumps	Classic pangram phrase	100	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:02:01.353395	f	0	custom	en
3ea15d0b-3096-47c4-a1ed-247838a41e83	scoring system test	Testing our new feature	41	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:02:01.370125	f	0	custom	en
7de1e91d-9448-4dbd-ad46-27abb8aa2089	leaderboard ranking	Competition system	48	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-08 16:02:01.379347	f	1	custom	en
6a8be1e1-b8f6-46e4-a6fb-ad91226bc71d	Ghjhhfhjhggh Jjjjhhhjhh	Unscramble these 2 words	100	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 18:56:44.699425	t	0	custom	en
34a55d40-67b8-4c2a-95de-8ec4eb91c544	H  Fd gjhh	Jug h	97	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 19:02:13.312677	t	0	custom	en
93718f8b-2d13-4736-b9c9-76465af58076	H  Fd gjhh	Jug h	97	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 19:02:13.339573	t	0	custom	en
ce78667b-f0af-49a7-8d10-78da1bf66805	Bas Kas	B to the k	53	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 19:03:48.164371	t	1	custom	en
eaf2539a-6295-4009-89f3-7c097e98b290	Fhhh Jjh	Hej	100	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 19:11:45.82956	t	0	custom	en
1f667b80-13fe-45f3-8011-084b2dbcca57	Hara Hh	Hug	41	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 19:37:35.240622	t	0	custom	en
24b52495-be3a-423c-adaf-94c205fd2c57	Fdsa Adsf	Fdsa	43	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 20:40:03.576423	t	0	custom	en
a3a09e90-8329-468f-9bfa-c81619280bb7	Sror Fbol	Vejde	49	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 21:30:58.038355	t	0	custom	en
2de0f583-084a-47a8-ad5c-b5bc554432b1	hello world amazing test	Testing the new enhanced endpoint	77	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.553343	f	0	custom	en
b08e89ac-8837-422a-8655-6e2ba42211e0	global test phrase for everyone	Available to all participants	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.561874	f	0	community	en
b72c31fe-b9c7-4c28-aa99-06a76ea6cc12	multi target test phrase	Challenge for multiple recipients	44	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.564828	f	0	challenge	sv
1eba7b85-1a40-4c3f-9ac3-473462b2d0d2	validation test phrase	Unscramble this challenging message	44	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.572327	f	0	custom	en
2dfae67c-bd76-4497-9be0-e43488b271db	level 1 sample words	Unscramble this level 1 message	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.577111	f	0	custom	en
1a59c406-4fdc-48b3-ab40-da7a8c6f84f8	level 2 sample words	Unscramble this level 2 message	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.579241	f	0	custom	en
1d3e61e6-e935-46b9-849c-0d47634e57f3	level 3 sample words	Unscramble this level 3 message	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.580934	f	0	custom	en
9245bc56-e018-490b-a384-4f8230711c1e	level 4 sample words	Unscramble this level 4 message	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.582703	f	0	custom	en
712e5e98-b350-4d35-82f1-5a5dae9c2618	level 5 sample words	Unscramble this level 5 message	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.584616	f	0	custom	en
978cf492-70e4-41b8-95d7-baab62c4d1ec	custom type test phrase	Testing custom phrase type	44	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.587896	f	0	custom	en
89d0d6dd-2b86-4d7c-a2eb-b20424fa9c60	global type test phrase	Testing global phrase type	47	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.590226	f	0	global	en
8c25ccd0-7f24-453c-bc01-2030062450be	community type test phrase	Testing community phrase type	45	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.591999	f	0	community	en
23289080-d48e-4bbd-bc6c-3056b0c4aa83	challenge type test phrase	Testing challenge phrase type	43	t	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.59418	f	0	challenge	en
a0d68653-6fd1-4802-a492-e66bfc819acb	sample output testing demo	Check the enhanced data format	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 23:51:44.596903	f	0	custom	en
bf8f45d4-2c51-4ccf-a4d6-6b2a6dec1ec1	Hagga Pagga	Fin dag	42	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:36:18.869821	t	0	custom	sv
e8b69f54-07e5-4f97-a876-aa8486fb6b26	Dsf Dfsa	Sdfa	48	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:37:48.906989	t	0	custom	en
a30b3b1f-0b32-42f0-b8db-8dbba6a02a4f	Sad Asdf	Sdf	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:40:24.677247	t	0	custom	en
02548d49-7531-4b14-a296-fa90e5f98123	Sadf Asdf	Dsf	43	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:42:03.512407	t	0	custom	en
fcdb0c76-74e4-4df1-82ae-450329a18688	Fds Fds	Fds	38	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:42:27.193154	t	0	custom	en
041d4171-f15f-4671-9a91-64fa3a898688	Sdfa Asdf	Dfsa	38	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:43:16.461528	t	0	custom	en
9c6e2c87-412d-464c-9c61-e81d197029f0	Asdf Sdaf	Fdsa	43	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:46:01.444234	t	0	custom	en
155ba304-d722-485e-bbba-31c49d0992c9	Phrase 2	2	44	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:47:51.778549	t	0	custom	en
0165f61b-967e-47eb-a6e7-e6ed0a820336	Phrase 3	3	44	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:48:07.322467	t	0	custom	en
1fb820e3-c7a2-4e2c-be6d-5ea4cfc437d1	Ghhh Hhh Hh	High	22	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-09 10:55:51.636232	t	0	custom	en
778b8a82-f615-4503-abf3-64504f0a930e	Asdf Asdf	Asd	34	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:59:56.886089	t	0	custom	en
59d996fc-1340-489c-b856-7478fc7ae3aa	Asad Asd	Asd	36	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:07:32.701451	t	0	custom	en
94aa3f75-caf1-4cb4-bc15-31b3a8745d51	Asdf Dsf	Asdf	48	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:12:33.371006	t	0	custom	en
7434d709-e5d1-432f-b531-0d4298b98d86	Asd Asdf	Sdfa	35	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:12:49.883439	t	0	custom	en
f1f2a429-82a4-497b-aaef-cf022d3b77a1	Fdas Asdf	Sadf	43	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:26:14.340386	t	0	custom	en
d8974f02-948d-40f8-a299-33dba4eb5801	Sadf Sdfa	Sdfa	43	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:34:24.848477	t	0	custom	en
23a7db68-cb98-4426-938b-49b931aaee29	Sdfa Ads	Dsf	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:36:32.440334	t	0	custom	en
8670937c-4da4-4f8e-ad84-c1668c6c1bf1	Sf Df	Fd	53	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:41:11.348943	t	0	custom	en
70a3108a-ac73-47f7-bb9b-1938e0824a69	Sda Dsfa	Sda	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:43:41.922639	t	0	custom	en
7b590a25-819e-4662-9be3-692443cedc69	Sad Dfs	Dfsa df	46	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:54:26.654011	t	0	custom	en
ffe944e1-0e2b-45b5-9895-bdca46ca9dc5	Asd Adsf	Sadf	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:55:12.389859	t	0	custom	en
80c5e8a9-8296-4677-8199-ab9de0663575	Sad Dfsa	Sadf	40	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:01:19.830241	t	0	custom	en
4f958260-3a0f-476a-9d74-5b6c9e6f317e	Asfd Afs	Adfs	47	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:01:38.664247	t	0	custom	en
962e987e-67bc-49b4-87c7-f8747a25607a	Fdsa Asdf	Sa	47	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:02:03.5388	t	0	custom	en
5296e6e9-842f-41c8-b671-dd435ddf01c9	Fdgs Dsfg	Dfgs	54	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:02:21.789798	t	0	custom	en
eb033b60-6972-4901-a569-9d955192c7b3	Asdf Dfas	Fdsa	38	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:05:17.460604	t	0	custom	en
ad2bd8e0-210b-4045-821f-b246bf2436f1	Dsf Dsfa	Df	38	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:06:22.751153	t	0	custom	en
7e991de2-8b04-4c3a-9efb-46c35de4b20c	Asdf Asdf	Asdf	34	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:11:40.634652	t	0	custom	en
9934d499-f0a1-475e-ab52-1f7e0efff9fe	Asdf Asdf	Sadf	34	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:11:53.910622	t	0	custom	en
77aa408f-14d7-4759-b3a7-c41e7428118b	Sdaf Asdf	Dsaf	43	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:13:22.687519	t	0	custom	en
163049ae-8429-4d57-b336-16374779b71a	Asdfasdf Df	Sadf	35	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:13:33.973866	t	0	custom	en
7f915907-b8a0-4e5c-a1c3-a88c620004da	Chhg. H	Jag	49	f	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-09 12:13:59.152911	t	0	custom	en
e2163f75-6b45-4623-8f5e-c71834c79cf8	Asd Adfs	Dfsa	45	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:15:21.977446	t	0	custom	en
b1355d07-d5b8-4bc4-a1c3-5908e3ce2169	Sad Sad	Sadf	30	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:27:15.04502	t	0	custom	en
161daf73-a405-4511-9af4-a04de88578d4	Sadf Adsf	Sadf	43	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:33:35.827902	t	0	custom	en
048a5b2e-5919-4ebf-adbb-63d2d934f2d3	Fads Adsf	Fsda	38	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:43:57.365346	t	0	custom	en
54e5d5f9-3ea5-4eb1-b245-3d4ce65fd434	hello world	A simple greeting	45	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-09 15:47:36.172223	f	0	custom	en
ab9d296b-4905-44b0-9485-ad469202120d	difficult anagram puzzle challenge	This is quite complex	91	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-09 15:47:36.176864	f	0	custom	en
40bf3ebb-46e5-4bc7-8c97-93c414d57545	quick brown fox jumps	Classic pangram phrase	100	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-09 15:47:36.182972	f	0	custom	en
009458e1-245e-40a3-8054-667963f3e9b3	scoring system test	Testing our new feature	41	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-09 15:47:36.185413	f	0	custom	en
51fd5f22-a2d7-43a0-a849-5edf13ebf2bd	leaderboard ranking	Competition system	48	t	842d0a5c-a025-4485-90c4-540ff3cfaaae	2025-07-09 15:47:36.190108	f	1	custom	en
b87aaedb-e8f5-4774-92c9-5ae5b852e2b0	Apa Hej	A h	100	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 15:53:46.272768	t	1	custom	sv
e6ce128c-aa76-4c9a-9b7a-116f194ab43b	Sdf Sad	Sadf	46	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 15:56:12.717822	t	0	custom	sv
ca449815-00a8-45af-ba36-cbe745b44c09	integration test phrase	Unscramble these 3 words	37	f	059b139d-b480-4bb4-95f6-6fb2e79db5d9	2025-07-09 16:06:18.681964	t	0	custom	en
c867f814-0d0c-401e-910e-e6c02c80f31d	Sad Sdf	Sdf	46	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 16:08:33.460178	t	0	custom	en
492bfb82-b58b-4974-80ba-4c6bed39afd6	hej världen	svensk hälsning	85	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 16:13:14.5283	t	0	custom	sv
625f7594-ce52-4e18-a59d-5a0314fb1dfa	Asdf Asfd	Fdsa	43	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 16:15:47.834126	t	0	custom	sv
da50ab17-7652-4b50-a498-d23eb20512f9	Liten Anka	Sdaf	45	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-10 11:04:47.602493	t	0	custom	sv
53d5d899-46e6-4122-846e-50700ab65ee7	Liten Anka	Sdaf	45	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-10 11:04:47.624036	t	0	custom	sv
5b8d8208-f084-49ff-93e2-0e0fa3c22e65	Liten Anka	Sdaf	45	f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-10 11:04:47.636938	t	0	custom	sv
f3390f5d-07e7-4b9e-ad6b-d95a58512e25	sadf Asdf	Sad	39	f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-10 11:41:16.732406	t	0	custom	sv
\.


--
-- Data for Name: player_phrases; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.player_phrases (id, phrase_id, target_player_id, assigned_at, is_delivered, delivered_at) FROM stdin;
f5f73014-21a8-4d58-acd2-7bd1fe8f47bb	a4065dd9-6438-4fa1-9c00-741753903746	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:06.770146	f	\N
a6952de9-9d47-4010-acc8-ccb52c6e7705	b3878e04-4dd9-425d-b4d0-5d66c9c7c498	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:15.788195	f	\N
8f3bb379-b808-46bf-b767-f00100b76d78	6bcb0525-de57-4fd2-8481-ea6ca5f5974e	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:15.797825	f	\N
e664928c-1e6c-4524-af12-468d16779e84	1b2a5e3c-1771-4fec-a9f8-b6b78d105108	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:15.806651	f	\N
b4a5be3e-91af-4901-88a0-7e74c770184e	b78fd268-c107-43cd-9850-e4b193275b42	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:15.839912	f	\N
969aa80b-faab-4ced-aa6e-20d4c2760e7d	33a5d6d1-0a83-472f-b7f4-32d8daae82d3	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:16.870789	f	\N
fa0eb2a0-60aa-4e02-b3dd-3ec83e433cec	e3b63d3b-3bcf-48dc-a93b-bfc16f8fe1a0	7c4bcde4-13c5-4ea5-99ff-8152fdb56349	2025-07-07 20:05:16.947057	t	2025-07-07 20:05:16.958557
b09bc5e6-5b04-4426-8588-006d04a59855	7f5805a4-f491-458f-976c-b6d990e7a964	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:06.412836	f	\N
35d4c5c4-d504-461f-a432-a6580130b942	57edc53f-049a-4c75-b635-2055c5a8b0da	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:06.426041	f	\N
d604e1f1-b646-4647-945a-93a88b313ba0	8df536b9-7a91-4435-a675-a811fd3e8a65	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:06.442842	f	\N
7a481161-26f2-4145-ab9b-1d6308786cf6	408f906d-b77d-4a31-9d3b-87c14e60c9d9	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:06.506804	f	\N
ff025ef8-1914-4fe3-afab-f2d731f3a7b5	82a02934-6cd1-4cff-be1d-558c5c4d414d	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:06.519503	f	\N
61386027-d54a-4585-8876-a7a55a0ca2ae	1bc015fa-623c-4a30-b572-f46282f4e5a8	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:07.550738	f	\N
d3b77c97-55ea-4a17-b538-2d5e49f2780d	c5d09453-4eca-4191-a648-f9e2a546c544	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:06:07.585688	t	2025-07-07 20:06:07.595588
22a38891-643c-4ce4-9f64-74e9749623e0	e21bca9d-fc26-439a-bf22-a4a81a3fba07	3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	2025-07-07 20:28:31.342438	f	\N
8eee3618-7ff9-4ec1-b6e0-d5878622535c	643b57dc-ba7d-40c8-bb65-796df77f1f48	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:31:49.587534	f	\N
13cb18ea-6283-440a-9cd7-209ac25a4f03	643b57dc-ba7d-40c8-bb65-796df77f1f48	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:31:49.587534	f	\N
a2dfbf58-3578-47b9-8bbf-c73152c2aca9	f2331484-2050-412b-b025-e4612b616f88	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:33:31.11206	f	\N
39e1f5ad-e9be-45b9-90fc-d32b28766897	e57d19ed-75d7-46b3-a052-e38b59fa0538	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:33:31.133757	f	\N
ef4a15df-c7bf-46aa-a5a3-841be0646100	e57d19ed-75d7-46b3-a052-e38b59fa0538	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:33:31.133757	f	\N
d3af2eec-2ec4-4573-a580-eabc0743e4f4	7b774ae4-e2f2-4a79-bedf-bf7704bfae11	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:33:49.812333	f	\N
2b207a12-943d-479b-8cec-9a958f423035	3a258e33-e1dd-4680-aeab-86eefdb10ede	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:33:49.841792	f	\N
84384083-1a8e-492c-a4c2-20f642dcfa78	3a258e33-e1dd-4680-aeab-86eefdb10ede	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:33:49.841792	f	\N
317706d2-eabd-4bf6-8a92-766859c9d5b8	90db795d-8f46-40cd-b4a8-1ba5ac1cdad6	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:34:09.291204	f	\N
f9062c3d-ca39-4666-b4ab-641153aa95c3	528e1963-9f18-4525-af30-df5bdbcf441e	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:34:09.307117	f	\N
5d1afa65-ab14-4951-a62c-f59eccff813f	528e1963-9f18-4525-af30-df5bdbcf441e	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:34:09.307117	f	\N
60e948b0-0437-474d-9c50-25f805a82ef4	7fb1438f-ba54-4324-a59b-da2b1803ce22	e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	2025-07-07 20:34:09.396292	f	\N
bdc56d53-d46d-4e37-a3f6-5bab569dd447	4281bd47-0454-4fcd-8356-1e9328e9c6d1	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:47:13.561949	f	\N
2f14069b-876b-4d9a-a09e-15454ecd6ed9	1c0908c3-852b-4457-b46c-5c3feb0e5178	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:47:13.565167	f	\N
fd8e6299-df75-4416-bfc7-2690b7661393	0da606b5-0c37-4a90-8fa5-61eb48083a68	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:47:13.573942	f	\N
9fb57e0b-ff7e-403b-ba30-41c4d3ed8076	c8299493-e25e-4480-925e-38b278523b1e	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 20:47:13.55813	t	2025-07-07 20:47:13.660518
be049eb4-e87d-441a-b024-85cacad9c640	e619cf1d-d9f1-4e83-810b-4cb51bda2ab3	6e029b8e-c018-4095-a3d3-d4dbd64d1f96	2025-07-07 20:47:24.931882	f	\N
962aba5e-03f1-4a30-a751-75900d03eca9	b9b8395b-c4a5-4ec1-9dc7-5e550bb08ce3	6e029b8e-c018-4095-a3d3-d4dbd64d1f96	2025-07-07 20:47:24.93821	f	\N
36ca6885-6954-4ab8-8129-96ff78f522ac	b9b8395b-c4a5-4ec1-9dc7-5e550bb08ce3	d180dfee-a6fd-489d-b056-196fc042a340	2025-07-07 20:47:24.93821	f	\N
a291a3ce-9e81-48c1-aa97-894b14025a5e	cec48ac7-97fe-45c5-8bb3-848cf9e50073	6e029b8e-c018-4095-a3d3-d4dbd64d1f96	2025-07-07 20:47:25.011982	f	\N
af87264c-e579-4dc2-98d5-79c21d7b77de	360a8cd9-65f7-4b90-86a8-8c50f75ca7cf	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:00:28.137306	f	\N
02a5d8ad-df2a-41cc-8563-520860e69570	f88410af-2ef3-4664-b9fb-9275b9d34c4f	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:00:28.139632	f	\N
4afc0ee1-2d7c-4a38-9b72-277f08314a7a	f7c001cc-8cd0-4d92-86f3-9bb2338987d0	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:00:28.15058	f	\N
96d08b6d-48cd-40be-a858-c31f823652f4	9f249ec2-3663-45c0-ab80-d5b257070a4d	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:00:28.134259	t	2025-07-07 21:00:28.217824
45c22959-18d6-41f0-be44-d2dc79735272	e7c16160-8be5-4ea0-ae7b-44ff09e391d4	2aed5a5f-684a-4956-8b97-4016d2666224	2025-07-07 21:00:39.620763	f	\N
bba4fa3a-af24-43d0-ab7d-3b5be99111f8	4b494875-dd5e-45b9-b930-40a4d3ad334e	2aed5a5f-684a-4956-8b97-4016d2666224	2025-07-07 21:00:39.640652	f	\N
4f2bd3fe-bba0-4fe1-b8d6-5c45167eac8d	4b494875-dd5e-45b9-b930-40a4d3ad334e	7cd90cf4-c596-4f20-870b-705f7ca3a4a8	2025-07-07 21:00:39.640652	f	\N
67cc404e-46db-4b67-9813-b122e033c81a	cb9e3ecc-d69e-4d0a-a5fe-e249d84680c3	2aed5a5f-684a-4956-8b97-4016d2666224	2025-07-07 21:00:39.705565	f	\N
898adfda-9362-464e-a4a7-167f594d1fe2	048c6043-e79f-4377-bf9a-2a186e53b6aa	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:01:57.788216	f	\N
1faa77a9-241a-4bd4-881c-ca1a71a70cb8	6bcf9b43-cdee-4bb0-bb9d-a4c284ca5d6b	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:01:57.790326	f	\N
0b712349-fc9d-4f05-b78d-edd371fc719f	22ee7ff0-6959-4c0f-b955-54593c141139	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:01:57.800975	f	\N
239689a0-7ff1-4be0-901f-3fbe44b0382d	22c44c20-35f8-4991-9807-58b31749d2ef	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:01:57.785658	t	2025-07-07 21:01:57.824315
aab1a3ff-3163-466d-bbd6-aedbc2c4aa35	f8893c89-66dd-4dbc-88dc-2145f87b3370	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:04:37.476128	f	\N
699dce7f-a38b-47fe-89fd-09c7fabf4b5d	3a14415c-c06e-40b3-bb8b-59a801f4e4ca	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:04:37.488508	f	\N
3a54f76b-7bc0-4664-ac89-eea870cb16d0	70323597-e40d-4b4a-8967-7392c6fd86df	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:04:37.491387	f	\N
c140ff7b-c35a-49c5-a791-b1882c3185c3	1cc93298-0031-4046-a1f1-3184a29e61c1	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:04:37.473389	t	2025-07-07 21:04:37.545566
80af4fcb-529b-47cb-b869-7bdbde0ced33	c3ef1dad-f504-4f57-873f-13b43739bd2e	4c499e07-c79e-445a-b081-efd89328bc28	2025-07-07 21:14:22.967145	t	2025-07-07 21:14:22.979006
2fa8271e-d0dd-421c-a456-734b828dea6f	43287691-4a63-4d43-946a-ce9f1efc156c	c71f91c8-a60d-4eff-af40-03ea02e5bebe	2025-07-07 21:15:11.566057	t	2025-07-07 21:15:11.569494
0a60d6b7-4c90-4bc8-92b4-7ef83a830130	8ba8b674-28b7-459b-bf73-816e9ee0b0db	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:15:22.594656	f	\N
d5b71656-4f87-4e32-b475-1d91c81ce343	398ff63f-9126-4036-959f-be6a2bae716a	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:15:22.607688	f	\N
73cd8ca3-b23e-43ce-82b5-8da59d7ec216	a067a1f9-5ccf-4f90-81f2-05c0cb7d675f	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:15:22.613041	f	\N
edcca554-50f8-4717-8d05-d7e3ecb3c73f	1cd4ee2a-cb4f-4e04-89b8-f05618583fa6	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-07 21:15:22.583726	t	2025-07-07 21:15:22.662556
7abde0aa-ffe1-41e4-8765-b3dae74458dc	6ae58199-f644-4897-bac1-d51cf62c69e5	f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	2025-07-07 21:15:33.868461	t	2025-07-07 21:15:33.89893
d17855bb-456e-4492-ab3f-83f6bb2c9eb2	469ed4ad-83eb-4e37-afa2-a2f43cc9eae3	88e5d907-b590-4a04-adae-3ece35bf8240	2025-07-07 21:15:34.031638	f	\N
2cc10d91-72d2-4d87-99b2-489bf491f71a	bc8d05ee-1255-4800-8281-b4d9673aaaf0	88e5d907-b590-4a04-adae-3ece35bf8240	2025-07-07 21:15:34.104512	f	\N
bb9ffc1f-ea6c-49b6-b528-c0949ecd4f0a	bc8d05ee-1255-4800-8281-b4d9673aaaf0	214125ac-328b-42f5-9297-16ee90428794	2025-07-07 21:15:34.104512	f	\N
d8f6ceb4-d38d-44ef-aa33-75f2c111a8e7	e27fa831-4575-4da9-bd89-449b0e3f2770	88e5d907-b590-4a04-adae-3ece35bf8240	2025-07-07 21:15:34.263005	f	\N
458799b3-91d8-491a-ab32-f8e02afc12c5	88126b19-d929-418c-ab72-fde6d0be8178	468954d5-42b3-4f6f-a49a-eedf265d916d	2025-07-07 21:47:04.453457	f	\N
e1fefa15-a2cd-415e-b516-841c0322ccbb	50fcf241-0488-442c-aa98-25218996b7a9	468954d5-42b3-4f6f-a49a-eedf265d916d	2025-07-07 21:47:04.644844	t	2025-07-07 21:47:04.700392
9322c07a-4310-48d9-82e3-2e990de35934	d25d3133-0b78-4f76-91d4-1b755184a141	468954d5-42b3-4f6f-a49a-eedf265d916d	2025-07-07 21:47:04.921465	f	\N
7cf34a58-5034-4e09-b712-2640c0537d63	20eb1933-d397-4650-a0e0-028cc1a059d4	2867b455-c969-4e43-922e-124bedad465b	2025-07-07 21:48:19.750647	f	\N
5f5c7b47-7714-4859-9d81-30c8a5b92f9b	568f03e8-d71c-41e5-94c9-4b6017c4f92e	2867b455-c969-4e43-922e-124bedad465b	2025-07-07 21:48:19.788222	t	2025-07-07 21:48:19.790188
f1e0372f-4889-4be1-977c-069445a6ba43	4281438b-c37c-48f9-a7f3-b60000e4fba0	2867b455-c969-4e43-922e-124bedad465b	2025-07-07 21:48:19.9277	f	\N
6e606866-f92f-498e-a762-3d1501282713	bbc5454d-ecd6-45ac-894c-eb0e4709d23b	da0122f9-476d-4257-842c-fd2b194a216e	2025-07-07 21:48:56.10752	f	\N
0299ff9a-bbdc-4787-9f98-9aed5ad3c8e6	2f2cd57b-c80b-45c0-951f-532add7cf389	da0122f9-476d-4257-842c-fd2b194a216e	2025-07-07 21:48:56.154109	t	2025-07-07 21:48:56.160695
42d16e75-afd3-4471-a3ff-1a1c2adc191b	904d9a10-e048-4e13-b7fa-212f530b4946	da0122f9-476d-4257-842c-fd2b194a216e	2025-07-07 21:48:56.292248	f	\N
36cf31b7-7a40-49ee-b65c-f4ba5aed53dc	8a0a2aa0-5221-4977-bed6-85845d7f5610	b87c04fc-abd7-4248-8339-458b83038dfe	2025-07-07 21:52:50.215517	f	\N
2a2afbb3-601d-4d78-a57d-b6e634910887	ef948f79-78b5-469e-a8a5-6b0e64f3f718	b87c04fc-abd7-4248-8339-458b83038dfe	2025-07-07 21:52:50.256428	t	2025-07-07 21:52:50.261347
488e1178-8681-4ebf-a1a4-57956ab1ee2c	ceabb3c5-dd34-4428-9fa7-2188bc1ac58b	b87c04fc-abd7-4248-8339-458b83038dfe	2025-07-07 21:52:50.544085	f	\N
b27414d8-c4ab-4ed2-abbf-845a2256bd03	833b6624-7d0e-4f4d-9801-e7068b3c22fa	23748510-8839-4334-9f74-20b76dc36c3e	2025-07-07 22:09:47.388248	f	\N
36f27930-b302-4475-afc5-4679124c2957	84605adc-5fd4-4fb1-9f0b-9f5c7727f059	dbe18fb1-2dc4-4a6d-97d7-66059135706b	2025-07-07 22:10:43.232532	f	\N
c5ebf37f-4172-43cf-9036-f921baa81319	08941179-0945-42de-8055-6666969192fe	c143e11c-9e54-4804-b8bc-4057af36d423	2025-07-07 22:13:00.576322	f	\N
3327d01b-75c5-4b36-8e3c-fc872703bc7f	0ab1478b-05d7-4ad2-8f5a-0a7166b96e7f	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 00:02:31.597135	f	\N
b32fba48-0786-4583-848a-6a6c6b6b1f2d	01265652-b8c3-47ad-a61a-4b4e277fa18f	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 00:02:31.603381	f	\N
707a859c-4645-42f6-870b-49ebd78dc953	3658f67c-54d8-4a65-bbbb-dff1448321da	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 00:02:31.611231	f	\N
80b55c80-38b8-4cda-8fba-4c5ecb5976ed	b48ff951-c8bb-45ef-8c3f-c8dc43f1167c	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 00:02:31.585154	t	2025-07-08 00:02:31.705543
41610f9a-d980-4d9a-bc22-1acd861afcb3	207efbe0-a868-4ea4-89c1-2d6675e66fda	5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	2025-07-08 00:02:42.92802	t	2025-07-08 00:02:42.936129
cfdc22fc-8aad-4df1-9c26-0c04c42fe153	a61259f7-d065-421b-8c67-b24de665f0b2	f123666c-7101-42ff-9945-f0a80359edbf	2025-07-08 00:02:42.976872	f	\N
83943c9f-d66b-49f0-a64e-546643f7596b	cab1199a-4f95-4965-bd91-339b380b9c9a	f123666c-7101-42ff-9945-f0a80359edbf	2025-07-08 00:02:42.982922	f	\N
a778f5b1-bf84-4b83-950d-5788b503c183	cab1199a-4f95-4965-bd91-339b380b9c9a	49186290-9c69-4da1-aa42-66c943d4944d	2025-07-08 00:02:42.982922	f	\N
38274f20-027d-457e-a3e5-3fbbc6e0ffe5	46c6482b-21bf-4968-b5e3-66b35ef2f8a8	f123666c-7101-42ff-9945-f0a80359edbf	2025-07-08 00:02:43.035284	f	\N
d0c0cb09-bab0-4332-b528-6161aafe1171	10666f64-b227-438d-ac50-1a935df71123	cdbdaa45-d9e6-4506-8433-9127c7e5f46c	2025-07-08 00:02:43.116647	f	\N
5cf76391-b736-4000-b118-4a24b570c3ab	00414a32-c3b5-4f33-ab4a-3e18598a7282	71e637aa-31e7-442f-bf69-ab3298edb2d9	2025-07-08 00:02:43.209702	f	\N
d217d71c-a99c-480e-a69b-975952c29b6c	c790532b-b614-4f03-b5b3-b61408fa8af0	71e637aa-31e7-442f-bf69-ab3298edb2d9	2025-07-08 00:02:43.21931	t	2025-07-08 00:02:43.220677
30b3df93-025c-4cf2-88e1-8e74a7f9aefd	6bf151e4-1af5-4825-b916-52516afc4a2e	71e637aa-31e7-442f-bf69-ab3298edb2d9	2025-07-08 00:02:43.25501	f	\N
c837f3b5-745c-4289-88b5-8b9aefec37e0	bfbf6735-ca14-40b6-a3d8-3c9cc57e97fc	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 09:41:36.243677	f	\N
f697fe73-3739-4a19-a253-190b14003fe2	86e2d838-ce0b-43f7-97f6-99e3a2b90295	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 09:41:36.292392	f	\N
9711d569-bc9c-44c4-acad-c767f6d70e69	4180d35c-dba8-45c2-b448-7c72db212f8d	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 09:41:36.310541	f	\N
e63e7e2e-f171-40d5-82f8-e0794b24b672	85b901dc-1a3f-4d52-9953-3accb3f69680	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 09:41:36.226724	t	2025-07-08 09:41:36.379451
b9c7b595-0420-43f7-a666-fe3203b44e5b	8d31b54a-b320-4dfa-8305-0b97b186d6fc	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 11:20:08.029697	f	\N
8f5d2a13-2458-428d-8597-c2cd36b2f58b	2c0dfc1a-14eb-48db-af44-458457279e9d	cef6ede3-9ded-4092-aff8-39f36492634a	2025-07-08 11:52:38.511233	f	\N
024a575f-f07b-4666-9aee-2844d8ee3897	f9758961-a796-44fc-a23e-5c4d68d50179	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:27:13.164992	f	\N
9792629c-100d-44dc-9d80-8e89b08892c5	17224f05-9efb-4952-9170-146f227d9bee	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:36:25.896866	f	\N
1f8ebd4d-616a-46d1-8b2c-1f6b4bbbba7c	64c06c75-dd75-4af2-ad66-4e49803cf957	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:39:40.887259	f	\N
20f37941-d004-40d2-bf31-b69c4ce3ae3e	72a2b0bc-cfb2-4733-be2a-d7e47538184e	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:41:59.523641	f	\N
a3cf995b-2f03-4b45-9840-362dfca08f89	9f92f01f-9073-435d-a8b9-b4998abe5d17	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:44:59.75675	f	\N
fb61ebd4-ff54-427b-b5be-93be5e156ea1	84aa0fcb-19ac-4e36-89ec-ff980138a783	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:45:14.387222	f	\N
1d4c7a45-6857-473e-b2bd-bfff3fd3161a	da222535-14ba-4ca9-a019-b599ff6b4b29	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:48:45.080995	f	\N
c1608aac-0f19-4066-a2a0-6ae446599257	e0934ec2-00db-4f1a-8cc2-d9f0cbb9c722	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:51:09.705537	f	\N
96bcd53e-e3ac-4f30-b157-6e58fb568ffa	323556c4-b8dc-44f9-8fe5-fa116da2c488	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:53:18.41245	f	\N
f49c09d2-0b92-4d50-9adf-401bca656b04	c46f5c1d-3e08-4df6-8340-7e0109e36b2c	fe32cb8f-8459-4cc5-875f-a3a5347513c3	2025-07-08 12:55:02.459921	f	\N
4145c058-10a5-4db6-9b19-9187ff5c3d15	4fa027c3-df86-4f14-bab5-aaa7d56d136e	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:11:24.941286	f	\N
8a915794-8d90-430a-af71-304ab2c0a175	fbd1453e-406e-4afb-962d-1d74dd6dde78	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:21:14.538534	f	\N
7cecbc07-7269-45cc-9e59-e80e20039ea2	6159195f-45a9-4194-a9fc-fceebb8ea351	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:22:24.016158	f	\N
fc09be54-e16b-4567-8e64-331b64dc6a72	443c459b-7ef4-4894-9e45-a30dcffd7dc2	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:26:46.798857	f	\N
0e9c32d2-3e00-4952-8e57-71bf70a71167	b0d80fe0-93a0-4504-b38d-0c8dada46a54	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:28:56.115824	f	\N
582a5e26-e8c8-4944-9e13-d697ce05f68b	5d555474-26e5-4a64-bc1a-cc2f9f86b548	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:39:38.699949	t	2025-07-08 13:39:44.985307
831a81ba-6105-45d2-b4ae-234f58aab212	15a1e19b-63da-431a-975c-81b4e255dc1c	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 13:57:37.479101	t	2025-07-08 13:57:43.666391
f08261e0-25cb-455f-b954-e836034a734b	ce537516-568f-4f11-98fb-e49bcafbb173	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 13:57:26.379981	t	2025-07-08 13:58:14.014136
74419d27-f441-42a3-8413-96302c8afc82	9373b647-6778-42ab-a0df-3c51d4daf120	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:03:43.979915	t	2025-07-08 14:03:47.79457
a1d3e7ce-0463-4515-b578-3036ee6ed379	5900f572-f4ec-4094-8b91-194d1137ce51	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:04:11.388693	t	2025-07-08 14:04:13.080605
af421ea6-5594-4385-88c7-86fef4ded2db	9734aee3-d8f4-489b-9750-1be4ad374afe	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:04:50.201879	t	2025-07-08 14:04:51.935564
ec4b5569-b830-4451-a744-806bbeca11b2	9a1d95e0-471a-4c56-b8db-0ad800c29ae3	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 14:14:00.191161	t	2025-07-08 14:14:58.643483
7689cadd-397a-416e-9029-50fc3ebd0d2d	45809dbd-6adb-43e0-b445-897a908ce827	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 14:17:31.697827	t	2025-07-08 14:18:54.777602
fbcd34b6-ab9d-4fb4-ab74-2650e5c2d842	78aea051-45e7-4f78-afab-316743eb9670	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:24:17.352274	t	2025-07-08 14:24:20.494338
629df427-efae-4989-9641-10303ac90147	bea8e03d-196f-4171-9b6b-5491f4c3717f	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 14:26:07.708594	t	2025-07-08 14:26:10.328131
be429ba3-4fff-4e3a-8cc5-84e96257232b	08740e0e-06c0-41dd-a61b-afd73b2471d7	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:30:15.38865	t	2025-07-08 14:31:08.650995
5b3f3eaa-b338-4146-b7a5-010ed2fe61c3	224517ff-9833-4684-bd20-31bcb5ac160a	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:57:26.763338	t	2025-07-08 14:58:06.27372
c6ba7f77-9de4-4bf1-97ce-d50e89dc9f0e	a2b44fb9-0fc2-4fc9-a165-f1c7a673b272	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 14:58:42.737812	t	2025-07-08 14:58:50.678932
f8ef8215-9d1a-4535-9c11-a0307483b915	6c4d0520-dda0-473e-8565-721215b6056e	467c7f9e-9cb3-477c-ad64-c309528ccc79	2025-07-08 15:03:47.707641	t	2025-07-08 15:03:47.711552
e3615835-bae8-4f85-b900-62a790c3685c	4a9d504b-b56b-4afb-a038-89a9f11f4419	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:06:48.643632	f	\N
1d989c92-1d13-43cf-b133-2e1768e5daa7	76f6a31d-fb49-484f-b2dd-6f8965f15f23	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:06:48.648556	f	\N
a01fb5ee-ff51-4605-82d0-4a37c07c3496	ae4a2ae8-dbe0-4938-a00c-27834e4c1c0e	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:06:48.666183	f	\N
e4df2ec4-b70e-4185-a24d-ddbe787a07b2	ec75d8f7-2d50-4e88-b8e6-6bdbbf31350e	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:06:48.628772	t	2025-07-08 15:06:48.849014
eaca2fac-80b2-45b8-9212-539353328742	bc4c6d30-6e81-4400-8f01-afed1d9310da	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:10:46.652375	f	\N
ff35e10a-c815-4594-8a88-517fc0f20a07	9feb1685-e889-4794-abc1-b7f3bd6bcec0	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:10:46.673623	f	\N
ee947fee-fc41-4e53-b1fe-389d23dc6b68	9941b025-8367-4be7-80a9-53d725b173d5	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:10:46.682462	f	\N
f3b29377-4dde-466d-a4e2-7c873e78abd5	10d0331f-59af-40d1-bccf-8aad48e55356	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:10:46.647099	t	2025-07-08 15:10:46.804666
302566a2-98c3-41d0-b8ad-92454562254d	b091b3dc-6663-4aaf-b7b8-76fe84b5911a	af435ea3-de1e-4b5d-b272-ae0dfda93eba	2025-07-08 15:10:58.248867	t	2025-07-08 15:10:58.253666
78ca2edb-15d8-4773-be18-b532e962892c	cde0d416-d0f3-4f83-953a-a09e0583e3ab	bd2fc8a5-52db-46f0-9436-8d1ad8e09e2d	2025-07-08 15:10:58.285899	f	\N
5cff2bcd-e3d7-44c6-869e-100504893259	dfba3b62-02f3-4f8b-8a28-e6dc23ec69f0	bd2fc8a5-52db-46f0-9436-8d1ad8e09e2d	2025-07-08 15:10:58.317074	f	\N
859919a6-e91b-45ed-b1f3-53e0ad96066e	dfba3b62-02f3-4f8b-8a28-e6dc23ec69f0	d4882edf-48fc-4efe-ae41-9ed68177319f	2025-07-08 15:10:58.317074	f	\N
b9775b86-e13d-458f-8c09-dd17b6f6ac24	4509f9fc-3291-4af7-9a2b-aea29e92b22d	bd2fc8a5-52db-46f0-9436-8d1ad8e09e2d	2025-07-08 15:10:58.421891	f	\N
c456b959-bd8f-4643-aa56-715a1679ed43	65f65708-79fa-44ac-9f88-38c242a3f23e	1f66b384-ef28-4e59-9f00-9a36c182cb7b	2025-07-08 15:10:58.682754	f	\N
8a64084d-4b5e-49f4-9754-8f65266bab64	8642657f-c655-4cda-9a5b-95a7e1b49b00	65e501f0-cc3c-407c-9649-3e317a4cc5b0	2025-07-08 15:10:58.867086	f	\N
d6c7aeb4-64a3-46d4-b650-73b282a72c00	123f1dfd-f0d1-49d9-b5ce-d4039319c2bf	65e501f0-cc3c-407c-9649-3e317a4cc5b0	2025-07-08 15:10:58.896092	t	2025-07-08 15:10:58.899247
830b737b-af9f-4909-bffb-afa10a018a05	e3292026-70d3-4274-9caa-e3ca66622b24	65e501f0-cc3c-407c-9649-3e317a4cc5b0	2025-07-08 15:10:58.916807	f	\N
f7cdbb93-6a02-4d9e-8886-d1f8950f015a	7c9fd074-8983-4ae9-9016-aad5f3978e09	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:12:08.784634	f	\N
14eb54c8-7a36-4abd-b7c4-19547672a4dc	c0c0c943-9123-44f0-9c99-38855eca7ced	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:12:08.788397	f	\N
61837bc8-332e-4b12-85fa-208fae28cf38	d0a430f2-3acd-40c8-98a6-893c9227cbdb	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:12:08.801377	f	\N
4d46a014-6bb7-4c47-92de-edd6789f38fe	c5d7d82a-6828-478d-b2ad-a9fbeed969b6	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:12:08.771343	t	2025-07-08 15:12:08.898641
4e38550a-ee0d-4ad2-8338-1f558776781e	9a85fce8-fb61-4717-9a2e-e67265709c8a	cb948adf-2646-4aa1-a8ff-0c3327723fd0	2025-07-08 15:12:20.357066	t	2025-07-08 15:12:20.369067
0d9b7535-0830-4b1c-95e6-65d39e82db75	7cce2a2f-ffce-4e14-b12d-1a1f9c1d2c3f	2bdfae9b-9aa1-4037-a50d-99815d4b3b98	2025-07-08 15:12:20.439865	f	\N
7fc5757b-b832-4d76-9fe1-950d31493933	5fb475f5-31b7-4dfd-997c-744b2557928e	2bdfae9b-9aa1-4037-a50d-99815d4b3b98	2025-07-08 15:12:20.457481	f	\N
135bdac7-318e-4a6d-86eb-47fdfae3c910	5fb475f5-31b7-4dfd-997c-744b2557928e	af6cae65-961b-4e71-9e88-d03380c6a05c	2025-07-08 15:12:20.457481	f	\N
66144acf-514f-4b74-92fd-27402d5324d0	c3547be5-5de2-450a-9d2f-f7a267ea95bd	2bdfae9b-9aa1-4037-a50d-99815d4b3b98	2025-07-08 15:12:20.5302	f	\N
ccb1fde1-a655-4cba-a69e-2d2c38af15d4	88712952-32a9-4ba6-a9e6-b42b2198f44b	76796385-e66f-435e-9137-b24cdc0d4eb6	2025-07-08 15:12:20.603952	f	\N
01e0fcbd-8f61-43ce-bcc4-7a8a84226687	545bb838-f096-4126-85d5-a669f9fd4b9a	babae5bb-39fd-4d15-8ba1-a899b83b5489	2025-07-08 15:12:20.65903	f	\N
575ca496-792e-497f-85c2-36a1cf9c26dc	53b583d7-0cf6-41a9-9fa4-8480c74d5f56	babae5bb-39fd-4d15-8ba1-a899b83b5489	2025-07-08 15:12:20.68844	t	2025-07-08 15:12:20.695864
56830438-14fc-4ac6-813b-a7520139d9e8	cb46c8ec-e7e9-4319-9839-a6eda8afb0f8	babae5bb-39fd-4d15-8ba1-a899b83b5489	2025-07-08 15:12:20.74062	f	\N
c7355749-362f-4f16-a885-b0d5477f4ac8	ce89caf6-c0c6-4f0e-ba75-b03e8afa1565	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:16:48.106659	f	\N
90944a1d-b500-4db8-8386-8f9b3b0f6119	cf772388-e002-4a1f-bee8-0f064b085d4a	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:18:59.240993	f	\N
c3a058c0-547d-4463-8458-a6ba3ff7c00b	105ec468-6d2a-4e39-899e-0ed3358425eb	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:20:33.838517	f	\N
26cc78cf-b054-4cf1-8185-ef588d3ead86	8e55081a-558e-4df7-ac95-fd1c843b803b	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:21:04.817604	f	\N
823f527d-f922-4136-bcab-61c85280c30b	f5c59b42-3359-4acb-b734-208258e8a8b5	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:22:05.457186	f	\N
7c62ce18-3ccd-4478-914d-8e0742b299e4	38173e98-b509-4f9b-8e17-8950ce841870	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:22:13.031652	f	\N
8b9b3fab-8ff1-4f80-ac36-576678eab479	a2330fc3-f4cc-436a-aecf-2c24f2d00980	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:22:19.371837	f	\N
3b08d44c-587a-46b2-aa9b-e0ce48561dbd	784bf70e-fcab-444c-a4d6-afcc350039ee	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:22:19.38552	f	\N
313b420c-e72d-4fd9-8bce-f7266fa27fae	cdf2ceac-a0ff-488f-9453-ef09a877388d	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:22:19.40052	f	\N
cd833060-099a-452e-acf5-2e392efd73be	e9f19d8a-d0a4-420d-bbf8-6f2bbde43f73	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:22:19.36706	t	2025-07-08 15:22:19.462622
0f9c0e64-56df-4991-abe6-49429a59f0fa	af3c4613-ce76-4985-ac9e-c7142e829348	da9a14f5-a12b-4b53-aada-e1530fac4280	2025-07-08 15:22:30.901235	t	2025-07-08 15:22:30.905454
c93abe04-379b-4157-bc3d-8ab58252383c	f7c733fe-1463-41a8-91ec-6ec5043ef4e8	8b162299-7933-4498-a8b9-a9f271f37fda	2025-07-08 15:22:30.948627	f	\N
47ab4e73-12ea-4f9c-b310-ddaa09a37bc8	ddc9820d-fb26-4332-9d98-68de9e701238	8b162299-7933-4498-a8b9-a9f271f37fda	2025-07-08 15:22:30.954512	f	\N
0c6e2cca-81d3-4e72-affe-b78a509ce088	ddc9820d-fb26-4332-9d98-68de9e701238	ba4c55b5-9c77-4e12-9908-130fd34fd533	2025-07-08 15:22:30.954512	f	\N
22af51fa-c3c2-4121-8b61-3928e2915d2c	0d9ae418-452b-43b9-8c24-116d454c0c78	8b162299-7933-4498-a8b9-a9f271f37fda	2025-07-08 15:22:31.021894	f	\N
41e21845-d30a-4f67-b859-70ae17ba7db0	87bf3c51-6778-4b8b-9450-546b64ece630	775a493d-ac27-456c-b21f-fd1bdbcd704c	2025-07-08 15:22:31.15576	f	\N
b5814615-d690-4ffc-aa2f-4b8478157a5a	0aafbe1e-33e2-48d4-bff5-f8374f9879fd	a20dc404-a1d3-4b32-9c6c-d925c0506070	2025-07-08 15:22:31.457532	f	\N
ee49d4a9-36cb-4261-b8c7-5b6fc022eb06	ece2519a-3bdf-4e67-8310-6c05324e4ecb	a20dc404-a1d3-4b32-9c6c-d925c0506070	2025-07-08 15:22:31.487047	t	2025-07-08 15:22:31.488697
f3161464-e9f9-47d2-a900-424e82e3c631	0857b332-4967-41da-97fe-b5116a92667e	a20dc404-a1d3-4b32-9c6c-d925c0506070	2025-07-08 15:22:31.527703	f	\N
23997750-6d69-4228-a8ad-e4e3b7807113	6d30e99b-d717-470e-a0b5-26e73ee91412	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:27:33.137743	f	\N
ba96e7c8-ca18-4c8e-9f19-4b54419a19e5	83f175a0-f485-455c-a995-bbddc4b3d585	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:27:33.149829	f	\N
9327c2d5-8d0f-42db-a688-4dd6606769be	66c8aaab-6742-4377-b0b2-f158930f4db8	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:27:33.197677	f	\N
0eed83b9-37bd-4fa8-ac7c-cb1e55da56d2	ef8e56f0-9aa2-4970-a538-58d2ffb45eff	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:27:33.116096	t	2025-07-08 15:27:33.351785
2fa1c66f-fce0-464a-b7f4-a51821d526f7	d4366ef0-c831-422c-a1f3-14790138ced3	c8732a21-9d8f-4031-a933-0044e05870f6	2025-07-08 15:27:44.726254	t	2025-07-08 15:27:44.752116
cafb5d9c-83aa-47d1-8e12-9e7d53ec0b39	cb17ef7d-581f-4bfe-a00a-bb9290d7bcba	bb6e5dff-0e61-4de4-9e9e-fc0997cd69f9	2025-07-08 15:27:44.8311	f	\N
4a68aaa2-11dd-476a-971a-b2ae79de27c8	756c998a-2708-46b0-93f6-03206241e6ce	bb6e5dff-0e61-4de4-9e9e-fc0997cd69f9	2025-07-08 15:27:44.861627	f	\N
7c234e62-9dda-47d9-be6a-ea9984388368	756c998a-2708-46b0-93f6-03206241e6ce	1d6197cc-cc9e-4c9a-b996-cbc5e938439f	2025-07-08 15:27:44.861627	f	\N
49af95c9-1e27-475f-a9eb-8a2530aa9369	5e694415-96ea-4577-b56a-bd9cefc7515a	bb6e5dff-0e61-4de4-9e9e-fc0997cd69f9	2025-07-08 15:27:44.914706	f	\N
5bd2e54a-82b2-4b64-bfa9-08da0fd95db6	85e086b4-39e9-44f1-95a9-722295610449	1ce2d84f-3644-4572-add4-649c4a4421e0	2025-07-08 15:27:44.995767	f	\N
d706cf68-1fe7-45b1-8523-c5146d32daf1	a9122e5c-bf60-40bd-8863-9b8f029164ca	6ae8612f-cfd2-421a-b084-39536cd58ed9	2025-07-08 15:27:45.062604	f	\N
0c6b6042-2971-4882-b7ca-13a6fe73e3ab	94476c1d-448b-4250-9dbf-3aed567bc174	6ae8612f-cfd2-421a-b084-39536cd58ed9	2025-07-08 15:27:45.069071	t	2025-07-08 15:27:45.070043
1b077906-60c5-4e71-9f33-e295a7956aa8	5b4635d2-bce3-42a6-bb87-e456b7b6c38d	6ae8612f-cfd2-421a-b084-39536cd58ed9	2025-07-08 15:27:45.081469	f	\N
26d60a1f-6c92-4c0f-ab7c-9462b415a44e	49ddf61c-d338-4edd-a00c-83159d6e25a2	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:27:45.650569	f	\N
6a75b583-4a72-45b5-bc36-6a87d7fc5616	115c22fd-e496-4bb1-b688-241e2f0b0d6d	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:27:46.594318	f	\N
49034a63-efc3-410a-917f-fea7cef3e506	14cb84fe-e4a8-4c4d-a0b4-1197f5307494	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:50:43.866916	f	\N
58687cf5-8ad2-4d78-9a7d-eecacc9ff2fa	7c208952-b16a-4ee7-ad2f-27b413d9171e	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:50:43.872675	f	\N
a40a06ab-e937-42e5-9ee2-4c42f481e264	5526d3e7-9ea3-4800-8618-0e99a7d4e527	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:50:43.875859	f	\N
14d81ab7-52a1-4690-917a-9507f51b3f41	583ef98d-4df3-43d6-8d85-0a3fc9365940	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 15:50:43.860387	t	2025-07-08 15:50:44.004412
1ad35b7f-3108-4423-b3da-9a24fd370c69	77fe1215-2c64-4a36-9d40-b1d984fb5bf4	6417764b-cf0d-4e17-a452-8cf52e2f654d	2025-07-08 15:50:55.425908	t	2025-07-08 15:50:55.43106
1c3e4efe-89d1-49a9-b39b-3aef771d11e5	e5b1b135-f3af-4aed-836f-a8780793320a	c0c04d9a-bf94-40b0-9424-7f4157bde78c	2025-07-08 15:50:55.470572	f	\N
ff403497-65e0-4399-81c8-f7f128b2c5f1	9862b697-7931-42d2-b0cb-5d5fe1507014	c0c04d9a-bf94-40b0-9424-7f4157bde78c	2025-07-08 15:50:55.47556	f	\N
12c0cdfa-a96b-46ef-a18b-9a540abad241	9862b697-7931-42d2-b0cb-5d5fe1507014	aa2db026-bd21-4213-9912-5e6174efbdc3	2025-07-08 15:50:55.47556	f	\N
742c53f2-4618-4055-a151-c1743bb086ff	344af6d4-514e-47ef-8664-32ba327d266d	c0c04d9a-bf94-40b0-9424-7f4157bde78c	2025-07-08 15:50:55.570435	f	\N
7ad70f5d-db0d-42a4-b62d-5bf7536c7207	ab3b1b83-9c55-48b9-b98c-298413df30f7	ca91595a-e986-4dc0-ad62-14417f12c04d	2025-07-08 15:50:55.686942	f	\N
fcc797f8-6971-467b-a668-c4c9c692486d	76d33595-d58e-4f5a-9d24-ddf46c8674f6	c23b3bf1-6be8-45cd-9bfa-2c9475b19654	2025-07-08 15:50:55.812229	f	\N
0895957b-b934-482d-81cd-e59066e3a683	c5243f0c-bee8-4b99-9702-95d92fdc7f03	c23b3bf1-6be8-45cd-9bfa-2c9475b19654	2025-07-08 15:50:55.839717	t	2025-07-08 15:50:55.841931
31f5ddbf-b566-4d3f-a6d4-824b4216bed0	b5bf74f4-f3b9-4e2e-b9b9-6bc840dbafb0	c23b3bf1-6be8-45cd-9bfa-2c9475b19654	2025-07-08 15:50:55.859219	f	\N
41bb0123-a1ed-4be9-9245-088312297f90	c65b7e36-f137-4828-a2aa-4b5a002849e4	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:50:56.442858	f	\N
49c5c646-9714-4fd9-982c-03aa35016281	8bfa62ae-4b2b-4db9-8253-7463ed00e054	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 15:50:57.357103	f	\N
a2b52642-1f4a-4078-bcdd-3717b902d477	73507da5-ebfb-4cc9-8eec-ae9531a0cc42	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 16:01:48.287589	f	\N
39d0a4bf-9aba-4592-b769-d5630f9c525a	a1e7ff38-b89f-4da5-8199-b5c1a9bc23a7	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 16:01:48.316895	f	\N
cd670d31-7671-4ae2-a394-1394b4fc71a6	78b1fe8f-2b66-44bd-aae5-0335f3bd72d1	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 16:01:48.324615	f	\N
bd1c0cf7-fc7a-43e4-920a-49eeabd78e86	bf1df45d-3e8b-4175-855d-6ee9ba9d486c	29274f2e-5b34-4727-97fc-69c84bdbd595	2025-07-08 16:01:48.283095	t	2025-07-08 16:01:48.501615
8edd725b-e778-4353-a4a4-3df9691e3acf	388f4d85-7090-4629-8ecf-6b959efb69fa	3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	2025-07-08 16:01:59.796445	t	2025-07-08 16:01:59.809292
b8cf078e-2e65-41f0-96e6-1dcfa018e2de	13e5e749-dc05-4f84-8c6d-b37ada41e1b1	57b25b2f-9f26-4633-ba53-8dc70c17b6ec	2025-07-08 16:01:59.910263	f	\N
4877f1d0-302e-4081-8baf-8ce18c94c456	d430887f-04b9-4950-9fec-138fe71d01ec	57b25b2f-9f26-4633-ba53-8dc70c17b6ec	2025-07-08 16:01:59.918023	f	\N
4854c30d-819a-443a-b368-787f90407bcf	d430887f-04b9-4950-9fec-138fe71d01ec	f69bd249-310a-4849-87e7-83f670dd0956	2025-07-08 16:01:59.918023	f	\N
67226424-d153-4d78-81d7-d1fbbd0564c3	ffa9f28d-dc9d-44ad-891b-2399bef6ed1f	57b25b2f-9f26-4633-ba53-8dc70c17b6ec	2025-07-08 16:01:59.953117	f	\N
8e631b19-05ad-48c4-a7d9-d4a4d96e02e6	69d35357-1ae2-49c2-a7c8-140f902f2815	87c9b857-f9c2-46a8-a90e-8ccfee17fe7e	2025-07-08 16:02:00.057495	f	\N
ab0e5b3d-8e41-4c8a-bcb4-446e3bf1c60e	f24fdde3-9072-4edb-b557-df5a76aef8a6	b68e2f88-b983-4891-ac97-53ee10a3ca75	2025-07-08 16:02:00.15135	f	\N
48f6c90f-6aeb-4232-a1c3-2b19607970cf	2aeb27e4-2375-4fe9-a9fc-b0288bca27e2	b68e2f88-b983-4891-ac97-53ee10a3ca75	2025-07-08 16:02:00.171882	t	2025-07-08 16:02:00.178187
12260277-3cf3-44fb-8fd0-f6ed16cd9e73	f97b45d2-07fb-41d9-9fbd-15b978c1f441	b68e2f88-b983-4891-ac97-53ee10a3ca75	2025-07-08 16:02:00.211756	f	\N
9a8598ac-8500-4053-b71b-5197b7ab336b	1d4bbaee-9fe4-4409-af12-730c26316a87	0c338ee6-0942-41f1-8d90-6aa882487ced	2025-07-08 16:02:00.782479	f	\N
010af725-2ab8-4a7d-bb5e-eefd374997ee	6a8be1e1-b8f6-46e4-a6fb-ad91226bc71d	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 18:56:44.706872	f	\N
9a674f7f-d202-46ab-8461-084cb6a24b54	34a55d40-67b8-4c2a-95de-8ec4eb91c544	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 19:02:13.317103	t	2025-07-08 19:02:31.705411
6373c5c5-dd14-413d-ac81-90de69b79799	93718f8b-2d13-4736-b9c9-76465af58076	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 19:02:13.340438	t	2025-07-08 19:02:43.471653
2ecdbc0d-aaaf-403d-bbc2-be99af56e841	ce78667b-f0af-49a7-8d10-78da1bf66805	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 19:03:48.165523	t	2025-07-08 19:04:01.360941
538fbe8c-9514-4ce2-a2c1-441505412c36	eaf2539a-6295-4009-89f3-7c097e98b290	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 19:11:45.833203	f	\N
3f2f84a3-0dd1-465a-b5b7-3a91d5addc83	1f667b80-13fe-45f3-8011-084b2dbcca57	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 19:37:35.247661	f	\N
1c7f92eb-a63b-4f82-bd94-e9c347374357	24b52495-be3a-423c-adaf-94c205fd2c57	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 20:40:03.579224	t	2025-07-08 20:40:06.428731
91725f39-2d91-4424-9eae-c60592816b73	a3a09e90-8329-468f-9bfa-c81619280bb7	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-08 21:30:58.056454	t	2025-07-08 23:34:06.97347
bf908969-2808-4af0-a150-7a4b22d253d9	2de0f583-084a-47a8-ad5c-b5bc554432b1	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 23:51:44.553343	f	\N
299ad68d-fa19-42e1-8b50-4720e3c821df	b72c31fe-b9c7-4c28-aa99-06a76ea6cc12	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 23:51:44.564828	f	\N
56456381-af30-4004-8728-ae60e4fd0a9c	b72c31fe-b9c7-4c28-aa99-06a76ea6cc12	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-08 23:51:44.564828	f	\N
fb5d152e-b59c-404e-95c3-bf7d5ef10193	a0d68653-6fd1-4802-a492-e66bfc819acb	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-08 23:51:44.596903	f	\N
e0f474f4-65f1-44d6-a42b-504a42dd190c	bf8f45d4-2c51-4ccf-a4d6-6b2a6dec1ec1	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:36:18.881012	t	2025-07-09 10:36:36.765364
be1d8b0f-f998-4539-8adb-c0e10b43fe76	e8b69f54-07e5-4f97-a876-aa8486fb6b26	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:37:48.908649	f	\N
d1c53fee-9a18-4491-9c1f-4492cc384f68	a30b3b1f-0b32-42f0-b8db-8dbba6a02a4f	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:40:24.682952	f	\N
8a857e44-4583-4d7e-96f8-b549c1aec833	02548d49-7531-4b14-a296-fa90e5f98123	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:42:03.513531	f	\N
6ffe22ff-28a2-4f18-b6af-2339d43228e6	fcdb0c76-74e4-4df1-82ae-450329a18688	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:42:27.206856	f	\N
a3910984-e27d-4abc-aa01-bf65f36643c4	041d4171-f15f-4671-9a91-64fa3a898688	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 10:43:16.463149	t	2025-07-09 10:43:35.89571
9d17d9f0-f543-4006-82aa-b29606c66995	9c6e2c87-412d-464c-9c61-e81d197029f0	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:46:01.449158	f	\N
f6205491-53e3-4c40-ad8f-10f6e29ecb27	155ba304-d722-485e-bbba-31c49d0992c9	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:47:51.783509	f	\N
18f45a04-6bc8-48f1-a66c-eb9b2f2d22df	0165f61b-967e-47eb-a6e7-e6ed0a820336	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:48:07.327835	t	2025-07-09 10:48:15.904626
9d49469e-9182-40b7-bb25-98ed0a8c4755	1fb820e3-c7a2-4e2c-be6d-5ea4cfc437d1	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 10:55:51.643474	f	\N
648278e1-cf55-40d3-9980-ce874861f58e	778b8a82-f615-4503-abf3-64504f0a930e	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-09 10:59:56.895554	f	\N
5de5f0af-6702-4f2e-a178-3b8da2121316	59d996fc-1340-489c-b856-7478fc7ae3aa	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:07:32.705763	t	2025-07-09 11:12:53.084666
65e8f1da-8898-4e45-905e-9dffbb88592c	94aa3f75-caf1-4cb4-bc15-31b3a8745d51	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:12:33.375318	t	2025-07-09 11:12:54.853006
ceee7cfb-14ac-4f98-866e-58a19a9cfcee	7434d709-e5d1-432f-b531-0d4298b98d86	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:12:49.884591	t	2025-07-09 11:12:56.838095
b0625a04-1ff9-4452-bbc9-361f0124705a	f1f2a429-82a4-497b-aaef-cf022d3b77a1	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:26:14.34352	f	\N
7381d5ed-ada7-4410-b41d-9671452fe471	d8974f02-948d-40f8-a299-33dba4eb5801	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:34:24.850836	f	\N
779fcbda-9192-4556-85ca-d9ba1ef12e0a	23a7db68-cb98-4426-938b-49b931aaee29	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:36:32.466204	f	\N
1ff35c65-358a-4167-bdfe-a0ef4bd5d1ea	8670937c-4da4-4f8e-ad84-c1668c6c1bf1	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 11:41:11.352515	t	2025-07-09 11:42:03.975287
24e0e895-0db3-41b3-887c-52564eb1b431	70a3108a-ac73-47f7-bb9b-1938e0824a69	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:43:41.92644	f	\N
b0d6cd56-6342-40d3-ba1c-b79eb62af150	7b590a25-819e-4662-9be3-692443cedc69	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:54:26.655376	f	\N
c959514d-ccab-4323-bcc9-59e3d7797d9f	ffe944e1-0e2b-45b5-9895-bdca46ca9dc5	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 11:55:12.392126	f	\N
e9e4852e-2ad0-415d-8348-5dfd42c4f49b	80c5e8a9-8296-4677-8199-ab9de0663575	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:01:19.835322	f	\N
a9f152ec-39d8-4c7e-9a39-30fe245c91a4	4f958260-3a0f-476a-9d74-5b6c9e6f317e	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:01:38.667129	f	\N
29e51113-9744-4616-8a02-f2e2d247ecae	962e987e-67bc-49b4-87c7-f8747a25607a	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:02:03.540806	f	\N
e6e2a885-e4eb-4704-a832-9a6ec7f05f9d	5296e6e9-842f-41c8-b671-dd435ddf01c9	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:02:21.791366	f	\N
4b24a6bd-e468-4a8f-b864-24ae1a5bbafd	eb033b60-6972-4901-a569-9d955192c7b3	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:05:17.462583	f	\N
8d39b13b-9b8c-4898-a43d-a92740138756	ad2bd8e0-210b-4045-821f-b246bf2436f1	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:06:22.754114	f	\N
5e688100-f11b-4014-9997-8a06cd1ea571	7e991de2-8b04-4c3a-9efb-46c35de4b20c	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:11:40.639531	f	\N
e9a5fd66-4d8a-4b18-932c-056212563750	9934d499-f0a1-475e-ab52-1f7e0efff9fe	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:11:53.912525	f	\N
1d8107b1-e155-41bc-86cd-44af70cdedcc	77aa408f-14d7-4759-b3a7-c41e7428118b	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:13:22.689562	t	2025-07-09 12:14:08.583248
a07aed01-b24e-47c7-962b-bbf3b7ebcb3f	163049ae-8429-4d57-b336-16374779b71a	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:13:33.976497	t	2025-07-09 12:14:11.895996
de99f7c9-3c37-4d67-9195-75f431a6f01e	7f915907-b8a0-4e5c-a1c3-a88c620004da	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:13:59.154865	t	2025-07-09 12:14:15.617566
5022d458-0494-4766-8273-69f333f9213a	e2163f75-6b45-4623-8f5e-c71834c79cf8	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:15:21.979994	t	2025-07-09 12:15:37.421124
34169a5e-0500-45a0-a4d0-ab4dff795308	b1355d07-d5b8-4bc4-a1c3-5908e3ce2169	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:27:15.049346	t	2025-07-09 12:27:51.116862
a669e12a-bd77-485e-862b-a843c23adb80	161daf73-a405-4511-9af4-a04de88578d4	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 12:33:35.831702	t	2025-07-09 12:33:52.445708
1e4ec27f-21da-437a-87e7-e3b53dfdb206	048a5b2e-5919-4ebf-adbb-63d2d934f2d3	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 12:43:57.370263	f	\N
34cf44d8-0484-462d-b7a5-e59f5837d5d2	b87aaedb-e8f5-4774-92c9-5ae5b852e2b0	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 15:53:46.280411	t	2025-07-09 15:54:15.818798
e0647329-2c81-46b5-ac61-818b508e1b42	e6ce128c-aa76-4c9a-9b7a-116f194ab43b	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 15:56:12.72527	f	\N
5be22c35-b0f1-4e1b-9df3-57c85d889d8f	ca449815-00a8-45af-ba36-cbe745b44c09	0fa30159-b132-42f5-a7c5-47a4f4bbe9e3	2025-07-09 16:06:18.684287	t	2025-07-09 16:06:18.689871
9d2a5ff5-2935-47c3-b9d8-e2b19cc707fd	c867f814-0d0c-401e-910e-e6c02c80f31d	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 16:08:33.462623	t	2025-07-09 16:08:35.842386
e4ac93f1-a272-4164-8996-c9a316e46394	492bfb82-b58b-4974-80ba-4c6bed39afd6	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-09 16:13:14.544669	f	\N
1b5dcf1d-bca9-4d27-82fd-011f11ac094f	625f7594-ce52-4e18-a59d-5a0314fb1dfa	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-09 16:15:47.839725	t	2025-07-09 16:15:58.115152
bc53aa92-4f11-4f25-a543-5fec4e4a76a2	da50ab17-7652-4b50-a498-d23eb20512f9	989d493b-42ec-489f-b25f-c4700e8ee735	2025-07-10 11:04:47.610919	f	\N
a4b26c2a-0d4d-4d40-b653-ceeccbfff569	53d5d899-46e6-4122-846e-50700ab65ee7	8f43e562-9d44-4b54-8025-20824d3975af	2025-07-10 11:04:47.625504	f	\N
fd84e6b7-f19f-4979-94ee-95141b4a87be	5b8d8208-f084-49ff-93e2-0e0fa3c22e65	efdbfea9-63ee-46e2-a089-cdff1a89329b	2025-07-10 11:04:47.63795	f	\N
634096b5-0a5d-4cc9-8710-f03e74613d9a	f3390f5d-07e7-4b9e-ad6b-d95a58512e25	6611542b-d5be-441d-ba28-287b5b79903e	2025-07-10 11:41:16.737394	f	\N
\.


--
-- Data for Name: player_scores; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.player_scores (id, player_id, score_period, period_start, total_score, phrases_completed, avg_score, rank_position, last_updated) FROM stdin;
c712d002-6421-4288-b3a1-0aedcc1c8862	989d493b-42ec-489f-b25f-c4700e8ee735	daily	2025-07-09	100	1	100.00	1	2025-07-09 15:54:15.863037
0a91a6a2-d89c-4626-ba49-ebfdc2775567	842d0a5c-a025-4485-90c4-540ff3cfaaae	daily	2025-07-09	34	1	34.00	2	2025-07-09 15:47:37.445152
2703611b-d5e9-4e59-bbc6-4f55ebc350a5	989d493b-42ec-489f-b25f-c4700e8ee735	weekly	2025-07-07	100	1	100.00	3	2025-07-09 15:54:15.863037
1030899a-f831-4b14-808d-4fcc0163680f	3d01c53d-593b-4053-8004-63f33daece6c	weekly	2025-07-07	253	11	23.00	1	2025-07-08 16:02:00.873374
d9673736-f0d7-4c54-8df5-52f05ebee993	8f43e562-9d44-4b54-8025-20824d3975af	weekly	2025-07-07	95	2	47.50	4	2025-07-08 19:04:01.389136
7acbca1e-2709-479a-a947-75a37c37b657	842d0a5c-a025-4485-90c4-540ff3cfaaae	weekly	2025-07-07	170	5	34.00	2	2025-07-09 15:47:37.445152
a644b400-a446-4789-8e67-edd3b5358923	989d493b-42ec-489f-b25f-c4700e8ee735	total	1970-01-01	100	1	100.00	3	2025-07-09 15:54:15.863037
a6c8e2a5-2047-4ea6-9816-c4ccac3dfb31	3d01c53d-593b-4053-8004-63f33daece6c	total	1970-01-01	253	11	23.00	1	2025-07-08 16:02:00.873374
52ab85cd-9550-419a-8d2c-7d74c7babd38	8f43e562-9d44-4b54-8025-20824d3975af	total	1970-01-01	95	2	47.50	4	2025-07-08 19:04:01.389136
7272e484-db71-45b2-8584-1365ec4529d3	842d0a5c-a025-4485-90c4-540ff3cfaaae	total	1970-01-01	170	5	34.00	2	2025-07-09 15:47:37.445152
dd5d76ee-01a2-4be2-829a-91ef0a2babb5	842d0a5c-a025-4485-90c4-540ff3cfaaae	daily	2025-07-08	136	4	34.00	2	2025-07-08 16:02:02.746521
26e5b05d-0ace-434a-b194-b576cf0976de	3d01c53d-593b-4053-8004-63f33daece6c	daily	2025-07-08	253	11	23.00	1	2025-07-08 16:02:00.873374
31c154a6-5950-41f7-b592-05626e249abe	8f43e562-9d44-4b54-8025-20824d3975af	daily	2025-07-08	95	2	47.50	3	2025-07-08 19:04:01.389136
\.


--
-- Data for Name: players; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.players (id, name, is_active, last_seen, phrases_completed, socket_id, created_at) FROM stdin;
956bf461-441e-4a95-a743-fb4c08141995	Bosse	t	2025-07-07 21:32:56.004751	0	\N	2025-07-07 21:32:56.004751
40cc6572-dc8f-4a0f-b343-6363661c39f5	Klasse	t	2025-07-07 21:33:04.364926	0	\N	2025-07-07 21:33:04.364926
8f43e562-9d44-4b54-8025-20824d3975af	Mmeee	t	2025-07-09 15:25:46.478256	2	3HUdlqNI7wCjcLBXAACF	2025-07-07 22:07:18.783966
b82e1b95-7ee3-4475-b1d8-46edf4fd60cf	TestPlayer	t	2025-07-07 18:58:37.871733	2	test-socket-123	2025-07-07 18:25:45.12467
f976d33d-7710-427d-989e-198a6aa868be	ComprehensiveTestUser2	t	2025-07-09 16:06:10.587942	0	comp-test-2	2025-07-07 19:42:01.277397
3606db8a-7fba-4265-8fcd-c900bf1626ec	WSTestPlayer2_1751980944687	f	2025-07-08 15:22:30.703715	0	\N	2025-07-08 15:22:24.706578
c62a9f01-010b-44f4-8800-45bfce756218	ConcurrentUser_1_1751914839507	t	2025-07-07 21:00:39.513311	0	concurrent-1	2025-07-07 21:00:39.513311
0370daaf-bf40-4006-8087-dc96de96dea5	ConcurrentUser_0_1751914839507	t	2025-07-07 21:00:39.513932	0	concurrent-0	2025-07-07 21:00:39.513932
b7593035-06ef-4d72-b999-06f2ea547093	ConcurrentUser_2_1751914839508	t	2025-07-07 21:00:39.514676	0	concurrent-2	2025-07-07 21:00:39.514676
69de4fde-9ecd-4ad1-96dc-f8b39019075f	ConcurrentUser_4_1751914839509	t	2025-07-07 21:00:39.533693	0	concurrent-4	2025-07-07 21:00:39.533693
cce84b06-cc86-4600-81c6-c7976e5c57e1	ConcurrentUser_3_1751914839508	t	2025-07-07 21:00:39.534098	0	concurrent-3	2025-07-07 21:00:39.534098
7cd90cf4-c596-4f20-870b-705f7ca3a4a8	IntegrationPlayer1_1751914839535	t	2025-07-07 21:00:39.539784	0	integration-socket-1	2025-07-07 21:00:39.539784
2aed5a5f-684a-4956-8b97-4016d2666224	IntegrationPlayer2_1751914839540	t	2025-07-07 21:00:39.54932	0	integration-socket-2	2025-07-07 21:00:39.54932
3de25faa-49ca-4e35-ab6d-82f6cdbd37f0	BobTestPlayer	t	2025-07-08 16:01:48.249688	0	test-socket-1751983308235-0.3799832164707134	2025-07-07 19:25:03.878229
10d2a2f9-a68a-4f8a-9d70-a88b3a33547e	ConcurrentUser_1_1751914911293	t	2025-07-07 21:01:51.315996	0	concurrent-1	2025-07-07 21:01:51.315996
f38bec66-0ac8-4658-98f2-eb6191f442f0	ConcurrentUser_0_1751914911293	t	2025-07-07 21:01:51.308092	0	concurrent-0	2025-07-07 21:01:51.308092
7b1ea9ae-1fcf-41d5-afda-7da772a3558a	ConcurrentUser_2_1751914911294	t	2025-07-07 21:01:51.320523	0	concurrent-2	2025-07-07 21:01:51.320523
0f79e501-054b-434d-b714-5aabb9af6bf2	ConcurrentUser_0_1751910129334	t	2025-07-07 19:42:09.348209	0	concurrent-0	2025-07-07 19:42:09.348209
68ac3094-c920-4404-a3d3-bd529dda4fa5	ConcurrentUser_1_1751910129335	t	2025-07-07 19:42:09.354263	0	concurrent-1	2025-07-07 19:42:09.354263
f28944ec-8298-4593-875e-1365638c8313	ConcurrentUser_2_1751910129335	t	2025-07-07 19:42:09.35465	0	concurrent-2	2025-07-07 19:42:09.35465
3309ab86-c0d6-4c00-9d82-47efb4f51adc	ConcurrentUser_4_1751910129335	t	2025-07-07 19:42:09.355311	0	concurrent-4	2025-07-07 19:42:09.355311
dbc62d5a-f82d-4852-882c-43f9563b6c23	ConcurrentUser_3_1751910129335	t	2025-07-07 19:42:09.355512	0	concurrent-3	2025-07-07 19:42:09.355512
d0da4894-13c6-4532-a977-1978a1082e6e	IntegrationPlayer1_1751910129356	t	2025-07-07 19:42:09.357543	0	integration-socket-1	2025-07-07 19:42:09.357543
7d84cbe3-3020-44f7-aa37-4900feec5039	IntegrationPlayer2_1751910129358	t	2025-07-07 19:42:09.359149	0	integration-socket-2	2025-07-07 19:42:09.359149
dc4455cf-a150-4e9b-9c4f-32a1fe5cae49	ConcurrentUser_3_1751914911294	t	2025-07-07 21:01:51.354388	0	concurrent-3	2025-07-07 21:01:51.354388
32814393-f097-4805-b8aa-d0b6efe4fe53	ConcurrentUser_4_1751914911294	t	2025-07-07 21:01:51.354653	0	concurrent-4	2025-07-07 21:01:51.354653
89887052-5395-4554-af7b-4bb22a4c8265	IntegrationPlayer1_1751914911356	t	2025-07-07 21:01:51.356957	0	integration-socket-1	2025-07-07 21:01:51.356957
46a3809d-7d41-4e9e-aeee-11c3ffc2c8e1	IntegrationPlayer2_1751914911357	t	2025-07-07 21:01:51.358465	0	integration-socket-2	2025-07-07 21:01:51.358465
e36b8cc2-5ffa-42eb-8d4e-cc5fa4074677	Player-123	t	2025-07-07 21:06:03.053189	0	test-1751915163049	2025-07-07 19:42:09.325962
a02d96a4-f1f6-417b-b612-aa7bd2f65faf	Test_User	t	2025-07-07 21:06:03.056946	0	test-1751915163054	2025-07-07 19:42:09.32988
c8566422-adc5-4780-9a5e-defadfdcd788	ConcurrentUser_1_1751915163062	t	2025-07-07 21:06:03.071441	0	concurrent-1	2025-07-07 21:06:03.071441
d2d3d95a-5a94-4cda-8b13-667e95388d84	Phase3TestUser3	t	2025-07-07 20:02:32.287043	0	phase3-test-1751911352283-0.6396767884178395	2025-07-07 20:02:32.287043
485bb1f2-f992-423b-946e-c4a5a05cb178	ConcurrentUser_0_1751915163062	t	2025-07-07 21:06:03.071553	0	concurrent-0	2025-07-07 21:06:03.071553
926bb694-5368-431a-b170-2a6162000d44	Phase3TestUser2	f	2025-07-07 20:03:00.090388	0	\N	2025-07-07 20:02:32.281988
e8310d70-df21-4282-ac38-03363018aba3	ConcurrentUser_2_1751915163062	t	2025-07-07 21:06:03.086633	0	concurrent-2	2025-07-07 21:06:03.086633
7c4bcde4-13c5-4ea5-99ff-8152fdb56349	Phase3TestUser1	f	2025-07-07 20:05:16.874668	0	\N	2025-07-07 20:02:32.274739
895b7eef-6509-4a63-8cb3-b9819f3e24c3	ConcurrentUser_3_1751915163062	t	2025-07-07 21:06:03.087795	0	concurrent-3	2025-07-07 21:06:03.087795
19b27287-c11c-4f26-bacf-3a6a63e9db42	ConcurrentUser_4_1751915163062	t	2025-07-07 21:06:03.089147	0	concurrent-4	2025-07-07 21:06:03.089147
d319826a-1331-46a0-8cf9-c6e3076007a3	IntegrationPlayer1_1751915163090	t	2025-07-07 21:06:03.091983	0	integration-socket-1	2025-07-07 21:06:03.091983
3e848a96-a989-43e1-9917-429b96eaf814	IntegrationPlayer2_1751915163093	t	2025-07-07 21:06:03.094256	0	integration-socket-2	2025-07-07 21:06:03.094256
5cb3918b-eec5-491a-9476-9852788fb0ea	ConcurrentUser_0_1751914044815	t	2025-07-07 20:47:24.82584	0	concurrent-0	2025-07-07 20:47:24.82584
61c1974b-11df-417e-808e-04f4e9c64029	ConcurrentUser_1_1751914044815	t	2025-07-07 20:47:24.828708	0	concurrent-1	2025-07-07 20:47:24.828708
e4580249-5175-44b3-bbe9-9a61b98e8f29	ConcurrentUser_2_1751914044815	t	2025-07-07 20:47:24.827599	0	concurrent-2	2025-07-07 20:47:24.827599
a4949119-425d-4357-a573-72e3a9aeeaea	ConcurrentUser_4_1751914044816	t	2025-07-07 20:47:24.862266	0	concurrent-4	2025-07-07 20:47:24.862266
802ca675-e8b8-4cd6-8d16-f5ff078a207d	ConcurrentUser_3_1751914044815	t	2025-07-07 20:47:24.86247	0	concurrent-3	2025-07-07 20:47:24.86247
d180dfee-a6fd-489d-b056-196fc042a340	IntegrationPlayer1_1751914044864	t	2025-07-07 20:47:24.869682	0	integration-socket-1	2025-07-07 20:47:24.869682
6e029b8e-c018-4095-a3d3-d4dbd64d1f96	IntegrationPlayer2_1751914044871	t	2025-07-07 20:47:24.872565	0	integration-socket-2	2025-07-07 20:47:24.872565
e253bcc5-a8a3-485c-858d-73bc6caabba2	WSTestPlayer1_1751915258184	f	2025-07-07 21:07:44.19613	0	\N	2025-07-07 21:07:38.190802
331a18ff-016d-48bb-b233-83bf194ceb3b	WSTestPlayer2_1751915258193	f	2025-07-07 21:07:44.269382	0	\N	2025-07-07 21:07:38.220155
18d2d9a4-2bec-44bc-94f2-ac39ea3c5236	Player-123_1751915264202_0	t	2025-07-07 21:07:44.277371	0	test-1751915264202-0	2025-07-07 21:07:44.277371
9c3cdd4f-8166-49b3-83c4-16f25e3a9905	Test_User_1751915264295_1	t	2025-07-07 21:07:44.296889	0	test-1751915264295-1	2025-07-07 21:07:44.296889
e07c2e70-867e-4759-a2d9-f5c479b6837c	ConcurrentUser_0_1751915264301	t	2025-07-07 21:07:44.308504	0	concurrent-0	2025-07-07 21:07:44.308504
77351955-e4a4-4e7c-9b9e-f9b15c5529fe	ConcurrentUser_3_1751915264301	t	2025-07-07 21:07:44.309468	0	concurrent-3	2025-07-07 21:07:44.309468
9d0225e4-3754-471c-8ff1-0e6220c3802d	ConcurrentUser_2_1751915264301	t	2025-07-07 21:07:44.309367	0	concurrent-2	2025-07-07 21:07:44.309367
6a1110f3-5786-48ec-9745-2eb592f3bcc2	ConcurrentUser_1_1751915264301	t	2025-07-07 21:07:44.312525	0	concurrent-1	2025-07-07 21:07:44.312525
2c66d927-880b-4642-a548-e399e92918a5	ConcurrentUser_4_1751915264301	t	2025-07-07 21:07:44.338644	0	concurrent-4	2025-07-07 21:07:44.338644
beac55fc-9842-4212-afd7-5a939f5b5ad6	IntegrationPlayer1_1751915264342	t	2025-07-07 21:07:44.344315	0	integration-socket-1	2025-07-07 21:07:44.344315
faaadb0d-08b3-4a6b-8aac-159f5170ba89	IntegrationPlayer2_1751915264346	t	2025-07-07 21:07:44.347506	0	integration-socket-2	2025-07-07 21:07:44.347506
8299d480-659b-4e06-866a-7da36f85f389	test	t	2025-07-07 21:11:50.243596	0	123	2025-07-07 19:42:09.387558
40fb4579-dc0c-42d4-81ce-c8ba95e8e62f	WSTestPlayer1_1751915565716	f	2025-07-07 21:12:51.728106	0	\N	2025-07-07 21:12:45.734921
a2c5c30a-c10d-431f-87b7-f7bf0f6c116a	WSTestPlayer2_1751915565738	f	2025-07-07 21:12:51.762143	0	\N	2025-07-07 21:12:45.740767
adce6d3d-4694-4dab-8a85-64cc8f783195	Player-123_1751915571734_0	t	2025-07-07 21:12:51.76533	0	test-1751915571734-0	2025-07-07 21:12:51.76533
f98ea977-0758-4508-bbd7-24d6b52914c0	Test_User_1751915571767_1	t	2025-07-07 21:12:51.779014	0	test-1751915571767-1	2025-07-07 21:12:51.779014
95efe416-4d54-4475-84d4-2d623f80d4c4	ConcurrentUser_2_1751915571785	t	2025-07-07 21:12:51.817969	0	concurrent-2	2025-07-07 21:12:51.817969
40a84949-2939-4dff-a853-53d31e8da43f	ConcurrentUser_0_1751915571784	t	2025-07-07 21:12:51.830606	0	concurrent-0	2025-07-07 21:12:51.830606
6f6988f8-06dc-4389-9977-5072e2dfb6c0	ConcurrentUser_1_1751915571785	t	2025-07-07 21:12:51.83815	0	concurrent-1	2025-07-07 21:12:51.83815
79a28f29-c165-460d-93c6-a2c21043181d	ConcurrentUser_3_1751915571785	t	2025-07-07 21:12:51.851117	0	concurrent-3	2025-07-07 21:12:51.851117
66212d7d-988a-483f-91fe-3669eaa0bc3e	ConcurrentUser_4_1751915571785	t	2025-07-07 21:12:51.85104	0	concurrent-4	2025-07-07 21:12:51.85104
b272f6c8-143d-4e05-8a94-de1769445b59	IntegrationPlayer1_1751915571853	t	2025-07-07 21:12:51.857252	0	integration-socket-1	2025-07-07 21:12:51.857252
cbe23d8b-16aa-40c6-a6cd-e1b424d3b60a	IntegrationPlayer2_1751915571859	t	2025-07-07 21:12:51.859904	0	integration-socket-2	2025-07-07 21:12:51.859904
0671fb3b-1bfe-43e7-bf17-b936f76f33d4	WSTestPlayer1_1751980944679	f	2025-07-08 15:22:30.687516	0	\N	2025-07-08 15:22:24.685681
99d2a217-42d5-414a-b4f1-2afa0baeea7a	ConcurrentUser_3_1751980950839	t	2025-07-08 15:22:30.882935	0	concurrent-3	2025-07-08 15:22:30.882935
f1e4411f-8b37-4185-9585-22e92a82a04c	ValidSocketString_1751917624350	t	2025-07-07 21:47:04.368726	0	valid-string-id	2025-07-07 21:47:04.368726
468954d5-42b3-4f6f-a49a-eedf265d916d	ValidSocketNull_1751917624372	t	2025-07-07 21:47:04.382112	0	\N	2025-07-07 21:47:04.382112
9bc243e7-4f78-4bd3-9d73-cf632f6cb6e0	ValidSocketUndefined_1751917624383	t	2025-07-07 21:47:04.389193	0	\N	2025-07-07 21:47:04.389193
6d096c8e-5b0a-43c6-a4e5-bb1aa4a52a04	FormatTestPlayer_1751917624390	t	2025-07-07 21:47:04.405106	0	format-test-socket	2025-07-07 21:47:04.405106
cb380c6d-2c70-445e-8b5e-f58ff86e13d8	ModernAppUser_1751917624988	t	2025-07-07 21:47:04.989788	0	modern-socket	2025-07-07 21:47:04.989788
ef2ae282-a53e-4f37-bbcf-f1f703e4bada	StatusTestPlayer_1751917699828	t	2025-07-07 21:48:19.874825	0	status-test	2025-07-07 21:48:19.874825
4aa4ff17-5957-448e-bcd8-901b7c914287	ValidSocketString_1751917736030	t	2025-07-07 21:48:56.054769	0	valid-string-id	2025-07-07 21:48:56.054769
da0122f9-476d-4257-842c-fd2b194a216e	ValidSocketNull_1751917736057	t	2025-07-07 21:48:56.0611	0	\N	2025-07-07 21:48:56.0611
cceb1850-f59b-4e84-8d49-713c300228f8	ValidSocketUndefined_1751917736063	t	2025-07-07 21:48:56.067866	0	\N	2025-07-07 21:48:56.067866
fb0305ca-59ab-4d2f-9b83-9be49db123fd	FormatTestPlayer_1751917736069	t	2025-07-07 21:48:56.071756	0	format-test-socket	2025-07-07 21:48:56.071756
7495af42-0fb1-463f-8bcc-f90c6346bd9a	ModernAppUser_1751917736390	t	2025-07-07 21:48:56.392399	0	modern-socket	2025-07-07 21:48:56.392399
b61b7686-01e4-483f-8942-78170b391bc6	StatusTestPlayer_1751917970429	t	2025-07-07 21:52:50.460294	0	status-test	2025-07-07 21:52:50.460294
53e405ad-4843-45da-b15e-a268c37a43f3	ApprovalTestPlayer_1751919043086_mktzgab5f	t	2025-07-07 22:10:43.138216	0	test-socket-1751919043086-7xwm6sdzt	2025-07-07 22:10:43.138216
dbe18fb1-2dc4-4a6d-97d7-66059135706b	NonGlobalPlayer1_1751919043205_hebk373qj	t	2025-07-07 22:10:43.211803	0	test-socket-1751919043205-86sm06o3p	2025-07-07 22:10:43.211803
78cab71b-bccd-489d-affa-0f4c537ca799	NonGlobalPlayer2_1751919043215_c3kwx3l1f	t	2025-07-07 22:10:43.218538	0	test-socket-1751919043215-ac6xvh0vt	2025-07-07 22:10:43.218538
eb22082b-b283-4d06-8267-4de309582897	AlreadyApprovedPlayer_1751919043251_fwjiscuvc	t	2025-07-07 22:10:43.253239	0	test-socket-1751919043251-3ms7zvlx6	2025-07-07 22:10:43.253239
3371a4b3-aed8-43c6-b845-79db1c88592d	ResponseFormatPlayer_1751919043271_k6wg42i3l	t	2025-07-07 22:10:43.27382	0	test-socket-1751919043271-03ykb0upv	2025-07-07 22:10:43.27382
3839350a-9c43-4d15-8c41-bb060e8b5e74	VisibilityTestPlayer_1751919043288_v4hxq7qmc	t	2025-07-07 22:10:43.299285	0	test-socket-1751919043288-p0zfh8k1m	2025-07-07 22:10:43.299285
974a587a-54d6-469a-b775-51e0e2fe92b9	TestPlayer1_1751920204831	t	2025-07-07 22:30:04.992227	0	\N	2025-07-07 22:30:04.992227
bdc9f5d2-31d9-4cf4-8b43-26bf9536270f	TestPlayer2_1751920204998	t	2025-07-07 22:30:05.000192	0	\N	2025-07-07 22:30:05.000192
340d5325-47e7-4f3f-b904-e93cd6051c78	TestPlayer3_1751920205003	t	2025-07-07 22:30:05.011951	0	\N	2025-07-07 22:30:05.011951
dd2064cd-8351-4fae-809c-171f0f59f7b5	TestPlayerOffline	t	2025-07-07 22:31:02.143132	0	\N	2025-07-07 22:31:02.143132
4a67af66-246c-4fb4-ab15-1d23cc9724ed	TestPlayer1_1751920278334	t	2025-07-07 22:31:18.35551	0	\N	2025-07-07 22:31:18.35551
c722bd54-5717-4ed2-a311-ba47c32aff6a	TestPlayer2_1751920278358	t	2025-07-07 22:31:18.360756	0	\N	2025-07-07 22:31:18.360756
9a9b4e2d-283f-4111-bed1-b5cfa62b6856	TestPlayer3_1751920278362	t	2025-07-07 22:31:18.374351	0	\N	2025-07-07 22:31:18.374351
901682b0-3c53-42af-b7af-c3787b52c306	TestPlayer1_1751920564816	t	2025-07-07 22:36:04.842119	0	\N	2025-07-07 22:36:04.842119
b0adf5d0-ff2c-4e1c-8d1c-f7328323af2e	TestPlayer2_1751920564846	t	2025-07-07 22:36:04.848607	0	\N	2025-07-07 22:36:04.848607
76cf776d-1d08-4cd2-b9da-e17db5beff33	TestPlayer3_1751920564859	t	2025-07-07 22:36:04.861685	0	\N	2025-07-07 22:36:04.861685
5b8a6048-31c5-453a-a5c6-ad8a7660fa08	FreshTestPlayer	t	2025-07-07 22:41:55.520024	0	\N	2025-07-07 22:41:55.520024
40682e11-e7fc-4b84-9ad3-2c09298f67d5	TestPlayer1_1751920959717	t	2025-07-07 22:42:39.784453	0	\N	2025-07-07 22:42:39.784453
03a4ccad-2557-4828-b1ec-e4d3d0cb2dcd	TestPlayer2_1751920959800	t	2025-07-07 22:42:39.802274	0	\N	2025-07-07 22:42:39.802274
d0654012-742d-4e23-ab6c-5d921574a1c0	TestPlayer3_1751920959804	t	2025-07-07 22:42:39.810387	0	\N	2025-07-07 22:42:39.810387
12bb186c-3aaf-428b-9182-5fea9984e1b3	TestPlayer1_1751921040462	t	2025-07-07 22:44:00.485521	0	\N	2025-07-07 22:44:00.485521
d238f9eb-6432-426f-969b-a394ae850893	TestPlayer2_1751921040493	t	2025-07-07 22:44:00.495582	0	\N	2025-07-07 22:44:00.495582
3c091e8b-8ee2-4d42-bfdc-ecfbf1f3a3ad	TestPlayer3_1751921040496	t	2025-07-07 22:44:00.49859	0	\N	2025-07-07 22:44:00.49859
c9b235db-4309-4573-9800-db505f70274c	TestPlayer1_1751921427219	t	2025-07-07 22:50:27.308252	0	\N	2025-07-07 22:50:27.308252
38b317b0-8468-4ef2-9ef2-e621233e4619	TestPlayer2_1751921427315	t	2025-07-07 22:50:27.317396	0	\N	2025-07-07 22:50:27.317396
7934628e-6daa-4b73-857c-db4c5fdc9c3a	TestPlayer3_1751921427318	t	2025-07-07 22:50:27.320194	0	\N	2025-07-07 22:50:27.320194
1203de34-904c-405f-97c0-00ae573062ff	ChampionPlayer_1751921427538	t	2025-07-07 22:50:27.546007	0	\N	2025-07-07 22:50:27.546007
9db0a42d-b964-4ede-9e37-68c3c7c0b8d2	TestPlayer1_1751921604629	t	2025-07-07 22:53:24.702533	0	\N	2025-07-07 22:53:24.702533
c987746c-1945-4170-a67d-19e8eabfbffc	TestPlayer2_1751921604708	t	2025-07-07 22:53:24.713948	0	\N	2025-07-07 22:53:24.713948
a860abd6-2fee-4838-9e84-0f8ce4cf96c8	TestPlayer3_1751921604715	t	2025-07-07 22:53:24.720741	0	\N	2025-07-07 22:53:24.720741
b10c80be-b76f-4182-b18b-26495c71700c	ChampionPlayer_1751921604857	t	2025-07-07 22:53:24.863113	0	\N	2025-07-07 22:53:24.863113
39981124-6a61-421f-912f-6dbee57849eb	ManualChampionTest	t	2025-07-07 22:54:53.447702	0	\N	2025-07-07 22:54:53.447702
57e87ec4-f54f-4b6a-bb8b-018a0d606b28	DownloadTestPlayer	t	2025-07-07 23:12:36.833933	0	\N	2025-07-07 23:12:36.833933
95d68292-0f0e-4d95-ab21-70061c1f079e	John Doe	t	2025-07-07 23:46:29.042166	0	xyz123abc	2025-07-07 23:46:29.042166
bd068ef7-9edb-4173-a702-84aef1f47f78	WSTestPlayer1_1751925756824	f	2025-07-08 00:02:42.827126	0	\N	2025-07-08 00:02:36.829392
0f13e04f-7c4f-4346-9ce0-0d0789c02a5f	WSTestPlayer2_1751925756831	f	2025-07-08 00:02:42.833125	0	\N	2025-07-08 00:02:36.834666
71a2d951-9411-4b85-9521-15e3d2e73462	Player-123_1751925762834_0	t	2025-07-08 00:02:42.846617	0	test-1751925762834-0	2025-07-08 00:02:42.846617
faa4495b-00a0-4b68-99f0-640eb374435c	Test_User_1751925762848_1	t	2025-07-08 00:02:42.849483	0	test-1751925762848-1	2025-07-08 00:02:42.849483
fdf6acf0-fe58-41d2-9cc0-9ccf7a38d432	ConcurrentUser_0_1751925762855	t	2025-07-08 00:02:42.876048	0	concurrent-0	2025-07-08 00:02:42.876048
478cdc63-1b8f-483f-9ffc-654c0733ca0b	ConcurrentUser_1_1751925762855	t	2025-07-08 00:02:42.87886	0	concurrent-1	2025-07-08 00:02:42.87886
8a17785c-979f-4a2d-a788-f728366e76e0	ConcurrentUser_2_1751925762855	t	2025-07-08 00:02:42.879472	0	concurrent-2	2025-07-08 00:02:42.879472
86dc21bc-374e-4190-986a-2da8ef284a2c	ConcurrentUser_3_1751925762855	t	2025-07-08 00:02:42.879714	0	concurrent-3	2025-07-08 00:02:42.879714
49186290-9c69-4da1-aa42-66c943d4944d	ConcurrentUser_4_1751925762855	t	2025-07-08 00:02:42.879822	0	concurrent-4	2025-07-08 00:02:42.879822
f123666c-7101-42ff-9945-f0a80359edbf	IntegrationPlayer1_1751925762909	t	2025-07-08 00:02:42.911647	0	integration-socket-1	2025-07-08 00:02:42.911647
5cc1fc63-ecb3-42c0-bf44-9cd6756d6934	IntegrationPlayer2_1751925762914	t	2025-07-08 00:02:42.91856	0	integration-socket-2	2025-07-08 00:02:42.91856
5006b465-d0d3-4364-9d0f-8f79b10130fb	ApprovalTestPlayer_1751925763100_c6afektuk	t	2025-07-08 00:02:43.10165	0	test-socket-1751925763100-j0qiw905i	2025-07-08 00:02:43.10165
cdbdaa45-d9e6-4506-8433-9127c7e5f46c	NonGlobalPlayer1_1751925763111_mrzaocjsq	t	2025-07-08 00:02:43.111926	0	test-socket-1751925763111-igh50h5ee	2025-07-08 00:02:43.111926
d5721161-531f-4910-a17c-ec4068e754e3	NonGlobalPlayer2_1751925763112_wr4ix3sc2	t	2025-07-08 00:02:43.114104	0	test-socket-1751925763112-hpf7ct0rb	2025-07-08 00:02:43.114104
44942768-c4a5-4327-ae8a-fbf6d7e89f29	AlreadyApprovedPlayer_1751925763127_1nuv7wb35	t	2025-07-08 00:02:43.129053	0	test-socket-1751925763127-w5y2bfa0s	2025-07-08 00:02:43.129053
2417a2bd-3ee0-4bf4-bb22-78205d8b8429	ResponseFormatPlayer_1751925763136_lo4omolqp	t	2025-07-08 00:02:43.137267	0	test-socket-1751925763136-qx2cntk4f	2025-07-08 00:02:43.137267
525945c6-22bf-48c7-b58d-b4ddd0f1878b	VisibilityTestPlayer_1751925763150_l1a1h2ofz	t	2025-07-08 00:02:43.150894	0	test-socket-1751925763150-1y4wr17cq	2025-07-08 00:02:43.150894
57feef81-fae9-49c4-b9fa-e51121362589	ValidSocketString_1751925763166	t	2025-07-08 00:02:43.167863	0	valid-string-id	2025-07-08 00:02:43.167863
71e637aa-31e7-442f-bf69-ab3298edb2d9	ValidSocketNull_1751925763170	t	2025-07-08 00:02:43.1771	0	\N	2025-07-08 00:02:43.1771
4be395f3-e95e-4f5d-bae4-96d06c73d11d	Asdf	f	2025-07-08 11:18:24.037542	0	\N	2025-07-07 21:35:11.972525
d8684d2b-d111-490c-bc65-a297091d2d11	WSTestPlayer1_1752069972604	f	2025-07-09 16:06:18.614495	0	\N	2025-07-09 16:06:12.608154
0294f5ae-0dab-42c5-a1f0-b0ce2a538b41	Player-123_1751980950692_0	t	2025-07-08 15:22:30.717828	0	test-1751980950692-0	2025-07-08 15:22:30.717828
19d8b001-d530-48e0-93c8-621a99836055	StatusTestPlayer_1751917624856	t	2025-07-07 21:47:04.887163	0	status-test	2025-07-07 21:47:04.887163
2560b8bb-4966-4d67-812a-60f37cac3cf4	WSTestPlayer1_1751915656674	f	2025-07-07 21:14:22.700222	0	\N	2025-07-07 21:14:16.680284
d5154ab6-9cf2-4de8-950b-7669a0494bbf	WSTestPlayer2_1751915656693	f	2025-07-07 21:14:22.744914	0	\N	2025-07-07 21:14:16.694549
ee9aeeb7-6aac-4143-8162-1879e332ab57	Player-123_1751915662706_0	t	2025-07-07 21:14:22.768109	0	test-1751915662706-0	2025-07-07 21:14:22.768109
a5e5a07d-2f38-48d4-8ede-6ef8fe255dc2	Test_User_1751915662794_1	t	2025-07-07 21:14:22.801028	0	test-1751915662794-1	2025-07-07 21:14:22.801028
1ff7e9a3-ebc7-4441-be29-5620598c1ae0	ConcurrentUser_1_1751915662806	t	2025-07-07 21:14:22.82722	0	concurrent-1	2025-07-07 21:14:22.82722
891fd953-f19a-4cf1-8759-79ca0f368fe5	ConcurrentUser_2_1751915662806	t	2025-07-07 21:14:22.827543	0	concurrent-2	2025-07-07 21:14:22.827543
bd8e8704-f4fd-44ad-b083-e8bae936a3eb	ConcurrentUser_0_1751915662805	t	2025-07-07 21:14:22.831102	0	concurrent-0	2025-07-07 21:14:22.831102
741f8c35-f156-4bed-be85-6a33d998d5dc	ConcurrentUser_3_1751915662806	t	2025-07-07 21:14:22.844953	0	concurrent-3	2025-07-07 21:14:22.844953
ffc6994b-53de-4f1f-bad3-375679ee8523	ConcurrentUser_4_1751915662806	t	2025-07-07 21:14:22.934379	0	concurrent-4	2025-07-07 21:14:22.934379
004a92bd-7600-44f3-959d-60e4b8f8d95e	IntegrationPlayer1_1751915662947	t	2025-07-07 21:14:22.949541	0	integration-socket-1	2025-07-07 21:14:22.949541
4c499e07-c79e-445a-b081-efd89328bc28	IntegrationPlayer2_1751915662950	t	2025-07-07 21:14:22.951497	0	integration-socket-2	2025-07-07 21:14:22.951497
c61eaa45-aa2e-41d7-ac8e-c86970348466	ValidSocketString_1751917699667	t	2025-07-07 21:48:19.688482	0	valid-string-id	2025-07-07 21:48:19.688482
2867b455-c969-4e43-922e-124bedad465b	ValidSocketNull_1751917699690	t	2025-07-07 21:48:19.703827	0	\N	2025-07-07 21:48:19.703827
ae76b214-21ed-4283-b472-db79833a1015	ValidSocketUndefined_1751917699705	t	2025-07-07 21:48:19.722289	0	\N	2025-07-07 21:48:19.722289
fa87179a-0234-4cad-b614-e23a28fdd604	WSTestPlayer1_1751915705452	f	2025-07-07 21:15:11.478388	0	\N	2025-07-07 21:15:05.464084
bab2a3c4-b393-40de-89e5-a064733b99b2	Player-123_1751915711481_0	t	2025-07-07 21:15:11.514063	0	test-1751915711481-0	2025-07-07 21:15:11.514063
8bf8f8f3-4c93-43f8-92f2-aeafc599b50d	Test_User_1751915711515_1	t	2025-07-07 21:15:11.518925	0	test-1751915711515-1	2025-07-07 21:15:11.518925
037419d0-a350-4761-9783-ab0fe6f82b3d	ConcurrentUser_0_1751915711524	t	2025-07-07 21:15:11.537848	0	concurrent-0	2025-07-07 21:15:11.537848
d3b97577-6edb-430f-8d00-6865f01faf7e	WSTestPlayer2_1751915705466	f	2025-07-07 21:15:11.539897	0	\N	2025-07-07 21:15:05.47199
7fdf9e90-fb2d-4078-b914-c1378a7e24a0	ConcurrentUser_2_1751915711525	t	2025-07-07 21:15:11.553724	0	concurrent-2	2025-07-07 21:15:11.553724
a1bee603-a305-4226-a367-5f7f090a1c4e	ConcurrentUser_1_1751915711524	t	2025-07-07 21:15:11.553508	0	concurrent-1	2025-07-07 21:15:11.553508
93869753-b717-43d5-90d8-48fe04383297	ConcurrentUser_4_1751915711525	t	2025-07-07 21:15:11.555434	0	concurrent-4	2025-07-07 21:15:11.555434
03877f6e-5d08-4f9f-bfcd-11bde283a41c	ConcurrentUser_3_1751915711525	t	2025-07-07 21:15:11.555743	0	concurrent-3	2025-07-07 21:15:11.555743
c2cc4bb4-f035-4962-ba11-b4e72f50035a	IntegrationPlayer1_1751915711557	t	2025-07-07 21:15:11.558104	0	integration-socket-1	2025-07-07 21:15:11.558104
c71f91c8-a60d-4eff-af40-03ea02e5bebe	IntegrationPlayer2_1751915711559	t	2025-07-07 21:15:11.561412	0	integration-socket-2	2025-07-07 21:15:11.561412
d23579ab-b7b3-4581-93f2-fb9e5a2a0d93	FormatTestPlayer_1751917699725	t	2025-07-07 21:48:19.735322	0	format-test-socket	2025-07-07 21:48:19.735322
59321f72-5969-4137-9f3c-064f62a778ef	ModernAppUser_1751917700073	t	2025-07-07 21:48:20.088798	0	modern-socket	2025-07-07 21:48:20.088798
dcded7e9-65dd-4033-a993-08c0171198aa	WSTestPlayer1_1751915727754	f	2025-07-07 21:15:33.76189	0	\N	2025-07-07 21:15:27.766284
98945f13-0280-407d-a720-b0d4347ee08b	WSTestPlayer2_1751915727768	f	2025-07-07 21:15:33.761904	0	\N	2025-07-07 21:15:27.783513
0690f026-50ed-42fb-afe7-e0045efc5839	Player-123_1751915733763_0	t	2025-07-07 21:15:33.7797	0	test-1751915733763-0	2025-07-07 21:15:33.7797
5a9c8245-4a78-4d52-8e96-089bbbf40679	Test_User_1751915733781_1	t	2025-07-07 21:15:33.789795	0	test-1751915733781-1	2025-07-07 21:15:33.789795
af9d8a29-28c4-40bf-b45a-8daf9c177602	ConcurrentUser_1_1751915733797	t	2025-07-07 21:15:33.823127	0	concurrent-1	2025-07-07 21:15:33.823127
11411329-48ce-4f3d-b1c1-e06edee43731	ConcurrentUser_2_1751915733797	t	2025-07-07 21:15:33.823289	0	concurrent-2	2025-07-07 21:15:33.823289
4af04bbc-c2e5-482f-b4ee-41c05f28eb4b	ConcurrentUser_0_1751915733797	t	2025-07-07 21:15:33.82473	0	concurrent-0	2025-07-07 21:15:33.82473
87779961-d351-468f-bc8f-20d52f3ff744	ConcurrentUser_3_1751915733798	t	2025-07-07 21:15:33.842843	0	concurrent-3	2025-07-07 21:15:33.842843
214125ac-328b-42f5-9297-16ee90428794	ConcurrentUser_4_1751915733798	t	2025-07-07 21:15:33.849261	0	concurrent-4	2025-07-07 21:15:33.849261
88e5d907-b590-4a04-adae-3ece35bf8240	IntegrationPlayer1_1751915733851	t	2025-07-07 21:15:33.852381	0	integration-socket-1	2025-07-07 21:15:33.852381
f2ec11c4-3a7f-4c4a-b4f9-cc0dd98b4a1e	IntegrationPlayer2_1751915733853	t	2025-07-07 21:15:33.855849	0	integration-socket-2	2025-07-07 21:15:33.855849
15e01aad-e72d-48fb-a151-6f8aa12c8be5	Asdsaadfssdfdfsa	t	2025-07-07 21:27:23.57747	0	\N	2025-07-07 21:27:23.57747
869af75c-32aa-46e6-b70f-b3e32e1b6259	Frasse	t	2025-07-07 21:27:29.370376	0	\N	2025-07-07 21:27:29.370376
d3d9a025-1447-4837-a275-8a272d9eed09	Rune	t	2025-07-07 21:27:34.683445	0	\N	2025-07-07 21:27:34.683445
d5c239e9-5686-41ed-9255-915289d78e6c	StatusTestPlayer_1751917736242	t	2025-07-07 21:48:56.274706	0	status-test	2025-07-07 21:48:56.274706
a306226b-329f-4c5e-85de-fa16e685a865	Bruno	t	2025-07-07 21:27:48.242095	0	\N	2025-07-07 21:27:42.967168
76832a95-e644-4c49-8282-1879003166a4	ValidSocketString_1751917970091	t	2025-07-07 21:52:50.144108	0	valid-string-id	2025-07-07 21:52:50.144108
b87c04fc-abd7-4248-8339-458b83038dfe	ValidSocketNull_1751917970146	t	2025-07-07 21:52:50.170547	0	\N	2025-07-07 21:52:50.170547
40c65104-79be-45c8-9e37-d598c9e6acf5	ValidSocketUndefined_1751917970172	t	2025-07-07 21:52:50.175277	0	\N	2025-07-07 21:52:50.175277
2aea220f-91f0-4d7b-ab6b-dba1f88fcd15	FormatTestPlayer_1751917970176	t	2025-07-07 21:52:50.189225	0	format-test-socket	2025-07-07 21:52:50.189225
6150242b-af79-42d6-bc19-16f14c863231	ModernAppUser_1751917971028	t	2025-07-07 21:52:51.038515	0	modern-socket	2025-07-07 21:52:51.038515
9eeddf1f-227b-485b-9ab7-c2aa43025593	ApprovalTestPlayer_1751918938905_mao0c53kw	t	2025-07-07 22:08:58.969635	0	test-socket-1751918938905-m2a4iovot	2025-07-07 22:08:58.969635
16a2f8f3-a31b-4802-a12c-52072303bff6	NonGlobalPlayer1_1751918939028_wlhwppb9e	t	2025-07-07 22:08:59.029966	0	test-socket-1751918939028-6im7ev145	2025-07-07 22:08:59.029966
0b5636fa-eecd-429c-9f3b-0b10e7ca70f6	NonGlobalPlayer2_1751918939031_1imw0jwiy	t	2025-07-07 22:08:59.045327	0	test-socket-1751918939031-fsc882yt4	2025-07-07 22:08:59.045327
c4b7d178-7c02-44e0-97fe-cb1f8108c7e1	ApprovalTestPlayer_1751918987323_d45atflh2	t	2025-07-07 22:09:47.343955	0	test-socket-1751918987323-qflr2nfdd	2025-07-07 22:09:47.343955
23748510-8839-4334-9f74-20b76dc36c3e	NonGlobalPlayer1_1751918987365_46x2ec8h8	t	2025-07-07 22:09:47.367209	0	test-socket-1751918987365-fxal6235y	2025-07-07 22:09:47.367209
938ade80-b6de-4243-a9f4-1c1099b973f0	NonGlobalPlayer2_1751918987368_7mw030ph5	t	2025-07-07 22:09:47.383013	0	test-socket-1751918987368-ibfk9jet1	2025-07-07 22:09:47.383013
3abcdb2a-a750-4095-99e0-525443896f38	AlreadyApprovedPlayer_1751918987408_akn7ecczs	t	2025-07-07 22:09:47.415334	0	test-socket-1751918987408-vzn6tnnzu	2025-07-07 22:09:47.415334
68f83f5d-c9f0-4822-801f-ca0a285a1349	ResponseFormatPlayer_1751918987436_gnwxaay70	t	2025-07-07 22:09:47.43812	0	test-socket-1751918987436-onwn4h2gw	2025-07-07 22:09:47.43812
fe43ae0d-3310-4458-9279-c4f25ea79445	VisibilityTestPlayer_1751918987469_z6ets0gaq	t	2025-07-07 22:09:47.470537	0	test-socket-1751918987469-g9l5lm9wy	2025-07-07 22:09:47.470537
44c0515e-c2d3-4145-8432-3f5e9f34a7a0	ApprovalTestPlayer_1751919180471_senbmdfvr	t	2025-07-07 22:13:00.519399	0	test-socket-1751919180471-3mjfka5ks	2025-07-07 22:13:00.519399
c143e11c-9e54-4804-b8bc-4057af36d423	NonGlobalPlayer1_1751919180535_z7zfoiyui	t	2025-07-07 22:13:00.536743	0	test-socket-1751919180535-7r0y0ymwb	2025-07-07 22:13:00.536743
57a8c4db-4039-4e1c-9aa7-b59de6553164	NonGlobalPlayer2_1751919180537_9bnuk4q1i	t	2025-07-07 22:13:00.571728	0	test-socket-1751919180537-wmmmwsvu9	2025-07-07 22:13:00.571728
a63e5ff9-f50b-430c-a4d5-57cebe8f4f15	AlreadyApprovedPlayer_1751919180600_upk748f05	t	2025-07-07 22:13:00.603918	0	test-socket-1751919180600-qwno832ur	2025-07-07 22:13:00.603918
ab48b17c-78bc-4453-89c8-3fdd5101bbeb	ResponseFormatPlayer_1751919180619_p3g3d1mbj	t	2025-07-07 22:13:00.621447	0	test-socket-1751919180619-3b9cy2qfl	2025-07-07 22:13:00.621447
e77d7fa3-277c-4c5f-8e3d-271ac0ba1a0a	VisibilityTestPlayer_1751919180667_ng94veest	t	2025-07-07 22:13:00.668208	0	test-socket-1751919180667-zihpgvbut	2025-07-07 22:13:00.668208
854e272a-5d4d-478c-8139-d5fc3f8e0939	Fasdffasd	f	2025-07-08 11:18:23.825145	0	\N	2025-07-07 21:35:17.783846
751a6388-c6d0-4a5a-b172-dcdc663b94c0	ValidSocketUndefined_1751925763178	t	2025-07-08 00:02:43.183135	0	\N	2025-07-08 00:02:43.183135
27dbe1c5-05f9-4873-abab-07e06fefce36	FormatTestPlayer_1751925763184	t	2025-07-08 00:02:43.195645	0	format-test-socket	2025-07-08 00:02:43.195645
c488d054-9f47-469e-938c-f9cc4caef3d5	WSTestPlayer1_1751979821368	f	2025-07-08 15:03:47.377564	0	\N	2025-07-08 15:03:41.376027
aebcc673-fe39-43bc-9343-e50d1db4ffba	ConcurrentUser_1_1751979827644	t	2025-07-08 15:03:47.673555	0	concurrent-1	2025-07-08 15:03:47.673555
4cad8b49-493d-4a34-90a3-221715b1e1ba	ConcurrentUser_2_1751979827645	t	2025-07-08 15:03:47.69654	0	concurrent-2	2025-07-08 15:03:47.69654
a1a4cd9e-65d1-4d9a-be74-ce0033893c94	Test_User_1751980950786_1	t	2025-07-08 15:22:30.810749	0	test-1751980950786-1	2025-07-08 15:22:30.810749
be04d984-ee88-400f-a125-2dca4746e706	ConcurrentUser_0_1751980950838	t	2025-07-08 15:22:30.840018	0	concurrent-0	2025-07-08 15:22:30.840018
ba4c55b5-9c77-4e12-9908-130fd34fd533	ConcurrentUser_1_1751980950838	t	2025-07-08 15:22:30.883081	0	concurrent-1	2025-07-08 15:22:30.883081
8b162299-7933-4498-a8b9-a9f271f37fda	IntegrationPlayer1_1751980950889	t	2025-07-08 15:22:30.890488	0	integration-socket-1	2025-07-08 15:22:30.890488
1013a7ce-a3ef-4c4f-bf5f-90c1b6d73882	Player-123_1751980258050_0	t	2025-07-08 15:10:58.069491	0	test-1751980258050-0	2025-07-08 15:10:58.069491
64697f30-bd3a-491d-8e13-3b68cc5a6a7a	ConcurrentUser_2_1751980258125	t	2025-07-08 15:10:58.222526	0	concurrent-2	2025-07-08 15:10:58.222526
9999aeff-421f-4533-8dbd-33f159a93756	StatusTestPlayer_1751980258913	t	2025-07-08 15:10:58.914169	0	status-test	2025-07-08 15:10:58.914169
da9a14f5-a12b-4b53-aada-e1530fac4280	IntegrationPlayer2_1751980950891	t	2025-07-08 15:22:30.892832	0	integration-socket-2	2025-07-08 15:22:30.892832
0c0eab7e-ee0d-4f87-baa8-f23f8fb2a994	WSTestPlayer1_1751980334008	f	2025-07-08 15:12:20.015371	0	\N	2025-07-08 15:12:14.032011
61a70843-519f-48ef-87c4-42d385a8f683	WSTestPlayer2_1751980334038	f	2025-07-08 15:12:20.015389	0	\N	2025-07-08 15:12:14.052102
3160dbbf-1e0a-4b8a-a9d4-bccadb88c0f4	ConcurrentUser_2_1751980340134	t	2025-07-08 15:12:20.167653	0	concurrent-2	2025-07-08 15:12:20.167653
02379b19-2f55-4a6e-90a3-2342687c66c8	ConcurrentUser_0_1751980340133	t	2025-07-08 15:12:20.168739	0	concurrent-0	2025-07-08 15:12:20.168739
53ec24d0-0979-410b-a3ca-204fd281d482	ModernAppUser_1751980340772	t	2025-07-08 15:12:20.773661	0	modern-socket	2025-07-08 15:12:20.773661
74301c21-ab31-4f58-a947-cfd9c72b888a	WSTestPlayer1_1751981258518	f	2025-07-08 15:27:44.5473	0	\N	2025-07-08 15:27:38.527257
c80da943-ab2e-4f94-b3cd-f5e55574c18a	WSTestPlayer2_1751981258530	f	2025-07-08 15:27:44.54737	0	\N	2025-07-08 15:27:38.536645
87d6dcd1-3d92-4191-bedc-8fcfdd327953	ConcurrentUser_1_1751981264598	t	2025-07-08 15:27:44.607765	0	concurrent-1	2025-07-08 15:27:44.607765
37ffaa57-a959-4811-be0f-db7b139fd483	ConcurrentUser_3_1751981264599	t	2025-07-08 15:27:44.632882	0	concurrent-3	2025-07-08 15:27:44.632882
f9eb55db-405a-4ccd-a167-ef075dc24069	StatusTestPlayer_1751981265078	t	2025-07-08 15:27:45.079204	0	status-test	2025-07-08 15:27:45.079204
aee5986b-3fc2-40d7-a55e-2df9872efdd2	ScoringTestPlayer2	t	2025-07-09 15:47:36.136449	0	\N	2025-07-08 15:42:39.114122
11530b42-2ad0-4c6c-a5e2-d5c42e1e1352	ConcurrentUser_3_1751982655337	t	2025-07-08 15:50:55.341708	0	concurrent-3	2025-07-08 15:50:55.341708
aa2db026-bd21-4213-9912-5e6174efbdc3	ConcurrentUser_4_1751982655337	t	2025-07-08 15:50:55.351142	0	concurrent-4	2025-07-08 15:50:55.351142
c0c04d9a-bf94-40b0-9424-7f4157bde78c	IntegrationPlayer1_1751982655354	t	2025-07-08 15:50:55.361617	0	integration-socket-1	2025-07-08 15:50:55.361617
6417764b-cf0d-4e17-a452-8cf52e2f654d	IntegrationPlayer2_1751982655362	t	2025-07-08 15:50:55.393015	0	integration-socket-2	2025-07-08 15:50:55.393015
e124b4e0-089c-4dc0-a09b-48f0492c1897	StatusTestPlayer_1751982655856	t	2025-07-08 15:50:55.857162	0	status-test	2025-07-08 15:50:55.857162
1a63a1c0-b3a7-4458-957e-8458d6d7ab54	ScoringTestPlayer3	t	2025-07-09 15:47:36.141649	0	\N	2025-07-08 15:42:39.128362
158da148-407d-4b08-8390-650692fccc6a	ScoringTestPlayer4	t	2025-07-09 15:47:36.160523	0	\N	2025-07-08 15:42:39.146037
0478bfd9-a4c3-43be-817a-9853e9a4c72b	ScoringTestPlayer5	t	2025-07-09 15:47:36.167332	0	\N	2025-07-08 15:42:39.162876
842d0a5c-a025-4485-90c4-540ff3cfaaae	ScoringTestPlayer1	t	2025-07-09 15:47:36.12372	5	\N	2025-07-08 15:42:39.084993
e7abca8f-4530-4e94-8ce8-a9e82fcfdc5d	AliceTestPlayer	t	2025-07-08 16:01:48.233881	0	test-socket-1751983308228-0.9421198717712811	2025-07-07 19:25:03.869004
0e5b8bc8-fa5c-4cbd-b900-55c53d0263ba	ComprehensiveTestUser1	t	2025-07-09 16:06:10.579597	0	comp-test-1	2025-07-07 19:42:01.265058
fe95e6fb-d9d4-4771-b5e3-04e3fbbee467	WSTestPlayer2_1752069972629	f	2025-07-09 16:06:18.632512	0	\N	2025-07-09 16:06:12.631613
ba9fcb00-3262-421e-a4a4-b297f2bfd098	TestUser1	f	2025-07-08 16:01:51.599219	0	\N	2025-07-07 19:08:06.43575
ad00087a-46dc-4bfb-8180-7352602db967	Test_User_1752069978635_1	t	2025-07-09 16:06:18.637139	0	test-1752069978635-1	2025-07-09 16:06:18.637139
8fa3b344-703e-49fc-b3c1-e73c428ed699	ConcurrentUser_0_1752069978641	t	2025-07-09 16:06:18.643401	0	concurrent-0	2025-07-09 16:06:18.643401
470bc1a0-1b58-4127-b0ad-e90330baaa56	WSTestPlayer2_1751983313728	f	2025-07-08 16:01:59.711122	0	\N	2025-07-08 16:01:53.752779
b6f61f87-8522-40b2-98c1-314087079faa	WSTestPlayer1_1751983313705	f	2025-07-08 16:01:59.710952	0	\N	2025-07-08 16:01:53.721122
4943b5b6-fcd5-40b3-8ae5-28dca0e802d8	ConcurrentUser_2_1751983319751	t	2025-07-08 16:01:59.756749	0	concurrent-2	2025-07-08 16:01:59.756749
f24ed699-bdaf-4dbb-93d0-658c55bde1a7	ConcurrentUser_4_1751983319752	t	2025-07-08 16:01:59.777244	0	concurrent-4	2025-07-08 16:01:59.777244
1487b8f6-acef-4e10-ab65-3d2aa6de05b1	VisibilityTestPlayer_1751983320102_vzvx2s9x7	t	2025-07-08 16:02:00.1107	0	test-socket-1751983320102-0fesj2l07	2025-07-08 16:02:00.1107
e9ee8f28-dc0b-40f7-a275-d619c20bc76c	ValidSocketString_1751983320127	t	2025-07-08 16:02:00.129644	0	valid-string-id	2025-07-08 16:02:00.129644
b68e2f88-b983-4891-ac97-53ee10a3ca75	ValidSocketNull_1751983320130	t	2025-07-08 16:02:00.132176	0	\N	2025-07-08 16:02:00.132176
d058930b-f841-4a9f-a4e3-985e085eb7a2	ValidSocketUndefined_1751983320133	t	2025-07-08 16:02:00.134113	0	\N	2025-07-08 16:02:00.134113
c9dc9348-9243-4441-a828-c9a13d892e9a	FormatTestPlayer_1751983320134	t	2025-07-08 16:02:00.136847	0	format-test-socket	2025-07-08 16:02:00.136847
8f835006-146f-4ba9-8c11-154876a13686	ModernAppUser_1751983320238	t	2025-07-08 16:02:00.24044	0	modern-socket	2025-07-08 16:02:00.24044
4ac0b90c-22c4-462d-a226-07c740cc6ebb	LangTestPlayer2_1752069978695	t	2025-07-09 16:06:18.695869	0	lang-test-2	2025-07-09 16:06:18.695869
1d693ab0-4e0d-4645-b004-8e5207cad03c	ConcurrentUser_1_1752069978641	t	2025-07-09 16:06:18.644973	0	concurrent-1	2025-07-09 16:06:18.644973
6611542b-d5be-441d-ba28-287b5b79903e	Asd	t	2025-07-10 11:40:27.755118	3	5Kyy4oBi57Qvs9ZmAAAF	2025-07-08 13:10:48.586123
989d493b-42ec-489f-b25f-c4700e8ee735	Harry	t	2025-07-10 11:40:40.563579	1	lPTtvFQ1p-cLa6oGAAAH	2025-07-08 13:10:47.850143
bd45506b-14de-4403-a999-df997e574df2	StatusTestPlayer_1751925763251	t	2025-07-08 00:02:43.251983	0	status-test	2025-07-08 00:02:43.251983
268e0011-7d9c-4a95-b462-e0ad09dcd50b	Player-123_1751979827390_0	t	2025-07-08 15:03:47.570999	0	test-1751979827390-0	2025-07-08 15:03:47.570999
883be03d-af7f-4b03-adae-db0de8eaed8e	Test_User_1751979827621_1	t	2025-07-08 15:03:47.630154	0	test-1751979827621-1	2025-07-08 15:03:47.630154
00cb75ab-b9ae-4bc2-b84e-446c51ff6d52	ConcurrentUser_0_1751979827644	t	2025-07-08 15:03:47.672911	0	concurrent-0	2025-07-08 15:03:47.672911
e41f5a47-1572-453d-8b59-dee397a2b403	ConcurrentUser_3_1751979827645	t	2025-07-08 15:03:47.696908	0	concurrent-3	2025-07-08 15:03:47.696908
0f9c0fc2-cf0b-4207-bb69-47988110b74a	DebugPlayer	t	2025-07-08 15:09:25.049189	0	\N	2025-07-08 15:09:25.049189
d9538e3c-4e44-452a-b978-97d409d7886c	Test_User_1751980258090_1	t	2025-07-08 15:10:58.118353	0	test-1751980258090-1	2025-07-08 15:10:58.118353
1a8cd77a-cdc2-4a80-9e85-85edb921ee65	ConcurrentUser_0_1751980258124	t	2025-07-08 15:10:58.154086	0	concurrent-0	2025-07-08 15:10:58.154086
d4882edf-48fc-4efe-ae41-9ed68177319f	ConcurrentUser_4_1751980258125	t	2025-07-08 15:10:58.235837	0	concurrent-4	2025-07-08 15:10:58.235837
bd2fc8a5-52db-46f0-9436-8d1ad8e09e2d	IntegrationPlayer1_1751980258237	t	2025-07-08 15:10:58.240582	0	integration-socket-1	2025-07-08 15:10:58.240582
af435ea3-de1e-4b5d-b272-ae0dfda93eba	IntegrationPlayer2_1751980258241	t	2025-07-08 15:10:58.242817	0	integration-socket-2	2025-07-08 15:10:58.242817
41b222d8-0d07-4b3a-a3d7-fd23b52c0b69	ModernAppUser_1751980258937	t	2025-07-08 15:10:58.937878	0	modern-socket	2025-07-08 15:10:58.937878
75da0aab-d734-4652-abbe-c3b8d77c17e9	Player-123_1751980340040_0	t	2025-07-08 15:12:20.12537	0	test-1751980340040-0	2025-07-08 15:12:20.12537
64f1d5a9-588c-4720-a920-c332f4b49048	Test_User_1751980340127_1	t	2025-07-08 15:12:20.129059	0	test-1751980340127-1	2025-07-08 15:12:20.129059
f692e434-2530-4060-8712-30a0e5a3d721	ConcurrentUser_1_1751980340134	t	2025-07-08 15:12:20.164769	0	concurrent-1	2025-07-08 15:12:20.164769
af6cae65-961b-4e71-9e88-d03380c6a05c	ConcurrentUser_4_1751980340134	t	2025-07-08 15:12:20.249842	0	concurrent-4	2025-07-08 15:12:20.249842
2bdfae9b-9aa1-4037-a50d-99815d4b3b98	IntegrationPlayer1_1751980340255	t	2025-07-08 15:12:20.268786	0	integration-socket-1	2025-07-08 15:12:20.268786
cb948adf-2646-4aa1-a8ff-0c3327723fd0	IntegrationPlayer2_1751980340271	t	2025-07-08 15:12:20.30216	0	integration-socket-2	2025-07-08 15:12:20.30216
95705943-613b-43df-af6c-441a654d14b8	ConcurrentUser_4_1751980950839	t	2025-07-08 15:22:30.882382	0	concurrent-4	2025-07-08 15:22:30.882382
9184ce0e-f656-4070-8d6d-08e9fa748480	ApprovalTestPlayer_1751980951114_xxdab08vc	t	2025-07-08 15:22:31.11602	0	test-socket-1751980951114-80iviudgp	2025-07-08 15:22:31.11602
775a493d-ac27-456c-b21f-fd1bdbcd704c	NonGlobalPlayer1_1751980951129_wkt3d2f7n	t	2025-07-08 15:22:31.13194	0	test-socket-1751980951129-v2hax1iiw	2025-07-08 15:22:31.13194
caa062d4-ecf0-4318-ba28-70943e115343	NonGlobalPlayer2_1751980951132_v5q68ntle	t	2025-07-08 15:22:31.139272	0	test-socket-1751980951132-t252qicwu	2025-07-08 15:22:31.139272
747fcd7f-94b4-450f-8f4c-d656a89beda9	AlreadyApprovedPlayer_1751980951166_nxb5585rk	t	2025-07-08 15:22:31.171868	0	test-socket-1751980951166-97e51ahra	2025-07-08 15:22:31.171868
f564d20f-590c-4d35-a271-04e86d40518d	ResponseFormatPlayer_1751980951256_oatrm5ax4	t	2025-07-08 15:22:31.26567	0	test-socket-1751980951256-cl2v7xwpn	2025-07-08 15:22:31.26567
46f7b5e0-cc46-4487-a983-d83755492142	VisibilityTestPlayer_1751980951302_bg677nlfe	t	2025-07-08 15:22:31.302937	0	test-socket-1751980951302-o8fddnzy3	2025-07-08 15:22:31.302937
efb1c13f-a7e1-47fc-968f-3f93723366e8	ValidSocketString_1751980951335	t	2025-07-08 15:22:31.376093	0	valid-string-id	2025-07-08 15:22:31.376093
a20dc404-a1d3-4b32-9c6c-d925c0506070	ValidSocketNull_1751980951396	t	2025-07-08 15:22:31.416207	0	\N	2025-07-08 15:22:31.416207
8cc029ee-95a0-44cb-8079-c61614d0ba8f	ValidSocketUndefined_1751980951418	t	2025-07-08 15:22:31.421161	0	\N	2025-07-08 15:22:31.421161
f3398cef-14b7-4aba-bc69-7131d0c32123	FormatTestPlayer_1751980951422	t	2025-07-08 15:22:31.435606	0	format-test-socket	2025-07-08 15:22:31.435606
c70317e3-93cc-478e-9efa-6147700a7aef	StatusTestPlayer_1751980951506	t	2025-07-08 15:22:31.51394	0	status-test	2025-07-08 15:22:31.51394
5fd50c53-d93a-4035-b464-ad781fb36acc	Player-123_1751981264542_0	t	2025-07-08 15:27:44.549278	0	test-1751981264542-0	2025-07-08 15:27:44.549278
8f8f0fe6-a645-4755-9c20-c1413bf7fa72	Test_User_1751981264552_1	t	2025-07-08 15:27:44.585004	0	test-1751981264552-1	2025-07-08 15:27:44.585004
aa35b9fb-433d-42f2-834f-5fe7eb74677b	ConcurrentUser_0_1751981264598	t	2025-07-08 15:27:44.60691	0	concurrent-0	2025-07-08 15:27:44.60691
1d6197cc-cc9e-4c9a-b996-cbc5e938439f	ConcurrentUser_4_1751981264599	t	2025-07-08 15:27:44.63335	0	concurrent-4	2025-07-08 15:27:44.63335
bb6e5dff-0e61-4de4-9e9e-fc0997cd69f9	IntegrationPlayer1_1751981264634	t	2025-07-08 15:27:44.637317	0	integration-socket-1	2025-07-08 15:27:44.637317
c8732a21-9d8f-4031-a933-0044e05870f6	IntegrationPlayer2_1751981264638	t	2025-07-08 15:27:44.639824	0	integration-socket-2	2025-07-08 15:27:44.639824
d6ca67ba-c27d-412a-9242-efd465ef8c24	ModernAppUser_1751981265094	t	2025-07-08 15:27:45.095478	0	modern-socket	2025-07-08 15:27:45.095478
40a9da88-7c7a-48a0-9731-7567160a0d2e	ConcurrentUser_2_1751982655337	t	2025-07-08 15:50:55.346726	0	concurrent-2	2025-07-08 15:50:55.346726
048c6b58-53e0-4b8d-ab7c-431304657dbc	ApprovalTestPlayer_1751982655657_4mg87swjr	t	2025-07-08 15:50:55.670193	0	test-socket-1751982655657-jy1c9eii1	2025-07-08 15:50:55.670193
ca91595a-e986-4dc0-ad62-14417f12c04d	NonGlobalPlayer1_1751982655674_pl0ehjxqk	t	2025-07-08 15:50:55.675622	0	test-socket-1751982655674-461xytya6	2025-07-08 15:50:55.675622
74f54141-db60-4d3c-b28d-d218fa26a817	NonGlobalPlayer2_1751982655676_kk1f6kbif	t	2025-07-08 15:50:55.677156	0	test-socket-1751982655676-foh7hl6fx	2025-07-08 15:50:55.677156
66b92f69-887d-421e-8465-22537f5ddb14	AlreadyApprovedPlayer_1751982655708_4kgvs5t4w	t	2025-07-08 15:50:55.71021	0	test-socket-1751982655708-r5n8kap48	2025-07-08 15:50:55.71021
be77fd1d-53aa-4395-b3cd-57ed90d38e68	ResponseFormatPlayer_1751982655715_p6bhnnadk	t	2025-07-08 15:50:55.715932	0	test-socket-1751982655715-q7mmoo8zz	2025-07-08 15:50:55.715932
a79a6da1-fd72-4206-b4ae-6cdbbf8dd57c	VisibilityTestPlayer_1751982655719_exem0olsi	t	2025-07-08 15:50:55.721099	0	test-socket-1751982655719-50jt3tbna	2025-07-08 15:50:55.721099
13b59552-1c34-45d8-b791-41c33fc2cd28	ValidSocketString_1751982655740	t	2025-07-08 15:50:55.749307	0	valid-string-id	2025-07-08 15:50:55.749307
c23b3bf1-6be8-45cd-9bfa-2c9475b19654	ValidSocketNull_1751982655753	t	2025-07-08 15:50:55.770773	0	\N	2025-07-08 15:50:55.770773
e0537fdc-cb54-41b2-942c-be5f02c5ec13	ValidSocketUndefined_1751982655771	t	2025-07-08 15:50:55.773125	0	\N	2025-07-08 15:50:55.773125
fe2a53e5-6bb0-4ca9-bd4b-cc980854de68	FormatTestPlayer_1751982655773	t	2025-07-08 15:50:55.774601	0	format-test-socket	2025-07-08 15:50:55.774601
aa34160b-ee3c-47fe-8668-d34a7503f391	Player-123_1752069978624_0	t	2025-07-09 16:06:18.633279	0	test-1752069978624-0	2025-07-09 16:06:18.633279
523d7937-14bd-4e21-947e-5182d18e8a2b	ConcurrentUser_2_1752069978641	t	2025-07-09 16:06:18.64387	0	concurrent-2	2025-07-09 16:06:18.64387
b01537a5-0219-4165-b6cf-74f9b9a96986	ConcurrentUser_3_1752069978641	t	2025-07-09 16:06:18.672491	0	concurrent-3	2025-07-09 16:06:18.672491
059b139d-b480-4bb4-95f6-6fb2e79db5d9	IntegrationPlayer1_1752069978673	t	2025-07-09 16:06:18.675122	0	integration-socket-1	2025-07-09 16:06:18.675122
0fa30159-b132-42f5-a7c5-47a4f4bbe9e3	IntegrationPlayer2_1752069978675	t	2025-07-09 16:06:18.677101	0	integration-socket-2	2025-07-09 16:06:18.677101
586746fc-08e3-4b4b-b092-bced4ce0c8c6	Player-123_1751983319726_0	t	2025-07-08 16:01:59.742412	0	test-1751983319726-0	2025-07-08 16:01:59.742412
728e8ce2-def9-493b-9ea4-4079d483ab30	Test_User_1751983319745_1	t	2025-07-08 16:01:59.746238	0	test-1751983319745-1	2025-07-08 16:01:59.746238
3a690064-a60f-4c29-beb8-4371b6f0282e	ConcurrentUser_0_1751983319751	t	2025-07-08 16:01:59.754978	0	concurrent-0	2025-07-08 16:01:59.754978
f69bd249-310a-4849-87e7-83f670dd0956	ConcurrentUser_3_1751983319751	t	2025-07-08 16:01:59.778138	0	concurrent-3	2025-07-08 16:01:59.778138
57b25b2f-9f26-4633-ba53-8dc70c17b6ec	IntegrationPlayer1_1751983319779	t	2025-07-08 16:01:59.780845	0	integration-socket-1	2025-07-08 16:01:59.780845
3e9a0e8c-5b30-47fe-82c0-4ab80ee7318e	IntegrationPlayer2_1751983319781	t	2025-07-08 16:01:59.782911	0	integration-socket-2	2025-07-08 16:01:59.782911
3645a7d6-59bf-4846-b406-5b94c1d60c3d	StatusTestPlayer_1751983320197	t	2025-07-08 16:02:00.199317	0	status-test	2025-07-08 16:02:00.199317
35bcd4cd-1663-42b5-b657-0ce99c85be33	WSDataTestPlayer1	f	2025-07-08 16:02:00.784747	0	\N	2025-07-08 15:16:47.422163
0c338ee6-0942-41f1-8d90-6aa882487ced	WSDataTestPlayer2	f	2025-07-08 16:02:00.785672	0	\N	2025-07-08 15:16:47.542004
b28c4c40-f9a4-4867-8296-7b63a645ef00	PhraseStructureTestPlayer	t	2025-07-08 16:02:00.78699	0	\N	2025-07-08 15:18:46.3907
151db730-f580-4eaa-b670-fd5a1ef8c28b	ModernAppUser_1751925763272	t	2025-07-08 00:02:43.274846	0	modern-socket	2025-07-08 00:02:43.274846
58354c52-c439-4419-8726-132f1a69e216	ConcurrentUser_4_1752069978642	t	2025-07-09 16:06:18.644885	0	concurrent-4	2025-07-09 16:06:18.644885
852d99c7-28cc-4def-b513-68ec9b086039	LangTestPlayer1_1752069978690	t	2025-07-09 16:06:18.691982	0	lang-test-1	2025-07-09 16:06:18.691982
c00b5644-406b-4104-9660-404bab90dfdf	Player-123_1751982655271_0	t	2025-07-08 15:50:55.296536	0	test-1751982655271-0	2025-07-08 15:50:55.296536
e6c737b3-01a2-4b8e-ab17-285648368549	ConcurrentUser_2_1751980950839	t	2025-07-08 15:22:30.882534	0	concurrent-2	2025-07-08 15:22:30.882534
4fcad282-9f6c-4d9f-b25e-365f55b3c45e	ModernAppUser_1751980951688	t	2025-07-08 15:22:31.697468	0	modern-socket	2025-07-08 15:22:31.697468
6ea248c5-2162-45c4-a9d2-8530961a9c80	ConcurrentUser_2_1751981264599	t	2025-07-08 15:27:44.608389	0	concurrent-2	2025-07-08 15:27:44.608389
984dfa6d-eb55-4031-b487-d71fd9789362	ApprovalTestPlayer_1751981264986_thi8cj328	t	2025-07-08 15:27:44.987344	0	test-socket-1751981264986-rut9dqpdn	2025-07-08 15:27:44.987344
1ce2d84f-3644-4572-add4-649c4a4421e0	NonGlobalPlayer1_1751981264991_rc6lrxndm	t	2025-07-08 15:27:44.992401	0	test-socket-1751981264991-quordpfvb	2025-07-08 15:27:44.992401
a087924f-76e1-4d1e-9a50-0d6e1b5eb66b	WSTestPlayer2_1751979821382	f	2025-07-08 15:03:47.560904	0	\N	2025-07-08 15:03:41.396696
1f3a7143-d919-4554-98fb-09fba828309b	ConcurrentUser_4_1751979827645	t	2025-07-08 15:03:47.698341	0	concurrent-4	2025-07-08 15:03:47.698341
d9938742-8ff0-4fff-9658-cdb081b44642	IntegrationPlayer1_1751979827699	t	2025-07-08 15:03:47.700366	0	integration-socket-1	2025-07-08 15:03:47.700366
081ebacd-08a6-4ba8-b55a-914f88c8b7bd	Lorry	f	2025-07-08 11:22:44.746668	0	\N	2025-07-08 11:19:26.670474
467c7f9e-9cb3-477c-ad64-c309528ccc79	IntegrationPlayer2_1751979827700	t	2025-07-08 15:03:47.701711	0	integration-socket-2	2025-07-08 15:03:47.701711
73836676-30d1-4ba1-ac3a-c60850dfa431	NonGlobalPlayer2_1751981264992_lfobk4g7i	t	2025-07-08 15:27:44.993631	0	test-socket-1751981264992-4cd7lyt9i	2025-07-08 15:27:44.993631
ad356dc5-9a40-4557-a27a-9f220d47ac29	AlreadyApprovedPlayer_1751981265010_ypgf94ben	t	2025-07-08 15:27:45.013336	0	test-socket-1751981265010-270mold6h	2025-07-08 15:27:45.013336
3bfc2008-f6ec-45da-9de6-5d773fb39f67	ResponseFormatPlayer_1751981265027_o26weg0vb	t	2025-07-08 15:27:45.02799	0	test-socket-1751981265027-wzw38hdfb	2025-07-08 15:27:45.02799
9b007f97-dc5c-47ae-878a-c8fc334e6d42	VisibilityTestPlayer_1751981265031_6zu8epyzh	t	2025-07-08 15:27:45.033686	0	test-socket-1751981265031-hcf9v3npf	2025-07-08 15:27:45.033686
b26ea39c-b24f-4996-a041-6cdd08270c48	ValidSocketString_1751981265046	t	2025-07-08 15:27:45.047346	0	valid-string-id	2025-07-08 15:27:45.047346
6ae8612f-cfd2-421a-b084-39536cd58ed9	ValidSocketNull_1751981265048	t	2025-07-08 15:27:45.052329	0	\N	2025-07-08 15:27:45.052329
c8bb77b8-e5fa-4caa-85e2-847aea88d012	ValidSocketUndefined_1751981265055	t	2025-07-08 15:27:45.056476	0	\N	2025-07-08 15:27:45.056476
88f50e0e-a897-4c7b-9eda-c110d5519fe3	FormatTestPlayer_1751981265057	t	2025-07-08 15:27:45.057686	0	format-test-socket	2025-07-08 15:27:45.057686
1bab5810-0e58-4ad7-892b-d939867bee1f	WSTestPlayer1_1751980252035	f	2025-07-08 15:10:58.038163	0	\N	2025-07-08 15:10:52.049675
a164281e-a603-4ff4-a098-a81f3fe61711	WSTestPlayer2_1751980252066	f	2025-07-08 15:10:58.044765	0	\N	2025-07-08 15:10:52.087971
a399719d-1152-4ec1-b465-cd68cdbfb568	ConcurrentUser_3_1751980258125	t	2025-07-08 15:10:58.154855	0	concurrent-3	2025-07-08 15:10:58.154855
411bdf0c-9c99-4036-9d21-4743b0f51e19	ConcurrentUser_1_1751980258124	t	2025-07-08 15:10:58.154431	0	concurrent-1	2025-07-08 15:10:58.154431
90cb8121-5522-434d-bb56-4ed42e6dc46d	ApprovalTestPlayer_1751980258569_g61r9tj0r	t	2025-07-08 15:10:58.585355	0	test-socket-1751980258569-8wxaf211g	2025-07-08 15:10:58.585355
1f66b384-ef28-4e59-9f00-9a36c182cb7b	NonGlobalPlayer1_1751980258621_aaglx159p	t	2025-07-08 15:10:58.63257	0	test-socket-1751980258621-f1h6bc3qe	2025-07-08 15:10:58.63257
ba3bbe4d-34a5-4e57-bae3-543aa8b82ccc	NonGlobalPlayer2_1751980258633_bt43osm13	t	2025-07-08 15:10:58.652244	0	test-socket-1751980258633-237iktngu	2025-07-08 15:10:58.652244
2d71cfee-9f20-4c61-a04e-6fff0c5db83c	AlreadyApprovedPlayer_1751980258734_47wop7zu7	t	2025-07-08 15:10:58.735844	0	test-socket-1751980258734-rk2h3lni2	2025-07-08 15:10:58.735844
77f4b9eb-d615-4587-b7f0-23100eca9be4	ResponseFormatPlayer_1751980258744_r1dwuldaf	t	2025-07-08 15:10:58.745802	0	test-socket-1751980258744-5wjoio392	2025-07-08 15:10:58.745802
2a5c2de9-5dec-401e-8c8c-9ac4fa9b1ef5	VisibilityTestPlayer_1751980258751_zuwbykya2	t	2025-07-08 15:10:58.752083	0	test-socket-1751980258751-vgi7f7o48	2025-07-08 15:10:58.752083
ed0f1492-463e-4850-b920-48176cd9eb84	ValidSocketString_1751980258770	t	2025-07-08 15:10:58.772472	0	valid-string-id	2025-07-08 15:10:58.772472
65e501f0-cc3c-407c-9649-3e317a4cc5b0	ValidSocketNull_1751980258787	t	2025-07-08 15:10:58.793415	0	\N	2025-07-08 15:10:58.793415
825e81a4-efd0-42f8-8a43-26e11fde219f	ValidSocketUndefined_1751980258794	t	2025-07-08 15:10:58.803635	0	\N	2025-07-08 15:10:58.803635
08d82044-eec1-44c2-aa55-57c952d262f5	FormatTestPlayer_1751980258817	t	2025-07-08 15:10:58.819096	0	format-test-socket	2025-07-08 15:10:58.819096
5077f0ce-2278-4f87-ab57-70ddcb9860fd	ConcurrentUser_3_1751980340134	t	2025-07-08 15:12:20.165794	0	concurrent-3	2025-07-08 15:12:20.165794
bb67393c-1a22-46ce-b4d1-c6553f908001	ApprovalTestPlayer_1751980340577_vhclo0pzw	t	2025-07-08 15:12:20.578309	0	test-socket-1751980340577-xjdkdnoks	2025-07-08 15:12:20.578309
76796385-e66f-435e-9137-b24cdc0d4eb6	NonGlobalPlayer1_1751980340587_mj0jzxfaw	t	2025-07-08 15:12:20.588803	0	test-socket-1751980340587-vor3t2um4	2025-07-08 15:12:20.588803
cb726906-cd93-4f79-9fed-a48e69be06e3	NonGlobalPlayer2_1751980340589_1qq5y6uzi	t	2025-07-08 15:12:20.60108	0	test-socket-1751980340589-p2bb0fyzl	2025-07-08 15:12:20.60108
de837188-65c0-4abe-8536-bc6b8d8e851b	AlreadyApprovedPlayer_1751980340611_1n3bioj39	t	2025-07-08 15:12:20.612088	0	test-socket-1751980340611-oypevbvmx	2025-07-08 15:12:20.612088
1e7fc343-667c-42fd-9c03-ac0b379e723e	ResponseFormatPlayer_1751980340621_kphhj2xe9	t	2025-07-08 15:12:20.628669	0	test-socket-1751980340621-t0tdtlutw	2025-07-08 15:12:20.628669
81d6384f-1864-4204-89c8-1e83f1ab8cae	VisibilityTestPlayer_1751980340633_17zdyhmk0	t	2025-07-08 15:12:20.634007	0	test-socket-1751980340633-96u7winq7	2025-07-08 15:12:20.634007
6c9aa9d8-ddaf-4217-87ba-b751fc43721c	ValidSocketString_1751980340649	t	2025-07-08 15:12:20.649822	0	valid-string-id	2025-07-08 15:12:20.649822
babae5bb-39fd-4d15-8ba1-a899b83b5489	ValidSocketNull_1751980340650	t	2025-07-08 15:12:20.651392	0	\N	2025-07-08 15:12:20.651392
891aace6-ecaf-428e-88bf-6076ef7b5200	ValidSocketUndefined_1751980340653	t	2025-07-08 15:12:20.653767	0	\N	2025-07-08 15:12:20.653767
4a7a1a5c-854e-4ed2-908f-5fc75804b710	FormatTestPlayer_1751980340654	t	2025-07-08 15:12:20.655014	0	format-test-socket	2025-07-08 15:12:20.655014
d1af3dd0-cef5-4491-af19-ee67fca0a12c	StatusTestPlayer_1751980340736	t	2025-07-08 15:12:20.737631	0	status-test	2025-07-08 15:12:20.737631
fe32cb8f-8459-4cc5-875f-a3a5347513c3	Glenn	t	2025-07-08 12:52:53.617069	0	AMQ0R6skZAscN2nAAABV	2025-07-08 11:19:20.191701
cef6ede3-9ded-4092-aff8-39f36492634a	Kjell	t	2025-07-08 12:53:08.112433	0	4YQe4W3xbf5nOTVCAABX	2025-07-08 11:24:40.12757
f8c6499a-f1ef-452f-9508-dc7f23a479af	WSTestPlayer1_1751982649252	f	2025-07-08 15:50:55.264638	0	\N	2025-07-08 15:50:49.26198
4f844b68-61b9-4edf-9594-e022f2d7e888	WSTestPlayer2_1751982649270	f	2025-07-08 15:50:55.265244	0	\N	2025-07-08 15:50:49.274743
a3268779-7e2a-40cd-9a71-c3d0e6169ec6	Test_User_1751982655301_1	t	2025-07-08 15:50:55.325646	0	test-1751982655301-1	2025-07-08 15:50:55.325646
62c105c3-0048-45c8-85a0-26201becdd8e	ConcurrentUser_0_1751982655336	t	2025-07-08 15:50:55.346416	0	concurrent-0	2025-07-08 15:50:55.346416
0feaa841-b858-44f6-a179-9bdb33849a04	ConcurrentUser_1_1751982655336	t	2025-07-08 15:50:55.350475	0	concurrent-1	2025-07-08 15:50:55.350475
d85959fc-bae5-4a6b-bd3a-353ff28f1c7c	ModernAppUser_1751982655879	t	2025-07-08 15:50:55.880655	0	modern-socket	2025-07-08 15:50:55.880655
1c929159-760c-440a-8d03-acaa21bffaa4	SkipTestPlayer	t	2025-07-08 16:02:00.865216	0	\N	2025-07-08 10:53:33.842996
29274f2e-5b34-4727-97fc-69c84bdbd595	TestUser2	t	2025-07-08 16:01:48.2211	0	test-socket-1751983308212-0.6857126117380273	2025-07-07 19:08:51.247605
5d341e29-fb99-406f-8699-93513c0b5dc4	ConcurrentUser_1_1751983319751	t	2025-07-08 16:01:59.756978	0	concurrent-1	2025-07-08 16:01:59.756978
d980f8f7-106e-4342-a4ab-283b00d17b9d	ApprovalTestPlayer_1751983320033_eqwdfak0n	t	2025-07-08 16:02:00.034999	0	test-socket-1751983320033-y248nbjjg	2025-07-08 16:02:00.034999
87c9b857-f9c2-46a8-a90e-8ccfee17fe7e	NonGlobalPlayer1_1751983320043_cfws2pyui	t	2025-07-08 16:02:00.044546	0	test-socket-1751983320043-c30e9mwe6	2025-07-08 16:02:00.044546
79050e78-e2ed-4504-8073-92503bc225a0	NonGlobalPlayer2_1751983320046_qxsoinwly	t	2025-07-08 16:02:00.052523	0	test-socket-1751983320046-is6fvl2gy	2025-07-08 16:02:00.052523
256d1910-6906-4d96-8407-349f70a9178d	AlreadyApprovedPlayer_1751983320068_98pcmb9oj	t	2025-07-08 16:02:00.069309	0	test-socket-1751983320068-p5ejjppmo	2025-07-08 16:02:00.069309
efdbfea9-63ee-46e2-a089-cdff1a89329b	ResponseFormatPlayer_1751983320083_oqvfvxvas	t	2025-07-08 16:02:00.084779	0	test-socket-1751983320083-w5ctc2en0	2025-07-08 16:02:00.084779
3d01c53d-593b-4053-8004-63f33daece6c	HintTestPlayer	t	2025-07-08 16:02:00.822912	11	\N	2025-07-08 10:53:33.705542
\.


--
-- Data for Name: skipped_phrases; Type: TABLE DATA; Schema: public; Owner: fredriksafsten
--

COPY public.skipped_phrases (id, player_id, phrase_id, skipped_at) FROM stdin;
2ab99d4d-4da5-46f7-a43c-b054534fb9f3	ba9fcb00-3262-421e-a4a4-b297f2bfd098	70323597-e40d-4b4a-8967-7392c6fd86df	2025-07-07 21:04:37.555089
96ce2997-bca8-46cd-875d-7c717e253753	ba9fcb00-3262-421e-a4a4-b297f2bfd098	a067a1f9-5ccf-4f90-81f2-05c0cb7d675f	2025-07-07 21:15:22.678989
6baeffa7-e334-4c0c-b22e-655de3dce495	468954d5-42b3-4f6f-a49a-eedf265d916d	88126b19-d929-418c-ab72-fde6d0be8178	2025-07-07 21:47:04.490489
259b4d0a-8593-4ed7-8659-81f56e6eedbd	2867b455-c969-4e43-922e-124bedad465b	20eb1933-d397-4650-a0e0-028cc1a059d4	2025-07-07 21:48:19.754229
d5096475-adfd-43da-9c08-304a48fd5272	da0122f9-476d-4257-842c-fd2b194a216e	bbc5454d-ecd6-45ac-894c-eb0e4709d23b	2025-07-07 21:48:56.114949
8992830d-38d3-4e1f-8717-a7f8f8f325ff	b87c04fc-abd7-4248-8339-458b83038dfe	8a0a2aa0-5221-4977-bed6-85845d7f5610	2025-07-07 21:52:50.222261
10ed1b1e-cc5f-43ba-8ba9-cf07daa9eceb	ba9fcb00-3262-421e-a4a4-b297f2bfd098	3658f67c-54d8-4a65-bbbb-dff1448321da	2025-07-08 00:02:31.749312
175606cc-0898-4703-ac40-42d272eab8fb	71e637aa-31e7-442f-bf69-ab3298edb2d9	00414a32-c3b5-4f33-ab4a-3e18598a7282	2025-07-08 00:02:43.212735
3cf15c3e-14ad-4adf-9bf6-28ce3a00dca2	ba9fcb00-3262-421e-a4a4-b297f2bfd098	4180d35c-dba8-45c2-b448-7c72db212f8d	2025-07-08 09:41:36.388276
f9663abe-33dd-4fd3-b862-3d0a894233f4	8f43e562-9d44-4b54-8025-20824d3975af	9a1d95e0-471a-4c56-b8db-0ad800c29ae3	2025-07-08 14:16:15.866059
79921664-8d7e-4e5b-81d8-c9d9ad6e925d	6611542b-d5be-441d-ba28-287b5b79903e	a2b44fb9-0fc2-4fc9-a165-f1c7a673b272	2025-07-08 14:59:07.241924
7a99ef42-0791-459f-8d42-f7c4a98c6fb0	ba9fcb00-3262-421e-a4a4-b297f2bfd098	ae4a2ae8-dbe0-4938-a00c-27834e4c1c0e	2025-07-08 15:06:48.871207
b4d03eeb-a20e-45b7-bf4e-f4f57aa23510	ba9fcb00-3262-421e-a4a4-b297f2bfd098	9941b025-8367-4be7-80a9-53d725b173d5	2025-07-08 15:10:46.822773
e5969a4a-0018-4d11-815f-dd29f2653660	65e501f0-cc3c-407c-9649-3e317a4cc5b0	8642657f-c655-4cda-9a5b-95a7e1b49b00	2025-07-08 15:10:58.869412
73697939-2abd-4ae3-8646-394f768628d0	ba9fcb00-3262-421e-a4a4-b297f2bfd098	d0a430f2-3acd-40c8-98a6-893c9227cbdb	2025-07-08 15:12:08.905897
8d4e7dd0-c366-472e-904c-4230df5fd424	babae5bb-39fd-4d15-8ba1-a899b83b5489	545bb838-f096-4126-85d5-a669f9fd4b9a	2025-07-08 15:12:20.682278
c1930d30-5f1d-422a-8740-dcd3430db276	ba9fcb00-3262-421e-a4a4-b297f2bfd098	cdf2ceac-a0ff-488f-9453-ef09a877388d	2025-07-08 15:22:19.468185
9a87ff1d-4b43-4b65-acc7-5db2e55e0068	a20dc404-a1d3-4b32-9c6c-d925c0506070	0aafbe1e-33e2-48d4-bff5-f8374f9879fd	2025-07-08 15:22:31.464775
3da8cffd-397f-46b0-8800-9a6e4c46ec78	ba9fcb00-3262-421e-a4a4-b297f2bfd098	66c8aaab-6742-4377-b0b2-f158930f4db8	2025-07-08 15:27:33.370097
f485f0a1-bc28-45fb-992c-f382aa427154	6ae8612f-cfd2-421a-b084-39536cd58ed9	a9122e5c-bf60-40bd-8863-9b8f029164ca	2025-07-08 15:27:45.065081
ec97824a-7548-46f1-b005-a3138726b4fe	ba9fcb00-3262-421e-a4a4-b297f2bfd098	5526d3e7-9ea3-4800-8618-0e99a7d4e527	2025-07-08 15:50:44.124273
79333cf8-44e7-4cd7-98d4-781e6005c28f	c23b3bf1-6be8-45cd-9bfa-2c9475b19654	76d33595-d58e-4f5a-9d24-ddf46c8674f6	2025-07-08 15:50:55.820408
a0348b9d-ef7a-42bb-b463-c657f2db547a	ba9fcb00-3262-421e-a4a4-b297f2bfd098	78b1fe8f-2b66-44bd-aae5-0335f3bd72d1	2025-07-08 16:01:48.550086
742e88f2-eaeb-4d83-9288-1331d4155272	b68e2f88-b983-4891-ac97-53ee10a3ca75	f24fdde3-9072-4edb-b557-df5a76aef8a6	2025-07-08 16:02:00.153106
ce4dfd3f-bb82-4938-98ab-612a4578e0ff	989d493b-42ec-489f-b25f-c4700e8ee735	93718f8b-2d13-4736-b9c9-76465af58076	2025-07-08 19:03:16.399325
9042cf65-e04e-4db2-99f0-17abbd518be2	6611542b-d5be-441d-ba28-287b5b79903e	34a55d40-67b8-4c2a-95de-8ec4eb91c544	2025-07-08 19:03:27.176468
5efcee4f-5a6f-4613-8480-49ecf66c8bf5	989d493b-42ec-489f-b25f-c4700e8ee735	a3a09e90-8329-468f-9bfa-c81619280bb7	2025-07-08 23:35:23.78653
ea65fb99-8756-47c7-9eaa-fd2292c361a2	989d493b-42ec-489f-b25f-c4700e8ee735	0165f61b-967e-47eb-a6e7-e6ed0a820336	2025-07-09 10:48:18.512901
00442cb8-27d8-431e-80f2-6835e642bce6	6611542b-d5be-441d-ba28-287b5b79903e	59d996fc-1340-489c-b856-7478fc7ae3aa	2025-07-09 11:12:54.826942
a19e1058-45e9-45ff-ab97-1485b339a2a4	6611542b-d5be-441d-ba28-287b5b79903e	94aa3f75-caf1-4cb4-bc15-31b3a8745d51	2025-07-09 11:12:56.819959
c3465ea9-4983-401a-a155-1d1ba9c7b3e1	6611542b-d5be-441d-ba28-287b5b79903e	7434d709-e5d1-432f-b531-0d4298b98d86	2025-07-09 11:12:58.030234
ff217454-689c-4bd8-bf5f-132184b91ece	989d493b-42ec-489f-b25f-c4700e8ee735	8670937c-4da4-4f8e-ad84-c1668c6c1bf1	2025-07-09 11:42:05.096793
909946eb-929c-49ee-910c-b9954b47297c	6611542b-d5be-441d-ba28-287b5b79903e	77aa408f-14d7-4759-b3a7-c41e7428118b	2025-07-09 12:14:11.882919
21fbd1f8-67ba-4b5a-886e-60d1d278f0d1	6611542b-d5be-441d-ba28-287b5b79903e	163049ae-8429-4d57-b336-16374779b71a	2025-07-09 12:14:15.609616
156fc7a6-0d4a-4265-b5bb-9b2f7cb8b078	6611542b-d5be-441d-ba28-287b5b79903e	7f915907-b8a0-4e5c-a1c3-a88c620004da	2025-07-09 12:14:19.545572
e536e3e1-c322-4b6a-b9e5-5decf31e3ebb	6611542b-d5be-441d-ba28-287b5b79903e	b1355d07-d5b8-4bc4-a1c3-5908e3ce2169	2025-07-09 12:27:59.985232
a7a1df73-52aa-4974-9fe5-ef00f6b62323	989d493b-42ec-489f-b25f-c4700e8ee735	b87aaedb-e8f5-4774-92c9-5ae5b852e2b0	2025-07-09 15:54:22.682136
6ccebcb0-54aa-4a4b-a327-3701458c1130	6611542b-d5be-441d-ba28-287b5b79903e	625f7594-ce52-4e18-a59d-5a0314fb1dfa	2025-07-09 16:16:08.753214
\.


--
-- Name: completed_phrases completed_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_pkey PRIMARY KEY (id);


--
-- Name: completed_phrases completed_phrases_player_id_phrase_id_key; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_player_id_phrase_id_key UNIQUE (player_id, phrase_id);


--
-- Name: hint_usage hint_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_pkey PRIMARY KEY (id);


--
-- Name: hint_usage hint_usage_player_id_phrase_id_hint_level_key; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_player_id_phrase_id_hint_level_key UNIQUE (player_id, phrase_id, hint_level);


--
-- Name: leaderboards leaderboards_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_pkey PRIMARY KEY (id);


--
-- Name: leaderboards leaderboards_score_period_period_start_player_id_key; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_score_period_period_start_player_id_key UNIQUE (score_period, period_start, player_id);


--
-- Name: offline_phrases offline_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.offline_phrases
    ADD CONSTRAINT offline_phrases_pkey PRIMARY KEY (id);


--
-- Name: phrases phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.phrases
    ADD CONSTRAINT phrases_pkey PRIMARY KEY (id);


--
-- Name: player_phrases player_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.player_phrases
    ADD CONSTRAINT player_phrases_pkey PRIMARY KEY (id);


--
-- Name: player_scores player_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.player_scores
    ADD CONSTRAINT player_scores_pkey PRIMARY KEY (id);


--
-- Name: player_scores player_scores_player_id_score_period_period_start_key; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.player_scores
    ADD CONSTRAINT player_scores_player_id_score_period_period_start_key UNIQUE (player_id, score_period, period_start);


--
-- Name: players players_name_key; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_name_key UNIQUE (name);


--
-- Name: players players_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_pkey PRIMARY KEY (id);


--
-- Name: skipped_phrases skipped_phrases_pkey; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_pkey PRIMARY KEY (id);


--
-- Name: skipped_phrases skipped_phrases_player_id_phrase_id_key; Type: CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_player_id_phrase_id_key UNIQUE (player_id, phrase_id);


--
-- Name: idx_completed_phrases_player; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_completed_phrases_player ON public.completed_phrases USING btree (player_id, completed_at);


--
-- Name: idx_hint_usage_phrase; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_hint_usage_phrase ON public.hint_usage USING btree (phrase_id, hint_level);


--
-- Name: idx_hint_usage_player_phrase; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_hint_usage_player_phrase ON public.hint_usage USING btree (player_id, phrase_id, hint_level);


--
-- Name: idx_leaderboards_period_rank; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_leaderboards_period_rank ON public.leaderboards USING btree (score_period, period_start, rank_position);


--
-- Name: idx_leaderboards_period_score; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_leaderboards_period_score ON public.leaderboards USING btree (score_period, period_start, total_score DESC);


--
-- Name: idx_offline_phrases_player; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_offline_phrases_player ON public.offline_phrases USING btree (player_id, is_used);


--
-- Name: idx_phrases_difficulty; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_phrases_difficulty ON public.phrases USING btree (difficulty_level, is_global, is_approved);


--
-- Name: idx_phrases_global; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_phrases_global ON public.phrases USING btree (is_global, is_approved) WHERE ((is_global = true) AND (is_approved = true));


--
-- Name: idx_phrases_language; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_phrases_language ON public.phrases USING btree (language, is_global, is_approved);


--
-- Name: idx_player_phrases_delivered; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_player_phrases_delivered ON public.player_phrases USING btree (target_player_id, delivered_at) WHERE (is_delivered = true);


--
-- Name: idx_player_scores_period_rank; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_player_scores_period_rank ON public.player_scores USING btree (score_period, rank_position);


--
-- Name: idx_player_scores_period_score; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_player_scores_period_score ON public.player_scores USING btree (score_period, total_score DESC);


--
-- Name: idx_player_scores_player_period; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_player_scores_player_period ON public.player_scores USING btree (player_id, score_period);


--
-- Name: idx_players_active; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_players_active ON public.players USING btree (is_active, last_seen) WHERE (is_active = true);


--
-- Name: idx_skipped_phrases_player; Type: INDEX; Schema: public; Owner: fredriksafsten
--

CREATE INDEX idx_skipped_phrases_player ON public.skipped_phrases USING btree (player_id, skipped_at);


--
-- Name: completed_phrases completed_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: completed_phrases completed_phrases_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.completed_phrases
    ADD CONSTRAINT completed_phrases_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: hint_usage hint_usage_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: hint_usage hint_usage_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.hint_usage
    ADD CONSTRAINT hint_usage_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: leaderboards leaderboards_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: offline_phrases offline_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.offline_phrases
    ADD CONSTRAINT offline_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: offline_phrases offline_phrases_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.offline_phrases
    ADD CONSTRAINT offline_phrases_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: phrases phrases_created_by_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.phrases
    ADD CONSTRAINT phrases_created_by_player_id_fkey FOREIGN KEY (created_by_player_id) REFERENCES public.players(id) ON DELETE SET NULL;


--
-- Name: player_phrases player_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.player_phrases
    ADD CONSTRAINT player_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: player_phrases player_phrases_target_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.player_phrases
    ADD CONSTRAINT player_phrases_target_player_id_fkey FOREIGN KEY (target_player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: player_scores player_scores_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.player_scores
    ADD CONSTRAINT player_scores_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: skipped_phrases skipped_phrases_phrase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_phrase_id_fkey FOREIGN KEY (phrase_id) REFERENCES public.phrases(id) ON DELETE CASCADE;


--
-- Name: skipped_phrases skipped_phrases_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fredriksafsten
--

ALTER TABLE ONLY public.skipped_phrases
    ADD CONSTRAINT skipped_phrases_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

