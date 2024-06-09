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
