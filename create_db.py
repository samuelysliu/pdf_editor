"""Create the pdf_editor database in PostgreSQL if it doesn't exist."""
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT


def create_database_if_not_exists():
    """Connect to PostgreSQL and create the pdf_editor database."""
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        user="postgres",
        password="0000",
        dbname="postgres"
    )
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cursor = conn.cursor()

    # Check if database exists
    cursor.execute("SELECT 1 FROM pg_database WHERE datname = 'pdf_editor'")
    exists = cursor.fetchone()

    if not exists:
        cursor.execute("CREATE DATABASE pdf_editor")
        print("Database 'pdf_editor' created successfully!")
    else:
        print("Database 'pdf_editor' already exists.")

    cursor.close()
    conn.close()


if __name__ == "__main__":
    create_database_if_not_exists()
