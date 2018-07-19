-- 创建表，然后添加记录，接着修改看看情况
-- create table pois (
--     id INT PRIMARY KEY,
--     child INT REFERENCES pois(id) on UPDATE CASCADE on  DELETE CASCADE,
--     parent INT
-- )

-- TRUNCATE table pois; 
-- insert into pois (id) values  (1);
-- insert into pois (id) values  (2);
-- insert into pois (id) values  (3);

-- update pois set child = 3 where id =2;
-- select * from pois;


-- delete from pois where id = 1;
-- select * from pois;

-- BEGIN
-- select sm_regh('pois');
-- ROLLBACK
-- drop VIEW pois_vw;
-- alter table pois drop column sm_opr_type CASCADE, drop column sm_user CASCADE, drop column sm_from_date CASCADE, drop column sm_to_date,
-- drop column sm_parent_id CASCADE, drop column sm_child_id CASCADE;

-- insert into pois_vw (id)  values(2);
-- insert into pois_vw (id)  values(3);

-- update  pois_vw set id = 10 where id = 3;
-- delete from pois_vw where id = 4;
-- TODO: 测试中文表名，字段名的情况; 在字段添加需要处理字段添加事件，然后修改视图，以及函数；ID可以赋值的情况下，不能重新计算一个ID

-- TODO： svn使用关联表来记录提交的时间，不记录每次编辑所提交的时间，历史时态，与版本管理为两功能来处理

-- select sm_enableSvn();
select sm_regv('pois');
-- select reset('pois');

-- DROP FUNCTION sm_createbranche(character varying,character varying,character varying,character varying,integer)
-- drop function sm_regv(tablename character varying);
-- drop function sm_regv(tablename character varying, schemaname character varying);
-- drop function sm_createbranche(branchename character varying, tablename character varying);
-- drop function sm_createbranche(branchename character varying, tablename character varying, schemaname character varying);
-- DROP FUNCTION sm_createbranche(character varying,character varying,character varying,character varying,integer)
-- \df sm_createbranche
-- \df sm_regv

-- drop schema public_trunk_rev_head cascade;
-- alter table pois drop column sm_from_date CASCADE, drop column sm_to_date CASCADE ,drop column sm_parent_id CASCADE, drop column sm_child_id CASCADE,
-- drop column sm_trunk_rev_begin CASCADE, drop column sm_trunk_rev_end CASCADE, drop column sm_trunk_parent CASCADE

-- TODO: 需要写删除数据，回退用的函数


