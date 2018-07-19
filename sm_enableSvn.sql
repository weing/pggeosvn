-- 对数据库启用版本管理
-- 对某个schema启用版本管理,会在该schema中创建subversion表，用于记录当前schema的版本号
-- 默认情况
CREATE OR REPLACE FUNCTION public.sm_enableSvn()
RETURNS BOOLEAN AS
$$
BEGIN
    RETURN public.sm_enableSvn('public');
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION public.sm_enableSvn(schemaname varchar)
RETURNS BOOLEAN AS
$$
DECLARE
    VTable CONSTANT varchar :='smsubversion';
    seqname CONSTANT VARCHAR :='smsubversion_rev_seq';
    VTPK CONSTANT varchar :=VTable ||'_pkey' ;
    isCreated boolean := TRUE;
    createsql VARCHAR :='';
    name VARCHAR :='';
BEGIN
    -- 判断VTable是否存在，不存在则创建之
    isCreated := (SELECT count(*) FROM information_schema.tables WHERE table_schema= schemaname  and table_name=VTable) != 0;
    IF(not isCreated) THEN
    -- 创建序列，创建表
        name :=quote_ident(schemaname)||'.'||quote_ident(VTable) ;
        createsql := 'create sequence ' || quote_ident(schemaname) || '.'|| seqname ||' increment by 1 minvalue 1 no maxvalue start with 1;';
        createsql := createsql || 'CREATE TABLE '|| name || ' 
            (
                rev integer NOT NULL DEFAULT nextval(''' || seqname || '''),
                commit_msg varchar ,
                branch varchar,
                date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
                author varchar ,
                CONSTRAINT VTPK PRIMARY KEY (rev)
            );';        
        EXECUTE(createsql);
        -- 添加初始化版本记录
        EXECUTE format('INSERT INTO %I.%I(commit_msg, branch,date,author) VALUES (%L,%L,now(),USER)',
        schemaName,VTable,'initialize subversion.' ,'trunk');
    END IF;
    RETURN not isCreated;
END;
$$
LANGUAGE 'plpgsql'; 