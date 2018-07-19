-- checkout到新的工作目录中进行编辑，这里需要考虑支持离线spatialite的情况，离线spatialite只能通过C++程序来实现
-- 原型只考虑支持当前库创建一个schema的方式来开展
set plpgsql.extra_warnings to 'all';
set plpgsql.extra_errors to 'all';

-- 最后一个为可变参数
CREATE or REPLACE FUNCTION  public.sm_co(workingCopy varchar,schemaName varchar, VARIADIC tableNames varchar[])
RETURNS BOOLEAN AS 
$$
DECLARE 
    isvalid BOOLEAN :=1;
BEGIN
    isvalid := ((SELECT schema_name FROM information_schema.schemata WHERE schema_name = workingCopy) == NULL);
    IF (isvalid) THEN
        --创建schema，同时创建表和视图
        CREATE SCHEMA  workingCopy;
        -- SELECT quote_ident(a.attname) as column_name FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) WHERE i.indrelid = '"public"."building"'::regclass AND i.indisprimary;
        -- SELECT DISTINCT branch FROM public.revisions;
        -- SELECT MAX(rev) FROM public.revisions;
        -- SELECT MAX(id) FROM public.building;
    END IF;
    RETURN isvalid;
END;
$$
LANGUAGE "plpgsql";