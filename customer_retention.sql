/*
    Create tables
*/
create table first_purchases (
  first_purchase_date varchar(8),
  user_id int primary key,
  purchase_id varchar(15),
  venue_id varchar(11),
  product_line varchar(15)
);
create table purchases (
  purchase_date varchar(8),
  user_id int,
  purchase_id varchar(15),
  venue_id varchar(11),
  product_line varchar(15)
);


/*
    Delete first header import from CSV
*/
delete from first_purchases limit 1;
delete from purchases limit 1;


/*
    Create date_converted from date string
*/
alter table first_purchases add column date_converted date generated always as (str_to_date(first_purchase_date, '%d.%m.%y')) virtual;
alter table purchases add column date_converted date generated always as (str_to_date(purchase_date, '%d.%m.%y')) virtual;


/*
    Clean \r from product line in first_purchases table
*/
alter table first_purchases add column clean_product_line varchar(15) generated always as (replace(product_line, "\r", "")) virtual;


/*
    Create indexex for user_id in tables
*/
create index user_index on first_purchases (user_id);
create index user_index on purchases (user_id);


/*
    Count total user_id in tables
*/
select count(*) from first_purchases; -- There are 71257 user_id in first_purchases
select count(distinct user_id) from purchases; --There are 39744 distinct user_id in purchases


/*
    Check if there are user_id in purchases but not in first_purchases
*/
select count(*) from (select distinct user_id from purchases where user_id not in (select user_id from first_purchases)) t;
--There are 3311 distinct user_id in purchases but not in first_purchase
--retention of all product line can be calculated as (39744-3311)/(71257+3311)=0.4886


/*
    Create view of user_id not in first_purchases
*/
create view not_in_first_purchase as
select distinct user_id from purchases where user_id not in (select user_id from first_purchases);


/*
    Create view of user_id and earliest day that they order
*/
create view nifp_date_user_ids as
select min(date_converted) first_purchase_date, user_id from purchases where user_id in (select * from not_in_first_purchase) group by 2;


/*
    Create view join user_id, first_purchase_date from nifp_date_user_ids and product_line from purchases
*/
create view first_purchases_second as
select n.first_purchase_date, n.user_id, max(p.product_line) product_line from nifp_date_user_ids n inner join purchases p 
on n.user_id = p.user_id and n.first_purchase_date = p.date_converted
group by 1, 2;


/*
    Calculate retention for each product line
*/
delimiter //
create procedure retention_percentage_from (in product varchar(15))
begin
    declare fp_num int;
    declare fps_num int;
    declare p_num int;
    set fp_num = (select count(*) from first_purchases where clean_product_line = product);
    set fps_num = (select count(*) from first_purchases_second where product_line = product);
    set p_num = (select count(distinct user_id) from purchases where product_line = product);
    select (p_num-fps_num)/(fp_num+fps_num)*100 retention_percentage;
end//
delimiter;


call retention_percentage_from("Restaurant"); --51.0354
call retention_percentage_from("Retail store"); --32.3009


/*
    Create cohort table by months
*/
with start_months as (
    select f.user_id, month(f.date_converted) first_month from first_purchases f
    union all
    select s.user_id, month(s.first_purchase_date) first_month from first_purchases_second s
),
user_activities as (
    select p.user_id, (month(p.date_converted) - s.first_month) month_period from purchases p
    left join start_months s on p.user_id = s.user_id
    group by 1, 2
),
cohort_size as (
    select first_month, count(user_id) num_users from start_months
    group by 1
),
retention_table as (
    select st.first_month, uc.month_period, count(uc.user_id) num_users from user_activities uc
    left join start_months st on st.user_id = uc.user_id
    group by 1, 2
)
select rt.first_month, cz.num_users as total_users, rt.month_period, rt.num_users total_repeators from retention_table rt
left join cohort_size cz on rt.first_month = cz.first_month
order by 1, 3;