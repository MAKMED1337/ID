
-- View for educational certificates

CREATE VIEW educational_certificates_view AS
SELECT
    id,
    (
        SELECT name FROM educational_certificates_types WHERE id = type
    ) AS "Level of education",
    (
        SELECT name FROM educational_instances WHERE id = issuer
    ) AS "Issuer instance",
    issue_date AS "Date of issue"
FROM educational_certificates;