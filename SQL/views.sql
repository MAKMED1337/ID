DROP VIEW IF EXISTS educational_certificates_view;

CREATE OR REPLACE VIEW educational_certificates_view AS
SELECT
    id,
    holder,
    (
        SELECT name FROM educational_certificates_types WHERE id = edu_cert.kind
    ) AS "Level of Education",
    (
        SELECT name FROM educational_instances WHERE id = edu_cert.issuer
    ) AS "Issuer Instance",
    issue_date AS "Date of Issue"
FROM educational_certificates edu_cert ORDER BY "Date of Issue" DESC;

DROP VIEW IF EXISTS marriage_certificates_view;

CREATE OR REPLACE VIEW marriage_certificates_view AS
SELECT
    id AS "ID",
    marriage_id AS "Marriage ID",
    (
        SELECT person1 FROM marriages WHERE id = mar_cert.marriage_id
    ) AS "First Person",
    (
        SELECT person2 FROM marriages WHERE id = mar_cert.marriage_id
    ) AS "Second Person",
    (
        SELECT marriage_date FROM marriages WHERE id = mar_cert.marriage_id
    ) AS "Date of Marriage",
    issuer AS "Issuer",
    issue_date AS "Date of Issue"
FROM public.marriage_certificates AS mar_cert ORDER BY issue_date DESC;

CREATE OR REPLACE VIEW divorce_certificates_view AS
SELECT
    id AS "ID",
    divorce_id AS "Divorce ID",
    (
        SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
    ) AS "Marriage ID",
    (
        SELECT person1 FROM marriages WHERE id = (
            SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
        )
    ) AS "First Person",
    (
        SELECT person2 FROM marriages WHERE id = (
            SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
        )
    ) AS "Second Person",
    (
        SELECT marriage_date FROM marriages WHERE id = (
            SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
        )
    ) AS "Date of Marriage",
    (
        SELECT divorce_date FROM divorces WHERE id = div_cert.divorce_id
    ),
    issue_date AS "Date of Issue",
    issuer AS "Issuer"
FROM divorce_certificates div_cert ORDER BY issue_date DESC;

-- view for birth certificates
CREATE OR REPLACE VIEW birth_certificates_view AS
SELECT
    id,
    person,
    (
        SELECT name FROM people WHERE id = birth_cert.person
    ) AS "Person's Name",
    (
        SELECT date_of_birth FROM people WHERE id = birth_cert.person
    ) AS "Date of Birth",
    city_of_birth AS "City of Birth",
    country_of_birth AS "Country of Birth",
    (
        SELECT father FROM people WHERE id = birth_cert.person
    ) AS "Father's Name",
    (
        SELECT mother FROM people WHERE id = birth_cert.person
    ) AS "Mother's Name",
    (
        SELECT issue_date FROM birth_certificates WHERE id = birth_cert.id
    ) AS "Date of Issue"
FROM birth_certificates birth_cert ORDER BY 6 DESC;

-- view for death certificates
CREATE OR REPLACE VIEW death_certificates_view AS
SELECT
    id AS "ID",
    person AS "Person ID",
    (
        SELECT name FROM people WHERE id = death_cert.person
    ) AS "Name",
    (
        SELECT surname FROM people WHERE id = death_cert.person
    ) AS "Surname",
    (
        SELECT date_of_death FROM people WHERE id = death_cert.person
    ) AS "Date of Death",
    issue_date AS "Date of Issue"
FROM death_certificates death_cert ORDER BY 6 DESC;

-- view for drivers licences
CREATE OR REPLACE VIEW drivers_licences_view AS
SELECT
    id AS "ID",
    person AS "Person ID",
    (
        SELECT name FROM people WHERE id = drivers_licence.person
    ) AS "Name",
    (
        SELECT surname FROM people WHERE id = drivers_licence.person
    ) AS "Surname",
    (
        SELECT date_of_birth FROM people WHERE id = drivers_licence.person
    ) AS "Date of Birth",
    issue_date AS "Date of Issue",
    expiration_date AS "Expiration Date"
FROM drivers_licences drivers_licence ORDER BY "Date of Issue" DESC;

CREATE OR REPLACE VIEW visa_view AS
SELECT
    id AS "ID",
    (
        SELECT series || id FROM international_passports WHERE id = visa.passport
    ) AS "Passport ID",
    (
        SELECT description FROM visa_categories WHERE id = visa.type
    ) AS "Visa Category",
    issue_date AS "Date of Issue",
    issue_date + (
        SELECT duration FROM visa_categories WHERE type = visa.type
    ) AS "Expiration Date"
FROM visas visa ORDER BY "Date of Issue" DESC;

CREATE OR REPLACE RULE insert_birth_certificates AS
    ON INSERT TO birth_certificates_view
    DO INSTEAD INSERT INTO birth_certificates (person, city_of_birth, country_of_birth, issue_date) VALUES (NEW.person, NEW."City of Birth", NEW."Country of Birth", NOW());

CREATE OR REPLACE RULE insert_death_certificates AS
    ON INSERT TO death_certificates_view
    DO INSTEAD INSERT INTO death_certificates (person, issue_date) VALUES (NEW."Person ID", NOW());

CREATE OR REPLACE RULE insert_drivers_licences AS
    ON INSERT TO drivers_licences_view
    DO INSTEAD INSERT INTO drivers_licences (person, issue_date, expiration_date) VALUES (NEW."Person ID", NOW(), NEW."Expiration Date");

CREATE OR REPLACE RULE insert_educational_certificates AS
    ON INSERT TO educational_certificates_view
    DO INSTEAD 
    INSERT INTO educational_certificates (holder, kind, issuer, issue_date)
    VALUES (
        NEW.holder, 
        (SELECT id FROM educational_certificates_types WHERE name = NEW."Level of Education"), 
        (SELECT id FROM educational_instances WHERE name = NEW."Issuer Instance"), 
        NOW()
    );

CREATE OR REPLACE RULE insert_marriage_certificates AS
    ON INSERT TO marriage_certificates_view
    DO INSTEAD INSERT INTO marriage_certificates (marriage_id, issuer, issue_date) VALUES ((SELECT id FROM marriages WHERE person1 = NEW."First Person" AND person2 = NEW."Second Person"), NEW."Issuer", NOW());

CREATE OR REPLACE RULE insert_divorce_certificates AS
    ON INSERT TO divorce_certificates_view
    DO INSTEAD INSERT INTO divorce_certificates (divorce_id, issuer, issue_date) VALUES ((SELECT id FROM divorces WHERE marriage_id = NEW."Marriage ID"), NEW."Issuer", NOW());

CREATE OR REPLACE RULE insert_visa AS
    ON INSERT TO visa_view
    DO INSTEAD INSERT INTO visas (passport, type, issue_date) VALUES ((SELECT id FROM international_passports WHERE id = RIGHT(NEW."Passport ID",-2)::bigint), (SELECT type FROM visa_categories WHERE description = NEW."Visa Category"), NOW());