/* 00_create_database.sql — БД для 4 таблиц, 1M+ строк.
   RCSI без NOLOCK, SIMPLE recovery для быстрой загрузки. */

IF DB_ID(N'test_sql_join') IS NOT NULL
BEGIN
    ALTER DATABASE test_sql_join SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE test_sql_join;
END
GO

CREATE DATABASE test_sql_join;
GO

ALTER DATABASE test_sql_join SET RECOVERY SIMPLE;
ALTER DATABASE test_sql_join SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE test_sql_join SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE test_sql_join SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE test_sql_join SET MULTI_USER;
GO

ALTER DATABASE test_sql_join MODIFY FILE (NAME = N'test_sql_join',     SIZE = 512MB, FILEGROWTH = 128MB);
ALTER DATABASE test_sql_join MODIFY FILE (NAME = N'test_sql_join_log', SIZE = 256MB, FILEGROWTH = 128MB);
GO

PRINT '>>> 00: БД test_sql_join готова.';
GO
