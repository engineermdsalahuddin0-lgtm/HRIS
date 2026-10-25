-- =============================================================================
-- Fix: list_organogram_grades seeds the default grades (an INSERT) but was marked
-- STABLE. PostgREST runs stable functions in a read-only transaction, so the call
-- failed with HTTP 405 (25006 read-only transaction). Re-created as VOLATILE.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.organogram_grades') is null then
    raise exception 'Apply 20261101000100_organogram.sql first, then run this file again';
  end if;
end;
$guard$;

alter function public.list_organogram_grades() volatile;
