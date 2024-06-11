CREATE OR REPLACE VIEW educational_certificates_view AS
SELECT
    id,
    holder,
    (
        SELECT name FROM educational_certificates_types WHERE id = edu_cert.kind
    ) AS level_of_education,
    (
        SELECT name FROM educational_instances WHERE id = edu_cert.issuer
    ) AS issuer_instance,
    issue_date AS date_of_issue
FROM educational_certificates edu_cert ORDER BY issue_date DESC;


CREATE OR REPLACE VIEW marriage_certificates_view AS
SELECT
    id,
    marriage_id,
    (
        SELECT person1 FROM marriages WHERE id = mar_cert.marriage_id
    ) AS first_person,
    (
        SELECT person2 FROM marriages WHERE id = mar_cert.marriage_id
    ) AS second_person,
    (
        SELECT marriage_date FROM marriages WHERE id = mar_cert.marriage_id
    ),
    issuer,
    issue_date
FROM public.marriage_certificates AS mar_cert ORDER BY issue_date DESC;


CREATE OR REPLACE VIEW divorce_certificates_view AS
SELECT
    id,
    divorce_id,
    (
        SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
    ),
    (
        SELECT person1 FROM marriages WHERE id = (
            SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
        )
    ) AS first_person,
    (
        SELECT person2 FROM marriages WHERE id = (
            SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
        )
    ) AS second_person,
    (
        SELECT marriage_date FROM marriages WHERE id = (
            SELECT marriage_id FROM divorces WHERE id = div_cert.divorce_id
        )
    ),
    (
        SELECT divorce_date FROM divorces WHERE id = div_cert.divorce_id
    ),
    issue_date,
    issuer
FROM divorce_certificates div_cert ORDER BY issue_date DESC;

-- view for birth certificates
CREATE OR REPLACE VIEW birth_certificates_view AS
SELECT
    id,
    person_id,
    (
        SELECT name FROM people WHERE id = birth_cert.person_id
    ) AS person_name,
    (
        SELECT birth_date FROM people WHERE id = birth_cert.person_id
    ) AS birth_date,
    (
        SELECT birth_place FROM people WHERE id = birth_cert.person_id
    ) AS birth_place,
    (
        SELECT father FROM people WHERE id = birth_cert.person_id
    ) AS father,
    (
        SELECT mother FROM people WHERE id = birth_cert.person_id
    ) AS mother,
    (
        SELECT birth_date FROM birth_certificates  WHERE id = birth_cert.id
    ) AS date_of_issue
FROM birth_certificates birth_cert ORDER BY date_of_issue DESC;

-- view for death certificates
CREATE OR REPLACE VIEW death_certificates_view AS
SELECT
    id,
    person_id,
    (
        SELECT name FROM people WHERE id = death_cert.person_id
    ) AS person_name,
    (
        SELECT death_date FROM people WHERE id = death_cert.person_id
    ) AS death_date,
    (
        SELECT death_place FROM people WHERE id = death_cert.person_id
    ) AS death_place,
    (
        SELECT father FROM people WHERE id = death_cert.person_id
    ) AS father,
    (
        SELECT mother FROM people WHERE id = death_cert.person_id
    ) AS mother,
    (
        SELECT death_date FROM death_certificates  WHERE id = death_cert.id
    ) AS date_of_issue
FROM death_certificates death_cert ORDER BY date_of_issue DESC;

-- view for drivers licences
CREATE OR REPLACE VIEW drivers_licences_view AS
SELECT
    id,
    person_id,
    (
        SELECT name FROM people WHERE id = drivers_licence.person_id
    ) AS person_name,
    (
        SELECT birth_date FROM people WHERE id = drivers_licence.person_id
    ) AS birth_date,
    (
        SELECT birth_place FROM people WHERE id = drivers_licence.person_id
    ) AS birth_place,
    (
        SELECT father FROM people WHERE id = drivers_licence.person_id
    ) AS father,
    (
        SELECT mother FROM people WHERE id = drivers_licence.person_id
    ) AS mother,
    (
        SELECT issue_date FROM drivers_licences WHERE id = drivers_licence.id
    ) AS date_of_issue,
    (
        SELECT expiration_date FROM drivers_licences WHERE id = drivers_licence.id
    ) AS expiration_date
FROM drivers_licences drivers_licence ORDER BY date_of_issue DESC;