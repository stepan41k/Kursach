#!/bin/bash

DB_CONTAINER="deploy-db-1"
DB_USER="user"
DB_NAME="mydb"
TEST_FILE="./tests.sql"

if [ ! "$(docker ps -q -f name=$DB_CONTAINER)" ]; then
    echo "ERROR: Container '$DB_CONTAINER' not running"
    exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: File '$TEST_FILE' not found"
    exit 1
fi


cat "$TEST_FILE" | docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1

if [ $? -eq 0 ]; then
    echo "All tests passed successfully"
else
    echo "Error while try to execute sql-script"
    exit 1
fi