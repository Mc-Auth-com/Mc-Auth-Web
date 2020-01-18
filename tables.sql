CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "plpgsql";

/* Sequences */
CREATE SEQUENCE "public"."application_id_sequence" 
INCREMENT 1
MINVALUE  1
MAXVALUE 9223372036854775807
START 1
CACHE 1;

CREATE SEQUENCE "public"."secret_id_sequence" 
INCREMENT 1
MINVALUE  1
MAXVALUE 9223372036854775807
START 1
CACHE 1;

CREATE SEQUENCE "public"."grant_id_sequence" 
INCREMENT 1
MINVALUE  1
MAXVALUE 9223372036854775807
START 1
CACHE 1;

/* Function: id_generator_apps */
CREATE OR REPLACE FUNCTION "public"."id_generator_apps"(OUT "result" int8)
  RETURNS "pg_catalog"."int8" AS $BODY$
DECLARE
    our_epoch bigint := 1314220021721;
    seq_id bigint;
    now_millis bigint;
    -- the id of this DB shard, must be set for each
    -- schema shard you have - you could pass this as a parameter too
    shard_id int := 1;
BEGIN
    SELECT nextval('public.application_id_sequence') % 1024 INTO seq_id;

    SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000) INTO now_millis;
    result := (now_millis - our_epoch) << 23;
    result := result | (shard_id << 10);
    result := result | (seq_id);
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

/* Function: id_generator_secrets */
CREATE OR REPLACE FUNCTION "public"."id_generator_secrets"(OUT "result" int8)
  RETURNS "pg_catalog"."int8" AS $BODY$
DECLARE
    our_epoch bigint := 1314220021721;
    seq_id bigint;
    now_millis bigint;
    -- the id of this DB shard, must be set for each
    -- schema shard you have - you could pass this as a parameter too
    shard_id int := 1;
BEGIN
    SELECT nextval('public.secret_id_sequence') % 1024 INTO seq_id;

    SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000) INTO now_millis;
    result := (now_millis - our_epoch) << 23;
    result := result | (shard_id << 10);
    result := result | (seq_id);
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;


/* Function: id_generator_grants */
CREATE OR REPLACE FUNCTION "public"."id_generator_grants"(OUT "result" int8)
  RETURNS "pg_catalog"."int8" AS $BODY$
DECLARE
    our_epoch bigint := 1314220021721;
    seq_id bigint;
    now_millis bigint;
    -- the id of this DB shard, must be set for each
    -- schema shard you have - you could pass this as a parameter too
    shard_id int := 1;
BEGIN
    SELECT nextval('public.grant_id_sequence') % 1024 INTO seq_id;

    SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000) INTO now_millis;
    result := (now_millis - our_epoch) << 23;
    result := result | (shard_id << 10);
    result := result | (seq_id);
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

/* Function: random_string */
CREATE OR REPLACE FUNCTION "public"."random_string"("length" int4)
  RETURNS "pg_catalog"."varchar" AS $BODY$
declare
  chars text[] := '{0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z}';
  result varchar := '';
  i integer := 0;
begin
  for i in 1..length loop
    result := result || chars[1+random()*(array_length(chars, 1)-1)];
  end loop;
  return result;
end;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

/* otp */
CREATE TABLE "public"."otp" (
  "minecraft" uuid NOT NULL,
  "code" int4 NOT NULL,
  "issued" timestamptz(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "otp_pkey" PRIMARY KEY ("minecraft")
);

/* session */
CREATE TABLE "public"."session" (
  "sid" varchar COLLATE "pg_catalog"."default" NOT NULL,
  "sess" json NOT NULL,
  "expire" timestamp(6) NOT NULL,
  CONSTRAINT "session_pkey" PRIMARY KEY ("sid")
);
CREATE INDEX "IDX_session_expire" ON "public"."session" USING btree("expire" "pg_catalog"."timestamp_ops" ASC NULLS LAST);

/* images */
CREATE TABLE "public"."images" (
  "id" int8 NOT NULL GENERATED BY DEFAULT AS IDENTITY (INCREMENT 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1),
  "optimized" bytea NOT NULL,
  "original" bytea NOT NULL,
  CONSTRAINT "images_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "idx_image_hash" ON "public"."images" USING btree(digest(original, 'sha1' :: text) "pg_catalog"."bytea_ops" ASC NULLS LAST);

/* applications */
CREATE TABLE "public"."applications" (
  "id" int8 NOT NULL DEFAULT id_generator_apps(),
  "owner" uuid NOT NULL,
  "name" varchar(128) COLLATE "pg_catalog"."default" NOT NULL,
  "description" varchar(512) COLLATE "pg_catalog"."default",
  "icon" int8,
  "redirect_uris" json,
  "secret" varchar(255) COLLATE "pg_catalog"."default" DEFAULT concat(random_string(8), '.', id_generator_secrets(), '.', random_string(4)),
  "verified" bool NOT NULL DEFAULT false,
  "deleted" bool NOT NULL DEFAULT false,
  "created" timestamptz(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "applications_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "applications_icon_fkey" FOREIGN KEY ("icon") REFERENCES "public"."images" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION
);

/* grants */
CREATE TYPE "public"."GrantResult" AS ENUM (
  'NONE',
  'GRANTED',
  'DENIED',
  'REVOKED'
);

CREATE TABLE "public"."grants" (
  "id" int8 NOT NULL DEFAULT id_generator_grants(),
  "application" int8 NOT NULL,
  "mc_uuid" uuid NOT NULL,
  "result" "public"."GrantResult" NOT NULL DEFAULT 'NONE'::"GrantResult",
  "scope" json,
  "state" varchar(128) COLLATE "pg_catalog"."default",
  "access_token" varchar(32) COLLATE "pg_catalog"."default",
  "exchange_token" varchar(32) COLLATE "pg_catalog"."default" NOT NULL DEFAULT random_string(32),
  "redirect_uri" varchar(255) COLLATE "pg_catalog"."default" NOT NULL,
  "issued" timestamptz(0) DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "grants_pkey" PRIMARY KEY ("exchange_token"),
  CONSTRAINT "grants_application_access_token_key" UNIQUE ("application", "access_token")
);