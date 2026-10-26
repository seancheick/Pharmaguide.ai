-- Read-only structural receipt for the shared public schema. Excludes provider
-- internals, fixture schemas, object OIDs and owner-specific ACL grantors.
SET search_path = public, pg_catalog;
WITH objects AS (
  SELECT 'function' AS kind,
    p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS name,
    jsonb_build_object('definition',pg_get_functiondef(p.oid),
      'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
      'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),
      'service_execute',has_function_privilege('service_role',p.oid,'EXECUTE')) AS value
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prokind='f'
    AND p.prorettype <> 'event_trigger'::regtype
    AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
      AND d.objid=p.oid AND d.deptype='e')
  UNION ALL
  SELECT 'constraint',c.relname || ':' || pg_get_constraintdef(k.oid),
    jsonb_build_object('definition',pg_get_constraintdef(k.oid),'validated',k.convalidated)
  FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'
  UNION ALL
  SELECT 'column',c.relname || ':' || a.attname,
    jsonb_build_object('ordinal',a.attnum,
      'type',format_type(a.atttypid,a.atttypmod),
      'dimensions',a.attndims,'nullable',NOT a.attnotnull,
      'default',pg_get_expr(d.adbin,d.adrelid),
      'identity',a.attidentity,'generated',a.attgenerated,
      'collation',CASE WHEN a.attcollation=0 THEN NULL
        ELSE cn.nspname || '.' || co.collname END,
      'storage',a.attstorage,'compression',a.attcompression)
  FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  LEFT JOIN pg_collation co ON co.oid=a.attcollation
  LEFT JOIN pg_namespace cn ON cn.oid=co.collnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f')
    AND a.attnum>0 AND NOT a.attisdropped
  UNION ALL
  SELECT 'index',c.relname || ':' || ix.relname,
    jsonb_build_object('definition',pg_get_indexdef(i.indexrelid),
      'valid',i.indisvalid,'ready',i.indisready,'live',i.indislive,
      'unique',i.indisunique,'primary',i.indisprimary,
      'exclusion',i.indisexclusion,'immediate',i.indimmediate,
      'nulls_not_distinct',i.indnullsnotdistinct,
      'replica_identity',i.indisreplident,'clustered',i.indisclustered)
  FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_class ix ON ix.oid=i.indexrelid
  WHERE n.nspname='public'
  UNION ALL
  SELECT 'policy',tablename || ':' || policyname,
    jsonb_build_object('roles',roles,'command',cmd,'permissive',permissive,
      'using',qual,'check',with_check)
  FROM pg_policies WHERE schemaname='public'
  UNION ALL
  SELECT 'trigger',c.relname || ':' || t.tgname,
    jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled)
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND NOT t.tgisinternal
  UNION ALL
  SELECT 'table',c.relname,
    jsonb_build_object('rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
      'anon_select',has_table_privilege('anon',c.oid,'SELECT'),
      'anon_insert',has_table_privilege('anon',c.oid,'INSERT'),
      'anon_update',has_table_privilege('anon',c.oid,'UPDATE'),
      'anon_delete',has_table_privilege('anon',c.oid,'DELETE'),
      'authenticated_select',has_table_privilege('authenticated',c.oid,'SELECT'),
      'authenticated_insert',has_table_privilege('authenticated',c.oid,'INSERT'),
      'authenticated_update',has_table_privilege('authenticated',c.oid,'UPDATE'),
      'authenticated_delete',has_table_privilege('authenticated',c.oid,'DELETE'))
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p')
)
SELECT coalesce(jsonb_agg(jsonb_build_object('kind',kind,'name',name,'value',value)
  ORDER BY kind,name),'[]'::jsonb) FROM objects;
