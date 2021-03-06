set search_path=public;
\set AUTOCOMMIT off

/* This file contains DDL for creating relational schema in PostgreSQL. We will also populate the reference tables with values. for some of the tables that uses serial data type, the serial data 
is adjusted to higher value so that it doesn't conflict with the migrated data from source */

CREATE TABLE cab_types (
  id serial primary key,
  type text
);

INSERT INTO cab_types (type) SELECT 'yellow';
INSERT INTO cab_types (type) SELECT 'green';
INSERT INTO cab_types (type) SELECT 'uber';
INSERT INTO cab_types (type) SELECT 'lyft';

create table car_model(id serial primary key,make varchar not null, model varchar);
insert into car_model(make,model) values('Toyota','SUV 2016');
insert into car_model(make,model) values('Honda','SEDAN 2016');
insert into car_model(make,model) values('Nissan','SEDAN 2016');
insert into car_model(make,model) values('Ford','TRUCK 2016');
insert into car_model(make,model) values('Subaru','SUV 2016');

create table payment_types (payment_id bigint primary key, name varchar(100) unique not null, description varchar(100));
insert into payment_types values (1,'Credit Card',null);
insert into payment_types values (2,'Cash',null);
insert into payment_types values (3,'No Charge',null);
insert into payment_types values (4,'Dispute',null);
insert into payment_types values (5,'Unknown',null);
insert into payment_types values (6,'Cancelled',null);
insert into payment_types values (7,'Bank Deposit',null);

create table trip_status (status varchar(100) unique not null,description varchar(100));
insert into trip_status(status) values ('Completed');
insert into trip_status(status) values ('Cancelled');
insert into trip_status(status) values ('Booked');
insert into trip_status(status) values ('In-progress');

create table rate_codes (rate_id bigint primary key, name varchar(100) unique not null);
insert into rate_codes values (1,'Standard rate');
insert into rate_codes values (2,'JFK');
insert into rate_codes values (3,'Newark');
insert into rate_codes values (4,'Nassau or Westchester');
insert into rate_codes values (5,'Negotiated fare');
insert into rate_codes values (6,'Group ride');
insert into rate_codes values (99,'Peak rate');


CREATE TABLE drivers(
   driver_id bigint PRIMARY KEY,
   driver_name VARCHAR (100)  NOT NULL,
   vehicle_id VARCHAR (50) UNIQUE  NOT NULL,
   make bigint  references car_model(id),
   driver_email VARCHAR (100) UNIQUE NOT NULL,
   created_on TIMESTAMP NOT NULL,
   driver_mobile varchar(100) NOT NULL,
   payment_id bigint not null references payment_types(payment_id),
   address varchar(1000),
   rating varchar(10),
   profile varchar(1000)
);

CREATE TABLE riders(
   rider_id bigint PRIMARY KEY,
   rider_name VARCHAR (100)  NOT NULL,
   rider_email VARCHAR (100) UNIQUE NOT NULL,
   created_on TIMESTAMP NOT NULL,
   payment_id bigint  not null references payment_types(payment_id),
   rider_mobile varchar(100) NOT NULL,
   address varchar(1000),
   rating varchar(10),
   profile varchar(1000)
);

CREATE TABLE billing(
   id serial primary key,
   driver_id bigint references drivers(driver_id),
   billing_cycle double precision default 1,
   billing_start timestamp without time zone,
   billing_end timestamp without time zone,
   billing_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
   billing_amount numeric(10,6),
   commissions numeric(10,6) default 0.2,
   description varchar(500),
   rides_total bigint,
   billing_status varchar(100)
);



CREATE TABLE payment(
   id serial primary key,
   billing_id bigint references billing(id),
   driver_id bigint references drivers(driver_id),
   billing_cycle double precision default 1,
   payment_amount numeric(10,6),
   payment_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
   payment_id bigint default 7 references payment_types(payment_id),
   payment_status varchar(100),
   description varchar(500)
);



create table trips(
  id serial primary key,
  rider_id bigint references riders(rider_id),
  driver_id bigint references drivers(driver_id),
  rider_name varchar(100),
  rider_mobile varchar(100),
  rider_email varchar(100) not null,
  trip_info varchar(100) not null,
  driver_name varchar(100),
  driver_email varchar(100),
  driver_mobile varchar(100),
  vehicle_id varchar(50),
  cab_type_id integer references cab_types(id),
  vendor_id integer,
  pickup_datetime timestamp without time zone,
  dropoff_datetime timestamp without time zone,
  store_and_fwd_flag varchar(100),
  rate_code_id bigint references rate_codes(rate_id),
  pickup_longitude DOUBLE PRECISION,
  pickup_latitude DOUBLE PRECISION,
  dropoff_longitude DOUBLE PRECISION,
  dropoff_latitude DOUBLE PRECISION,
  passenger_count DOUBLE PRECISION,
  trip_distance DOUBLE PRECISION,
  fare_amount DOUBLE PRECISION,
  extra DOUBLE PRECISION,
  mta_tax DOUBLE PRECISION,
  tip_amount DOUBLE PRECISION,
  tolls_amount DOUBLE PRECISION,
  ehail_fee DOUBLE PRECISION,
  improvement_surcharge DOUBLE PRECISION,
  total_amount DOUBLE PRECISION,
  payment_type bigint references payment_types (payment_id),
  trip_type integer,
  pickup_location_id integer,
  dropoff_location_id integer,
  status varchar(100) references trip_status(status),
unique (rider_email,trip_info)
);
 SELECT pg_catalog.setval(pg_get_serial_sequence('trips', 'id'),max(2000000));
 SELECT pg_catalog.setval(pg_get_serial_sequence('billing', 'id'),max(200000));
 SELECT pg_catalog.setval(pg_get_serial_sequence('payment', 'id'),max(200000));
 
create sequence billing_cycle_seq start with 2;

CREATE or REPLACE PROCEDURE billingandpayments()
LANGUAGE plpgsql
as $$
DECLARE
        t RECORD;
        l_sequence integer;
        l_count integer;
        l_rcount integer;
BEGIN

    select count(*) into l_count from trips where dropoff_datetime < current_date+1 and dropoff_datetime > current_date and status = 'Completed';

    RAISE NOTICE 'Found % trip(s) record to be processed for billing', l_count;

    if (l_count > 0) then

        l_sequence := (SELECT nextval('billing_cycle_seq'));

        RAISE NOTICE 'Running Billing Cycle # %', l_sequence;

        insert into billing (driver_id, billing_cycle, billing_start, billing_end, billing_amount, commissions, rides_total, description, billing_status)
        select driver_id, l_sequence, current_date, current_date+1, sum(total_amount), 0.8, count(*), 'billing cycle ' || l_sequence, 'Completed'
        from trips
        where dropoff_datetime < current_date+1 and dropoff_datetime > current_date and status = 'Completed'
        group by driver_id;

        GET DIAGNOSTICS l_rcount = ROW_COUNT;

        RAISE NOTICE 'Inserted % record(s) into billing table', l_rcount;

        insert into payment(billing_id,driver_id,billing_cycle,payment_amount,payment_date, payment_id, payment_status,description)
        select a.id, a.driver_id, a.billing_cycle,sum(a.billing_amount*a.commissions),a.billing_date, b.payment_id, 'Completed','Payment Cycle ' || to_char(transaction_timestamp(),'FMMonth YYYY')
        from billing a, drivers b
        where a.driver_id=b.driver_id and a.billing_cycle = l_sequence and a.billing_status = 'Completed'
        group by a.id, a.driver_id, a.billing_cycle, a.billing_date, b.payment_id;

        GET DIAGNOSTICS l_rcount = ROW_COUNT;

        RAISE NOTICE 'Inserted % record(s) into payment table', l_rcount;

        update trips set status = 'Processed'
        where dropoff_datetime < current_date+1 and dropoff_datetime > current_date and status = 'Completed';

        GET DIAGNOSTICS l_rcount = ROW_COUNT;

        RAISE NOTICE 'Updated % record(s) in trips table and marked status as Processed', l_rcount;

        update billing set billing_status = 'Processed'
        where billing_cycle = l_sequence and billing_status = 'Completed';

        GET DIAGNOSTICS l_rcount = ROW_COUNT;

        RAISE NOTICE 'Updated % record(s) in billing table and marked status as Processed', l_rcount;

        RAISE NOTICE 'Billing Cycle # % Completed Successfully', l_sequence;

    else

            RAISE NOTICE 'No records found to be processed for billing. Exiting...';

    end if;

exception when others then
  raise;

END;
$$;

commit;
\dt
       
