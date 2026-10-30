-- 1. Let the booking function accept the Gym (7) and the Clubhouse (8)
do $$
declare v_oid oid; d0 text; d text;
begin
  select oid into v_oid from pg_proc
   where proname = 'book_training' and pronamespace = 'public'::regnamespace;
  d0 := pg_get_functiondef(v_oid);
  d := replace(d0, 'array[1,2,3,4,5,6]', 'array[1,2,3,4,5,6,7,8]');
  if d = d0 and d0 not like '%1,2,3,4,5,6,7,8%' then
    raise exception 'Could not find the half check in book_training. Nothing was changed.';
  end if;
  d := replace(d, 'Your pitch booking is confirmed.', 'Your booking is confirmed.');
  if position('when p_halves <@ array[7,8]' in d) = 0 then
    d := replace(d, 'else ''pitch'' end', 'when p_halves <@ array[7,8] then halves_text(p_halves) else ''pitch'' end');
  end if;
  execute d;
end $$;

-- 2. Let the confirmation emails describe them (and use South / North for the Old Pitch)
create or replace function public.halves_text(h integer[])
returns text language sql immutable as $$
  select string_agg(
    case when p.b is null then p.name
         when p.a = any(h) and p.b = any(h) then p.name || ' (whole pitch)'
         when p.a = any(h) then p.name || ' - ' || p.sa || ' side'
         else p.name || ' - ' || p.sb || ' side' end,
    ', ' order by p.n)
  from (values (1,'Old Pitch',1,2,'South','North'),
               (2,'Juvenile Pitch',3,4,'Front','Back'),
               (3,'Senior Pitch',5,6,'Back','Front'),
               (4,'Gym',7,null::int,null::text,null::text),
               (5,'Clubhouse Meeting Room',8,null::int,null::text,null::text)) p(n,name,a,b,sa,sb)
  where p.a = any(h) or p.b = any(h);
$$;

-- 3. If the bookings table has its own rule limiting halves to 1-6, widen it
do $$
declare c record;
begin
  for c in select conname, pg_get_constraintdef(oid) as def from pg_constraint
            where conrelid = 'public.bookings'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%halves%'
              and pg_get_constraintdef(oid) like '%4, 5, 6]%'
  loop
    execute format('alter table public.bookings drop constraint %I', c.conname);
    execute format('alter table public.bookings add constraint %I %s',
                   c.conname, replace(c.def, '4, 5, 6]', '4, 5, 6, 7, 8]'));
  end loop;
end $$;

-- 4. Show me what is left, plus two quick tests of the email wording
select 'rule' as kind, conname::text as name, pg_get_constraintdef(oid) as detail
  from pg_constraint where conrelid = 'public.bookings'::regclass and contype in ('c','x')
union all
select 'view', viewname::text, definition from pg_views where viewname = 'public_schedule'
union all
select 'test', 'Gym + Clubhouse', halves_text(array[7,8])
union all
select 'test', 'Old Pitch south + Gym', halves_text(array[1,7]);
