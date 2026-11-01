-- Apokalypserebusen 2026: read-only SECURITY DEFINER RPC privilege audit.
-- Verifies the exact allowlist, role grants, locked search_path and basic guards.
-- Does not change roles, grants, policies, or data. Text checks are NOT proof
-- of complete security: pair with role-impersonation and two-client E2E tests.
WITH expected(name,auth_allowed,kind) AS (
 VALUES
 ('claim_rebus_admin',true,'claim'),
 ('hk_advance_team_stage',true,'hk'),
 ('hk_release_special',true,'hk'),
 ('hk_rotate_team_code',true,'hk'),
 ('hk_set_team_stage',true,'hk'),
 ('join_rebus_team',false,'disabled'),
 ('join_rebus_team_by_choice',false,'disabled'),
 ('join_rebus_team_by_code',true,'join_code'),
 ('join_rebus_team_by_name',true,'join_name')
),
observed AS (
 SELECT e.name,e.auth_allowed,e.kind,p.oid,p.prosecdef,p.proconfig,
        pg_get_functiondef(p.oid) definition,
        has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
        has_function_privilege('authenticated',p.oid,'EXECUTE') auth_exec,
        has_function_privilege('public',p.oid,'EXECUTE') public_exec
 FROM expected e LEFT JOIN pg_proc p ON p.proname=e.name
  AND p.pronamespace='public'::regnamespace
),
checks AS (
 SELECT 1 id,'Exactly nine expected SECURITY DEFINER RPCs' label,
    (SELECT count(*)=9 AND bool_and(oid IS NOT NULL AND prosecdef) FROM observed) passed
 UNION ALL SELECT 2,'No extra public SECURITY DEFINER functions',
    (SELECT count(*)=9 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.prosecdef)
 UNION ALL SELECT 3,'No anonymous EXECUTE privilege',
    (SELECT bool_and(NOT anon_exec) FROM observed)
 UNION ALL SELECT 4,'No PUBLIC role EXECUTE privilege',
    (SELECT bool_and(NOT public_exec) FROM observed)
 UNION ALL SELECT 5,'Authenticated EXECUTE matches intended allowlist',
    (SELECT bool_and(auth_exec=auth_allowed) FROM observed)
 UNION ALL SELECT 6,'All functions pin an empty search_path',
    (SELECT bool_and(proconfig @> ARRAY['search_path=""']::text[]) FROM observed)
 UNION ALL SELECT 7,'HK-only functions check both auth.uid and admins',
    (SELECT count(*)=4 AND bool_and(definition ILIKE '%auth.uid()%' AND definition LIKE '%public.admins%')
       FROM observed WHERE kind='hk')
 UNION ALL SELECT 8,'Claim admin checks authentication and hashed one-use code',
    (SELECT bool_and(definition LIKE '%auth.uid()%' AND definition LIKE '%code_hash%'
      AND definition LIKE '%claimed_by is null%') FROM observed WHERE kind='claim')
 UNION ALL SELECT 9,'Join by code validates authenticated identity and code hash',
    (SELECT bool_and(definition LIKE '%auth.uid()%' AND definition LIKE '%code_hash%'
      AND definition LIKE '%team_members%') FROM observed WHERE kind='join_code')
 UNION ALL SELECT 10,'Join by name checks authentication and existing membership',
    (SELECT bool_and(definition LIKE '%auth.uid()%' AND definition LIKE '%team_members%'
      AND definition LIKE '%public.admins%') FROM observed WHERE kind='join_name')
 UNION ALL SELECT 11,'Disabled legacy join methods remain non-callable',
    (SELECT count(*)=2 AND bool_and(NOT auth_exec AND NOT anon_exec AND NOT public_exec)
       FROM observed WHERE kind='disabled')
)
SELECT id,label,CASE WHEN COALESCE(passed,false) THEN 'PASS' ELSE 'FAIL' END status FROM checks ORDER BY id;
