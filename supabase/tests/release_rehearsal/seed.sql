-- Public catalog metadata, copied from production's export_manifest and catalog_releases.
INSERT INTO public.export_manifest(id,db_version,pipeline_version,scoring_version,schema_version,product_count,checksum,min_app_version,generated_at,created_at,is_current) VALUES
('56c68ee9-db9b-4050-9bdc-1f6de5641db3','2026.10.12.142202','3.4.0','4.5.0','2.5.0',15407,'sha256:b1b0f30e4d21e26f2a80fcb432ad36781b47aabfb8af6063c7be8b77da90812e','1.0.0','2026-10-12T14:22:02.339005+00:00','2026-10-12T15:43:35.895262+00:00',false),
('6dd91bea-7962-4d29-8fd2-0722ad5d574e','2026.10.15.235610','3.4.0','4.5.0','2.5.0',15426,'sha256:aa00384d450ac268b8921d5889f4a4e388183d4dcf2ed30b3146568a9ae1d850','1.0.0','2026-10-15T23:56:10.465165+00:00','2026-10-16T02:32:56.406156+00:00',false),
('ac50197e-fe40-4f29-8381-155188bdbfae','2026.10.21.140823','3.4.0','4.8.1','2.5.0',15426,'sha256:dbf893e9bab8bb455c6d5817f4b5991e4276ac7e4990d34a36244e1660f64842','1.0.0','2026-10-21T14:08:23.353654+00:00','2026-10-21T18:14:51.941398+00:00',false),
('27237633-b19a-4e41-b1f8-38d616b5b878','2026.10.22.012241','3.4.0','4.8.1','2.5.0',15427,'sha256:66fb0877258081982dbffccd48704d5a5b1b735ab8b64cf4ccca7d82982b7a45','1.0.0','2026-10-22T01:22:41.963852+00:00','2026-10-22T01:57:18.289922+00:00',true);
INSERT INTO public.catalog_releases(db_version,state,release_channel,released_at,activated_at,retired_at,retired_reason,notes,bundled_in_app_versions) VALUES
('2026.10.21.140823','RETIRED','ota_stable','2026-10-21T18:14:51Z','2026-10-21T18:14:51Z','2026-10-22T01:57:18Z','superseded by active release 2026.10.22.012241','seed','{}'),
('2026.10.22.012241','ACTIVE','ota_stable','2026-10-22T01:57:18Z','2026-10-22T01:57:18Z',NULL,NULL,'seed','{}');
ALTER ROLE authenticator WITH PASSWORD 'disposable-fixture-only';
