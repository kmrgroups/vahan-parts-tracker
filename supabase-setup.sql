-- Child Parts Tracker: run this in Supabase → SQL Editor → New query → Run.
-- Safe to run again after app updates; it only adds what is missing.
create extension if not exists pgcrypto;

create table if not exists app_settings (key text primary key, value jsonb, updated_at timestamptz default now());
create table if not exists profiles (id uuid primary key references auth.users on delete cascade, email text, full_name text, role text default 'viewer', created_at timestamptz default now());
create table if not exists team (id uuid primary key default gen_random_uuid(), name text not null, phone text, email text, tags text[] default '{}', wa_apikey text, notify_email boolean default true, notify_whatsapp boolean default true, active boolean default true, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists masters (id uuid primary key default gen_random_uuid(), category text not null, value text not null, extra jsonb default '{}', sort int default 0, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists suppliers (id uuid primary key default gen_random_uuid(), name text not null, contact_person text, address text, process text, phone text, email text, location_url text, credit_days numeric, gst_no text, active boolean default true, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists customers (id uuid primary key default gen_random_uuid(), name text not null, contact_person text, phone text, email text, credit_days numeric, gst_no text, address text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists materials (id uuid primary key default gen_random_uuid(), grade text not null, rate_per_kg numeric, stock_kg numeric default 0, min_stock_kg numeric, density_factor numeric, preferred_supplier text, remarks text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists orders (id uuid primary key default gen_random_uuid(), order_no text, order_date date, customer text, customer_po text, project text, qty numeric, order_value numeric, delivery_date date, owner uuid, status text default 'Open', delivered_date date, invoice_no text, invoice_date date, invoice_amount numeric, credit_days numeric, received_amount numeric, received_date date, remarks text, alert_state text, created_by text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists parts (id uuid primary key default gen_random_uuid(), order_id uuid, drawing_no text, ga_drawing_no text, project text, part_name text, type text, grade text, dia numeric, length numeric, width numeric, thk numeric, qty numeric, planned_weight numeric, cost_per_kg numeric, cutting_charge numeric, planned_cost numeric, rm_source text, po_id uuid, actual_weight numeric, actual_rate numeric, actual_cost numeric, rm_received_date date, order_date date, target_date date, remarks text, created_by text, created_at timestamptz default now(), updated_at timestamptz default now());
alter table parts add column if not exists order_id uuid;
alter table parts add column if not exists rm_source text;
alter table parts add column if not exists po_id uuid;
alter table parts add column if not exists actual_rate numeric;
alter table parts add column if not exists rm_received_date date;
create table if not exists purchase_orders (id uuid primary key default gen_random_uuid(), po_no text, po_date date, supplier text, order_id uuid, expected_date date, status text default 'Draft', lines jsonb default '[]', total numeric, remarks text, created_by text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists grns (id uuid primary key default gen_random_uuid(), grn_no text, grn_date date, po_id uuid, supplier text, lines jsonb default '[]', bill_no text, bill_date date, bill_amount numeric, credit_days numeric, paid_amount numeric, paid_date date, remarks text, created_by text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists operations (id uuid primary key default gen_random_uuid(), order_id uuid, part_id uuid, drawing_no text, part_name text, project text, seq numeric, qty numeric, process text, owner_type text, owner_member uuid, supplier text, follow_up uuid, assigned_by text, target_date date, status text default 'Planned', progress numeric, start_date date, sent_date date, done_date date, hold_reason text, plan_rate numeric, plan_hours numeric, plan_cost numeric, actual_rate numeric, start_time text, end_time text, actual_hours numeric, actual_cost numeric, inspection text, rejection_qty numeric, debit_amount numeric, moved_by text, bill_no text, bill_amount numeric, paid_amount numeric, paid_date date, remarks text, alert_state text, alert_date date, created_by text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists tasks (id uuid primary key default gen_random_uuid(), title text not null, details text, assigned_to uuid, assigned_by text, due_date date, priority text default 'Normal', status text default 'Open', link_table text, link_id uuid, drawing_no text, completed_at timestamptz, created_by text, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists notifications (id uuid primary key default gen_random_uuid(), recipient_email text, recipient_team uuid, title text, body text, link text, is_read boolean default false, created_at timestamptz default now(), updated_at timestamptz default now());
create table if not exists activity (id uuid primary key default gen_random_uuid(), actor text, action text, entity text, entity_id uuid, summary text, created_at timestamptz default now(), updated_at timestamptz default now());
create index if not exists parts_order on parts (order_id);
create index if not exists parts_drawing on parts (drawing_no);
create index if not exists ops_part on operations (part_id);
create index if not exists ops_order on operations (order_id);
create index if not exists notif_to on notifications (recipient_email, created_at desc);

-- role of the signed-in person: admin | editor | member | viewer
create or replace function app_role() returns text language sql stable security definer set search_path = public as
$$ select coalesce((select role from profiles where id = auth.uid()), 'none') $$;
create or replace function my_team_id() returns uuid language sql stable security definer set search_path = public as
$$ select id from team where lower(email) = lower(auth.jwt()->>'email') limit 1 $$;

-- first person to sign up becomes admin, everyone after starts as viewer
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name, role)
  values (new.id, lower(new.email), coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
          case when (select count(*) from profiles) = 0 then 'admin'
               else coalesce((select value #>> '{}' from app_settings where key = 'default_role' and value #>> '{}' in ('editor','member','viewer')), 'member') end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
insert into profiles (id, email, full_name, role)
  select u.id, lower(u.email), split_part(u.email, '@', 1), case when row_number() over (order by u.created_at) = 1 and not exists (select 1 from profiles) then 'admin' else 'viewer' end
  from auth.users u on conflict (id) do nothing;

-- row level security
do $$ declare t text; begin
  foreach t in array array['team','masters','suppliers','customers','materials','orders','parts','purchase_orders','grns','operations','tasks','notifications','activity','app_settings','profiles'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "read" on %I', t);
    execute format('drop policy if exists "write" on %I', t);
    execute format('create policy "read" on %I for select to authenticated using (app_role() <> ''none'')', t);
  end loop;
  foreach t in array array['team','masters','suppliers','customers','materials','orders','parts','purchase_orders','grns','operations','tasks'] loop
    execute format('create policy "write" on %I for all to authenticated using (app_role() in (''admin'',''editor'')) with check (app_role() in (''admin'',''editor''))', t);
  end loop;
  foreach t in array array['notifications','activity'] loop
    execute format('create policy "write" on %I for all to authenticated using (app_role() <> ''none'') with check (app_role() <> ''none'')', t);
  end loop;
  execute 'create policy "write" on app_settings for all to authenticated using (app_role() = ''admin'') with check (app_role() = ''admin'')';
  execute 'create policy "write" on profiles for update to authenticated using (app_role() = ''admin'') with check (app_role() = ''admin'')';
end $$;
-- members may update the tasks and process steps assigned to them
drop policy if exists "member tasks" on tasks;
create policy "member tasks" on tasks for update to authenticated using (assigned_to = my_team_id()) with check (assigned_to = my_team_id());
drop policy if exists "member ops" on operations;
create policy "member ops" on operations for update to authenticated using (owner_member = my_team_id() or follow_up = my_team_id()) with check (owner_member = my_team_id() or follow_up = my_team_id());
drop policy if exists "brand" on app_settings;
create policy "brand" on app_settings for select to anon using (key in ('company_name','logo','app_title'));

-- live updates for everyone
do $$ declare t text; begin
  foreach t in array array['team','masters','suppliers','customers','materials','orders','parts','purchase_orders','grns','operations','tasks','notifications','app_settings'] loop
    begin execute format('alter publication supabase_realtime add table %I', t); exception when others then null; end;
  end loop;
end $$;
