1. **Создайте справочник стоимости доставки в страны shipping_country_rates из данных, указанных в shipping_country и shipping_country_base_rate. Первичным ключом сделайте серийный id, то есть серийный идентификатор каждой строчки. Важно дать серийному ключу имя «id». Справочник должен состоять из уникальных пар полей из таблицы shipping.**

Cоздание таблицы-справочника:
```sql
create table public.shipping_country_rates (
	shipping_country_id serial not null,
	shipping_country text null,
	shipping_country_base_rate numeric(14,3) null,
	constraint shipping_country_id_pkey primary key (shipping_country_id)
);
```

Заполнение справочника данными:

```sql
insert into public.shipping_country_rates
(shipping_country, shipping_country_base_rate)
select distinct
	shipping_country,
	shipping_country_base_rate
from public.shipping;
```



2. **Создайте справочник тарифов доставки вендора по договору shipping_agreement из данных строки vendor_agreement_description через разделитель «:» (двоеточие без кавычек). Названия полей:** 
- agreementid (первичный ключ),
- agreement_number,
- agreement_rate,
- agreement_commission.

Создание таблицы:
```sql
create table shipping_agreement (
	agreementid bigint not null,
	agreement_number text null,
	agreement_rate numeric(14,2) null,
	agreement_commission numeric(14,2) null,
	constraint shipping_agreementid_pkey primary key (agreementid)
);
```

Заполнение таблицы данными:
```sql
insert into public.shipping_agreement
(agreementid, agreement_number, agreement_rate, agreement_commission)
select distinct
	 cast((regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[1] as bigint) AS agreementid,
	 (regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[2] AS agreement_number,
	 cast((regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[3] as numeric(14,2)) AS agreement_rate,
	 cast((regexp_split_to_array(sh.vendor_agreement_description, E'\\:+'))[4] as numeric(14,2)) AS agreement_commission
from public.shipping as sh;
```

3. **Создайте справочник о типах доставки shipping_transfer из строки shipping_transfer_description через разделитель «:» (двоеточие без кавычек). Названия полей:**
- transfer_type,
- transfer_model,
- shipping_transfer_rate.

    **Первичным ключом таблицы сделайте серийный id.**

Создание таблицы:
```sql
create table shipping_transfer (
	transfer_type_id serial not null,
	transfer_type text null,
	transfer_model text null,
	shipping_transfer_rate numeric(14,3) null,
	constraint shipping_transfer_type_id_pkey primary key (transfer_type_id)
);
```

Заполнение таблицы данными:
```sql
insert into public.shipping_transfer
(transfer_type, transfer_model, shipping_transfer_rate)
select distinct
	(regexp_split_to_array(sh.shipping_transfer_description , E'\\:+'))[1] AS transfer_type,
	(regexp_split_to_array(sh.shipping_transfer_description, E'\\:+'))[2] AS transfer_model,
	sh.shipping_transfer_rate
from public.shipping as sh;
```

4. **Создайте таблицу shipping_info — справочник комиссий по странам с уникальными доставками shippingid.Свяжите её с созданными справочниками shipping_country_rates, shipping_agreement, shipping_transfer и константной информации о доставке shipping_plan_datetime, payment_amount, vendorid.**

Создание таблицы:
```sql
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
```

Заполнение таблицы данными:
```sql
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
```

5. **Создайте таблицу статусов о доставке shipping_status. Включите туда информацию из лога shipping (status , state). Также добавьте туда вычислимую информацию по фактическому времени доставки shipping_start_fact_datetime и shipping_end_fact_datetime.Отразите для каждого уникального shippingid его итоговое состояние доставки.**

Создание таблицы:
```sql
create table shipping_status (
	shippingid int8 not null,
	status text null,
	state text null,
	shipping_start_fact_datetime timestamp null,
	shipping_end_fact_datetime timestamp null
);
```

Заполнение таблицы данными:
```sql
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
```

6. **Создайте представление shipping_datamart на основании готовых таблиц для аналитики и включите в него:**
- shippingid
- vendorid
- transfer_type — тип доставки из таблицы shipping_transfer
- full_day_at_shipping — количество полных дней, в течение которых длилась доставка.
    
    Высчитывается так: shipping_end_fact_datetime − shipping_start_fact_datetime
- is_delay — статус, показывающий просрочена ли доставка.
    
    Высчитывается так: shipping_end_fact_datetime  > shipping_plan_datetime → 1; 0
- is_shipping_finish — статус, показывающий, что доставка завершена. 
    
    Если финальный status = finished → 1; 0
- delay_day_at_shipping — количество дней, на которые была просрочена доставка.
    
    Высчитывается как: shipping_end_fact_datetime > shipping_plan_datetime → shipping_end_fact_datetime − shipping_plan_datetime; 0)
- payment_amount — сумма платежа пользователя
- vat — итоговый налог на доставку
    
    Высчитывается так: payment_amount ∗ (shipping_country_base_rate + agreement_rate + shipping_transfer_rate)
- profit — итоговый доход компании с доставки.
    
    Высчитывается как: payment_amount ∗ agreement_commission

Создание представления:
```sql
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
```