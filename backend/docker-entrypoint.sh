#!/bin/sh
# Neon and Render hand out the database as postgresql://user:password@host/db?params;
# Spring wants the JDBC address with the user and password apart.
case "$DATABASE_URL" in
  postgres://*|postgresql://*)
    rest=${DATABASE_URL#*://}
    creds=${rest%%@*}
    export DATABASE_URL="jdbc:postgresql://${rest#*@}"
    export DATABASE_USER="${DATABASE_USER:-${creds%%:*}}"
    export DATABASE_PASSWORD="${DATABASE_PASSWORD:-$(printf '%s' "${creds#*:}" | sed 's/%40/@/g; s/%3A/:/g; s/%2F/\//g; s/%25/%/g')}"
    ;;
esac
# Small free hosts have 512 MB: keep the heap inside it.
exec java -XX:MaxRAMPercentage=70 -XX:+UseSerialGC -Xss512k -jar /app/app.jar
