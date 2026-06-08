-- V000001_init.sql
CREATE TABLE schema_version (
    installed_rank INT PRIMARY KEY,
    version        VARCHAR(50),
    installed_on   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
