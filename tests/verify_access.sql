-- Run after 001. All fixtures and changes are rolled back; no notifications sent.
-- Run as postgres (SQL Editor or database connection). Any failed assertion aborts.
begin;
set local statement_timeout = '30s';
create temporary table wb_test_ids as select gen_random_uuid() as a, gen_random_uuid() as b,
  gen_random_uuid() as source_a, gen_random_uuid() as source_b,
  gen_random_uuid() as model_id, gen_random_uuid() as assessment_a,
  gen_random_uuid() as assessment_b, gen_random_uuid() as alert_a;
grant select on wb_test_ids to authenticated, service_role;
insert into auth.users(id) select a from wb_test_ids union all select b from wb_test_ids;
insert into public.wb_profiles(user_id) select a from wb_test_ids union all select b from wb_test_ids;
insert into public.wb_sources(id,user_id,provider,external_account_id)
 select source_a,a,'verification','a' from wb_test_ids union all
 select source_b,b,'verification','b' from wb_test_ids;

create function pg_temp.expect_error(q text, expected text) returns void
language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    if sqlstate = expected then return; end if;
    raise;
  end;
  raise exception 'Expected SQLSTATE %, statement succeeded: %',expected,q;
end $$;

do $$ declare n integer; t text; begin
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
   where ns.nspname='public' and c.relname like 'wb\_%' escape '\' and c.relkind='r';
  if n <> 15 then raise exception 'Expected 15 app tables, found %',n; end if;
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'wb\_%' escape '\' loop
    if not (select relrowsecurity from pg_class where oid=format('public.%I',t)::regclass) then
      raise exception 'RLS missing: %',t;
    end if;
    if has_table_privilege('anon',format('public.%I',t),'SELECT') or
       has_table_privilege('anon',format('public.%I',t),'INSERT') then
      raise exception 'Anonymous access: %',t;
    end if;
  end loop;
end $$;

select set_config('request.jwt.claim.sub', (select a::text from wb_test_ids), true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.wb_profiles where user_id in (select a from wb_test_ids union select b from wb_test_ids)) <> 1 then
  raise exception 'User isolation failed'; end if;
 if (select count(*) from public.wb_sources where user_id in (select a from wb_test_ids union select b from wb_test_ids)) <> 1 then
  raise exception 'Source isolation failed'; end if;
end $$;
insert into public.wb_checkins(user_id,mood) select a,3 from wb_test_ids;
update public.wb_profiles set timezone='Europe/Bucharest' where user_id=(select a from wb_test_ids);
select pg_temp.expect_error('insert into public.wb_checkins(user_id,mood) select b,3 from wb_test_ids','42501');
select pg_temp.expect_error('insert into public.wb_consent_events(user_id,scope,granted,policy_version) select a,''wearables'',true,''test'' from wb_test_ids','42501');
select pg_temp.expect_error('insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value) select a,source_a,''x'',''steps'',now(),now(),1 from wb_test_ids','42501');
reset role;

set local role service_role;
-- Consent applies to privileged backend writes too.
select pg_temp.expect_error('insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value) select a,source_a,''x'',''steps'',now(),now(),1 from wb_test_ids','42501');
insert into public.wb_consent_events(user_id,scope,granted,policy_version)
 select a,'wearables',true,'test' from wb_test_ids;
insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value)
 select a,source_a,'x','steps',now(),now(),1 from wb_test_ids;
select pg_temp.expect_error('insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value) select a,source_b,''foreign'',''steps'',now(),now(),1 from wb_test_ids','23503');
select pg_temp.expect_error('insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value) select a,source_a,''x'',''steps'',now(),now(),1 from wb_test_ids','23505');
select pg_temp.expect_error('insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value) select a,source_a,''bad-time'',''steps'',now(),now()-interval ''1 hour'',1 from wb_test_ids','23514');
select pg_temp.expect_error('update public.wb_consent_events set granted=false where user_id=(select a from wb_test_ids)','42501');
insert into public.wb_consent_events(user_id,scope,granted,policy_version)
 select a,'wearables',false,'test' from wb_test_ids;
select pg_temp.expect_error('insert into public.wb_wearable_observations(user_id,source_id,external_id,metric_code,started_at,ended_at,value) select a,source_a,''after-withdrawal'',''steps'',now(),now(),1 from wb_test_ids','42501');
-- Exercise the assessment -> alert -> delivery flow and cross-owner links.
insert into public.wb_model_versions(id,name,version,description)
 select model_id,'verification-'||model_id::text,'test','Temporary security test' from wb_test_ids;
select pg_temp.expect_error('insert into public.wb_assessments(id,user_id,model_version_id,module,window_start,window_end,signal,data_coverage,evidence,explanation) select assessment_a,a,model_id,''wearables'',now()-interval ''1 day'',now(),''change_detected'',1,''{}''::jsonb,''Test'' from wb_test_ids','42501');
insert into public.wb_consent_events(user_id,scope,granted,policy_version)
 select a,'analysis',true,'test' from wb_test_ids union all
 select b,'analysis',true,'test' from wb_test_ids union all
 select a,'notifications',true,'test' from wb_test_ids;
insert into public.wb_assessments(id,user_id,model_version_id,module,window_start,window_end,signal,data_coverage,evidence,explanation)
 select assessment_a,a,model_id,'wearables',now()-interval '1 day',now(),'change_detected',1,'{}'::jsonb,'Test' from wb_test_ids union all
 select assessment_b,b,model_id,'wearables',now()-interval '1 day',now(),'insufficient_data',0,'{}'::jsonb,'Test' from wb_test_ids;
select pg_temp.expect_error('insert into public.wb_alerts(user_id,assessment_id,message) select a,assessment_b,''Test'' from wb_test_ids','23503');
insert into public.wb_alerts(id,user_id,assessment_id,message)
 select alert_a,a,assessment_a,'Temporary test: no notification sent' from wb_test_ids;
insert into public.wb_alert_deliveries(user_id,alert_id,channel,attempt,status)
 select a,alert_a,'in_app',1,'pending' from wb_test_ids;
insert into public.wb_consent_events(user_id,scope,granted,policy_version)
 select a,'notifications',false,'test' from wb_test_ids;
select pg_temp.expect_error('update public.wb_alert_deliveries set status=''sent'',sent_at=now() where user_id=(select a from wb_test_ids)','42501');
update public.wb_alert_deliveries set status='cancelled' where user_id=(select a from wb_test_ids);
reset role;

set local role authenticated;
insert into public.wb_alert_acknowledgements(user_id,alert_id) select a,alert_a from wb_test_ids;
select pg_temp.expect_error('insert into public.wb_alert_acknowledgements(user_id,alert_id) select b,alert_a from wb_test_ids','42501');
reset role;

select set_config('request.jwt.claim.sub', (select b::text from wb_test_ids), true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.wb_wearable_observations where user_id=(select a from wb_test_ids)) then
   raise exception 'Other user can read observations'; end if;
 if exists(select 1 from public.wb_checkins where user_id=(select a from wb_test_ids)) then
   raise exception 'Other user can read checkins'; end if;
 if exists(select 1 from public.wb_alerts where user_id=(select a from wb_test_ids)) then
   raise exception 'Other user can read alerts'; end if;
 perform pg_temp.expect_error('insert into public.wb_alert_acknowledgements(user_id,alert_id) select b,alert_a from wb_test_ids','23503');
end $$;
reset role;

-- Verify account deletion cascades through dependent app records.
delete from auth.users where id=(select a from wb_test_ids);
do $$ begin
 if exists(select 1 from public.wb_wearable_observations where user_id=(select a from wb_test_ids)) then
   raise exception 'Account deletion did not cascade'; end if;
 if exists(select 1 from public.wb_alert_deliveries where user_id=(select a from wb_test_ids)) then
   raise exception 'Account deletion left delivery records'; end if;
end $$;
rollback;
select 'PASS: ownership, privileges, consent, constraints, deduplication, alert workflow and deletion; fixtures rolled back' as result;
