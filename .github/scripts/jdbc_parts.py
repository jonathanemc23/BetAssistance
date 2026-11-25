"""Splits the DATABASE_URL secret into what the server needs: a JDBC address,
the user and the password, separated by tabs.

The secret is read by libpq (through psycopg), the same parser psql uses, so
whatever psql accepts the server gets too: a postgresql:// URL with or
without percent-encoded characters, or the key=value form. Always over SSL.
Supabase's transaction pooler (port 6543) breaks the server's prepared
statements, so it is refused: use the session pooler (5432).
"""
import sys

from psycopg.conninfo import conninfo_to_dict

url = sys.argv[1].strip()
if url.startswith("jdbc:"):
    url = url[len("jdbc:"):]
c = conninfo_to_dict(url)
host, port, db = c.get("host"), c.get("port") or "5432", c.get("dbname") or "postgres"
if not host or not c.get("user") or not c.get("password"):
    sys.exit("DATABASE_URL needs a host, a user and a password")
if port == "6543":
    sys.exit("DATABASE_URL uses the transaction pooler (6543); use the session pooler (5432)")
sslmode = c.get("sslmode") or "require"
print(f"jdbc:postgresql://{host}:{port}/{db}?sslmode={sslmode}", c["user"], c["password"], sep="\t")
