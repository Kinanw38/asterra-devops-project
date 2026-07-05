import os
import json
import time
import boto3
import psycopg2

# אתחול קליינטים רשמיים של AWS - הגישה מאובטחת ומבוססת על ה-IAM Instance Profile של השרת
s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager', region_name=os.environ.get('AWS_REGION', 'us-east-1'))


def get_db_credentials():
    """שליפת פרטי הגישה המאובטחים של בסיס הנתונים מתוך ה-Secrets Manager בזמן ריצה"""
    secret_name = os.environ.get('SECRET_NAME')
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        print(f"[ERROR] Failed to fetch secrets from Secrets Manager: {str(e)}")
        raise e


def init_spatial_database(conn):
    """אתחול בסיס הנתונים: הפעלת הרחבת PostGIS הגיאוגרפית ויצירת טבלת היעד המרחבית"""
    cursor = conn.cursor()
    # הפעלת הרחבת הניתוח המרחבי הנדרשת במפורש בדרישות המטלה של Asterra[cite: 1]
    cursor.execute("CREATE EXTENSION IF NOT EXISTS postgis;")

    # יצירת טבלה התומכת בעמודת גיאומטריה מבוססת היטל SRID 4326 (WGS 84 הסטנדרטי לקבצי GeoJSON)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS asterra_spatial_features (
            id SERIAL PRIMARY KEY,
            file_name VARCHAR(255),
            properties JSONB,
            geom GEOMETRY(Geometry, 4326),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    conn.commit()
    print("[INFO] Database spatial extension and targets initialized successfully.")


def process_geojson_file(bucket, key, conn):
    """הורדת קובץ ה-GeoJSON מהבאקט, ביצוע ולידציה קפדנית על המבנה שלו, והזרקתו לטבלה בעזרת שאילתה מרחבית"""
    print(f"[INFO] Starting data ingestion workflow for file: {key}")

    # משיכת הקובץ מתוך באקט ה-S3 ישירות לזיכרון הריצה של האפליקציה
    obj = s3_client.get_object(Bucket=bucket, Key=key)
    file_content = obj['Body'].read().decode('utf-8')

    try:
        geojson_data = json.loads(file_content)
    except json.JSONDecodeError:
        print(f"[VALIDATION FAILED] File {key} does not contain a valid JSON format structure.")
        return False

    # אימות שהקובץ המועלה אכן עונה על הסטנדרט המבני הרשמי של פורמט GeoJSON
    if "type" not in geojson_data or "features" not in geojson_data:
        print(f"[VALIDATION FAILED] File {key} is missing essential GeoJSON structural metadata blocks.")
        return False

    cursor = conn.cursor()
    success_count = 0

    for feature in geojson_data.get('features', []):
        geometry = feature.get('geometry')
        properties = feature.get('properties', {})

        if not geometry:
            continue

        # שימוש בפונקציה המובנית ST_GeomFromGeoJSON של PostGIS כדי להמיר את מחרוזת ה-JSON לאובייקט גיאומטרי במפת ה-DB
        geom_json_str = json.dumps(geometry)
        query = """
            INSERT INTO asterra_spatial_features (file_name, properties, geom)
            VALUES (%s, %s, ST_SetSRID(ST_GeomFromGeoJSON(%s), 4326));
        """
        try:
            cursor.execute(query, (key, json.dumps(properties), geom_json_str))
            success_count += 1
        except Exception as insert_err:
            print(f"[ERROR] Ingestion step failed for a specific feature node: {str(insert_err)}")
            conn.rollback()
            continue

    conn.commit()
    print(f"[SUCCESS] Ingestion pipeline finalized. Inserted {success_count} valid spatial features to RDS.")
    return True


def main_polling_loop():
    """לולאת האזנה רציפה (Polling Worker Pattern) המנטרת את ה-S3 ומעבדת קבצים חדשים (מתאים ומותאם ל-Free Tier)"""
    print("[START] Ingestion Core Worker service is online and listening for data landing events...")

    bucket_name = os.environ.get('INGEST_BUCKET_NAME')
    db_endpoint = os.environ.get('DB_ENDPOINT', 'localhost').split(':')[0]
    creds = get_db_credentials()

    conn = psycopg2.connect(
        host=db_endpoint,
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password'],
        port=5432
    )

    init_spatial_database(conn)
    processed_files = set()

    while True:
        try:
            response = s3_client.list_objects_v2(Bucket=bucket_name)
            if 'Contents' in response:
                for item in response['Contents']:
                    file_key = item['Key']
                    if file_key.endswith('.geojson') and file_key not in processed_files:
                        success = process_geojson_file(bucket_name, file_key, conn)
                        if success:
                            processed_files.add(file_key)
            time.sleep(10)
        except Exception as loop_err:
            print(f"[CRITICAL WORKER ERROR] Exception detected inside execution loop: {str(loop_err)}")
            time.sleep(15)


if __name__ == "__main__":
    main_polling_loop()