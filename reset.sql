-- 用于删除注册版本和历史对应的内容,使得表回复到原始状态，方便进行第二轮测试
-- 删除的内容包括，版本管理用的字段和视图；历史管理用的字段、视图，触发器

create or replace function reset(tableName varchar, schemaName varchar default 'public')
RETURNS BOOLEAN AS
$$
DECLARE
    VTable CONSTANT varchar :='smsubversion';
    SchemaFormat CONSTANT varchar :='%s_%s_rev_head';
    dropColumns VARCHAR;
    executeResult BOOLEAN;
    brancheSchema VARCHAR; -- 分支的schema均以该格式命名
    brancheName Record;
    row Record;
BEGIN
  

    -- 注册的是历史管理
    EXECUTE format('select count(*) > 0 from information_schema.columns 
    where table_schema=%L and table_name = %L and column_name = %L',schemaName, tableName,'sm_from_date') INTO executeResult;
    IF(executeResult) THEN
        -- 删除视图，及视图对应的触发函数
        EXECUTE format('Drop view %I.%I CASCADE',schemaName,tableName || '_vw');
    END IF;

    -- 如果注册了版本信息，删除对应的内容后
    FOR brancheName in EXECUTE format('select subString(column_name, ''sm_(.{1,})_rev_begin'') as name from information_schema.columns 
    where table_schema=%L and table_name = %L and column_name = %L',schemaName, tableName,'sm_%_rev_begin') LOOP
        -- 计算出版本的名称，然后到对应的shcema中删除对应的视图
        brancheSchema = format(SchemaFormat,brancheName.name);
        EXECUTE format('Drop view %I.%I CASCADE',brancheSchema,tableName);
    END LOOP;

    -- 删除表中sm开头的系统字段
    dropColumns :='';
    FOR row in EXECUTE format('select column_name from information_schema.columns 
    where table_schema=%L and table_name = %L AND column_name like %L',schemaName, tableName,'sm_%')  LOOP
        dropColumns := dropColumns || ' DROP COLUMN ' || quote_ident(row.column_name) || ' CASCADE ,';
    END LOOP;
    dropColumns = rtrim(dropColumns, ',');

    EXECUTE format('Alter table %I.%I %s',schemaName,tableName,dropColumns);

    -- 同时添加一条记录在smreversions表中添加记录
        EXECUTE format('INSERT INTO %I.%I(commit_msg, branch,date,author) VALUES (%L,%L,now(),USER)',
        schemaName,VTable,'reset the table ' || schemaName || '.' || tableName ,'trunk');

    RETURN TRUE;
END;
$$
LANGUAGE 'plpgsql'