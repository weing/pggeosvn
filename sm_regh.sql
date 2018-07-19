-- 对数据集组成历史信息，即添加对象创建时间字段，消亡时间字段，对象的父、子ID，支持普通表和几何对象表
-- 要求表有ID字段，通过视图查看最新数据，以及对对象进行增删改操作，视图的记录触发器记录对应的系统字段
-- 表用于存储对象的所有记录，以便进行更详细的历史回看
CREATE or REPLACE FUNCTION  public.sm_regh(tablename varchar)
RETURNS BOOLEAN AS
$$
BEGIN
    RETURN public.sm_regh(tablename,'public');
END
$$
LANGUAGE 'plpgsql';

CREATE or REPLACE FUNCTION  public.sm_regh(tableName varchar, schemaname varchar)
RETURNS BOOLEAN AS 
$$
DECLARE
    keyname VARCHAR :='';
    keyType VARCHAR :='';
    sqlcommond VARCHAR := '';
    tableStr VARCHAR :='';
    hasreg BOOLEAN := FALSE;
    row RECORD;
    viewColumns VARCHAR;
    viewName VARCHAR;
    updatefuc VARCHAR;
    deletefuc VARCHAR;
    insertfuc VARCHAR;
    updateCol VARCHAR;
    keyword VARCHAR;
BEGIN
    tableStr := '"' || schemaname|| '"."' || tableName || '"';
    EXECUTE format('select count(*) > 0 from information_schema.columns
        where table_schema=%L and table_name=%L and column_name = ''sm_from_date''',schemaname,tableName)
    INTO hasreg;
    -- 查询是否已注册历史表
    IF(hasreg) THEN
        RETURN TRUE;
    END IF;

    -- 判断是否存在主键，没有则注册失败
    sqlcommond := format('SELECT a.attname as column_name, format_type(a.atttypid,a.atttypmod)
    FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) 
    WHERE i.indrelid = %L::regclass AND i.indisprimary',tableStr);

    EXECUTE sqlcommond into keyname,keyType;
    IF(keyname is null) THEN
        raise notice '%', 'the '||tableStr||' does not have a primary key.';
        RETURN FALSE;
    END IF;
-- TODO：对于 sm_parent_id, sm_child_id 可以通过' REFERENCES '|| tableStr||'("'|| keyname ||'") ON UPDATE CASCADE ON DELETE CASCADE' 增加强依赖
-- 考虑到强依赖会影响性能，另外也会引起后续数据紧缩时，因为删除过期的父对象导致子
-- 单引号和|| 之间需要增加空格
   
    -- INTO rows;
    viewColumns :='';
    updateCol = '';
    FOR row in EXECUTE format('select column_name from information_schema.columns 
    where table_schema=%L and table_name = %L',schemaname, tablename)  LOOP
        IF(row.column_name != keyname) THEN
            viewColumns := viewColumns || row.column_name || ' ,';
            updateCol := updateCol || 'NEW.' || row.column_name || ' ,';
        END IF;
    END LOOP;
    -- 
    viewColumns = rtrim(viewColumns, ',');
    updateCol = rtrim(updateCol,',');
    
    -- raise notice '%', updateCol;
    sqlcommond := 'ALTER TABLE ' || tableStr || ' ADD COLUMN sm_opr_type text, Add COLUMN sm_user text, 
        ADD COLUMN sm_from_date TIMESTAMP, ADD COLUMN sm_to_date TIMESTAMP, ADD COLUMN sm_parent_id ' || keyType || ',
        ADD COLUMN sm_child_id ' || keyType;

    EXECUTE sqlcommond;

    -- 创建视图，用于返回最新的数据
    viewName := (tablename || '_vw');
    sqlcommond := format('create or REPLACE VIEW %s.%s as select %s from %s where sm_to_date is NULL OR sm_to_date >= now();'
                    ,quote_ident(schemaname),quote_ident(viewName),keyname || ', ' ||viewColumns,quote_ident(tablename));

    EXECUTE sqlcommond;

    keyword := '$' || '$';
    -- 创建数据添加删除函数
    deletefuc :='sm_' || viewName || '_del';
    insertfuc :='sm_' || viewName || '_insert';
    updatefuc := 'sm_' || viewName || '_update';

    sqlcommond := 'CREATE or REPLACE FUNCTION ' || schemaname || '.' || deletefuc || '()
        RETURNS TRIGGER AS
        ' || keyword || '
        BEGIN
            UPDATE ' || schemaname || '.' || tablename || ' set  (sm_to_date,sm_user,sm_opr_type) = (now(), USER, TG_OP) 
            WHERE ' || keyname || '=OLD.' || keyname || ';
            RETURN NULL;
        END;'
        || keyword || '
        LANGUAGE "plpgsql";
    CREATE or REPLACE  FUNCTION ' || schemaname || '.' || insertfuc || '()
        RETURNS TRIGGER AS
        ' || keyword || '
        DECLARE
            newID INTEGER :=0;
        BEGIN
            -- 如果ID为null，则自动计算一个
            IF NEW.' || keyname || ' is NULL THEN
                newID := (select max(' || keyname || ') from ' || schemaname || '.' ||tablename || ') +1;
            ELSE
                newID := NEW.' || keyname|| ';
            END IF;
            INSERT INTO ' || schemaname || '.' || tablename || '(' || keyname || ', ' || viewColumns || ',sm_from_date,sm_to_date,sm_user,sm_opr_type)
            VALUES (newID, ' || updatecol || ', now(),NULL,USER,TG_OP);
            RETURN NEW;
        END;'
        || keyword || '
        LANGUAGE "plpgsql";
    CREATE or REPLACE FUNCTION ' || schemaname || '.' ||updatefuc || '()
        RETURNS TRIGGER AS
        ' || keyword || '
            DECLARE
            newID INTEGER :=0;
        BEGIN
            -- 更新是标记旧的过时，然后插入一条新的    
            newID := (select max(' || quote_ident(keyname) || ') from ' || schemaname || '.' ||tablename || ') +1;
            UPDATE  ' || schemaname || '.' ||tablename || ' set  (sm_to_date,sm_user,sm_opr_type,sm_child_id) = (now(), USER, TG_OP,newID)
            WHERE ' || quote_ident(keyname) || ' = OLD.' || quote_ident(keyname) || ';
            INSERT INTO ' || schemaname || '.' || tablename || '(' || quote_ident(keyname) || ', ' || viewColumns || ', sm_from_date,sm_to_date,sm_user,sm_opr_type,sm_parent_id)
            VALUES ( newID, ' || updatecol || ', now(),NULL,USER,TG_OP,OLD.' || quote_ident(keyname) || ');
            RETURN NEW;
        END;'
        || keyword || '
        LANGUAGE "plpgsql";';

     EXECUTE sqlcommond;
    raise notice '%', sqlcommond;

    -- 创建触发器
    sqlcommond := 'CREATE TRIGGER delete_' || viewName || '
        INSTEAD OF DELETE
        ON ' || viewName || '
        FOR EACH ROW
        EXECUTE PROCEDURE ' || schemaname || '.' ||deletefuc|| '();
        CREATE TRIGGER insert_' || viewName || '
        INSTEAD OF INSERT
        ON '|| viewName || '
        FOR EACH ROW
        EXECUTE PROCEDURE ' ||  schemaname || '.' ||insertfuc || '();
        CREATE TRIGGER update_' || viewName || '
        INSTEAD OF UPDATE
        ON ' || viewName || '
        FOR EACH ROW
        EXECUTE PROCEDURE ' ||  schemaname || '.' ||updatefuc || '();';

    EXECUTE sqlcommond;
    -- raise notice '%', sqlcommond;

    RETURN TRUE;
END;
$$
LANGUAGE "plpgsql";