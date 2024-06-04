-- INSERT INTO educational_certificetes_types (kind, prerequirement, description) VALUES (1, $$Associate Degree$$);
-- INSERT INTO educational_certificetes_types (kind, prerequirement, description) VALUES (2, $$Bachelor Degree$$);
-- INSERT INTO educational_certificetes_types (kind, prerequirement, description) VALUES (3, $$Postgraduate Diploma$$);
-- INSERT INTO educational_certificetes_types (kind, prerequirement, description) VALUES (4, $$Master Degree$$);
-- INSERT INTO educational_certificetes_types (kind, prerequirement, description) VALUES (5, $$Doctoral Degree$$);


INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (1, NULL);
INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (2, 1);
INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (3, 2);
INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (4, 3);
INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (5, 4);