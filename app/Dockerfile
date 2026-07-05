FROM python:3.11-slim

WORKDIR /app

# התקנת ספריות מערכת חובה עבור חיבור ל-Postgres וספריות ה-GIS (GDAL ו-Proj עבור GeoPandas)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    libpq-dev \
    gdal-bin \
    libgdal-dev \
    proj-bin \
    && rm -rf /var/lib/apt/lists/*

# הגדרת משתני סביבה כדי שחבילות ה-Python יזהו את מיקומי ספריות ה-GDAL של המערכת
ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

CMD ["python", "app.py"]