--
-- PostgreSQL database dump
--

-- Dumped from database version 16.3 (Debian 16.3-1.pgdg120+1)
-- Dumped by pg_dump version 16.3 (Debian 16.3-1.pgdg120+1)

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
-- Name: add_user(bigint, character varying, character varying); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.add_user(p_id bigint, p_login character varying, p_password character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM accounts
        WHERE login = p_login
    ) THEN
        RAISE EXCEPTION 'User with given login already exists';
    END IF;

    INSERT INTO accounts (id, login, hashed_password)
    VALUES (p_id, p_login, crypt(p_password, gen_salt('bf')))
    RETURNING id INTO v_user_id;
    RETURN v_user_id;
END;
$$;


ALTER FUNCTION public.add_user(p_id bigint, p_login character varying, p_password character varying) OWNER TO admin;

--
-- Name: get_administrated_offices(integer); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.get_administrated_offices(p_administrator_id integer) RETURNS TABLE(id integer, office_type character varying, country character varying, city character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT offices.id, offices.office_type, offices.country, office.city
    FROM offices
    JOIN administrators ON offices.id = administrators.office_id
    WHERE administrators.user_id = p_administrator_id;
END;
$$;


ALTER FUNCTION public.get_administrated_offices(p_administrator_id integer) OWNER TO admin;

--
-- Name: login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.login(p_login character varying, p_password character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id INTO v_user_id
    FROM accounts
    WHERE login = p_login
    AND hashed_password = crypt(p_password, hashed_password);
    RETURN v_user_id;
END;
$$;


ALTER FUNCTION public.login(p_login character varying, p_password character varying) OWNER TO admin;

--
-- Name: verify_divorce_certificate_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_certificate_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_divorce_date DATE;
BEGIN
    SELECT divorce_date INTO v_divorce_date
    FROM divorces
    WHERE id = NEW.divorce_id;

    IF v_divorce_date > NEW.divorce_certificate_date THEN
        RAISE EXCEPTION 'Divorce certificate date is before divorce date';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_divorce_certificate_date() OWNER TO admin;

--
-- Name: verify_divorce_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_marriage_date DATE;
BEGIN
    SELECT marriage_date INTO v_marriage_date
    FROM marriages
    WHERE id = NEW.marriage_id;

    IF v_marriage_date > NEW.divorce_date THEN
        RAISE EXCEPTION 'Divorce date is before marriage date';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_divorce_date() OWNER TO admin;

--
-- Name: verify_divorce_unique(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_unique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM divorces
        WHERE marriage_id = NEW.marriage_id
    ) THEN
        RAISE EXCEPTION 'Divorce already exists for this marriage';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_divorce_unique() OWNER TO admin;

--
-- Name: verify_educational_certificate_birth_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_birth_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_birth_date DATE;
BEGIN
    SELECT date_of_birth INTO v_birth_date
    FROM people
    WHERE id = NEW.holder;

    IF v_birth_date > NEW.issue_date THEN
        RAISE EXCEPTION 'Educational certificate was issued before the holder was born';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_educational_certificate_birth_date() OWNER TO admin;

--
-- Name: verify_educational_certificate_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_educational_instance_date DATE;
BEGIN
    SELECT creation_date INTO v_educational_instance_date
    FROM educational_instances
    WHERE id = NEW.issuer;

    IF v_educational_instance_date > NEW.issue_date THEN
        RAISE EXCEPTION 'Educational certificate date is before educational instance creation date';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_educational_certificate_date() OWNER TO admin;

--
-- Name: verify_educational_certificate_death_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_death_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_death_date DATE;
BEGIN
    SELECT date_of_death INTO v_death_date
    FROM people
    WHERE id = NEW.holder;

    IF v_death_date IS NOT NULL THEN
        RAISE EXCEPTION 'Educational certificate is issued to a dead person';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_educational_certificate_death_date() OWNER TO admin;

--
-- Name: verify_educational_certificate_kind(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_kind() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_instance_kind INTEGER;
BEGIN
    SELECT kind INTO v_instance_kind
    FROM educational_instances
    WHERE id = NEW.issuer;

    IF v_instance_kind <> NEW.kind THEN
        RAISE EXCEPTION 'Educational certificate kind does not match educational instance kind';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_educational_certificate_kind() OWNER TO admin;

--
-- Name: verify_educational_certificate_prerequisites(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_prerequisites() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_prerequisite_kind INTEGER;
BEGIN
    FOR v_prerequisite_kind IN (SELECT prerequirement FROM educational_certificetes_types WHERE kind = NEW.kind)
    LOOP
        IF v_prerequisite_kind IS NOT NULL 
        AND NOT EXISTS (
            SELECT 1
            FROM educational_certificates
            WHERE kind = v_prerequisite_kind AND holder = NEW.holder
        ) THEN
            RAISE EXCEPTION 'Prerequisite educational certificate does not exist';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_educational_certificate_prerequisites() OWNER TO admin;

--
-- Name: verify_international_passport_number(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_international_passport_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_passport_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_passport_count
    FROM international_passports
    WHERE passport_owner = NEW.passport_owner
    AND issue_date <= CURRENT_DATE
    AND (expiration_date IS NULL OR CURRENT_DATE >= NEW.issue_date);

    IF v_passport_count >= 2 THEN
        RAISE EXCEPTION 'Person already has 2 active international passports';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_international_passport_number() OWNER TO admin;

--
-- Name: verify_marriage_certificate_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_marriage_certificate_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_marriage_date DATE;
BEGIN
    SELECT marriage_date INTO v_marriage_date
    FROM marriages
    WHERE id = NEW.marriage_id;

    IF v_marriage_date > NEW.marriage_certificate_date THEN
        RAISE EXCEPTION 'Marriage certificate date is before marriage date';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_marriage_certificate_date() OWNER TO admin;

--
-- Name: verify_marriage_unique(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_marriage_unique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM marriages
        WHERE (person1 = NEW.person1 AND person2 = NEW.person2)
        OR (person1 = NEW.person2 AND person2 = NEW.person1)
    ) THEN
        RAISE EXCEPTION 'Marriage already exists between these people';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_marriage_unique() OWNER TO admin;

--
-- Name: verify_passport_death_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_passport_death_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_death_date DATE;
BEGIN
    SELECT date_of_death INTO v_death_date
    FROM people
    WHERE id = NEW.passport_owner;

    IF v_death_date IS NOT NULL THEN
        RAISE EXCEPTION 'Passport is issued to a dead person';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_passport_death_date() OWNER TO admin;

--
-- Name: verify_passport_number(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_passport_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_passport_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_passport_count
    FROM passports
    WHERE passport_owner = NEW.passport_owner
    AND issue_date <= NEW.issue_date
    AND (expiration_date IS NULL OR expiration_date >= NEW.issue_date);

    IF v_passport_count >= 1 THEN
        RAISE EXCEPTION 'Person already has 1 active passports';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_passport_number() OWNER TO admin;

--
-- Name: verify_visa_passport_expiration_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_visa_passport_expiration_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_passport_expiration_date DATE;
BEGIN
    SELECT expiration_date INTO v_passport_expiration_date
    FROM passports
    WHERE id = NEW.passport;

    IF v_passport_expiration_date < NEW.issue_date THEN
        RAISE EXCEPTION 'Visa is issued to expired passport';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_visa_passport_expiration_date() OWNER TO admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    login character varying NOT NULL,
    hashed_password character varying(200) NOT NULL
);


ALTER TABLE public.accounts OWNER TO admin;

--
-- Name: administrators; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.administrators (
    user_id bigint NOT NULL,
    office_id integer NOT NULL
);


ALTER TABLE public.administrators OWNER TO admin;

--
-- Name: birth_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.birth_certificates (
    id bigint NOT NULL,
    father bigint,
    mother bigint,
    person bigint NOT NULL,
    issuer integer NOT NULL,
    country_of_birth character varying(100),
    city_of_birth character varying(100),
    issue_date date
);


ALTER TABLE public.birth_certificates OWNER TO admin;

--
-- Name: cities; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.cities (
    id integer NOT NULL,
    country character varying(100) NOT NULL,
    city character varying(100) NOT NULL
);


ALTER TABLE public.cities OWNER TO admin;

--
-- Name: countries; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.countries (
    country character varying NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.countries OWNER TO admin;

--
-- Name: death_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.death_certificates (
    id bigint NOT NULL,
    issuer integer NOT NULL,
    person bigint NOT NULL,
    issue_date date NOT NULL
);


ALTER TABLE public.death_certificates OWNER TO admin;

--
-- Name: divorce_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.divorce_certificates (
    id integer NOT NULL,
    divorce_id integer NOT NULL,
    issue_date date NOT NULL,
    issuer integer NOT NULL
);


ALTER TABLE public.divorce_certificates OWNER TO admin;

--
-- Name: divorces; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.divorces (
    id integer NOT NULL,
    marriage_id integer NOT NULL,
    divorce_date date NOT NULL
);


ALTER TABLE public.divorces OWNER TO admin;

--
-- Name: drivers_licences; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.drivers_licences (
    id bigint NOT NULL,
    type integer NOT NULL,
    person bigint NOT NULL,
    issuer integer NOT NULL,
    issue_date date NOT NULL,
    expiration_date date NOT NULL
);


ALTER TABLE public.drivers_licences OWNER TO admin;

--
-- Name: educational_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_certificates (
    id bigint NOT NULL,
    issuer integer NOT NULL,
    holder integer NOT NULL,
    issue_date date NOT NULL,
    kind integer NOT NULL
);


ALTER TABLE public.educational_certificates OWNER TO admin;

--
-- Name: educational_certificetes_types; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_certificetes_types (
    kind integer NOT NULL,
    prerequirement integer
);


ALTER TABLE public.educational_certificetes_types OWNER TO admin;

--
-- Name: educational_instances; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_instances (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    address character varying(200) NOT NULL,
    creation_date date NOT NULL,
    kind integer NOT NULL,
    country character varying NOT NULL,
    city character varying NOT NULL
);


ALTER TABLE public.educational_instances OWNER TO admin;

--
-- Name: educational_instances_types; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_instances_types (
    kind integer NOT NULL,
    educational_level character varying NOT NULL
);


ALTER TABLE public.educational_instances_types OWNER TO admin;

--
-- Name: international_passports; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.international_passports (
    id bigint NOT NULL,
    original_name character varying(100) NOT NULL,
    original_surname character varying(100) NOT NULL,
    en_name character varying(100) NOT NULL,
    en_surname character varying(100) NOT NULL,
    issuer integer NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    expiration_date date NOT NULL,
    sex character(1) NOT NULL,
    passport_owner bigint NOT NULL,
    CONSTRAINT cns_international_passports_sex CHECK ((sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])))
);


ALTER TABLE public.international_passports OWNER TO admin;

--
-- Name: marriage_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.marriage_certificates (
    id integer NOT NULL,
    marriege_id integer NOT NULL,
    issuer integer NOT NULL,
    issue_date date NOT NULL
);


ALTER TABLE public.marriage_certificates OWNER TO admin;

--
-- Name: marriages; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.marriages (
    id bigint NOT NULL,
    person1 bigint NOT NULL,
    person2 bigint NOT NULL,
    marriage_date date NOT NULL,
    CONSTRAINT cns_marriage_certificates_different_people CHECK ((person1 <> person2))
);


ALTER TABLE public.marriages OWNER TO admin;

--
-- Name: offices; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.offices (
    id integer NOT NULL,
    office_type character varying NOT NULL,
    country character varying NOT NULL,
    address character varying(200) NOT NULL,
    city character varying NOT NULL
);


ALTER TABLE public.offices OWNER TO admin;

--
-- Name: offices_kinds; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.offices_kinds (
    kind integer NOT NULL,
    description character varying(100) NOT NULL
);


ALTER TABLE public.offices_kinds OWNER TO admin;

--
-- Name: offices_kinds_relations; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.offices_kinds_relations (
    office_id integer NOT NULL,
    kind_id integer NOT NULL
);


ALTER TABLE public.offices_kinds_relations OWNER TO admin;

--
-- Name: passports; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.passports (
    id bigint NOT NULL,
    original_surname character varying(100) NOT NULL,
    original_name character varying(100) NOT NULL,
    en_name character varying(100) NOT NULL,
    en_surname character varying(100) NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    expiration_date date NOT NULL,
    sex character(1) NOT NULL,
    issuer integer NOT NULL,
    passport_owner bigint NOT NULL,
    CONSTRAINT cns_passports_issue_expiry CHECK ((issue_date < expiration_date)),
    CONSTRAINT cns_passports_sex CHECK ((sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])))
);


ALTER TABLE public.passports OWNER TO admin;

--
-- Name: people; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.people (
    id bigint NOT NULL,
    date_of_birth date DEFAULT CURRENT_DATE NOT NULL,
    date_of_death date
);


ALTER TABLE public.people OWNER TO admin;

--
-- Name: pet_passports; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.pet_passports (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    pet_owner bigint NOT NULL,
    issuer integer NOT NULL,
    date_of_birth date NOT NULL,
    species_id integer
);


ALTER TABLE public.pet_passports OWNER TO admin;

--
-- Name: visa_categories; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.visa_categories (
    type integer NOT NULL,
    description character varying(100),
    working_permit boolean NOT NULL,
    residence_permit boolean NOT NULL,
    duration integer,
    country character varying NOT NULL
);


ALTER TABLE public.visa_categories OWNER TO admin;

--
-- Name: visas; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.visas (
    id integer NOT NULL,
    type integer NOT NULL,
    passport integer NOT NULL,
    issue_date date NOT NULL,
    inner_issuer integer NOT NULL,
    country character varying NOT NULL
);


ALTER TABLE public.visas OWNER TO admin;

--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.accounts (id, login, hashed_password) FROM stdin;
0	admin	$2a$06$/6w9wfXj/RLbGGvU40aeHunTDLFnxBL3n9tjeSpyYlvqzItFGXzoi
1	user1	$2a$06$V2QC8sCwWZ3uoI3QJM57webyRyJ75n.JXv4.MwXpjnHDuBn67Ykpm
2	user2	$2a$06$sykyG5VI6qIwen1tCSpP1.dk94ZivF0kd/XzPLoOB8YKbAbGgdQe6
3	user3	$2a$06$xUHcZtuGRYDKZMavCxafVO/MBi9gzSBuH9oqz4oDOmGR0IFP.90va
4	user4	$2a$06$BtSBB8m3y5jak8jC5oH/g.vDWfsB73CDZgJjVvXw4NR/PEfnPM9Vq
5	user5	$2a$06$oi.pRb4WV55mTQAFFlHbB.skj6X1Lnmh0QS.o6Lo0828.Pr6cHVjm
6	user6	$2a$06$7xJOBUaKTwQRgXn/CKYz.OO74hOPDg5DS0CI8IIAmxDz2rM0jceyW
7	user7	$2a$06$Y9rJ2g031mGVXIbbko.v2er8yV5fbS29TeRY.CVYbA.bQ68w0Pokm
8	user8	$2a$06$djR/qKhhTiN94wG57S8JF.YdT6YRLlWMUVaWmHGNk.EUWCvx5zBxe
9	user9	$2a$06$jO2iCn9MTJQLoryABrj4p.c9YynqRgPSC/fwKG.tv6OqWehPX5cd6
10	user10	$2a$06$5ZHZSf4PhfwVrkcK/VEfNO/BaqB2OEerAAI2fPANGInS2L8VWM7u2
11	user11	$2a$06$HEYmF.dN89ms2Rc1TKLWI.h2XwskuadhQKNOJC0mKzFnAw1LFHgm.
12	user12	$2a$06$KethU9aSBv8Jb21MACu71O8UDuB72cV75FizMSgPjmU21HzHcnNBa
13	user13	$2a$06$37kVQ2ixcp22GmaD9nSi9.h3E6YfZB0MxNDBDa.oyQwi3aCqo6aFW
14	user14	$2a$06$bNgAVdspsC23ADAFELMjN.yfDaEwVfJ2h2WVWeBMvlXIybXcq8Cx.
15	user15	$2a$06$Celzq1kBM5c.5por3xn8ZuwFTBC7OmqBHcG2cwSq2PJEm94theEt2
16	user16	$2a$06$RqFAwgzVeSRfq2mZum/WIurmdEySwblTBM2/ArKPciRqUbYdUX/Wi
17	user17	$2a$06$.5oMJILabIJ30TEea4PhwueVP46A2T8sArPrSUAsYaoXMc6g1.1P2
18	user18	$2a$06$7IyLZEAOzPdQJxFomnC2jO30sMSp5Cr8DLcZFVgO.gQ8W0Kuvlp9q
19	user19	$2a$06$3yBXr3C7MRNKlQoNJRVs0.n0UeUK.LQhQjGjjAPiPaQbxyjqBCGMK
20	user20	$2a$06$TDK1/H0i8Bh2w1stPGdnZ.8KwjiAlgXwsJTHKnboJTEwqwhiyEDeS
21	user21	$2a$06$XeGgsEfDDAah8GdIosXNtO2JqSMJMlUemQhIdU6x7qTrbIqBN/Tq6
22	user22	$2a$06$HCnLxet28wnKL/xZKIDtGuNvnGuqBb9J6uVFhuEy7dqhTAy6UKExG
23	user23	$2a$06$k8yWPH9a.UBU0m4lzaNSbOcme75mirsZCBAinMBSnvsnzqW3EqGKu
24	user24	$2a$06$EGD348tOormAgwgdy4KTB.3BWSLpIs0r.WemTXW0WK7XFhtgY5y1a
25	user25	$2a$06$5hjMuMlFtvWHzBEMFUC4e.AqlUhrXXaX.REoxzrGpc/Qics4jBGTm
26	user26	$2a$06$tDaf9ubH86.1Z7j02MVZIezd2xu707HgM1d91I8P0p4oRfuJGgxRO
27	user27	$2a$06$cPRNfAHJ22VFlMKAiZ43/.lMBsiKlebGVB1YQnNkN4vAXfrA0soS2
28	user28	$2a$06$VMs1X4UT4uFBRVrMxsHmB.1Hb7SwFDaFrsLK1N/ZSkOXFR05Lp56e
29	user29	$2a$06$dxQkDj1gHRUk/sEmqejGxOGM.oyEYy69VS6QHaKRskDeZxFwqFm2m
30	user30	$2a$06$8ppdiyrBNwzWCd3OF1KAXuTtwfnAL802eAwQ3fC8oZU1h5FiwGHk6
31	user31	$2a$06$sw3dZEpaTTIMcqdSlUphYecKT6Wmc0JXjbaTqz.hZ.b/sQhlEcaQe
32	user32	$2a$06$vXYxkcwJ68xuRWf4P05t9e2tLjKsYCphjf6.mNQv/qPn3v.M0Hh5.
33	user33	$2a$06$HqjR9N1oi3H11SQX9f2HKe4AHHtOFRPM5Vq2iUfGXTYHvKDi4VuEC
34	user34	$2a$06$xGhXKSKgq/UkePGVIMjXveZ8EdeJxotRm2zGme9hGulOVpaq7kHFS
35	user35	$2a$06$qsx1H8RbwyDt9f/F1jiXb.tAOhNFFeZcc27soAAR1265aqetu7dUe
36	user36	$2a$06$BKr29I7Fe/nuMY.lYJ2ifOWFlV8QZ4D.zisBCxYL99xC37K6YZw5.
37	user37	$2a$06$CfGzVcDYW.so1jQqvNfNiel9eSS5lLHOsSK6bN1s6fRcvmRhFnXUO
38	user38	$2a$06$mhmUmXs7CpazdXIWFlg6teLzf9kStAe4LrMx6CLQUc37oPfs2z5KK
39	user39	$2a$06$jLN8X6JsOooCKdTqpJc0bea81xjtvLFKjqYcciwklqG9V2VfspZJO
40	user40	$2a$06$w07BQmn2YDEqBB.epTNzpuHu7Yo6gj3bR52.L7hXl3KbtuErnUxma
41	user41	$2a$06$WN5wZBZI4uINMtn4MJ3DB.dq6QnlCPlz2iBcbPeX4X0VbFkuPV0v.
42	user42	$2a$06$ZpdSQJHxH3dPWeDnl8smIO/SXNZllwLNXGBcmkAUG3TLf70aDxzYe
43	user43	$2a$06$t9dDa87J1ozRCud.hz.rFev.0AXpUVztQSm9RCw6.2Nmrje5nbq7G
44	user44	$2a$06$2mUr2eyqQ/9JidNz3IwTDOWUpsSy1gYTOzEMBQ85dmXV1SLhMW7vy
45	user45	$2a$06$a0ku.DBtEBiOocH.lpZVm.9Jniqytehm/TY5dQsQw/Zz466bbVnfa
46	user46	$2a$06$dVfF8mQBBic6fGyBQ9xKeuftiacZSpgzY33LU9C1oRPD8UXVLDshG
47	user47	$2a$06$.O3BHAPl/sFTtJXNMwDdlunxQ1x9fX8kPZMTkqHh6sSNzGeFAmPhy
48	user48	$2a$06$6LLeqlCibGK0I.QpkE2ekuT/VqpGKpmMs3RJnUPXP0t7046PczPTS
49	user49	$2a$06$UgEaRLxCQBvcPQva7Jz1fezgpmApbWF0ZDKmTNM0.0ZdPiJHPpY2.
50	user50	$2a$06$asmFc67VLpFLpkwpODUaTO7kGOekjAboamfhdYhupeV6Whons0EJK
51	user51	$2a$06$qbUJHBZ88vJzrAPbp6Q.WOgZPfcNNal27xXpC/NZqjXrvZgPZ0gAC
52	user52	$2a$06$wpIGIVIKAOfQ1rQXjBwlWuhmhkE3FkPTpNVy0vY3XTYWCSgZcmHb.
53	user53	$2a$06$9O2qMXQ3zuj4c9G2Uy57BO3GdD35KAOoSpBhxalPiWXWV6YTDL1Ka
54	user54	$2a$06$.KN2MBCK0q7MWgU3XHSO4.A2.md1UWBg9mLJ6icQeTYzRevZLDPT.
55	user55	$2a$06$rS9.v6BuY0DSO2P6hmuo4OjNiv7SL10PwN3EtsqduP74ad8xSel7y
56	user56	$2a$06$V0pSLkvq.eip273p6sZim.hICbu0XQDuG5jjx91sKo/W7GsMZtGVa
57	user57	$2a$06$pejjXtMZ/Xu1xbB2vR3kCektjqmyLkACTRUt/ZtdpaQ7SBKXeR6KW
58	user58	$2a$06$zjgolISVHk3O8ziMWGt4Zu8qc4XnfutzMcafMeyoDlsQ/a3gKqUkW
59	user59	$2a$06$UDogBrp7RjDYIhjIRDEY3ODajZ8M.cJhX0tYDPhn2WWFkepmCeTnm
60	user60	$2a$06$Ddf9OeW7LQeNv41S1SOfhO9ljtOqAFjJ/Sc71hVzCqV7bvN5N4EY6
61	user61	$2a$06$Xd5uskq/fudg/XLmuQdA6uLtXA/AxOR5h4V5jJAb1Dkx93R9BU0gC
62	user62	$2a$06$3yYe95D4tPYS1RB8hjD/seAIlpugeHDEgT2L/5VEFvCK4XuWcS0eO
63	user63	$2a$06$jB5eA6KtjD0IW9.MyFtkHebX6kCL/zCwmkKWyK.F724FdMDDCOIvG
64	user64	$2a$06$IkOxyy9X/dOcFIFI5jQM8eFlK5dGMrJJsOuQcs1gsoU.jVZNlU3jS
65	user65	$2a$06$UAW57TkJarpnbjPMKXJYuOrAoWGRv9/Vx.sXpvciIqplF1JubbVGe
66	user66	$2a$06$9chvkEKT9Y4VnTtw3iwycePYiSU468Uj.JB9IN7v8zA4uQlznqrrG
67	user67	$2a$06$FYO.Qmu9jVu/y0dt53.skeMTXPBhiu8Imbl5FMYF14mLCQOK9mxni
68	user68	$2a$06$xwuGqb5objLiUP3uCZyHCuqfqHoGZ0ZO7B5XTFJzu/rOKs4uo.1Eq
69	user69	$2a$06$DxM.64ijWAuzr.GscVIaBeat8QQsB/dzQV5A8qQTkQ3YOObEHSNDK
70	user70	$2a$06$xp4tCmW41S3AXhqmrt2nOeZSbAu1SIX0kwkf1SKJ2.VkOB/GixlMy
71	user71	$2a$06$Nmi7WhsLmUMyfq/ghiaj8eoIuI7SIipxiFHxLXLMY8.VB.GzivNAO
72	user72	$2a$06$bU2bMr93cGw6qyn5C.Ill.HASp4to4nqGNi8whVSxI4RCYreATt3y
73	user73	$2a$06$MblSEQp.0FjeyQnkVZdZJeQ5fjwUuTe9hCN4nhoIhkPCQKBBjAWXe
74	user74	$2a$06$7K8iBEYMu5EMgLauhmzvcuYuqHQDZJDGTFqZPYPThbaDtxmcfzD.2
75	user75	$2a$06$nlBug0UIBzAIRZZFCV5dgOAvlK84ga5UHhza0ww2QLU2afwX0dIDO
76	user76	$2a$06$IV1pFzZXiGxE414CJ9MI/eTMJDhnHW006ucUuCZF04bCDj7gJVsyK
77	user77	$2a$06$srokteMZJ9g/5wcRPvkHLeb3h5sfX5I8cU2dAlqIy.9PprwsR1oby
78	user78	$2a$06$tyNSZHD80ZKh5u8Hp0nxJumPWsCjgMH3AL37dtDDjzZz5VEXJgo5G
79	user79	$2a$06$qZI9j4nYWDLn8rtwVKBcq.KdqEevxxKz1IW3xpZ/PDWfmWCMApp1K
80	user80	$2a$06$YFZVzS1aPMNtEqMUTKkLTOzzPNAhyHZoSB6WGBFa.qn6hrwJxHhyK
81	user81	$2a$06$VQiYWZoP.whR4MVLbcAq7u7enfbd12Nw7ou2VNQ1tLzIL2jV8nJFC
82	user82	$2a$06$fL1VFFzwMs1ClMtKqbrDseCVChDNEi.k3hb3/H3JoYSjzmEICL85K
83	user83	$2a$06$VIHf8m09SxSy.NobTnumreFQEznZBo66L5kZs6iwHJ7tJChln/RNu
84	user84	$2a$06$qO8IMG2g97kOwRMslYhBvuxl71bZooPXllqi29o85T6bgMFx2rlme
85	user85	$2a$06$FHptuRU57mjjor/Q0aYWGuYq6BLIxfOUgiGFybwxY/4oyIGYdnrQa
86	user86	$2a$06$vkEJAxMzqF.ZafaOQ7j4rOUKNTfj0PeDd6WmXp49po9X/UXIUqlQS
87	user87	$2a$06$4Gv/XM7./IOcrBge12X04uSHAxxR9dHmiFE3GfkElqaOj9gRAJ8JG
88	user88	$2a$06$viFL8SpLEZ0qE8FBl8zEwO3887gD08ndtFRD22qfho2oZBSY2vst6
89	user89	$2a$06$t7GRG2s1nzMrc//7HUknFOm8Gj0xdjstCZr4N62iyJYORAhmvMqfW
90	user90	$2a$06$w8J3cRaMAtZG.2HxQwXC.O5TejDfljC68QYFWW2LkmTasv3Sqy6H.
91	user91	$2a$06$9UxMdoR8W/hl623k..j8y.tyCtoCCORd773fz6Kvnz1I3aXAKYs/S
92	user92	$2a$06$NSjoRJGprDXKzN/4TYDYvujo60AJe0QVhNhM7Hsz5pXlu4PFAnmxu
93	user93	$2a$06$NypI.lQshoIXyfCwbUajYOyoScl/7KRRZiLI.9IASRZ3o1Kmi1s5q
94	user94	$2a$06$fwEDZ.TTOkI/5Wb4B/VMm./.Cs509Bl6Om2uEE2qZ8HDh/kdEeNr.
95	user95	$2a$06$0KuPUJzoK2ax9eVV.yphuuUFWrWTDGh5Q1/iTQS3Fvpfbq2TwW1Fy
96	user96	$2a$06$zOjEa6vycQbZJiVSoDHJX.xHTseWeV9YlvLf1yrhi2dQ.0yknrvlu
97	user97	$2a$06$.jAeumK0LoGwqeOrBpNDZOnHI8TIlhlF5VfGGcSv/hgxXj7E9nJu.
98	user98	$2a$06$vgAgSx6CtyykPCsPCL9pTOdy8t83ePnbci/0ZJ4DIJ0rXXQ285YHW
99	user99	$2a$06$zmqkF2.k8NZVC9drh2wgn.F.z.lzzXETSZ6WKNCUi.BZfRel5zUHq
100	user100	$2a$06$./YC9urRlfnO4WW026SpfueBdnh3NUN74wOnRD5ZosiCKIJCZ5UXW
101	user101	$2a$06$01A1J2fpz/5MYbWy5yi2xOlm1XX6Pv52EDZarQhFG4yY.MjQuONhC
102	user102	$2a$06$svZHd3T7GgXsI.etAxqQ8uOjcs9xv2DyFYo.pDEoFJPMlz3YIGdLS
103	user103	$2a$06$jAY/6tim99NBGXWtgI5s8.xH45E/4IhOgfSmKbimiJuJVyNY.r15G
104	user104	$2a$06$W.3MvRFEaCsdOtSu8a9LueIsn07pcaCaJsvn66QFEagZJqpyp/WiO
105	user105	$2a$06$ePON0cAt73Nqrl7vzhMAgebNC9EMAkmQ3L/Jxz2mzLyeWBCmXRdQK
106	user106	$2a$06$RRZBFEDnezdFd8Audgw5FetTAilXlHVlKgcDiZAraJeJkfzWAv5ti
107	user107	$2a$06$SHsiQyUB5i1sFd0NOZ0Q9uWYxcTyC/csRBcHImrk4aHMJPlrin.8y
108	user108	$2a$06$9KLWDU/9WOrgphzeojAnkOWxg6DOvYw.A4mRA3E1k.8Ed816PXnve
109	user109	$2a$06$tQuBQTLoWLy1.OxqCyoMBuP.2awXb5aZc0eVfUrWJwHDsDeCPRIzK
110	user110	$2a$06$xx0i17nxx4uYny1zL9C9cOHYF6F6Kn.n3uqHg0Iuyy/Ox7cxLykLi
111	user111	$2a$06$BJBRxqIuILW0nTrTSFgqdO9WRyav1A5BZcO6GD3WJgiKj2XDQ2tje
112	user112	$2a$06$Bl4WmvHwFQTZbrP1h864HeFhtUXZ/9/x5wow9kCzIeOe.i5c6LIqG
113	user113	$2a$06$leTtwuMwxfoXQftVmlM8Nu1qcGgD1zzRD.GxDLeOk6m8wu63pgJze
114	user114	$2a$06$bEgTuBnrw1OizoCUXwauDujwV8l9Fo7qzI/ghQuhsWokinSXaWH5m
115	user115	$2a$06$d03UuvQzvf.vx2zQnWxkEe66a3K3CxWiGFsUH2VXsh.BpdmIhoH66
116	user116	$2a$06$6douAY8Pgfs6LwVkyeFvq.2Jg5JeQbKmlS6Y0DmtNk3HZ4lNGw7Im
117	user117	$2a$06$.h0.TyMzsn3ALmpUo4LVZepWoX02naJDKClxIlW3gGdD0KPFuzWUO
118	user118	$2a$06$5LSUTp/Yq1WIZHTohAlWweGrZaMr7yS925gpvLKjYZgOhzdSMGs6u
119	user119	$2a$06$jpxhyaq5AducybVwON4fIeHmWFsbPuOMY2tQNIhKzfa3Oy37C4Rrq
120	user120	$2a$06$90K3L.1mz8tkKwoB4ziai.mRd0WJUjadQMVL1F.aN7fogLtsqiL8a
121	user121	$2a$06$DQyDuEu1I.CDM0hNgNe/wuONs1xpEwaJlTqkOZSwDAjv1gOQCsvua
122	user122	$2a$06$HZ2tBU/amRv2wMymj/YgyuGCgOhE0ZiduWpNskSpk0UjMsuYEWATK
123	user123	$2a$06$u3Q9GiKg9muqvWbDwr/nv.KcqEtS8oMYYdtjOVBXk4kw6cOvuRN.u
124	user124	$2a$06$lkC73F0G1Rngwp/pR.R2j.9ypQ8Di/zMdgFR9v3lXOXk6iQiD0XXi
125	user125	$2a$06$wiZ.4W8zaxAUVYGXFOfAKumBHT9kiRAculrgqEtV9bVzqdN4rkVXC
126	user126	$2a$06$aMQ97GYS45XncI/w/YJaAuR9Uy/sZ2dITFA5yuTOGPXzElCUHk7qq
127	user127	$2a$06$SjieSDsLItSKsGoRW3/ysutgrGK8NkmB1E78BRUNgvFLfdxMY/EoS
128	user128	$2a$06$I6TYwRZHeEwF75tfSjw/Wucn9Juji4PkRs9aZlneI7tlakwQr4gMO
129	user129	$2a$06$RUqOTH9DCnKql/Xt6S0CXuw2SFqsohLNCKAGBYURd4o6T.y8AogQ6
130	user130	$2a$06$LhLwwVEcIs1qm2BsE2qFjOH/02J19eeDPrZNUIPEuCQViBBkRoC9y
131	user131	$2a$06$yiPlEGw3y40ZnRjWdzUomOKuSpJBHTkrKOw.DkyFrusp6Z/Z7qvim
132	user132	$2a$06$vWl5nvE3EqnOqBqH/a/bB.5Lfs/06jW1iuKEbQdlsspvAYII1iD6a
133	user133	$2a$06$r0jLbDLQaqBhplTqE5mTJOzTC1qam.YUbM3.uhL28cep5RhpYP5dO
134	user134	$2a$06$KfaYBBAIQ8khsU2UqpVese9uRuYc9kvx8yjb2W6QqvpybdUMQ2KE.
135	user135	$2a$06$yH00Yx703OGEkECZM5AvbuhUFMjJyp8CJnrDr7fzMtEaAbNkDV.76
136	user136	$2a$06$AYxwLrQt9Co14zlFLFVetO8ZsyG5ytAOQrkR/pynDV51yNd5MTEKW
137	user137	$2a$06$aV5gIPp/LUznsqb2nj/69OQnzPPXj9JcQLhTecj394ToZ4YAM.Kyy
138	user138	$2a$06$6WcFmbY..wMu6DHS/JuVceGruoZMejEEMJNdyCfwVGdM.9s2vhbNW
139	user139	$2a$06$F.5qszTu9F55kHgp98hblu9Dr8PIw0gclwvaEQiNAnM3rwNA0Q1YW
140	user140	$2a$06$SKVSohNL7JYOOmDT.KJWK.2e5lmE6HKKwO39iVo38nk6gnlYu9EZu
141	user141	$2a$06$PwBTqlnxSVE6IpW43hjntef94xdovCCqCJ0j53J5C0szUWKpaOl6e
142	user142	$2a$06$GmiiCiHsJgoYpcsSN1V88u27aYwUe.FjkQQdxZ2ZNJmp42o4TU0B2
143	user143	$2a$06$7PozzMpyIshZwQiDpIEH9u8LWTx85d9LUAbfBrKPdYmtsJsGZsHU.
144	user144	$2a$06$CZPna5l8aX85DafTVDTHc.aA12b.ODC2oPzrSsr9zZGc04B4SjdGO
145	user145	$2a$06$YS3DHcjAGoVoAb.5EH4PtutMiLhQUDv0JFR3d4X0Tbwd5b/Ub4Cia
146	user146	$2a$06$dYfr7TLKDgKwTmfiLa20nOgResqa1AN1Ze4/BGA0LhBAqoRH84e/O
147	user147	$2a$06$q6r7pSWw1b4HuLALHkD6vek3Q1wA1cPkrjuSgzke2eGCIDuNsMzsG
148	user148	$2a$06$zmz2Rx2TtbRD2BO77Lg0wu.sNgubKY8FEkEsbZNmZ6EarTPa8JP6q
149	user149	$2a$06$S86y3Dk4hsnN5A/IpEat8u5m/06ZBAW5vLKzUcsn.eMKjxMxuN2z2
150	user150	$2a$06$lig0TfmmAqOTDr/FI.NIX.mUeMeR.NYu3tjkmAU6awjZWD51OATzq
151	user151	$2a$06$ebOk.iOWjZ0H/cJ3EQb0k.NW/Ld0p8ZmGRVO9gny.tdhGCA25TGpS
152	user152	$2a$06$WYFjIXrMcBs6VrUK8asCf.nzfqSJbrynysqd5K7w9h.946d58gbKG
153	user153	$2a$06$pax5HCLP1vfRHeUMXDfaXeZ5ueQnU.c.okRQW8M8.ymOW2ms9qfRm
154	user154	$2a$06$HpPNJzpeKjuNc8zoMyUjqus8z.U6uOFvmWCtfK6wWDQG.fdnqUlia
155	user155	$2a$06$k67TDZVYJtqTvKfe9dqLCe2hBcR9NNvuTPphnUXAVxQtTzk8NHLyO
156	user156	$2a$06$CD897B5TaSuZ5eOX9oUX6uSsROA39P88O4T0c/vFNB5Xv5qkxMlGy
157	user157	$2a$06$3FZTusHGHjo4KN3yK.YiF.SgDmOBpy38m0O5qbSQXV1DtRHMaJdWm
158	user158	$2a$06$waCcdBhQQUuIiaJm5eCkVePUj7CJi/WqPARL/DeOOENV3MVn2hyTe
159	user159	$2a$06$hNtKdS1GjmIRVYtAKdd0iuPqzem2pyCaYogc8ZHiCmyf.CR6UJkKi
160	user160	$2a$06$ME7yc6dQOjruur9lKTLD4OPbirzdHGPCoGnPEeZyyuLrwFWacGocu
161	user161	$2a$06$DE33EYqR.k757RADQbZCce.dt/.u0ZfyhjUHJsJyP5bQGmbu2aVAm
162	user162	$2a$06$NZ0rN2Tl8VAqztOpoarmeurd/ULvsktDfr3nsqa.8WiDhP9yY6pgK
163	user163	$2a$06$5io0TKm6rRN1UELaHopRnuuI9LE2PKwO6uov1xmED5O7KvRqg5ez2
164	user164	$2a$06$qpGq7JnZSlHvk9SYhE91leEoERTQokEg4HaVA5ApuqFq4NvCriZp6
165	user165	$2a$06$37xna8/CpkkyTyZ5chNfw.FfXPTD0jA9S9oqBSIGIIoBkujM8JD/6
166	user166	$2a$06$heMe/WEiw8abF2zFeOY.qeCV2ZoGMrmI/YybW8vnoRmIPu1yfgG1O
167	user167	$2a$06$/5YVZ7BLNTwoEycRmk9hYuFqeMMFvpkCJpb2P0euKRlPfMUSXBixi
168	user168	$2a$06$FOQG5v9SnxIITLq.qgJxOeYTdaS3ZhbOR5IYlcfn1eud0i2XjU/JS
169	user169	$2a$06$9GZjHFTlepKv7vAE22UTm.aAp4lX4/RJb8eE5m5WDEo3z4YSQjGFG
170	user170	$2a$06$XWtQKApkU4q/EcU6IHNtyOaL8cQoI9o9k/rHltp3f2yJSVwv1k5.S
171	user171	$2a$06$A.zB37puS/Rge0VUjsCJZeXT0qBcAtxe.c75kv988/w/4zAH.vbbu
172	user172	$2a$06$pRVQ3glfnyrvFR9vsGf1neVVRfos/4dUes2BvGpJJnvqoA1We/V/S
173	user173	$2a$06$rECbn8upiyz4oF1PKGkxTOPAVkeevER0Jh20FuUCHpxkc7tQtiWV.
174	user174	$2a$06$0RvVT8YYQIeb9X8zBHObXelcZID9UJTW0i28V7bDRPP4sP/ARs6Qi
175	user175	$2a$06$Jq97FhOiWhbPB/j3ot2.fugM74eswx0RCN32du1DSMYA4Go5Wg4sC
176	user176	$2a$06$kr8wL18qevmBsIf7BOUyPesNq540QB1nrCcEz.l/v7xXJ3YnRoR1i
177	user177	$2a$06$.2Iqb9GfY4HfixKPiUUdteypK9U48pAz7cX6jOCMCWqQpELEs/5X6
178	user178	$2a$06$L5zjXtdm4uG8G3SYno7NUufObutLApDR8wqcNP1c7tfHciLSAwTKm
179	user179	$2a$06$IIimL/Af8bzbDwyyK1NZpOMqHilQZg50vazisy6bF5gLd1scM8QX6
180	user180	$2a$06$egNc8IbB8hEKoROn3ryRJ./mqiq6JEA0233HGGQTtMBz1IFzwAvgu
181	user181	$2a$06$H44DuVt02qbOTBMzimdff.FmvgdZI5Mlbh1RYcMjMxdYrq32mfmfa
182	user182	$2a$06$nftD9HGVwnsnt9gIVXX29eBced1T7Ap6hBNt6FekTN2KA/fxw5MEi
183	user183	$2a$06$Q2fHMqSf8oiB6vyurMGYJOgtEzm8Hm6xhpZArTv1cwFSfwvWOiIrC
184	user184	$2a$06$cU3NO97dTXPV8IhN2zpDx.iKH4.gU7s0ZXZrX0gyjYiwJfeKqJcdy
185	user185	$2a$06$d4aK3QhdxeaZMMSVK4JvS.cXQKRqn.nF/wGStDEbI3AY/MJckdyCG
186	user186	$2a$06$yswJHxDcookN9N6rBDJIKOB5sQiA4v9a5zlaSECMOMtiNTg9m9WVa
187	user187	$2a$06$bsWc.KXsNVX0c3YcD2OO3eNEspg8dvm6JoURFk9iEfVbvndeQFFt.
188	user188	$2a$06$CIeuljMXVomBdjcCH8pQxuKB0qNGRScpgzu5hMz6fOAYJQtpVxSKC
189	user189	$2a$06$agxRdffsIvBiZOWXBuZ9hOxTDE8d425RQJ1fV4KRJLBsTIJ90.gUu
190	user190	$2a$06$2GJnhbT3Lg/pr6xE492GmuhbxvvvlVROdTOXZxVvkQp9ZYEQ5sZz2
191	user191	$2a$06$JInfYXYyJMTYyCmnPMw4V.PaekgYV6/qysWbBe24pj7.Vi1m03d0.
192	user192	$2a$06$M3mHKWCUiK7pSMUIWJT83e7IWgxxF8omdcnbUiE.JS1PKZYZyywrS
193	user193	$2a$06$L0O05Ou5Dn6wdhPOdcy7puB8YRrmEVcW6IVJgETAmRho/OnVkaNB.
194	user194	$2a$06$wtubPZgES9H/ppXziWfB8Ok7yVrcFaKFPQ0WmMNGP00AdhAqp4OJC
195	user195	$2a$06$Gk1W0TGu2XK3pDCphTN1teNw4lyPNCwiehEagtBJI9aA39Mb21.5K
196	user196	$2a$06$glYjhxxTymMM2hsasUSKz.Hf4JYnhWhigo6/VLnq0swFXzdqn/v4e
197	user197	$2a$06$t8Y67frqKpfREah8T19AfeAu3mVIgQzz7BTPUk/E1PqeBn63jbFqK
198	user198	$2a$06$n0D3j1ljDHYi9Va0qTJe6OW4wOX3doceniXO1AEQoeT2Wabrxl346
199	user199	$2a$06$IidGKLevH6w3Gm3ZylSbNer3Vum0IXIcTjfIBfBP2sW3bqSpBXsEG
200	user200	$2a$06$vBCc7cQXr7Veuo7lvj2wnu3.At62D5AqnhqrL8dQ/1bOT6FAhttfm
201	user201	$2a$06$Tcc07TW6VQexN6AF3Y0FJ.OqUPnU6gGXtrmICuECPlzvgg6kXNIOW
202	user202	$2a$06$d4.xBnHsACCPNSgmkhAIEe0eSIBbMFVa.uqgONF.CUTJj7Mmnoeo6
203	user203	$2a$06$94Z04plrG0q3fa1WNV1OsegiiYBK1Vez6teeOkx/Ksz4iY6IZYdqS
204	user204	$2a$06$Z3aEDUySz1PTeJa0Od.8R.1ZUrZFIH3Bcww0xUzmMOJTlultVcDDm
205	user205	$2a$06$Nuf//PfxCcLPfO0QQty7yuDf/N6qL1o67Hg72Vc50Q4ECwm/ayxmy
206	user206	$2a$06$K3viSkOzQmOyaKuzYxYr2u1osnm1Kvnktg8S5K1wlcx3wDT0.Ywk6
207	user207	$2a$06$KnWObKv9DaGVlHz9z2jCkOxtpSTJD6jRaAiOZP5pknM5Dm7PZdr8S
208	user208	$2a$06$PqtTx14AouIklsNXMDppj.IhJHhRhaUZrr31/fqwSqsWJyEFPShsa
209	user209	$2a$06$4L8RDeHvpsOmNYZCGVPysOIpsIdjJeO0uyCANQ2.7ab9D9XIDSuea
210	user210	$2a$06$J0WPB76mBDirQ1m6DrqAkeb9vk7jf8JgOHzvZqmMhMBD5OrFwiAh6
211	user211	$2a$06$8sVoIULYMkUVVN3DJoazBuTu2Wpf/crs3O.xKn.RCyeIxVBJZOEsy
212	user212	$2a$06$AdiHp6fVW60fuKYmU2S/ke7hrVHJFHK..i1W/3eRY9aVTVHD4GHiu
213	user213	$2a$06$KyAOgJeGMU5sYvsmJxHYK.yPjALWMltHapkldxphp/NX3I7.F4uju
214	user214	$2a$06$Tgnit9NClRxrFOXX68T5VOXTx9u4F6mTX5GtuCUdojOMLCK6DPE2K
215	user215	$2a$06$n1.kfIPkGY40LA7Zgcke0uzfmU5SB5PAJqI9OSml2TS4A4uJ/xkTC
216	user216	$2a$06$LA3wdbeYKFlsTxs7dezZ9OrgXPhGPsjGQRVedrsK7u20zKmz6OXx6
217	user217	$2a$06$rgPLv2vBo4Sol5.x.kn5cO9MncDAUMTNAMfF.nDT900lCHuDXYILS
218	user218	$2a$06$axOy5qs9CFDAN0lg53B03OvAjUHINwvEKCUcnck6ySx8U4fEzxUSy
219	user219	$2a$06$i8cK.GuVl5PhwhJdpQWE5e35G.ZhxuyYyH9D10t.KSUDMwlXB8nOi
220	user220	$2a$06$JD.VIyDCv6Zz1wC3gqLXUe75AH91JAnsaeVmDCF0jrmdIG4H69F/6
221	user221	$2a$06$6R2V2OnS0nK1HgPHWL.q6.spycJPmThDJNvj80I3J6JAHL5lHjz3i
222	user222	$2a$06$pwafbx8.MdPYaoPkd/9hmuRsCoFx8KOKdJq2wNZ3npbJo93knJK.2
223	user223	$2a$06$knCl2Mn1eAwhHWMnyVXfJuQJAXsBUGCOodEodTC66Zycjgx97co5O
224	user224	$2a$06$3daSGU4L6jTt6ZT9jfWhIe4jHfKyc50jTSe0vBcS56DqjjH6MGwpy
225	user225	$2a$06$ce.BZJOd0B1/fyjBXycfnOfbJkLeA0/aLC8f3fdpIZTo39VJ/KGg2
226	user226	$2a$06$PQ7C2oRA.hNXSjLDT8nBk.nuTGcgv7nZVoDEhww1/p/KHtzqtlFQ2
227	user227	$2a$06$XXWrWnXxIDleyjw.rPV9EO7OkYeAB5MUmzIYClJu5KkItvOphmh2q
228	user228	$2a$06$jtY.EP/nibcmRvHRGwlC1OGAtGmpgqi4QjykoRaWPHKNixg2J.sLi
229	user229	$2a$06$l94KJNPfeQt/eQl3UEXrHuv2FTbHLj3/JCdmXEG29LRmgZxBls8xG
230	user230	$2a$06$hV5a94utAWYtSxY6j5eUVO0IwxKVaX8VdB9imZEO4eIYFFBsd8fJO
231	user231	$2a$06$kkQfq5Zq10RikZ4Xq2Is.OQtD6tXmbJo5yVKkYBmFfCRb4R1wC176
232	user232	$2a$06$GDG3Bd1oZpil2C1TieAkQ.GhujMFZsbE2wuDJIr20LKuimiK86C3C
233	user233	$2a$06$ADzOC3WPYbTgCnv9iMuG6eCYvXeETgksQIEduOSGpvcc9azSuS3CK
234	user234	$2a$06$dNWCZVcgE7s2iO240B/RE.Ka5DzcuaHgew3i4NQdQkL29WJtzHJaS
235	user235	$2a$06$.y9uSXXKSEC850HrEmzSiOZwxJlCTFyAHSH5XuAdY58BTSLQSyeTe
236	user236	$2a$06$eyiP1SVyCoPCV/ZXcVJjfuOC8kC1XJKD5Znj82B5mPvxrMUKRZzYy
237	user237	$2a$06$8gBHC7.Ek5VULH2d8oL1SuYTx1GZyHGPToo5xeU7ARZOLoZHnzQ06
238	user238	$2a$06$5R1D0cJkDGAtZZKWs5gdSOdOIoQgFSCy.fGxDuDQ0jUBP54xnBjDm
239	user239	$2a$06$a0Bj4xZKZq9Sdr7iUzhhjeY3c392dkfDzYw6yKE7pcS/QTjl7X9FK
240	user240	$2a$06$ZYUd1Dnf3Wc0DqyRO3.zNuPdXh96HO.9/kZjWiVge4Y2CDQpRb.Uq
241	user241	$2a$06$f0TJg7QxvWkF2a.vJJZkPemCVnGEQZwV5KGZvTAMhhAkcRHIllD3a
242	user242	$2a$06$plrb6ZQmKow0Zu1CLGhkg.sndp2vClyZD7aDYOnKGxHBRxdJQZpL6
243	user243	$2a$06$qVaPi/JjHnePk6S6RdGlB.JC/a1qqHZ2t1rbC4i2dxWz8X658P34i
244	user244	$2a$06$DjQ3hKX7QU01JKxF8p5mN.d4pZU6OTd0woxEMOX5wfPtNp4kp2h0G
245	user245	$2a$06$k6MwPlaSg6uVCfNTOc3J6.zpppO257rMofwhA1K37ffG9t1r1DGwi
246	user246	$2a$06$ZhT1BcEN1ea7mKyGR4qNjOLZmsOhamOTWOh5I.PoUhCHauzLX7HJ.
247	user247	$2a$06$PsGFkjY0p.4GNuWLHRpJKeqiINn3FN1KfuD4n0OOp.4.mVPsEUi9S
248	user248	$2a$06$85.C0RubR7Om5MVw.Xhhl..7Xju5rqRrbi8U724xo1MyXj0KQJ.my
249	user249	$2a$06$wJ7DZW0hKarV4jq6NIRPte6oeCRZffeMtE.IlntljDEZw8xDDaAIu
250	user250	$2a$06$jw0fgTyW08dwC7ZzXFDExucJ3n.zNwZm8wDXpnl0en2OR6bDZxdf.
251	user251	$2a$06$9/V7KgdCnxB4MIgCYg8kqexSDRqDG5Rkes/ZAdAnAu4zpbcbGr44q
252	user252	$2a$06$5QzCscGusXSpTjxVNfgEWeEFTwoVaqzXqp5GFyVgPsWeDr43RHm22
253	user253	$2a$06$faaQO5o7aGtWeAJyhmvk.ejQdvfM/BUw0S0zctN6PX2UN/D/Z8AU6
254	user254	$2a$06$JQfUI98FhsdA1vWxZewgGOa1t.Y6qXZu/6lPq7FCTn//LcDRsjKSm
255	user255	$2a$06$nHubvVdpGgDAB3AOvQNlMOd1zHxZrl/3RssTUNFgawhYIrArye/iy
256	user256	$2a$06$tBk1WSNNdjqIVJY8D8p8z.kgEHu6PUxfD8kS07gjY4pgR5/mjcywW
257	user257	$2a$06$sSMSCAbRnCBG5LmL6FAv/uJ5xQnosyvNWgkX06UVjRtFVSnhd53Lq
258	user258	$2a$06$tLXSczmR76GG/5pbH243r.QrYdC1Xq4jaomdS3PR4mpZ5HrjPnjvq
259	user259	$2a$06$LG6oyR.SnjXwzoE.XhmPueOb29AgFO62TUKXmudoQ6oZjBkug30UK
260	user260	$2a$06$oHycmXizCbnGUjZn7Xtf7.j0nhX8qVfK40kkaLl7kA0DqC.rqJbl2
261	user261	$2a$06$sv3WQ8yCP/TCktmwZWmBqeehi0cIP37b/AOeEGW3r6s3iyGKN2eDG
262	user262	$2a$06$io9zSUpG2yyBdnWOKlZWwu.yPujL3Vs4Q8.ztm/AZT.AQjdzGRN4a
263	user263	$2a$06$Y/wMd0vC2p7H2vFOMTjzgOiRvpkvHPwqoj1fmsjr3beDTs53cVkmS
264	user264	$2a$06$pI711i24M3bqZOjVj6an3.c.a2dWeUYuWF3Lj2CH0GAa9Jv4hYyiG
265	user265	$2a$06$k9L0SVZQN75/WUSagvH2lezaroF0T8tRntBy7dfWDQm2p0mEnWecu
266	user266	$2a$06$a2nOitKHqbSs0Qa5lCUJJO.cjma10YDvuWbr3FYgHM2xWHRT3QSPq
267	user267	$2a$06$S5aBz4WUBkpB./T9n721fuO3o7EqicockIK6aRNv45oMYxs4BdTrS
268	user268	$2a$06$WcSH./iKkTWZ4Xmwiy44J.5MHkhWYWgokarJorrfbYkEmfrdkMqOC
269	user269	$2a$06$zlA0dIu1ch.vBarOk1M5FuOjrJ1Zng5P1tEkgQE1BlQENyUe.5e8i
270	user270	$2a$06$pr3/FePxCdb0k3dnWvv4aO9rmWcSQ4GumKjIuFCzvgU.oeGNJu36e
271	user271	$2a$06$lswoZLfqsz/ig2mJ4VGJdOSz8R/nLRLAEi83/euJUcizP/LKOSLOu
272	user272	$2a$06$t8/phmQl4GWGqTgV/F85queO.mXMYhXoXtXROVyf7T.KHPGcLBC0y
273	user273	$2a$06$/6lx7xkQPRp8CUqRdh.9eeSEs4iB2vRO5ehoICnQSGCuVcAHPYndG
274	user274	$2a$06$LibjG3No/jKYTIslre51yuUHOIaai0opqiOVXo0V2yO3MndF4a.wW
275	user275	$2a$06$2c92.ltK2mZcp.zx5SZuO.HaJUjofRPlX8PzChM.ZrOvfZxesTwbu
276	user276	$2a$06$1V.W5lOx9roMWvEdfhoaw.7S4JhR9/gchWNoDfnss7XCFldo0j2ya
277	user277	$2a$06$IIB.QitBtjHIDuE9QILWw.WQZskrzH/ACuGx80Odrgy2GVG0ggQYW
278	user278	$2a$06$Sh.WcnsBu/wbeEdIMuN3u.dT0oMq58/tlY1gpu8YzrGIhUXuTxQd2
279	user279	$2a$06$ci33e7byWkefcZQxIrfJm.YCQCHSa2zhEh9q9vSgZWgBxR5DMMzPi
280	user280	$2a$06$3lYdp7a9t9hVqN8g5EhF4ef0WPrffT4OluKa3goTNELWzBySVr74u
281	user281	$2a$06$kLoc5a94/GkPk9gYZl0o4u3DT0x1RVIFfmxKWw/pUKyMM.hISgH5O
282	user282	$2a$06$ot1NvOCZqcYStuBjlwQGsuezkyBvPHMuUDhTE/eOPPlifYbgwzCgC
283	user283	$2a$06$BcfWSswkLThpvKylmwhCOOXwlcTDLA1xMFwjc0m4YaoL/1ERYYShK
284	user284	$2a$06$34kYtRspwNwWmHqGbbD9KO3c8wzfmbp588Fv7W2ZaNQ1s3fSFESgy
285	user285	$2a$06$Q9XsjE/H57kI23vf30y6oe1sUxFXnTd75C200jIM7dFzsG7P4SDIq
286	user286	$2a$06$f6Hob8oT1.pOPbUy3Xzebue4ZUq.PY3YzCZXggYNPipnK6qSUrBN2
287	user287	$2a$06$VoNPNtDDFN.Llk/EbSDN5.XsZwLccRItgl6dRxgsoCsQx1vnEfxO.
288	user288	$2a$06$BnRxKG7lijOxPbE75e7vmeqGTbJ4hJWZh6dduXpgYvUCv5Ss0qvtm
289	user289	$2a$06$5KkQN/DoqzLab6Qq/E4C4eMtwaqxLJD7wplW.SlQP/uSfdJg1CZze
290	user290	$2a$06$iv7XXGHorb3hAVCoh6DeRe9adZl57VPf9F54l./273nobKI6oRWVG
291	user291	$2a$06$O/YZ/tG1QapcElMACUzOqO3KAD9DMexG8qP4xPfYkT58ykN3w69HC
292	user292	$2a$06$dgFevRSmCG1RbVdWU4Fw.OXY6qP3a62yGL02WKnPSmIJXC0qYsxi6
293	user293	$2a$06$osi6Y6WDRxkyyOcp/AkQp.Wu1ajIp8EwN2w3TiVFmJBMFzhydVOgy
294	user294	$2a$06$J42zC1sgCtYsOxt/IUS3xeclp7ZICOvl7GhSM3jCmIIvmKAaQPvDK
295	user295	$2a$06$McUC807K56k90mzIVSCwiOuaCngbyOf0FvpSBVgwCv6IYOfm6HryK
296	user296	$2a$06$QxhUCZHTiYgR21puRwjbXedxl/fJDHfssM1r6bA.ETC.RXoXKzbVG
297	user297	$2a$06$/8ZOfTREdCHgG8jqab5kR.NSltbB89CNnGMRTupgv9unYbxGCwUj6
298	user298	$2a$06$vCLeZo/5kdIquLnJVDUgq.Ef7ADYO5sK74hMuX5SiNUi54pmkG81u
299	user299	$2a$06$A.bnSQPJI.4iaBYlGMTbSe.Z7Y4ASw.PQw8yCgOLhUR/VfaMDQRD6
300	user300	$2a$06$Hgwi96AyCE67iEF2IX0Xaekb.xvmfSZAZJgtoI4b.lXMIxD97PEyW
301	user301	$2a$06$w9VX7mI09sc.3DxVydjP2upccuJdTzwIumMqYFNHmfbqCJxgYfs96
302	user302	$2a$06$hrzFC/7fxPylK85zp5X5ledYQ5.lDlEOPWiC2zFTv848g6f7oAMym
303	user303	$2a$06$2xXr9zXDRpJKKu.C1BDDGex8kHpdwtQtLHxQ5GUIMpBOcTZZ1dpvi
304	user304	$2a$06$sfWa7IzMBj7xJpTUe0dYaugbazsxvBSTI9daOb0ANmjfJC3iPFl5y
305	user305	$2a$06$4ixatCn/W6d6DP1ccE79sO5olXhmCHnvf.sadGyOLR3WFbqmYEK1q
306	user306	$2a$06$YkNRRvy1/7Mis.EOPyJ8zurLQNe8AdeKPnP4xLDJ20wm6o5klYSmO
307	user307	$2a$06$cDR0QUF8.eTWae1.VklKKuTWed6aH1wGDG9AyrP8UB6uFwEtU60h6
308	user308	$2a$06$AJxU.s6Za1Yre3IAObMkWee/yUlnGIcfrvDKCIexneJNU6VoDAW9C
309	user309	$2a$06$qVK5jj623GteiSU3OAUdi.o8bze4MBW7i8sY2LMrFMX1m/ao5Bpca
310	user310	$2a$06$F4lzdblla87P0DSXdIW0x.k5Jyw6JwkTKtjD7RkGvBje/TvU5Crb6
311	user311	$2a$06$pYcnWTb3vbbSmAR7LCJrs.4.W7igZSuT7JJYzSV1C3xQTbzJI8SxK
312	user312	$2a$06$4XD3aHYNWjJ1AXB3xTCNWOQ9ZOBMXnT5hWYGfH8BjG.qJkzHLGQZ.
313	user313	$2a$06$0.qwr6xbq/jH/CMXGRTIquhFQyiM2NOnL7iJNJzcNBcW17tiGuLH.
314	user314	$2a$06$P7HHU/.xFz2QSoOYz.d0OOesh6qw3Cj7oo90FKDJJNDADfNx3RhKq
315	user315	$2a$06$i3hPS./T0t3516HoN5938OO9OxDJ2OJ1L/QXjzzzben01vNNNOs5O
316	user316	$2a$06$Wxx9ohGK8tZ2IXhBfIHPvuuMfSNz/t/HWjzDdSZ849RNUxPMtnXXC
317	user317	$2a$06$9HVjjFFJjfY5h/f92/GrleqTz07ZgVu20GY8sHGhGI4dLJ71fCCgO
318	user318	$2a$06$QONH6kRqvobaiyRCo3AXserk0zlzonAaBqgz3GhXJ157SBV4tpVU2
319	user319	$2a$06$ZKuyqsVyiIn.KjY7BsOo1ehdwGYXLSfVDzMwfIRL2BDMVYJiJijuS
320	user320	$2a$06$hYYQVkfi3njhv0NgWXK2o.uCgaP8E1IGeAIitlsWqjmOE9kk5lJC.
321	user321	$2a$06$mDWnMD/j/Jqswi8GVzdt1u6lBRh/UG46mHxzZ4GvHknu6gtAdse3i
322	user322	$2a$06$e3.UVEmhgz9ymGIRXDQsdOYVtSsLXiLTujauFtmxlDZ1tE/GzxT6K
323	user323	$2a$06$Gr/EzdJWLZTwco4TjtIfcuYLjJ9hCLuOEe5ERXVWsuOr9d37QFwBO
324	user324	$2a$06$XDDa4nRRhEo65mV5QToxpOSX8gb6XgtoiDf/FRGTmSnQxVO95snCS
325	user325	$2a$06$MfV0AArS75wz5wyjKeBZhOx4AaeyK51egHmEVAee7p3WkKa50zu8.
326	user326	$2a$06$Nzb6A59uXlKac4d6X30x8OXEA.o/6Tb/UTqcVehQ.tm/qx6uwh8/2
327	user327	$2a$06$hCAqhATvDpJQCZNvj1EpO.kxGh7Z2KBkzuFZk3EjSZySe1j.hy1C6
328	user328	$2a$06$6jrfGcwnoP77vNJKJVXsJeW35f/8UDjycEgmocMsfQu1KCKUns8zm
329	user329	$2a$06$pEMZX2TsbSRpRktMQIBDgOwd2KYcAcT2M/5Uth0X67PsRRwek.KuW
330	user330	$2a$06$jXvF4TYrgvFUwcMJIBdUrusIu/nlBPu8WiGgw8OTDOiUmMHp5LcJi
331	user331	$2a$06$8mYgwRWu5iJUd9kpNkxLSe/KWKdRyGKMGFd/T8xGlbYAWchp0CJZ2
332	user332	$2a$06$3BuDFD91bgi3ow4/0ijVmeEeGFkEJqDiXenBgaBcxhDBjz8b15x.i
333	user333	$2a$06$93EKfrXglH61yjimodia..1N0wR6DGi5/B6bddcWhx5WHkYiRz5o6
334	user334	$2a$06$i40QLFHFtsqYJvVyOHljW.LE29FVM5Uq9juZEvO26Dw80JxmEWuri
335	user335	$2a$06$Mq0R.8ecfUAYIQ03JnfvqO.lNITST7aNj9Hkr1jH6oKeDzP7SI/.m
336	user336	$2a$06$3caiXJ3o26UMHnTQg5IpWO8PJi.ZqPU9mUYBbHZRfWFMjUYLKuAQW
337	user337	$2a$06$eqnid.b2QsOBW7AbFHck3.EvYZCvbv81GE7yGOCvWnfWNldvkglDW
338	user338	$2a$06$0o4x6WjcmKHjKhzBkI31M.oJMN/ONKMEFHovr5.zCVtok/2hJhxWq
339	user339	$2a$06$LBkhUcif1J6qV7AV8yw8f.2FKPJFuNUAakflDDwxZ64azdaqYHUy.
340	user340	$2a$06$HDZEiq/Nk0kSlVuLqWCUY.Sq18RHu1LpBo9aVuvoOq.VRStfM.6zS
341	user341	$2a$06$alVGq0uophrVgSi6ArQOTePVOt0t91glxLFy4UU/ANnc5Jxcz9Jz6
342	user342	$2a$06$BAcj32E1wa0KUy3RRd5XEevo90YmqyzdYLJFQWAZCbNec5L2FzVCa
343	user343	$2a$06$jmdiv3KbWe.uGwW6i/HgZO5jmb1fFOVUGxfCwQAW5p3r3AJU4S/46
344	user344	$2a$06$qfML6O/vreb6aHNvhCH2QuSz3LFf3rb2rlWMrR75erhqoYMAsRDv6
345	user345	$2a$06$Pn/gu7sKkznh2qQCYZdgNO3.FY5oMjVJBbAGjO1IV2iBFz3cTdtvO
346	user346	$2a$06$ItWtJK5xl9clgQZ1Q9DNx.VO4iZr3tOU2gmbZrfBJnNwqvL5ZOinq
347	user347	$2a$06$sNGKPEBN88Zd1bt5WpbXHeLVLH9qQvhhju9gRmSelpAIiWV0tOza.
348	user348	$2a$06$SBtGAqwz4iTHIKHPWftDJu7wYZC2hjhgWWMu1AANEtyr5cofAL/qO
349	user349	$2a$06$fR0pmqMFXqwIRZatOyI1tu0A5XcnrY.Pw/CWzSeYBjI5v2PQSiNmi
350	user350	$2a$06$5olKh3mMQCWzmbx/2iKe6Oo1YwykM9gUNxzceeX/keQzn1EaBgBxm
351	user351	$2a$06$YODNwjRa8ZAUbC19x7jcfON/pvhds1R5xI78coP6L0sQ83AUmTf..
352	user352	$2a$06$Ti7qDXvvFhpSHpIVBcmGqu5mh1pYvp9YYWE9qJ8prOd4mAyPRkb5C
353	user353	$2a$06$.BU2Ss92ZBS4fKIGk0rFJOt6lR0O18cSGNLgR7.tg8/2701Im0I8a
354	user354	$2a$06$TWxzcEnXBhV9X4luy0YuaeLRkFNYDC727ovTnUCMGELJ4oruYYGuS
355	user355	$2a$06$IV6iLHj.SImXt0rRAaMV6.d2BZVMNlTDHm3mjjP7YcehA4gg5MXRS
356	user356	$2a$06$oPR1VQ.JWF06ueEHuhRMMe8wMjWhWUSMhemXT1TAxaqUBL3oBa11u
357	user357	$2a$06$Sd13vCYL6Wg05qi7ftYU5u8TKzY3ukZGfyQCsJixkS3ZwErXWv2de
358	user358	$2a$06$Zk46lv7RMukg0PIYXKBUue2ZICU36llS1K6toHQMES5AP6hPgYXgq
359	user359	$2a$06$3PYWRePDjgRk8CLLyhOVge/UTY1gQgxnpTL3qVL8CNQ0/SbvIFxYe
360	user360	$2a$06$rJ6glQ2p5dgd0QQ31wJc7OfiIclNSTvaFsL5uALRoCeC6Vf98vJSO
361	user361	$2a$06$m/J9cEwPycWg2kXBpWgqS..JDVWn58W2jwjhwZgdaIKnawc6mRJHy
362	user362	$2a$06$5Kbq8B/zK8Ibpxhs2Q4.jemeWOe4olyfcPMcQuepbN6ANcEUIHh/2
363	user363	$2a$06$zvvvB5v4b28BfNZmg7fuZ.ZojmINee2VrZ65v4tF8kUYfk2GtYBk.
364	user364	$2a$06$3ZfjLL/IfZYAeZgA4YnsVu7Uu.ee8VFoyrFHaRnQBFW35i9YR0k8.
365	user365	$2a$06$Ly9mswsXepHMU6nAx9g1/.6d/FwdNxPx2SoEkth3bDM9nr7eYNffC
366	user366	$2a$06$Hj1msRSRCSdFN2rwVWVITuw/4hZlSpg4DRyb0t5hv9VyENjW6k/Uu
367	user367	$2a$06$WIiG36aBjmnh6yKZ8.rEr.5aG6DW2KiFDG28jEzqgmfns9/FxXGsq
368	user368	$2a$06$B7rFStyzFc1G6CYJFDkN3.87/hU.3R6bL3ibittEvqsbrbJPSyANu
369	user369	$2a$06$/ujjP2TcGzDtKDEk2SYsk.N3wF7ejzWtuP/RXRQYtjWz1ZTEHy77K
370	user370	$2a$06$y73LsI7FTgUCXFM0l59bwebtLF5gn.vBVw1fYmXc1R9rM2xOvLhuC
371	user371	$2a$06$eOxMHNKP3gxDEXuJmOgal.waPyE6IS4HttwAuIvnrjlIoLYtBaomu
372	user372	$2a$06$anDSrIFrDDYRSr.TGcTP0emhtvoMu847A5q1O6TGmpqL5prbmGm16
373	user373	$2a$06$7DobrDNlV2VCSvECTXecdOIbcL87JN4vFtc1l7x5o9vjbVzoiVBz.
374	user374	$2a$06$5d4AG5tf/yZde2ZE9zTlZuEGEWECYiLMxeWR7eWhkFxzuqsabtj7y
375	user375	$2a$06$rsT.Q5WdaazkrMhcxD9ld.5wmKmcDZTmAQsN9.yvrG7JaxswqGyy2
376	user376	$2a$06$h2F0w5z3vIhdPWQfcImJO.OIvFX4NXSLQnVQjcvGhxuZDw19GtqhO
377	user377	$2a$06$Rl1QWGc1UNWBxhxjCcD9S.7BLgOFQzRBdv28bbmk6gHB1LgBxrMBW
378	user378	$2a$06$tjkJJ5tB3tl.5WpjzKyv3Oou/XOEuZW4ovCpBKidh7GTOasO0dxXC
379	user379	$2a$06$6ZOfeBv.G/duWZFQYje5VOZ5vGsyZ2F1fPwi/Ne9dP23prmKcX7qu
380	user380	$2a$06$3jIz0EYeYki9fjxID5V80OQcMolfydCtjf5NC7xxrDWXuCvF.quKS
381	user381	$2a$06$Qx1UzqrE8HH9HayUVk3Kc.17iWVBrebDR5l86GuTarjP4EOLeZ/by
382	user382	$2a$06$HSf9bq7j8xt9g4UYxpHKGuayceRa8sbYwTPc1qd4eAPA700jveab2
383	user383	$2a$06$gusTpaVZOlviqK2mKRHF6OWzqBL48Oz6IYvKJ1iZmbU1EpbJxUieq
384	user384	$2a$06$W66IWC9ak09L84SMgCLhhukQqy41UYwe.2JwBo49Nvqw.yHQv149G
385	user385	$2a$06$abJSsjilmcmBdfqQXvSLGuEh1Vvle7OON/Ld5FJWkFScd4PiRX8WW
386	user386	$2a$06$ox17dPprOEG5hLl187Kgie98V32KGfGBw.yIwZ4OULtuznyVT85xW
387	user387	$2a$06$8HZcxTcd2eQ5vy6UmeKUpOLnJNRcG/c6baFCrq7izTYUwFou.5ILG
388	user388	$2a$06$sIGqne6EkVgksmkuHB8lPu5jB563oXaEMiWIVE4fGjjZxcZd.Kfo.
389	user389	$2a$06$WXgRkVRDHhWvFdq.eukqq.wreVajPGxI9b1i6cFju19SQmQ3B6cD6
390	user390	$2a$06$sflkmiALyaFgVCqzboeg7.i94EZnvXik5HcQjKi31j3JsSYkoKGVm
391	user391	$2a$06$bb7fNNWRHQEQzCEgTzvMo.zjr9hzi37g/SkzQrRXxPvd0RHzCDCXC
392	user392	$2a$06$qNuxc47VO9o2JfkSr1//s.eB67JbRKHDkDsrFXQ2Cd5dco.lyda4W
393	user393	$2a$06$VEkPNVU4OHQuB7bJt22xDumNwpSNOZDaIRwhGrIPIwj7x6gmb63X.
394	user394	$2a$06$uKm6o7nijitVmgOIeGch1eAIk1hlEDdYgenXF65azYjRWI/kL9Fhy
395	user395	$2a$06$a8oRlnXGKyUbEsaOEALBUOXlbSZY2Ql59dY7Hjs5rSd0RgOKVhAxi
396	user396	$2a$06$IRg8mIud8dMRRCyyv7i2E.SgJUJqim8rR2cR/reRORne9X7vjEadS
397	user397	$2a$06$FqrIS/hlqmBWGJ3d24iHAOXI0Qb3/sH0RGVHCBB7WI/Szjvc1sn1.
398	user398	$2a$06$NW0P3.71QuJkosWgGeUANe1BM.kDizzFhw/fjoiMf4wFHAY5e3hTS
399	user399	$2a$06$5Lg8OLZOy7VbXYB7fCWeXuA32347u4vpnsLXhYEVRyWwxs57OzFzi
400	user400	$2a$06$ktgerAkzG1ogXGXl77j.8uvlPj6I33u4weUPREDzFjSo9W0.sdkyi
401	user401	$2a$06$olaFkpfcXDjaLcYKfbjSzu7DMocr5hqBcl5eV1yqBXvYTlYqM2Tmy
402	user402	$2a$06$RROYzPYB2tZxuIwMzJFyBu1UjsYbJ7qyHiRiSO5mdfpdTwW20gMKO
403	user403	$2a$06$SwyO2vvgHHk7AwPL1YP1aeVGujcWjidzwyyYUEbxVf9AQ/.c06lE6
404	user404	$2a$06$AiBGUkEanpokVOLCMMosnON7KD03oTLr5jvx0OV0xX23Q9JKV5/Jq
405	user405	$2a$06$0Oz7.hPj7MdMpymwn8Qj8eErWBwjz.Oz9Zx6GmYVhwXW9/UbgJUS.
406	user406	$2a$06$.3yqAtclBsIfl1u3CdKHSO273DltnQXLvKclTOOfwilPp3Nut1NsC
407	user407	$2a$06$2CJvF6.mRX0mGSIsTVHqp.bpJLx.NyXzGRM1Z8i6NkBFS1nCygrzG
408	user408	$2a$06$lQwbhu78EjCn5xdmLMyh9OrJRjYLwy3sAl6HK51Y0hbYjFBnGXgfC
409	user409	$2a$06$CZISZFWvGBolSGSJZN0s7uajunidGf.vhAB9H4a3/O69vwO9AXpX6
410	user410	$2a$06$WsMWNEBuXR9GBYtu/Ixty.6vcojWov48GR2CgvJwYHH2D01yYLRRK
411	user411	$2a$06$HsINh6C.0d7yQ1TVpHAz9Ospj.GgbkD0ZYrKfJShhP.wFcKN2dx/S
412	user412	$2a$06$EQukJM0nHG3/QKfmmxWxB.R3Vy3Dq.kN45QnGNCfyWfW7lPKbEE3W
413	user413	$2a$06$kuRNhBB88gRReXtV/c74auYtCPrZ4yRdgPlJQY2mIc1b3nwixokBe
414	user414	$2a$06$741tBd2XDyDFyzoVu3dJ8O6pXmKBGlrDn9O/kDuc9.IBOAsyuKBPe
415	user415	$2a$06$h5pRXOErblf7MDtDnF7dFeZVX/VNYJmyvntCxbswG3zUu0rBHECu2
416	user416	$2a$06$94H7n/IKaHiIViRduz9MheC/TUxjBBxvK5p1X4BI99EnFy/MUzFy2
417	user417	$2a$06$kJAkdEPxdW/OS8J7UJYnw.xdmIrJNNuIG8qxJK73b3uerWQOtXYwq
418	user418	$2a$06$8bNyZHCEX3qxfAwNGWXvxOI6esyV0k1Ar4amIZZkLtYmiKy4HgbUS
419	user419	$2a$06$16GjKzniytEl5fdJwmk2FeLLe9cOhqvUMou4gzNgjXB6g6YaAvA3u
420	user420	$2a$06$hHQBhPgSS6pCf86NKwMwDeIOBvJeWE7lBGk/UPQnj44zT1dXgWIMW
421	user421	$2a$06$8gzjAri3JH2iCpkD0.1nSeiMHHX4t1Jb0K92zT5wquJ11Y/DagugG
422	user422	$2a$06$qZ5lo2a6GQAMt.XwljWyxexgxKEKnJfUXj/OkF9RItFj6XqszGRcO
423	user423	$2a$06$Uc1n4siaYDnqqbNRYTFyw.47tlEYHK1PX.B2P0Ew6GQ7i2VDfEL5O
424	user424	$2a$06$igKb3TMuG.efuBihw7hit.xrZ.R87imja7jRHFb5zhPlmsYLIRMuq
425	user425	$2a$06$eOBKif8q9dHOF71d5hANaedfluhzZrd/Eu/8nkhVjhvt6a8q.rcVu
426	user426	$2a$06$3wqtdQaH3JkGj1yJ3manYO37z7G1ZL9QSzPIAEsw9mBm7eH50Vixe
427	user427	$2a$06$0J3NeBdAkNV8lkbEwJuG6.nbzhdaMEU5m2rJPEM0dKIZ2WYv4vyZC
428	user428	$2a$06$N.jSD0EvBhZNhsYFTXBim.rqyqAp/2GA7m.Z0A3W3NcjKIjEdRaze
429	user429	$2a$06$q2iw43pf5sGdlnoFwSXT4OYflFtrzKZ8T2pjFSbAnxhs35w0eFha.
430	user430	$2a$06$kf8KfthuDkFD6/pYFECkg.dA1uKWVeioHHti8I9dvi6tGlB1lsv6y
431	user431	$2a$06$04mGwh2lJHCmblNVpa9nHuf1lcgCtyjyBYgyCiIFxF.UE82./wwEO
432	user432	$2a$06$xqIQHHbNIrgo58S8YwopLO0gWblwwCkGlC30ZsyhDC5svqN9VwCHG
433	user433	$2a$06$ctZU8Q5C.ICFb7k.nFvZMuGJ/hmZJuKndLRO4DVC7VSxz87oNPB/a
434	user434	$2a$06$YwRPWKARi1Mvw0B00KsEhuhtB8cZklyGVbNRNDoQ40BWVik58Wm3i
435	user435	$2a$06$yxsH4ntFRzwx2tW3PFEbP.AbEmH5GjDfFLZ7.ufa7ldV9R4kO1APG
436	user436	$2a$06$oK5LqesTkk42xxHQP9p8LOr61ODcPnOzVKiLA7Rtb5JIq/26AqefO
437	user437	$2a$06$aOHa6kXa/F.iaqYFiJZWw.1w4QnCjBkWLdNPu4fXoBKol8UGMzmxu
438	user438	$2a$06$Tc/Z6X/zTbwPf6i03riEmu/h1V4y254CcqHBJ7qC5LXWyccsU.09u
439	user439	$2a$06$agW.q5ckP6MD9E9c6CoEUelxTnTYM/OiAn9Eguvs9ocmXLM7ih342
440	user440	$2a$06$D3QPHhxQ1Toi60/B.oMD0erNjxYFoRwfGSxP1Son6ItPo1vRIdcYi
441	user441	$2a$06$gaDWL6Xwrm34fW8twW6fquRRerb0T73en4xgPhEPoY6BUSNjleIz6
442	user442	$2a$06$FW4cVD0HMiNuUIPRwElX5O8dZp/BiFlYDcY73/KmXN1pgGWmo7pya
443	user443	$2a$06$htB8Mtne6Au32aMfVEWeyO6SK9Hkjk28KxSUCeUGPxjfOI2iWZgVG
444	user444	$2a$06$NntZy8ILM3hA4C2Yc8iJlO9ZCFwDLjHe82UgAFAG9.pVLuuQKiYuu
445	user445	$2a$06$Wnc0vy8QcModVl.QOpvkb.OPg7tUmPGV1zXnLcbuo80/igyjfo2Bm
446	user446	$2a$06$ufxGdUX4.M7EY36.eFuYceL69qBEDboZZKAZzk4c22/8FsBvxmGKO
447	user447	$2a$06$KVvUkRClZg1R4x2DsnrpWOZV5BDs/LyPMVwnAazxDkfaPJif.v1Yu
448	user448	$2a$06$Uw9XRKeh2I8/bM6YuNUWaeqsgWD/dYI7LuKxkE8TyXUyhQNql7yuq
449	user449	$2a$06$R1KjwfR1L476TWneKnyvlu54I/KCHH8QnAPzL/B/SFDmkqdFbH7yy
450	user450	$2a$06$cpRpCGZAD9ePR.LtVOezaO1YJxpgCq/wgPywzrKsl7CxMQBpFipaq
451	user451	$2a$06$Zf.Y22QAyD0d3os.QcNqHuQyn1yhf4Jp2zFHfIn0rj72UM4HKOBwW
452	user452	$2a$06$1bL6Chfjqs5pxQcXcLLfp.pF27uWVJFgUHl.GVgMDZcWET09/lgda
453	user453	$2a$06$C1fDj2I8CRA/R74Yji7tU.9cdlMgV3sb.ziho5PeGjavzWDyxbjCu
454	user454	$2a$06$tl//hcGLClypWOKKj6HCuOEXnB9bqk0fwLDDSDYsADTNBkaY4Z43m
455	user455	$2a$06$onuCXiBkiKF2TrMhVr3eS.nqlWsI.adXfU45J6AFr6BMkiItFhGRK
456	user456	$2a$06$5Y82tC62phKlJvbV9FaAZuci4mfVvG11wEEyBC4NupYG0JFkl3vaq
457	user457	$2a$06$AF1PMgs248wQvZXwbtGfY.QLOPUry3vmkYB7g21Eez0mvOaPQ8Wm6
458	user458	$2a$06$cf8XDWlQYMOhHSrr3jSy6.tvviMXg6UyiVKphZ68RZ5gDXLoL31SG
459	user459	$2a$06$j/Wnp8U/QBsmbRLlQ74lx.73Idp/BzHFpArm0JpOlvpMKKH47dbDO
460	user460	$2a$06$9mBgelmW8FO5zqQn6cFLOO1/5c.L3/9uoE/.Rd8Ycxt/zivXNVeB6
461	user461	$2a$06$n1XwvCEF5RiBhOsm6zb8bulq/mcQXC8Z4MPCgvv.0FSY315P6rD1C
462	user462	$2a$06$YJLugVS75eiX/WItfPX1munuGiHTY/wvj5GOb22FR02ykf7R8nNqC
463	user463	$2a$06$h51TKNWoQ61sRJfoESRQj.TO8kbIbozZbQbZecXIuSfVedzFScKGu
464	user464	$2a$06$vPu.ZQhOu69EKy/wyge0A.HCwLcnyF7ltyCFIxSk1I6kaFB1.aGb.
465	user465	$2a$06$5c87jFU9BMr1r9TvNegFzeOTPbbbpizM7PyTitRjKiSBbB/NAwBou
466	user466	$2a$06$sZfGOZ48lLYnx5sYBOhE6uRo/Os5nARlusr1gJS75QTHKKS/XaWVG
467	user467	$2a$06$r1Kjg9VuNDIN6JHLDnNQnOcndKFaCG7FLctDmTmrrdZKc.EE8LLKe
468	user468	$2a$06$tpL3.hWI7NrR8eIZ/7sHYOCToDrNnFuNUr4n8KL1ZhHV.2gfcXu/C
469	user469	$2a$06$t.N0VF/A/xqb4s.n5w3TtuilXdUoW2sv24XR/slb..RJO6aozW1jq
470	user470	$2a$06$0agM4KrhdavEAVUSEZhtbuOq/6.L5YZypVWfAIJfX25Bj3mcdxcr2
471	user471	$2a$06$QyFOoSDDWBsdPQ24OryIuuxRVSyOfW0gCOlWhtJNSHaubWuMGRsoG
472	user472	$2a$06$oilGSkN4v3K7apr1DOFe6eeV.v1MYN.1lETyZ7NoER4/duLjulYrO
473	user473	$2a$06$OkZveSxXX7DTntVnw.jdH.TUMUITezJm3HqxPvAcicJZSfXtTFdEC
474	user474	$2a$06$we4gPrJCsGDAgDrYzWQAZOSlAGFiVd4uRyF/HFkPjB3lbmKCE3J0m
475	user475	$2a$06$lPKp0E2PPMZYT49YGC1yl.3iPKlWQOxoI1CcJdB1Q29iQM0e5Qkym
476	user476	$2a$06$NU3R6.mHAzkJ7BDzkKcu6eg/DwBpQh./PQjgQf3QwnU2zmeRNzW8.
477	user477	$2a$06$47Tqq/kcKXslYKaY3TJHM.GGaOUydfxTnJYnPcuO8J5yl6TuFQ4SC
478	user478	$2a$06$Ih0LDezcEaOYtLG1KCXCTucKnNlEGydAVUQLIyD8It04UvbH8EAAq
479	user479	$2a$06$JGNy52g6AyiuPV.0JXiQOuqBkhgFdTgRCKmhMsrWq9OwHxykUP6ae
480	user480	$2a$06$JuaEFtKDZL0gX7SQ3r0dveI5xLKYPEwZxmGjxGOtQCMb6nuFwGqCO
481	user481	$2a$06$fcrgvS52HpohB.6m4td/jeRoTALlej.MMR/fQwU2zkhBPVo5Xhx8a
482	user482	$2a$06$k8RZTgjC7odDD2ZlQJW40uSoCTEv9Phlf6j.E.EqlT4zP7asqoGk.
483	user483	$2a$06$cNO6Kq7KPg7.IzqfjWOwiuiQvyF.5NEANwy4lhuDmzs.JkrtidxdS
484	user484	$2a$06$.z5XfHLHbWJ2cYlMfYHDtu9oRkdRxW8g1mkWPlTlfDg8lpc1Bw9cm
485	user485	$2a$06$rwVgswUMJSxuNkWH4dzsj.sTl3IDONRqbLiMecOZnhrwCTVF2.gCy
486	user486	$2a$06$oy5.l7Znpg3kOVb2ZFaIMe18c3UqvYYrieIPT2qAX38dr/b9WbD1C
487	user487	$2a$06$N0m54JowLEKyoA3lFRo8oOWRpvE/o9AV/jMSdcZEl2SzZX/5xIyAy
488	user488	$2a$06$0Mh03Te.cR7IKvyto3pOPOvYtbWmxza6uZg4KwMNmXmYWOMpUnk7W
489	user489	$2a$06$4we9JWlaKIkPO1Tos8JEqOfZBhmNEZH2Du3VqA0e60LXNmwMv//ky
490	user490	$2a$06$l1BdeV8HYQzK147VKxIdCu.7c8Fsx0rwsZeTAa3ytdNPO7BWkYEcC
491	user491	$2a$06$P6wqh482ZHlNkzWLNMa2zOpzoqZHzXLQ5NT76VgLTKWNWLbOmnjOO
492	user492	$2a$06$gEFkra5Bs2/Oqfx46VNtWemenwxc5TxemihVsDB2S/XyWJ13BVZgG
493	user493	$2a$06$/eKiQUBqWKHkBWXBsRabp.q0VZsToafrKTFF52Tm6.omqOjr8Sl0u
494	user494	$2a$06$AacsDfAYlbhOsFF/KY2uguQg5c4tcKBzvQFtiy1VBhEQQX65.v/mW
495	user495	$2a$06$jl3qTHPzCbbUpjBUgbFIYOaHoYiynCGSo8KOdPltC6FbJqoIZjfcq
496	user496	$2a$06$42Gem9i9q3iuVTTYUCbTHOwhc7IAv86JEf5tMEPpRlXCUQDKh9gTO
497	user497	$2a$06$K.PSNx/01GgtlCEyPBP3Ju3lMGx5Lh4gzfipYY/jCcNkjILiHSR5u
498	user498	$2a$06$9dX981wbqcg1sXJtpdlUw.vzC8RT6mKMgvghqVPi4LYFXYb3OyCEK
499	user499	$2a$06$SLGZJSkEiyfettxtvZBRbOe5A0m0m8TxpbfxPv114dSBvRb5u2DYq
500	user500	$2a$06$7ukZBMCuna2UpPnZmQayZO16c.2m1vlqhSHALbioNqgtfpnJKqNrO
\.


--
-- Data for Name: administrators; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.administrators (user_id, office_id) FROM stdin;
351	236
12	235
\.


--
-- Data for Name: birth_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.birth_certificates (id, father, mother, person, issuer, country_of_birth, city_of_birth, issue_date) FROM stdin;
\.


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.cities (id, country, city) FROM stdin;
0	Poland	Kraków
8501	Poland	Bartoszyce
8502	Poland	Bemowo
8503	Poland	Bielany
8504	Poland	Bielawa
8505	Poland	Bochnia
8506	Poland	Bogatynia
8507	Poland	Braniewo
8508	Poland	Brodnica
8509	Poland	Brzeg
8510	Poland	Brzesko
8511	Poland	Bydgoszcz
8512	Poland	Bytom
8513	Poland	Chojnice
8514	Poland	Choszczno
8515	Poland	Cieszyn
8516	Poland	Fordon
8517	Poland	Garwolin
8518	Poland	Gdynia
8519	Poland	Gliwice
8520	Poland	Gniezno
8521	Poland	Gorlice
8522	Poland	Gostynin
8523	Poland	Grajewo
8524	Poland	Gryfice
8525	Poland	Gryfino
8526	Poland	Gubin
8527	Poland	Jarocin
8528	Poland	Jawor
8529	Poland	Jaworzno
8530	Poland	Jelcz
8531	Poland	Kabaty
8532	Poland	Kalisz
8533	Poland	Kartuzy
8534	Poland	Katowice
8535	Poland	Kielce
8536	Poland	Kluczbork
8537	Poland	Konin
8538	Poland	Koszalin
8539	Poland	Kozienice
8540	Poland	Krapkowice
8541	Poland	Krasnystaw
8542	Poland	Krosno
8543	Poland	Krotoszyn
8544	Poland	Kutno
8545	Poland	Kwidzyn
8546	Poland	Legionowo
8547	Poland	Legnica
8548	Poland	Leszno
8549	Poland	Lubin
8550	Poland	Lublin
8551	Poland	Lubliniec
8552	Poland	Malbork
8553	Poland	Marki
8554	Poland	Mielec
8555	Poland	Nisko
8556	Poland	Nowogard
8557	Poland	Nysa
8558	Poland	Oborniki
8559	Poland	Ochota
8560	Poland	Olecko
8561	Poland	Olkusz
8562	Poland	Olsztyn
8563	Poland	Opoczno
8564	Poland	Opole
8565	Poland	Orzesze
8566	Poland	Otwock
8567	Poland	Pabianice
8568	Poland	Piaseczno
8569	Poland	Pionki
8570	Poland	Pisz
8571	Poland	Pleszew
8572	Poland	Police
8573	Poland	Polkowice
8574	Poland	Prudnik
8575	Poland	Przasnysz
8576	Poland	Przeworsk
8577	Poland	Pszczyna
8578	Poland	Pyskowice
8579	Poland	Radlin
8580	Poland	Radom
8581	Poland	Radomsko
8582	Poland	Rawicz
8583	Poland	Reda
8584	Poland	Ropczyce
8585	Poland	Rumia
8586	Poland	Rybnik
8587	Poland	Rypin
8588	Poland	Sandomierz
8589	Poland	Sanok
8590	Poland	Siedlce
8591	Poland	Siemiatycze
8592	Poland	Sieradz
8593	Poland	Sierpc
8594	Poland	Skawina
8595	Poland	Skierniewice
8596	Poland	Sochaczew
8597	Poland	Sopot
8598	Poland	Sosnowiec
8599	Poland	Starachowice
8600	Poland	Strzegom
8601	Poland	Szczecin
8602	Poland	Szczecinek
8603	Poland	Szczytno
8604	Poland	Tarnobrzeg
8605	Poland	Tczew
8606	Poland	Trzcianka
8607	Poland	Trzebinia
8608	Poland	Turek
8609	Poland	Tychy
8610	Poland	Ursus
8611	Poland	Ustka
8612	Poland	Wadowice
8613	Poland	Warsaw
8614	Poland	Wawer
8615	Poland	Wejherowo
8616	Poland	Wieliczka
8617	Poland	Wola
8618	Poland	Zabrze
8619	Poland	Zakopane
8620	Poland	Zawiercie
8621	Poland	Zgierz
8622	Poland	Zgorzelec
8623	Poland	Zielonka
\.


--
-- Data for Name: countries; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.countries (country, id) FROM stdin;
Poland	0
\.


--
-- Data for Name: death_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.death_certificates (id, issuer, person, issue_date) FROM stdin;
\.


--
-- Data for Name: divorce_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorce_certificates (id, divorce_id, issue_date, issuer) FROM stdin;
\.


--
-- Data for Name: divorces; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorces (id, marriage_id, divorce_date) FROM stdin;
\.


--
-- Data for Name: drivers_licences; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.drivers_licences (id, type, person, issuer, issue_date, expiration_date) FROM stdin;
\.


--
-- Data for Name: educational_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_certificates (id, issuer, holder, issue_date, kind) FROM stdin;
1	1	1	2025-01-01	1
2	1	0	2025-01-01	1
3	1	0	2025-01-01	1
4	1	0	2025-01-01	1
5	1	0	2025-01-01	1
\.


--
-- Data for Name: educational_certificetes_types; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_certificetes_types (kind, prerequirement) FROM stdin;
1	\N
2	1
3	2
4	3
5	4
\.


--
-- Data for Name: educational_instances; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_instances (id, name, address, creation_date, kind, country, city) FROM stdin;
1	Jagiellonian University	Gołębia 24, 31-007 Kraków	1364-05-12	1	Poland	Kraków
\.


--
-- Data for Name: educational_instances_types; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_instances_types (kind, educational_level) FROM stdin;
1	university
2	school
\.


--
-- Data for Name: international_passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.international_passports (id, original_name, original_surname, en_name, en_surname, issuer, issue_date, expiration_date, sex, passport_owner) FROM stdin;
0	Stolitnii	Andrii	Andrii	Stolitnii	0	2021-04-01	2024-04-01	M	0
1	Stolitnii	Andrii	Andrii	Stolitnii	0	2021-04-01	2024-04-01	M	0
\.


--
-- Data for Name: marriage_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriage_certificates (id, marriege_id, issuer, issue_date) FROM stdin;
\.


--
-- Data for Name: marriages; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriages (id, person1, person2, marriage_date) FROM stdin;
\.


--
-- Data for Name: offices; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices (id, office_type, country, address, city) FROM stdin;
0	Passport office	Poland	al. 3 Maja, 5	Kraków
235	consulat	Poland	Poland Bartoszyce	Bartoszyce
236	marriage agency	Poland	Poland Bemowo	Bemowo
\.


--
-- Data for Name: offices_kinds; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices_kinds (kind, description) FROM stdin;
\.


--
-- Data for Name: offices_kinds_relations; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices_kinds_relations (office_id, kind_id) FROM stdin;
\.


--
-- Data for Name: passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.passports (id, original_surname, original_name, en_name, en_surname, issue_date, expiration_date, sex, issuer, passport_owner) FROM stdin;
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.people (id, date_of_birth, date_of_death) FROM stdin;
0	2024-06-04	\N
1	2024-06-04	\N
2	2024-06-04	\N
3	1949-12-09	\N
4	2008-03-26	\N
5	1934-08-19	\N
6	1973-07-21	\N
7	2023-10-03	\N
8	1967-09-17	\N
9	2000-03-22	\N
10	2001-02-26	\N
11	1962-09-05	\N
12	1944-04-05	\N
13	1939-03-20	\N
14	1944-08-11	\N
15	1916-05-12	\N
16	1993-06-23	\N
17	1983-06-23	\N
18	1958-12-09	\N
19	2003-09-19	\N
20	1914-08-03	\N
21	1944-06-07	\N
22	1935-11-26	\N
23	1951-10-25	\N
24	2015-10-19	\N
25	1935-11-13	\N
26	1948-11-22	\N
27	1915-07-12	\N
28	1937-06-23	\N
29	2019-11-16	\N
30	2008-01-23	\N
31	1917-07-02	\N
32	2022-02-27	\N
33	1914-01-23	\N
34	1961-12-02	\N
35	1965-01-25	\N
36	1996-09-13	\N
37	1918-01-07	\N
38	1970-01-05	\N
39	2020-01-04	\N
40	2006-07-15	\N
41	1970-05-22	\N
42	2010-02-12	\N
43	2012-11-27	\N
44	1923-09-17	\N
45	1990-01-18	\N
46	1976-12-15	\N
47	1949-09-01	\N
48	1902-02-06	\N
49	1971-06-10	\N
50	1902-10-05	\N
51	2001-06-11	\N
52	1997-03-11	\N
53	1901-08-02	\N
54	2015-07-06	\N
55	1969-11-20	\N
56	1955-03-10	\N
57	1949-12-25	\N
58	1987-06-12	\N
59	1906-04-04	\N
60	1968-03-06	\N
61	2011-04-20	\N
62	1941-10-08	\N
63	1938-01-07	\N
64	1933-03-27	\N
65	1934-03-02	\N
66	1993-10-17	\N
67	1934-10-12	\N
68	1981-05-20	\N
69	1945-01-26	\N
70	1923-10-17	\N
71	1954-06-17	\N
72	1932-11-03	\N
73	1966-02-07	\N
74	1912-07-28	\N
75	1998-09-27	\N
76	1907-12-23	\N
77	1918-11-21	\N
78	2020-09-05	\N
79	1919-05-24	\N
80	2009-09-24	\N
81	2010-03-09	\N
82	2017-06-07	\N
83	1913-05-08	\N
84	1975-02-22	\N
85	1921-11-12	\N
86	1964-11-15	\N
87	1986-05-20	\N
88	1970-04-16	\N
89	1905-03-05	\N
90	2020-10-08	\N
91	1974-06-13	\N
92	2016-08-19	\N
93	2001-11-05	\N
94	1996-03-19	\N
95	1996-12-09	\N
96	1959-06-20	\N
97	2014-09-05	\N
98	1968-06-16	\N
99	1915-11-04	\N
100	1990-12-16	\N
101	1938-07-06	\N
102	1972-11-25	\N
103	1988-07-14	\N
104	1956-02-16	\N
105	1971-02-10	\N
106	1930-05-23	\N
107	1950-08-07	\N
108	1919-05-20	\N
109	1973-08-25	\N
110	1912-09-21	\N
111	1954-10-13	\N
112	1920-07-21	\N
113	1910-04-16	\N
114	1990-05-13	\N
115	1997-02-10	\N
116	2023-10-17	\N
117	1909-11-26	\N
118	1963-11-06	\N
119	2014-01-10	\N
120	1923-07-07	\N
121	2006-04-24	\N
122	1937-02-07	\N
123	1974-07-24	\N
124	1995-07-06	\N
125	1988-12-25	\N
126	1911-08-13	\N
127	1970-09-01	\N
128	1947-10-27	\N
129	1962-11-15	\N
130	1922-12-02	\N
131	1950-08-15	\N
132	1925-05-28	\N
133	2002-12-17	\N
134	2017-02-28	\N
135	1916-01-01	\N
136	1976-07-04	\N
137	2022-06-17	\N
138	1941-08-26	\N
139	1936-12-07	\N
140	1901-03-02	\N
141	1903-03-10	\N
142	1940-02-09	\N
143	1926-01-18	\N
144	1912-09-01	\N
145	1929-06-23	\N
146	2008-01-05	\N
147	1961-09-03	\N
148	2022-03-23	\N
149	1983-05-12	\N
150	1916-02-26	\N
151	2023-01-25	\N
152	1934-03-20	\N
153	1968-04-23	\N
154	2023-02-01	\N
155	1939-05-20	\N
156	1951-04-19	\N
157	1935-06-20	\N
158	1916-02-14	\N
159	2001-03-19	\N
160	1931-08-28	\N
161	1928-02-26	\N
162	1999-01-17	\N
163	1937-01-06	\N
164	1995-10-15	\N
165	1937-06-27	\N
166	1943-12-14	\N
167	1948-03-04	\N
168	1981-02-03	\N
169	1962-04-06	\N
170	1992-06-16	\N
171	1913-02-18	\N
172	1952-08-05	\N
173	1994-06-09	\N
174	1904-09-15	\N
175	1963-02-06	\N
176	2000-04-01	\N
177	2011-12-16	\N
178	1923-02-19	\N
179	1962-12-08	\N
180	1945-10-28	\N
181	2019-06-12	\N
182	1994-10-28	\N
183	1990-11-19	\N
184	2021-02-15	\N
185	1945-04-02	\N
186	1981-06-13	\N
187	1926-02-05	\N
188	1907-11-15	\N
189	1986-04-07	\N
190	1980-02-07	\N
191	2004-07-25	\N
192	1982-08-16	\N
193	1956-10-12	\N
194	1947-11-14	\N
195	1926-04-20	\N
196	1910-04-28	\N
197	1920-02-26	\N
198	1999-09-16	\N
199	1920-06-02	\N
200	1901-03-17	\N
201	1975-03-26	\N
202	1951-07-08	\N
203	1936-12-13	\N
204	1982-01-17	\N
205	1956-12-25	\N
206	1973-10-09	\N
207	1906-08-22	\N
208	1992-03-17	\N
209	1908-09-17	\N
210	1971-04-11	\N
211	1950-11-15	\N
212	1938-08-15	\N
213	1924-06-22	\N
214	1963-06-01	\N
215	1997-02-17	\N
216	2013-10-11	\N
217	2002-02-13	\N
218	1908-12-22	\N
219	1929-07-02	\N
220	1939-11-26	\N
221	1903-11-28	\N
222	2006-04-08	\N
223	1918-02-10	\N
224	2000-02-21	\N
225	1907-05-23	\N
226	1924-07-24	\N
227	1942-01-28	\N
228	1916-05-22	\N
229	2000-09-17	\N
230	1974-01-03	\N
231	1969-12-25	\N
232	1918-11-27	\N
233	1940-09-02	\N
234	1928-06-05	\N
235	1936-11-18	\N
236	1985-11-10	\N
237	1946-06-20	\N
238	1985-03-03	\N
239	2003-04-24	\N
240	1907-08-02	\N
241	1992-08-20	\N
242	2019-09-22	\N
243	1956-01-25	\N
244	2015-05-02	\N
245	2014-12-17	\N
246	2018-06-15	\N
247	1965-07-22	\N
248	1973-09-26	\N
249	1973-08-12	\N
250	2001-09-24	\N
251	1978-09-15	\N
252	1939-04-06	\N
253	1924-08-12	\N
254	2004-08-28	\N
255	1909-09-17	\N
256	1902-07-21	\N
257	1909-09-24	\N
258	1940-05-09	\N
259	1957-12-11	\N
260	1944-06-04	\N
261	1970-04-05	\N
262	1945-12-08	\N
263	1948-09-02	\N
264	1962-10-20	\N
265	1964-12-17	\N
266	1965-02-02	\N
267	1934-02-20	\N
268	1938-06-23	\N
269	1928-11-06	\N
270	1997-02-27	\N
271	1992-01-04	\N
272	2003-08-02	\N
273	2005-02-11	\N
274	1902-03-02	\N
275	2006-07-12	\N
276	1963-08-26	\N
277	1999-09-18	\N
278	2000-04-06	\N
279	1916-07-25	\N
280	2015-10-05	\N
281	1935-11-04	\N
282	1978-05-23	\N
283	1905-04-27	\N
284	2008-05-14	\N
285	2004-04-18	\N
286	1960-04-17	\N
287	1964-09-28	\N
288	1913-05-21	\N
289	1956-06-24	\N
290	1900-12-26	\N
291	1992-04-01	\N
292	1956-08-28	\N
293	1983-09-20	\N
294	2019-11-24	\N
295	2008-06-26	\N
296	2012-01-09	\N
297	1910-03-03	\N
298	1978-04-01	\N
299	2013-12-25	\N
300	2007-03-28	\N
301	1936-12-14	\N
302	1970-05-25	\N
303	1978-02-15	\N
304	2023-11-06	\N
305	1986-04-01	\N
306	1975-07-28	\N
307	1915-03-05	\N
308	2016-06-22	\N
309	1974-01-11	\N
310	1906-02-06	\N
311	1976-02-20	\N
312	2023-01-25	\N
313	2003-12-25	\N
314	2010-08-02	\N
315	2020-03-26	\N
316	2000-05-12	\N
317	1956-10-13	\N
318	1949-04-24	\N
319	2015-07-16	\N
320	1954-07-21	\N
321	1979-10-07	\N
322	2012-09-06	\N
323	1911-04-07	\N
324	1908-09-14	\N
325	1958-06-22	\N
326	1967-12-16	\N
327	1921-04-15	\N
328	2018-02-08	\N
329	2005-03-22	\N
330	1931-02-05	\N
331	1935-07-03	\N
332	2015-07-09	\N
333	1953-11-01	\N
334	1958-10-15	\N
335	1979-02-22	\N
336	1992-09-10	\N
337	1965-03-07	\N
338	1962-08-26	\N
339	1933-11-20	\N
340	2024-03-05	\N
341	1979-10-26	\N
342	1980-08-13	\N
343	1976-01-22	\N
344	1963-05-16	\N
345	2008-09-01	\N
346	1920-06-22	\N
347	1971-11-06	\N
348	1952-12-21	\N
349	2024-02-12	\N
350	1980-12-27	\N
351	2011-07-24	\N
352	2022-12-05	\N
353	1911-11-25	\N
354	1923-05-12	\N
355	1901-05-14	\N
356	1903-09-18	\N
357	1988-11-21	\N
358	1984-01-18	\N
359	1924-01-12	\N
360	1929-04-20	\N
361	2017-04-18	\N
362	1916-07-06	\N
363	1985-02-03	\N
364	1978-11-08	\N
365	1948-10-22	\N
366	2023-01-28	\N
367	2013-07-27	\N
368	2011-01-24	\N
369	1955-11-10	\N
370	1931-12-23	\N
371	2013-03-10	\N
372	1991-05-22	\N
373	1919-03-09	\N
374	1945-08-07	\N
375	2006-06-12	\N
376	1910-07-03	\N
377	1981-01-10	\N
378	1922-05-10	\N
379	1991-05-25	\N
380	1947-11-20	\N
381	1958-10-14	\N
382	1900-06-27	\N
383	1997-12-07	\N
384	1983-08-21	\N
385	2014-04-14	\N
386	1969-02-10	\N
387	2005-12-03	\N
388	1968-03-27	\N
389	1931-01-09	\N
390	1955-12-06	\N
391	1925-12-27	\N
392	1960-06-11	\N
393	2015-02-08	\N
394	1930-12-09	\N
395	1928-01-04	\N
396	1970-11-25	\N
397	1973-04-26	\N
398	1980-07-25	\N
399	1908-09-12	\N
400	2016-08-10	\N
401	1975-06-28	\N
402	1908-03-13	\N
403	1992-10-13	\N
404	1920-01-20	\N
405	1996-09-12	\N
406	2001-03-06	\N
407	1968-04-07	\N
408	1973-11-08	\N
409	1963-02-25	\N
410	1905-04-02	\N
411	1941-04-02	\N
412	1998-05-03	\N
413	1937-07-18	\N
414	1969-05-20	\N
415	2003-05-12	\N
416	1968-05-15	\N
417	1989-04-20	\N
418	2016-12-27	\N
419	1963-12-13	\N
420	1913-05-08	\N
421	1941-12-23	\N
422	1905-01-28	\N
423	1998-11-28	\N
424	1925-08-05	\N
425	1926-01-26	\N
426	2010-12-16	\N
427	1905-02-06	\N
428	1908-07-27	\N
429	2016-11-04	\N
430	1983-08-16	\N
431	2001-09-26	\N
432	1940-01-18	\N
433	1977-02-12	\N
434	2018-05-16	\N
435	1993-05-26	\N
436	1948-01-15	\N
437	1953-07-16	\N
438	1989-04-22	\N
439	1973-12-19	\N
440	1986-11-21	\N
441	2002-02-26	\N
442	1915-07-17	\N
443	1990-03-10	\N
444	1997-04-18	\N
445	1939-06-22	\N
446	1939-02-25	\N
447	1913-12-12	\N
448	1930-08-06	\N
449	1925-09-09	\N
450	1990-05-19	\N
451	2003-03-07	\N
452	2015-07-20	\N
453	1956-12-14	\N
454	1928-05-10	\N
455	1933-01-15	\N
456	1974-06-02	\N
457	2001-08-21	\N
458	2022-12-10	\N
459	1997-05-05	\N
460	2021-09-05	\N
461	1901-05-27	\N
462	1961-07-18	\N
463	1971-05-18	\N
464	1985-03-01	\N
465	1909-06-27	\N
466	1902-04-11	\N
467	1936-08-08	\N
468	1944-02-02	\N
469	2016-08-26	\N
470	1990-02-18	\N
471	2011-09-14	\N
472	1909-08-18	\N
473	2000-03-21	\N
474	2001-09-06	\N
475	1971-03-22	\N
476	1962-06-15	\N
477	2022-02-25	\N
478	1927-05-06	\N
479	1910-01-16	\N
480	1954-10-20	\N
481	1950-10-24	\N
482	1922-01-26	\N
483	1982-10-14	\N
484	1938-08-11	\N
485	1970-11-04	\N
486	1974-08-17	\N
487	1931-01-06	\N
488	1928-06-19	\N
489	2003-06-20	\N
490	1948-02-07	\N
491	1988-09-11	\N
492	1920-02-26	\N
493	2015-12-28	\N
494	1981-05-04	\N
495	1934-07-08	\N
496	2014-08-16	\N
497	1970-01-27	\N
498	1936-11-21	\N
499	1977-04-08	\N
500	2000-12-24	\N
\.


--
-- Data for Name: pet_passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.pet_passports (id, name, pet_owner, issuer, date_of_birth, species_id) FROM stdin;
\.


--
-- Data for Name: visa_categories; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visa_categories (type, description, working_permit, residence_permit, duration, country) FROM stdin;
\.


--
-- Data for Name: visas; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visas (id, type, passport, issue_date, inner_issuer, country) FROM stdin;
\.


--
-- Name: accounts pk_accounts; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT pk_accounts PRIMARY KEY (id);


--
-- Name: administrators pk_administrators; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.administrators
    ADD CONSTRAINT pk_administrators PRIMARY KEY (user_id, office_id);


--
-- Name: pet_passports pk_animal_passports; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT pk_animal_passports PRIMARY KEY (id);


--
-- Name: birth_certificates pk_birth_certificate; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT pk_birth_certificate PRIMARY KEY (id);


--
-- Name: cities pk_cities; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT pk_cities PRIMARY KEY (id);


--
-- Name: countries pk_countries; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT pk_countries PRIMARY KEY (id);


--
-- Name: death_certificates pk_death_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.death_certificates
    ADD CONSTRAINT pk_death_certificates PRIMARY KEY (id);


--
-- Name: divorce_certificates pk_divorce_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorce_certificates
    ADD CONSTRAINT pk_divorce_certificates PRIMARY KEY (id);


--
-- Name: divorces pk_divorces; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorces
    ADD CONSTRAINT pk_divorces PRIMARY KEY (id);


--
-- Name: drivers_licences pk_drivers_licence; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.drivers_licences
    ADD CONSTRAINT pk_drivers_licence PRIMARY KEY (id);


--
-- Name: educational_certificates pk_educational_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT pk_educational_certificates PRIMARY KEY (id);


--
-- Name: educational_certificetes_types pk_educational_certificetes_types; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificetes_types
    ADD CONSTRAINT pk_educational_certificetes_types PRIMARY KEY (kind);


--
-- Name: educational_instances pk_educational_instances; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances
    ADD CONSTRAINT pk_educational_instances PRIMARY KEY (id);


--
-- Name: educational_instances_types pk_educational_instances_types; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances_types
    ADD CONSTRAINT pk_educational_instances_types PRIMARY KEY (kind);


--
-- Name: passports pk_id_cards; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.passports
    ADD CONSTRAINT pk_id_cards PRIMARY KEY (id);


--
-- Name: international_passports pk_international_passports; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT pk_international_passports PRIMARY KEY (id);


--
-- Name: marriages pk_marriage_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriages
    ADD CONSTRAINT pk_marriage_certificates PRIMARY KEY (id);


--
-- Name: marriage_certificates pk_marriage_certificates_0; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriage_certificates
    ADD CONSTRAINT pk_marriage_certificates_0 PRIMARY KEY (id);


--
-- Name: offices pk_offices; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT pk_offices PRIMARY KEY (id, country, city);


--
-- Name: offices_kinds pk_offices_kinds; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds
    ADD CONSTRAINT pk_offices_kinds PRIMARY KEY (kind);


--
-- Name: offices_kinds_relations pk_offices_kinds_relations; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT pk_offices_kinds_relations PRIMARY KEY (office_id, kind_id);


--
-- Name: people pk_users; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT pk_users PRIMARY KEY (id);


--
-- Name: visa_categories pk_visa_categories; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visa_categories
    ADD CONSTRAINT pk_visa_categories PRIMARY KEY (type, country);


--
-- Name: visas pk_visas; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT pk_visas PRIMARY KEY (id);


--
-- Name: cities unq_cities_country_city; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT unq_cities_country_city UNIQUE (country, city);


--
-- Name: countries unq_countries_country; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT unq_countries_country UNIQUE (country);


--
-- Name: divorces unq_divorces_marriage_id; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorces
    ADD CONSTRAINT unq_divorces_marriage_id UNIQUE (marriage_id);


--
-- Name: offices unq_offices_id; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT unq_offices_id UNIQUE (id);


--
-- Name: offices_kinds_relations unq_offices_kinds_relations_office_id; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT unq_offices_kinds_relations_office_id UNIQUE (office_id);


--
-- Name: divorce_certificates verify_divorce_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_certificate_date BEFORE INSERT ON public.divorce_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_certificate_date();


--
-- Name: divorces verify_divorce_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_date BEFORE INSERT ON public.divorces FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_date();


--
-- Name: divorces verify_divorce_unique; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_unique BEFORE INSERT ON public.divorces FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_unique();


--
-- Name: educational_certificates verify_educational_certificate_birth_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_birth_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_birth_date();


--
-- Name: educational_certificates verify_educational_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_date();


--
-- Name: educational_certificates verify_educational_certificate_death_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_death_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_death_date();


--
-- Name: educational_certificates verify_educational_certificate_kind; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_kind BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_kind();


--
-- Name: educational_certificates verify_educational_certificate_prerequisites; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_prerequisites BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_prerequisites();


--
-- Name: international_passports verify_international_passport_number; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_international_passport_number BEFORE INSERT ON public.international_passports FOR EACH ROW EXECUTE FUNCTION public.verify_international_passport_number();


--
-- Name: marriage_certificates verify_marriage_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_marriage_certificate_date BEFORE INSERT ON public.marriage_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_marriage_certificate_date();


--
-- Name: marriages verify_marriage_unique; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_marriage_unique BEFORE INSERT ON public.marriages FOR EACH ROW EXECUTE FUNCTION public.verify_marriage_unique();


--
-- Name: international_passports verify_passport_death_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_death_date BEFORE UPDATE ON public.international_passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_death_date();


--
-- Name: passports verify_passport_death_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_death_date BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_death_date();


--
-- Name: passports verify_passport_number; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_number BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_number();


--
-- Name: accounts fk_accounts_people; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_accounts_people FOREIGN KEY (id) REFERENCES public.people(id);


--
-- Name: administrators fk_administrators_accounts; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.administrators
    ADD CONSTRAINT fk_administrators_accounts FOREIGN KEY (user_id) REFERENCES public.accounts(id);


--
-- Name: administrators fk_administrators_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.administrators
    ADD CONSTRAINT fk_administrators_offices FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: birth_certificates fk_birth_certificate_people_father; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificate_people_father FOREIGN KEY (father) REFERENCES public.people(id);


--
-- Name: birth_certificates fk_birth_certificate_people_mother; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificate_people_mother FOREIGN KEY (mother) REFERENCES public.people(id);


--
-- Name: birth_certificates fk_birth_certificates_cities; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificates_cities FOREIGN KEY (city_of_birth, country_of_birth) REFERENCES public.cities(city, country);


--
-- Name: birth_certificates fk_birth_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: cities fk_cities_countries; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT fk_cities_countries FOREIGN KEY (country) REFERENCES public.countries(country);


--
-- Name: death_certificates fk_death_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.death_certificates
    ADD CONSTRAINT fk_death_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: death_certificates fk_death_certificates_people; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.death_certificates
    ADD CONSTRAINT fk_death_certificates_people FOREIGN KEY (person) REFERENCES public.people(id);


--
-- Name: divorce_certificates fk_divorce_certificates_marriage; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorce_certificates
    ADD CONSTRAINT fk_divorce_certificates_marriage FOREIGN KEY (divorce_id) REFERENCES public.divorces(id);


--
-- Name: divorce_certificates fk_divorce_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorce_certificates
    ADD CONSTRAINT fk_divorce_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: divorces fk_divorces_marriage; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorces
    ADD CONSTRAINT fk_divorces_marriage FOREIGN KEY (marriage_id) REFERENCES public.marriages(id);


--
-- Name: drivers_licences fk_drivers_licences_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.drivers_licences
    ADD CONSTRAINT fk_drivers_licences_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: drivers_licences fk_drivers_licences_people; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.drivers_licences
    ADD CONSTRAINT fk_drivers_licences_people FOREIGN KEY (person) REFERENCES public.people(id);


--
-- Name: educational_certificates fk_educational_certificates_holder; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_holder FOREIGN KEY (holder) REFERENCES public.people(id);


--
-- Name: educational_certificates fk_educational_certificates_issuer; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_issuer FOREIGN KEY (issuer) REFERENCES public.educational_instances(id);


--
-- Name: educational_certificates fk_educational_certificates_kind; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_kind FOREIGN KEY (kind) REFERENCES public.educational_certificetes_types(kind);


--
-- Name: educational_certificetes_types fk_educational_certificetes_types_prerequirement; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificetes_types
    ADD CONSTRAINT fk_educational_certificetes_types_prerequirement FOREIGN KEY (prerequirement) REFERENCES public.educational_certificetes_types(kind);


--
-- Name: educational_instances fk_educational_instances; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances
    ADD CONSTRAINT fk_educational_instances FOREIGN KEY (country, city) REFERENCES public.cities(country, city);


--
-- Name: educational_instances fk_educational_instances_type; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances
    ADD CONSTRAINT fk_educational_instances_type FOREIGN KEY (kind) REFERENCES public.educational_instances_types(kind);


--
-- Name: international_passports fk_international_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT fk_international_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: international_passports fk_international_passports_owner; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT fk_international_passports_owner FOREIGN KEY (passport_owner) REFERENCES public.people(id);


--
-- Name: marriage_certificates fk_marriage_certificates; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriage_certificates
    ADD CONSTRAINT fk_marriage_certificates FOREIGN KEY (marriege_id) REFERENCES public.marriages(id);


--
-- Name: marriage_certificates fk_marriage_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriage_certificates
    ADD CONSTRAINT fk_marriage_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: marriages fk_marriage_certificates_person1; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriages
    ADD CONSTRAINT fk_marriage_certificates_person1 FOREIGN KEY (person1) REFERENCES public.people(id);


--
-- Name: marriages fk_marriage_certificates_person2; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriages
    ADD CONSTRAINT fk_marriage_certificates_person2 FOREIGN KEY (person2) REFERENCES public.people(id);


--
-- Name: offices fk_offices_cities; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT fk_offices_cities FOREIGN KEY (country, city) REFERENCES public.cities(country, city);


--
-- Name: offices_kinds_relations fk_offices_kinds_relations_kind; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT fk_offices_kinds_relations_kind FOREIGN KEY (kind_id) REFERENCES public.offices_kinds(kind);


--
-- Name: offices_kinds_relations fk_offices_kinds_relations_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT fk_offices_kinds_relations_offices FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: passports fk_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.passports
    ADD CONSTRAINT fk_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: passports fk_passports_person; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.passports
    ADD CONSTRAINT fk_passports_person FOREIGN KEY (passport_owner) REFERENCES public.people(id);


--
-- Name: pet_passports fk_pet_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT fk_pet_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: pet_passports fk_pet_passports_owner; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT fk_pet_passports_owner FOREIGN KEY (pet_owner) REFERENCES public.people(id);


--
-- Name: visa_categories fk_visa_categories_countries; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visa_categories
    ADD CONSTRAINT fk_visa_categories_countries FOREIGN KEY (country) REFERENCES public.countries(country);


--
-- Name: visas fk_visas_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT fk_visas_offices FOREIGN KEY (inner_issuer) REFERENCES public.offices(id);


--
-- Name: visas fk_visas_passport; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT fk_visas_passport FOREIGN KEY (passport) REFERENCES public.international_passports(id);


--
-- Name: visas fk_visas_visa_categories; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT fk_visas_visa_categories FOREIGN KEY (type, country) REFERENCES public.visa_categories(type, country);


--
-- PostgreSQL database dump complete
--

