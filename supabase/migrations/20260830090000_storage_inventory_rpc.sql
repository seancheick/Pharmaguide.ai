-- Storage-inventory RPCs for the pipeline's release-safety inventory.
--
-- MIGRATION OWNERSHIP: this linked Flutter repository's supabase/migrations/
-- directory is the single executable owner of live Supabase migrations. The
-- pipeline consumes these RPCs but intentionally carries no duplicate SQL.
-- `tool/apply_storage_inventory_rpc.sh` applies only this reviewed file and
-- records its exact version through the supported migration-repair command;
-- it does not rewrite the project's pre-existing multi-owner history.
--
-- Purpose: replace the 256-request shard walk with two read-only functions.
-- The pipeline client validates every row, requires monotonic keyset cursors,
-- cross-checks page totals against the summary, and falls back to the shard
-- walker on any disagreement.
--
-- Security model:
--   * SECURITY INVOKER; service_role already has SELECT on storage.objects.
--   * EXECUTE revoked from PUBLIC/anon/authenticated and granted only to
--     service_role.
--   * Prefixes restricted to recognized PharmaGuide layouts.
--
-- Index expectation: the half-open C-collation range uses the existing
-- storage.objects (bucket_id, name COLLATE "C") index. Live EXPLAIN remains a
-- rollout gate; a sequential scan blocks enabling the fast path.

create or replace function public.pg_storage_inventory_prefix_ok(p_prefix text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select p_prefix = 'shared/details/sha256'
      or p_prefix ~ '^shared/details/sha256/[0-9a-f]{2}$'
      or p_prefix ~ '^shared/quarantine/\d{4}-\d{2}-\d{2}$'
      or p_prefix ~ '^shared/quarantine/\d{4}-\d{2}-\d{2}/[0-9a-f]{2}$'
$$;

comment on function public.pg_storage_inventory_prefix_ok(text) is
  'Recognized PharmaGuide storage prefixes for the inventory RPCs. '
  'Anything else is refused regardless of caller privileges.';

create or replace function public.pg_storage_inventory_summary(p_prefix text)
returns table (object_count bigint, total_bytes bigint)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not public.pg_storage_inventory_prefix_ok(p_prefix) then
    raise exception 'unrecognized inventory prefix: %', p_prefix
      using errcode = '22023';
  end if;
  return query
    select count(*)::bigint,
           coalesce(sum((o.metadata ->> 'size')::bigint), 0)::bigint
    from storage.objects o
    where o.bucket_id = 'pharmaguide'
      and o.name collate "C" >= (p_prefix || '/') collate "C"
      and o.name collate "C" <  (p_prefix || '0') collate "C";
end;
$$;

create or replace function public.pg_storage_inventory_page(
  p_prefix text,
  p_after  text default null,
  p_limit  integer default 1000
)
returns table (name text, size bigint, etag text, updated_at timestamptz)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not public.pg_storage_inventory_prefix_ok(p_prefix) then
    raise exception 'unrecognized inventory prefix: %', p_prefix
      using errcode = '22023';
  end if;
  return query
    select o.name,
           coalesce((o.metadata ->> 'size')::bigint, 0),
           o.metadata ->> 'eTag',
           o.updated_at
    from storage.objects o
    where o.bucket_id = 'pharmaguide'
      and o.name collate "C" >= (p_prefix || '/') collate "C"
      and o.name collate "C" <  (p_prefix || '0') collate "C"
      and (p_after is null or o.name collate "C" > p_after collate "C")
    order by o.name collate "C"
    limit least(greatest(coalesce(p_limit, 1000), 1), 1000);
end;
$$;

comment on function public.pg_storage_inventory_summary(text) is
  'Read-only inventory summary for one recognized PharmaGuide prefix. '
  'Cross-checked by the client against the page stream; mismatch = fallback.';
comment on function public.pg_storage_inventory_page(text, text, integer) is
  'Keyset page (<=1000 rows, ORDER BY name COLLATE "C") of one recognized '
  'prefix. A page shorter than the limit is normal termination.';

revoke execute on function public.pg_storage_inventory_prefix_ok(text)
  from public, anon, authenticated;
revoke execute on function public.pg_storage_inventory_summary(text)
  from public, anon, authenticated;
revoke execute on function public.pg_storage_inventory_page(text, text, integer)
  from public, anon, authenticated;
grant execute on function public.pg_storage_inventory_prefix_ok(text)
  to service_role;
grant execute on function public.pg_storage_inventory_summary(text)
  to service_role;
grant execute on function public.pg_storage_inventory_page(text, text, integer)
  to service_role;
