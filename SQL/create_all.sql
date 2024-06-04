CREATE SCHEMA IF NOT EXISTS "public";

CREATE  TABLE "public".countries ( 
	country              varchar  NOT NULL  ,
	id                   integer  NOT NULL  ,
	CONSTRAINT pk_countries PRIMARY KEY ( id ),
	CONSTRAINT unq_countries_country UNIQUE ( country ) 
 );

CREATE  TABLE "public".educational_certificetes_types ( 
	kind                 integer  NOT NULL  ,
	prerequirement       integer    ,
	CONSTRAINT pk_educational_certificetes_types PRIMARY KEY ( kind )
 );

CREATE  TABLE "public".educational_instances_types ( 
	kind                 integer  NOT NULL  ,
	educational_level    varchar  NOT NULL  ,
	CONSTRAINT pk_educational_instances_types PRIMARY KEY ( kind )
 );

CREATE  TABLE "public".offices_kinds ( 
	kind                 integer  NOT NULL  ,
	description          varchar(100)  NOT NULL  ,
	CONSTRAINT pk_offices_kinds PRIMARY KEY ( kind )
 );

CREATE  TABLE "public".people ( 
	id                   bigint  NOT NULL  ,
	date_of_birth        date DEFAULT CURRENT_DATE NOT NULL  ,
	date_of_death        date    ,
	CONSTRAINT pk_users PRIMARY KEY ( id )
 );

CREATE  TABLE "public".visa_categories ( 
	"type"               integer  NOT NULL  ,
	description          varchar(100)    ,
	working_permit       boolean  NOT NULL  ,
	residence_permit     boolean  NOT NULL  ,
	duration             interval  NOT NULL ,
	country              varchar  NOT NULL  ,
	CONSTRAINT pk_visa_categories PRIMARY KEY ( "type", country )
 );

CREATE  TABLE "public".accounts ( 
	id                   bigint  NOT NULL  ,
	login                varchar  NOT NULL  ,
	hashed_password      varchar(200)  NOT NULL  ,
	CONSTRAINT pk_accounts PRIMARY KEY ( id )
 );

CREATE  TABLE "public".cities ( 
	id                   integer  NOT NULL  ,
	country              varchar(100)  NOT NULL  ,
	city                 varchar(100)  NOT NULL  ,
	CONSTRAINT pk_cities PRIMARY KEY ( id ),
	CONSTRAINT unq_cities_country_city UNIQUE ( country, city ) 
 );

CREATE  TABLE "public".educational_instances ( 
	id                   integer  NOT NULL  ,
	name                 varchar(100)  NOT NULL  ,
	address              varchar(200)  NOT NULL  ,
	creation_date        date  NOT NULL  ,
	kind                 integer  NOT NULL  ,
	country              varchar  NOT NULL  ,
	city                 varchar  NOT NULL  ,
	CONSTRAINT pk_educational_instances PRIMARY KEY ( id )
 );

CREATE  TABLE "public".marriages ( 
	id                   bigint  NOT NULL  ,
	person1              bigint  NOT NULL  ,
	person2              bigint  NOT NULL  ,
	marriage_date        date  NOT NULL  ,
	CONSTRAINT pk_marriage_certificates PRIMARY KEY ( id )
 );

ALTER TABLE "public".marriages ADD CONSTRAINT cns_marriage_certificates_different_people CHECK ( (person1 <> person2) );

CREATE  TABLE "public".offices ( 
	id                   integer  NOT NULL  ,
	office_type          varchar  NOT NULL  ,
	country              varchar  NOT NULL  ,
	address              varchar(200)  NOT NULL  ,
	city                 varchar  NOT NULL  ,
	CONSTRAINT unq_offices_id UNIQUE ( id ) ,
	CONSTRAINT pk_offices PRIMARY KEY ( id, country, city )
 );

CREATE  TABLE "public".offices_kinds_relations ( 
	office_id            integer  NOT NULL  ,
	kind_id              integer  NOT NULL  ,
	CONSTRAINT pk_offices_kinds_relations PRIMARY KEY ( office_id, kind_id ),
	CONSTRAINT unq_offices_kinds_relations_office_id UNIQUE ( office_id ) 
 );

CREATE  TABLE "public".passports ( 
	id                   bigint  NOT NULL  ,
	original_surname     varchar(100)  NOT NULL  ,
	original_name        varchar(100)  NOT NULL  ,
	en_name              varchar(100)  NOT NULL  ,
	en_surname           varchar(100)  NOT NULL  ,
	issue_date           date DEFAULT CURRENT_DATE NOT NULL  ,
	expiration_date      date  NOT NULL  ,
	sex                  char(1)  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	passport_owner       bigint  NOT NULL  ,
	CONSTRAINT pk_id_cards PRIMARY KEY ( id )
 );

ALTER TABLE "public".passports ADD CONSTRAINT cns_passports_sex CHECK ( (sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])) );

ALTER TABLE "public".passports ADD CONSTRAINT cns_passports_issue_expiry CHECK ( (issue_date < expiration_date) );

CREATE  TABLE "public".pet_passports ( 
	id                   integer  NOT NULL  ,
	name                 varchar(100)  NOT NULL  ,
	pet_owner            bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	date_of_birth        date  NOT NULL  ,
	species_id           integer    ,
	CONSTRAINT pk_animal_passports PRIMARY KEY ( id )
 );

CREATE  TABLE "public".administrators ( 
	user_id              bigint  NOT NULL  ,
	office_id            integer  NOT NULL  ,
	CONSTRAINT pk_administrators PRIMARY KEY ( user_id, office_id )
 );

CREATE  TABLE "public".birth_certificates ( 
	id                   bigint  NOT NULL  ,
	father               bigint    ,
	mother               bigint    ,
	person               bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	country_of_birth     varchar(100)    ,
	city_of_birth        varchar(100)    ,
	issue_date           date    ,
	CONSTRAINT pk_birth_certificate PRIMARY KEY ( id )
 );

CREATE  TABLE "public".death_certificates ( 
	id                   bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	person               bigint  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	CONSTRAINT pk_death_certificates PRIMARY KEY ( id )
 );

CREATE  TABLE "public".divorces ( 
	id                   integer  NOT NULL  ,
	marriage_id          integer  NOT NULL  ,
	divorce_date         date  NOT NULL  ,
	CONSTRAINT pk_divorces PRIMARY KEY ( id ),
	CONSTRAINT unq_divorces_marriage_id UNIQUE ( marriage_id ) 
 );

CREATE  TABLE "public".drivers_licences ( 
	id                   bigint  NOT NULL  ,
	"type"               integer  NOT NULL  ,
	person               bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	expiration_date      date  NOT NULL  ,
	CONSTRAINT pk_drivers_licence PRIMARY KEY ( id )
 );

CREATE  TABLE "public".educational_certificates ( 
	id                   bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	holder               integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	kind                 integer  NOT NULL  ,
	CONSTRAINT pk_educational_certificates PRIMARY KEY ( id )
 );

CREATE  TABLE "public".international_passports ( 
	id                   bigint  NOT NULL  ,
	original_name        varchar(100)  NOT NULL  ,
	original_surname     varchar(100)  NOT NULL  ,
	en_name              varchar(100)  NOT NULL  ,
	en_surname           varchar(100)  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	issue_date           date DEFAULT CURRENT_DATE NOT NULL  ,
	expiration_date      date  NOT NULL  ,
	sex                  char(1)  NOT NULL  ,
	passport_owner       bigint  NOT NULL  ,
	CONSTRAINT pk_international_passports PRIMARY KEY ( id )
 );

ALTER TABLE "public".international_passports ADD CONSTRAINT cns_international_passports_sex CHECK ( (sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])) );

CREATE  TABLE "public".marriage_certificates ( 
	id                   integer  NOT NULL  ,
	marriege_id          integer  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	CONSTRAINT pk_marriage_certificates_0 PRIMARY KEY ( id )
 );

CREATE  TABLE "public".visas ( 
	id                   integer  NOT NULL  ,
	"type"               integer  NOT NULL  ,
	passport             integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	inner_issuer         integer  NOT NULL  ,
	country              varchar  NOT NULL  ,
	CONSTRAINT pk_visas PRIMARY KEY ( id )
 );

CREATE  TABLE "public".divorce_certificates ( 
	id                   integer  NOT NULL  ,
	divorce_id           integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	CONSTRAINT pk_divorce_certificates PRIMARY KEY ( id )
 );

ALTER TABLE "public".accounts ADD CONSTRAINT fk_accounts_people FOREIGN KEY ( id ) REFERENCES "public".people( id );

ALTER TABLE "public".administrators ADD CONSTRAINT fk_administrators_accounts FOREIGN KEY ( user_id ) REFERENCES "public".accounts( id );

ALTER TABLE "public".administrators ADD CONSTRAINT fk_administrators_offices FOREIGN KEY ( office_id ) REFERENCES "public".offices( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificate_people_mother FOREIGN KEY ( mother ) REFERENCES "public".people( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificate_people_father FOREIGN KEY ( father ) REFERENCES "public".people( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificates_cities FOREIGN KEY ( city_of_birth, country_of_birth ) REFERENCES "public".cities( city, country );

ALTER TABLE "public".cities ADD CONSTRAINT fk_cities_countries FOREIGN KEY ( country ) REFERENCES "public".countries( country );

ALTER TABLE "public".death_certificates ADD CONSTRAINT fk_death_certificates_people FOREIGN KEY ( person ) REFERENCES "public".people( id );

ALTER TABLE "public".death_certificates ADD CONSTRAINT fk_death_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".divorce_certificates ADD CONSTRAINT fk_divorce_certificates_marriage FOREIGN KEY ( divorce_id ) REFERENCES "public".divorces( id );

ALTER TABLE "public".divorce_certificates ADD CONSTRAINT fk_divorce_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".divorces ADD CONSTRAINT fk_divorces_marriage FOREIGN KEY ( marriage_id ) REFERENCES "public".marriages( id );

ALTER TABLE "public".drivers_licences ADD CONSTRAINT fk_drivers_licences_people FOREIGN KEY ( person ) REFERENCES "public".people( id );

ALTER TABLE "public".drivers_licences ADD CONSTRAINT fk_drivers_licences_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".educational_certificates ADD CONSTRAINT fk_educational_certificates_issuer FOREIGN KEY ( issuer ) REFERENCES "public".educational_instances( id );

ALTER TABLE "public".educational_certificates ADD CONSTRAINT fk_educational_certificates_holder FOREIGN KEY ( holder ) REFERENCES "public".people( id );

ALTER TABLE "public".educational_certificates ADD CONSTRAINT fk_educational_certificates_kind FOREIGN KEY ( kind ) REFERENCES "public".educational_certificetes_types( kind );

ALTER TABLE "public".educational_certificetes_types ADD CONSTRAINT fk_educational_certificetes_types_prerequirement FOREIGN KEY ( prerequirement ) REFERENCES "public".educational_certificetes_types( kind );

ALTER TABLE "public".educational_instances ADD CONSTRAINT fk_educational_instances_type FOREIGN KEY ( kind ) REFERENCES "public".educational_instances_types( kind );

ALTER TABLE "public".educational_instances ADD CONSTRAINT fk_educational_instances FOREIGN KEY ( country, city ) REFERENCES "public".cities( country, city );

ALTER TABLE "public".international_passports ADD CONSTRAINT fk_international_passports_owner FOREIGN KEY ( passport_owner ) REFERENCES "public".people( id );

ALTER TABLE "public".international_passports ADD CONSTRAINT fk_international_passports_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".marriage_certificates ADD CONSTRAINT fk_marriage_certificates FOREIGN KEY ( marriege_id ) REFERENCES "public".marriages( id );

ALTER TABLE "public".marriage_certificates ADD CONSTRAINT fk_marriage_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".marriages ADD CONSTRAINT fk_marriage_certificates_person2 FOREIGN KEY ( person2 ) REFERENCES "public".people( id );

ALTER TABLE "public".marriages ADD CONSTRAINT fk_marriage_certificates_person1 FOREIGN KEY ( person1 ) REFERENCES "public".people( id );

ALTER TABLE "public".offices ADD CONSTRAINT fk_offices_cities FOREIGN KEY ( country, city ) REFERENCES "public".cities( country, city );

ALTER TABLE "public".offices_kinds_relations ADD CONSTRAINT fk_offices_kinds_relations_kind FOREIGN KEY ( kind_id ) REFERENCES "public".offices_kinds( kind );

ALTER TABLE "public".offices_kinds_relations ADD CONSTRAINT fk_offices_kinds_relations_offices FOREIGN KEY ( office_id ) REFERENCES "public".offices( id );

ALTER TABLE "public".passports ADD CONSTRAINT fk_passports_person FOREIGN KEY ( passport_owner ) REFERENCES "public".people( id );

ALTER TABLE "public".passports ADD CONSTRAINT fk_passports_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".pet_passports ADD CONSTRAINT fk_pet_passports_owner FOREIGN KEY ( pet_owner ) REFERENCES "public".people( id );

ALTER TABLE "public".pet_passports ADD CONSTRAINT fk_pet_passports_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".visa_categories ADD CONSTRAINT fk_visa_categories_countries FOREIGN KEY ( country ) REFERENCES "public".countries( country );

ALTER TABLE "public".visas ADD CONSTRAINT fk_visas_passport FOREIGN KEY ( passport ) REFERENCES "public".international_passports( id );

ALTER TABLE "public".visas ADD CONSTRAINT fk_visas_offices FOREIGN KEY ( inner_issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".visas ADD CONSTRAINT fk_visas_visa_categories FOREIGN KEY ( "type", country ) REFERENCES "public".visa_categories( "type", country );
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Function definitions

-- Function used to create new user with given login, email and password. On success returns user id, otherwise raises exception
CREATE OR REPLACE FUNCTION add_user(
    p_id bigint,
    p_login VARCHAR,
    p_password VARCHAR
) RETURNS INTEGER AS $$
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
$$ LANGUAGE plpgsql;

-- Function used to log in user with given login and password. On success returns user id, otherwise returns NULL
CREATE OR REPLACE FUNCTION login(
    p_login VARCHAR(255),
    p_password VARCHAR(255)
) RETURNS INTEGER AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id INTO v_user_id
    FROM accounts
    WHERE login = p_login
    AND hashed_password = crypt(p_password, hashed_password);
    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function that returns list of offices the given id is administrator at
CREATE OR REPLACE FUNCTION get_administrated_offices(
    p_administrator_id INTEGER
) RETURNS TABLE (
    id INTEGER,
    office_type VARCHAR,
    country VARCHAR,
    city VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT offices.id, offices.office_type, offices.country, office.city
    FROM offices
    JOIN administrators ON offices.id = administrators.office_id
    WHERE administrators.user_id = p_administrator_id;
END;
$$ LANGUAGE plpgsql;

-- TRIGGERS

-- Trigger used to verify that there does not exists a divorce for this marriage
CREATE OR REPLACE FUNCTION verify_divorce_unique()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_unique BEFORE INSERT ON divorces
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_unique();


-- Trigger used to verify that there does not exists an active marriage between two people
CREATE OR REPLACE FUNCTION verify_marriage_unique()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_marriage_unique BEFORE INSERT ON marriages
    FOR EACH ROW EXECUTE FUNCTION verify_marriage_unique();

-- Trigger used to verify that divorce date is after marriage date
CREATE OR REPLACE FUNCTION verify_divorce_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_date BEFORE INSERT ON divorces
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_date();

-- Trigger used to verify that marriage certificate date is after marriage date
CREATE OR REPLACE FUNCTION verify_marriage_certificate_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_marriage_certificate_date BEFORE INSERT ON marriage_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_marriage_certificate_date();

-- Trigger used to verify that divorce certificate date is after divorce date
CREATE OR REPLACE FUNCTION verify_divorce_certificate_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_certificate_date BEFORE INSERT ON divorce_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_certificate_date();

-- EDUCATIONAL CERTIFICATES

-- Trigger used to verify that educational certificate date is after educational instance creation date
CREATE OR REPLACE FUNCTION verify_educational_certificate_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_date BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_date();


-- Trigger used to check whether all prerequisites for educational certificate are met
CREATE OR REPLACE FUNCTION verify_educational_certificate_prerequisites()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_prerequisites BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_prerequisites();

-- Trigger used to check whether certificate was issued before the holder was born
CREATE OR REPLACE FUNCTION verify_educational_certificate_birth_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_birth_date BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_birth_date();

-- Trigger used to ensure that educational certificate is not issued to a dead person
CREATE OR REPLACE FUNCTION verify_educational_certificate_death_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_death_date BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_death_date();

-- Trigger used to ensure that educational certificate kind was issued by the educational instance of the same kind
CREATE OR REPLACE FUNCTION verify_educational_certificate_kind()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_kind BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_kind();

-- PASSPORTS

-- Trigger used to ensure that passport is not issued to a dead person
CREATE OR REPLACE FUNCTION verify_passport_death_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_passport_death_date BEFORE INSERT ON passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_death_date();

CREATE TRIGGER verify_passport_death_date BEFORE UPDATE ON international_passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_death_date();

-- Trigger used to ensure that passport is not issued to a person with more than 1 active passport
CREATE OR REPLACE FUNCTION verify_passport_number()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_passport_number BEFORE INSERT ON passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_number();


-- Trigger used to ensure that passport is not issued to a person with more than 2 active international passports
CREATE OR REPLACE FUNCTION verify_international_passport_number()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_international_passport_number BEFORE INSERT ON international_passports
    FOR EACH ROW EXECUTE FUNCTION verify_international_passport_number();

-- VISAS

-- Trigger to ensure that visa is not issued to expired passport
CREATE OR REPLACE FUNCTION verify_visa_passport_expiration_date()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;