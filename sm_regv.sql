-- sm_regv 函数主要用于创建主版本，后续需要更多的分支，改为使用分支的函数，内部实现全部使用创建分支的函数
CREATE or REPLACE FUNCTION  public.sm_regv(tableName varchar, schemaName varchar DEFAULT 'public')
RETURNS BOOLEAN AS 
$$
    BEGIN
        RETURN public.sm_createbranche('trunk',tableName,schemaName);
    END;
$$
LANGUAGE "plpgsql";

-- 支持基于分支，以及分支的baseRev作为基础来创建分支
-- 默认为基于trunk，和head来创建，baseRev 为0时表示为 head
CREATE or REPLACE FUNCTION public.sm_createbranche(branchename VARCHAR, tableName VARCHAR,
    schemaName varchar DEFAULT 'public', commitmsg VARCHAR DEFAULT 'create branch', 
    baseBranche VARCHAR DEFAULT 'trunk', baseRev INTEGER DEFAULT 0)
RETURNS BOOLEAN AS
$$
DECLARE
    VTable CONSTANT varchar :='smsubversion';
    seqname CONSTANT VARCHAR :='smsubversion_rev_seq';
    revbegin VARCHAR := 'sm_%s_rev_begin';
    revend VARCHAR := 'sm_%s_rev_end';
    parent VARCHAR := 'sm_%s_parent';
    child VARCHAR := 'sm_%s_child';
    uncreated BOOLEAN := FALSE;
    baseExists BOOLEAN := FALSE;    
    brancheSchema VARCHAR := '%s_%s_rev_head';-- 分支的schema均以该格式命名
    baseRevBegin VARCHAR := 'sm_%s_rev_begin';
    baseRevEnd VARCHAR := 'sm_%s_rev_end';
    baseSchema VARCHAR :='%s_%s_rev_head';
    viewColumns VARCHAR;
    row RECORD;
    maxRev INTEGER;
    executeResult BOOLEAN;
BEGIN
    -- 如果该表已注册了历史管理，则注册失败，历史管理和版本管理不能共存,版本管理是基于svn和分支的历史管理能力
    EXECUTE format('select count(*) > 0 from information_schema.columns 
    where table_schema=%L and table_name = %L and column_name = %L',schemaName, tableName,'sm_from_date') INTO executeResult;
    IF(executeResult) THEN
        RAISE NOTICE 'the table %I.%I has been registed as history.', schemaName,tableName;
        RETURN FALSE;
    END IF;

    -- 全局惟一的版本id，与svn功能类似，使用序列来实现
    -- 如果subversion表不存在则直接返回，注册失败
    -- 创建trunk的schema，同时view使用public的数据集的名称
    -- 对注册了版本的表，需要增加记录版本信息所需要的字段，同时创建表示最新数据的视图

    -- 判断分支是否存在，如果存在则不创建
    -- 创建schema，以及视图用于显示当前分支最新的数据  

    -- 检查baseBranche的合法性,为基础分支为trunk时，可以没有对应的字段,属于新创建
    baseSchema = format(baseSchema,schemaName,baseBranche);
    baseRevBegin  := format(baseRevBegin,baseBranche);
    baseRevEnd := format(baseRevEnd,baseBranche);
    EXECUTE format('select count(*) > 0 from information_schema.columns
        where table_schema=%L and table_name=%L and column_name = %L',schemaName,tableName,baseRevBegin) INTO baseExists;

    IF(baseBranche != 'trunk' AND not baseExists ) THEN        
        RAISE NOTICE 'the base branche %I does not exist.',baseBranche;
        RETURN FALSE;
    END IF;
    -- 检查baseRev的合法性，不为0时，需要baseRev在库中存在
    EXECUTE format('select count(*) > 0 from %I.%I where branch = %L and rev = %s'
        ,schemaName,VTable, baseBranche, baseRev) INTO executeResult;
    IF(baseRev != 0 AND executeResult)  THEN
        raise notice 'the rev id %s does not exist in the brache %I',baseRev,baseBranche;
        RETURN FALSE;
    END IF;

    revbegin := format(revbegin,brancheName);
    revend := format(revend,brancheName);
    parent := format(parent,brancheName);
    child := format(child,brancheName);
    brancheSchema = format(brancheSchema,schemaName,brancheName);

    EXECUTE format('SELECT count(*) = 0 FROM pg_namespace WHERE nspname = %L limit 1', brancheSchema) 
        into uncreated;
    IF (uncreated) THEN
        EXECUTE format('CREATE SCHEMA %I',brancheSchema);
    ELSE
        -- 如果该表的该分支已存在则失败返回,根据现有的字段信息来判断
        EXECUTE format('select count(*) > 0 from information_schema.columns
        where table_schema=%L and table_name=%L and column_name = %L',schemaName,tableName,revbegin)
        INTO executeResult;
        if(executeResult) THEN
            raise notice '%',format('the branche %I of %I has been created.', brancheName, tableName);
            RETURN FALSE;
        END IF;
    END IF;

    -- 添加svn信息
    maxRev = nextval(seqname);
    IF(commitmsg='create branch') THEN
        commitmsg = format('create branch %L for %I.%I',brancheName,schemaName,tableName);
    END IF;
    
    EXECUTE format('INSERT INTO %I.%I(rev, commit_msg, branch,date,author) VALUES ( %s,%L,%L,now(),USER)',
        schemaName,VTable,maxRev,commitMsg,brancheName);

    -- 修改主表，创建字段
    viewColumns :='';
    FOR row in EXECUTE format('select column_name from information_schema.columns 
    where table_schema=%L and table_name = %L',schemaName, tableName)  LOOP
        IF(position('sm_' in row.column_name) != 1) THEN
            viewColumns := viewColumns || row.column_name || ' ,';
        ENd IF;
    END LOOP;
    viewColumns = rtrim(viewColumns, ',');


    EXECUTE format('ALTER TABLE %I.%I Add COLUMN %I INTEGER, Add COLUMN %I INTEGER, Add COLUMN %I INTEGER, Add COLUMN %I INTEGER',
        schemaName,tableName,revbegin,revend, parent, child);

    -- 更新字段内容， 分别有以下几种情况（trunk只是分支的一个特例）
    -- 1、该表新注册版本管理；2、根据现有分支的head创建新分支；3、根据现有分支的指定版本号创建分支
    IF (not baseExists) THEN
        --1、 该表新注册版本管理；创建分支的基础不存在时，此时忽略baseRev值
        EXECUTE format('UPDATE %I.%I Set %I= %s',schemaName,tableName,revbegin,maxRev);
    ELSE
        IF(baseRev = 0 ) THEN
            -- 2、根据现有分支的head创建新分支
            EXECUTE format('UPDATE %I.%I Set %I= %s
                    where %I IS NOT NULL AND %I IS  NULL'
                    ,schemaName,tableName,revbegin,maxRev,baseRevBegin,baseRevEnd);
        ELSE
            -- 3、根据现有分支的指定版本号创建分支
            EXECUTE format('UPDATE %I.%I Set %I= %s
                    WHERE  %I IS NOT NULL AND ( %I IS NULL OR %I > %s) '
                    ,schemaName,tableName,revbegin,rev,baseRevBegin,baseRevEnd,baseRev);
        END IF;    
    END IF;

    -- 在新的schema中创建与tableName相同的视图, 单引号使用%L, 双引号使用%I
    EXECUTE format('CREATE OR REPLACE VIEW %I.%I AS Select %s FROM %I.%I where %I is NULL and %I is Not NULL'
                ,brancheSchema,tableName,viewColumns,schemaName,tableName, revend, revbegin);

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';

