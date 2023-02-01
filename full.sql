--drop table public.shipping_country_rates cascade;
--drop table shipping_agreement cascade;
--drop table shipping_transfer cascade;
--drop table shipping_info cascade;
--drop table shipping_status cascade;


create table public.shipping_country_rates (
	shipping_country_id serial not null,
	shipping_country text null,
	shipping_country_base_rate numeric(14,3) null,
	constraint shipping_country_id_pkey primary key (shipping_country_id)
);

insert into public.shipping_country_rates
(shipping_country, shipping_country_base_rate)
select distinct
	shipping_country,
	shipping_country_base_rate
from public.shipping;

create table shipping_agreement (
	agreementid bigint not null,
	agreement_number text null,
	agreement_rate numeric(14,2) null,
	agreement_commission numeric(14,2) null,
	constraint shipping_agreementid_pkey primary key (agreementid)
);

insert into public.shipping_agreement
(agreementid, agreement_number, agreement_rate, agreement_commission)
select distinct
	 cast((regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[1] as bigint) AS agreementid,
	 (regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[2] AS agreement_number,
	 cast((regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[3] as numeric(14,2)) AS agreement_rate,
	 cast((regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[4] as numeric(14,2)) AS agreement_commission
from public.shipping as sh;

create table shipping_transfer (
	transfer_type_id serial not null,
	transfer_type text null,
	transfer_model text null,
	shipping_transfer_rate numeric(14,3) null,
	constraint shipping_transfer_type_id_pkey primary key (transfer_type_id)
);

insert into public.shipping_transfer
(transfer_type, transfer_model, shipping_transfer_rate)
select distinct
	(regexp_split_to_array(sh.shipping_transfer_description , E'\\:+'))[1] AS transfer_type,
	(regexp_split_to_array(sh.shipping_transfer_description, E'\\:+'))[2] AS transfer_model,
	sh.shipping_transfer_rate
from public.shipping as sh;

create table shipping_info (
	shippingid int8 not null,
	vendorid int8 null,
	payment_amount numeric(14,2) null,
	shipping_plan_datetime timestamp null,
	transfer_type_id int8 null,
	shipping_country_id int8 null,
	agreementid int8 null,
	foreign key (transfer_type_id) references shipping_transfer (transfer_type_id) on update cascade,
	foreign key (shipping_country_id) references shipping_country_rates (shipping_country_id) on update cascade,
	foreign key (agreementid) references shipping_agreement (agreementid) on update cascade
);

insert into public.shipping_info
(shippingid, vendorid, payment_amount, shipping_plan_datetime, transfer_type_id, shipping_country_id, agreementid)
select
	s.shippingid,
	s.vendorid,
	s.payment_amount,
	s.shipping_plan_datetime,
	st.transfer_type_id,
	scr.shipping_country_id,
	sa.agreementid
from
	public.shipping s
join
	public.shipping_transfer st
		on st.transfer_type = (regexp_split_to_array(s.shipping_transfer_description , E'\\:+'))[1]
		and st.transfer_model = (regexp_split_to_array(s.shipping_transfer_description , E'\\:+'))[2]
		and st.shipping_transfer_rate = s.shipping_transfer_rate
join
	public.shipping_country_rates scr
		on scr.shipping_country = s.shipping_country
		and scr.shipping_country_base_rate = s.shipping_country_base_rate
join
	public.shipping_agreement sa
		on sa.agreementid = cast((regexp_split_to_array(s.vendor_agreement_description, E'\\:+'))[1] as bigint);

create table shipping_status (
	shippingid int8 not null,
	status text null,
	state text null,
	shipping_start_fact_datetime timestamp null,
	shipping_end_fact_datetime timestamp null
);

with
m_datetime as (
	select
		s.shippingid,
		max(s.state_datetime) as max_datetime
	from public.shipping s
	group by s.shippingid
),
ship_status_state as (
	select
		s2.shippingid,
		s2.status,
		s2.state
	from shipping s2
	join m_datetime as md
		on s2.shippingid = md.shippingid
		and s2.state_datetime = md.max_datetime
),
shipping_start as (
	select
		s.shippingid,
		s.state_datetime as shipping_start_fact_datetime
	from public.shipping s
	where s.state = 'booked'
),
shipping_end as (
	select
		s.shippingid,
		s.state_datetime as shipping_end_fact_datetime
	from public.shipping s
	where s.state = 'recieved'
)
insert into public.shipping_status
(shippingid, status, state, shipping_start_fact_datetime, shipping_end_fact_datetime)
select *
from ship_status_state
join shipping_start using(shippingid)
join shipping_end using(shippingid);

CREATE OR REPLACE VIEW public.shipping_datamart AS (
	select distinct
		ss.shippingid,
		si.vendorid,
		st.transfer_type,
		date_part('day', age(ss.shipping_end_fact_datetime, ss.shipping_start_fact_datetime)) as full_day_at_shipping,
		case
			when shipping_end_fact_datetime > shipping_plan_datetime then 1
			else 0
		end as is_delay,
		case
			when status = 'finished' then 1
			else 0
		end as is_shipping_finish,
		case
			when shipping_end_fact_datetime > shipping_plan_datetime
				then date_part('day', age(shipping_end_fact_datetime, shipping_plan_datetime))
			else 0
		end as delay_day_at_shipping,
		si.payment_amount,
		si.payment_amount * (scr.shipping_country_base_rate + sa.agreement_rate + st.shipping_transfer_rate) as vat,
		si.payment_amount * sa.agreement_commission as profit
	from shipping_info si
	left join shipping_transfer st using(transfer_type_id)
	left join shipping_status ss using(shippingid)
	left join shipping_country_rates scr using(shipping_country_id)
	left join shipping_agreement sa using(agreementid)
	order by shippingid
);

