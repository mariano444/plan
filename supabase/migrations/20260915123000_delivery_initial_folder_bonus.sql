-- MundoAuto: carpeta pagada separada, contador de entrega inicial y bonificacion de traslado.

alter table public.clients add column if not exists folder_paid boolean not null default false;
alter table public.clients add column if not exists folder_paid_date date;
alter table public.clients add column if not exists initial_due_date date;
alter table public.clients add column if not exists initial_extension_days int not null default 0 check (initial_extension_days >= 0);
alter table public.clients add column if not exists transfer_bonus_active boolean not null default false;

update public.clients
set
  initial_due_date = coalesce(initial_due_date, created_at::date + 10),
  folder_paid = case when folder_paid then true else initial_status in ('half','paid') end,
  folder_paid_date = case
    when folder_paid_date is not null then folder_paid_date
    when initial_status in ('half','paid') then coalesce(initial_confirmed_date, created_at::date)
    else null
  end,
  transfer_bonus_active = case when initial_status = 'paid' then true else transfer_bonus_active end;

comment on column public.clients.folder_paid is 'Carpeta pagada independiente de la entrega inicial';
comment on column public.clients.initial_due_date is 'Vencimiento base de la entrega inicial; si esta vacio se usa created_at + 10 dias';
comment on column public.clients.initial_extension_days is 'Dias adicionales otorgados desde administracion';
comment on column public.clients.transfer_bonus_active is 'Bonificacion del servicio de traslado a domicilio activada al completar la entrega inicial';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  if TG_TABLE_NAME = 'clients' then
    if new.initial_due_date is null then
      new.initial_due_date = (coalesce(new.created_at, now())::date + 10);
    end if;
    if new.folder_paid and new.folder_paid_date is null then
      new.folder_paid_date = current_date;
    end if;
    if not new.folder_paid then
      new.folder_paid_date = null;
    end if;
    if new.initial_status = 'paid' then
      new.transfer_bonus_active = true;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_clients_updated_at on public.clients;
create trigger trg_clients_updated_at
  before insert or update on public.clients
  for each row execute function public.set_updated_at();

create or replace view public.client_progress as
select
  c.id as client_id,
  c.folder_paid                                               as carpeta_done,
  (c.initial_status = 'paid')                                  as entrega_inicial_done,
  coalesce(p.paid_count, 0)                                    as cuotas_pagadas,
  coalesce(p.total_count, c.installment_count)                 as cuotas_total,
  (case when c.folder_paid then 1 else 0 end)
    + (case when c.initial_status = 'paid' then 1 else 0 end)
    + coalesce(p.paid_count, 0)                                 as completados,
  2 + coalesce(p.total_count, c.installment_count)              as total_compromisos,
  round(
    (
      (case when c.folder_paid then 1 else 0 end)
      + (case when c.initial_status = 'paid' then 1 else 0 end)
      + coalesce(p.paid_count, 0)
    )::numeric
    / nullif(2 + coalesce(p.total_count, c.installment_count), 0) * 100
  )                                                              as porcentaje,
  (c.initial_status = 'paid'
    and coalesce(p.total_count, 0) > 0
    and coalesce(p.paid_count, 0) = coalesce(p.total_count, 0)) as retiro_listo
from public.clients c
left join (
  select
    client_id,
    count(*)                                as total_count,
    count(*) filter (where status = 'paid') as paid_count
  from public.payments
  group by client_id
) p on p.client_id = c.id;

create or replace function public.get_client_by_dni(p_dni text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client public.clients%rowtype;
  v_result jsonb;
begin
  select * into v_client
  from public.clients
  where dni = regexp_replace(p_dni, '\D', '', 'g')
  limit 1;

  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'id', v_client.id,
    'name', v_client.name,
    'dni', v_client.dni,
    'phone', v_client.phone,
    'advisor', v_client.advisor,
    'folder', jsonb_build_object(
      'paid', v_client.folder_paid,
      'paidDate', v_client.folder_paid_date
    ),
    'initial', jsonb_build_object(
      'amount', v_client.initial_amount,
      'status', v_client.initial_status,
      'proof', v_client.initial_proof,
      'proofDate', v_client.initial_proof_date,
      'confirmedDate', v_client.initial_confirmed_date,
      'dueDate', v_client.initial_due_date,
      'extensionDays', v_client.initial_extension_days
    ),
    'installmentValue', v_client.installment_value,
    'installmentCount', v_client.installment_count,
    'retiroRequested', v_client.retiro_requested,
    'transferBonusActive', v_client.transfer_bonus_active,
    'createdAt', v_client.created_at,
    'payments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'n', pay.n, 'due', pay.due, 'status', pay.status,
          'paid', pay.paid_date, 'proof', pay.proof,
          'proofDate', pay.proof_date, 'note', pay.note
        ) order by pay.n
      )
      from public.payments pay
      where pay.client_id = v_client.id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.get_client_by_dni(text) to anon, authenticated;
