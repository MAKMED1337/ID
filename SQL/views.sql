
-- View for educational certificates

CREATE VIEW educational_certificates_view AS
SELECT
    id,
    (
        SELECT name FROM educational_certificates_types WHERE id = edu_cert.kind
    ) AS "Level of education",
    (
        SELECT name FROM educational_instances WHERE id = edu_cert.issuer
    ) AS "Issuer instance",
    issue_date AS "Date of issue"
FROM educational_certificates edu_cert ORDER BY issue_date DESC;