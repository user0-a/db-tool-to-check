-- V000002_create_users.sql
CREATE TABLE different_users (
    id       BIGINT PRIMARY KEY,
    email    VARCHAR(255) NOT NULL UNIQUE,
    created  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
