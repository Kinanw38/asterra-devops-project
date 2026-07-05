import sys


def load_gis_libraries():
    """טעינת ספריות ה-GIS בצורה מבודדת כדי למנוע כפל שמות ושגיאות סקופ ועיצוב"""
    try:
        import geopandas as local_gpd
        from shapely.geometry import Point as LocalPoint  # תיקון: שמירה על CamelCase עבור קלאס

        print(f"[SYSTEM HEALTH CHECK] GeoPandas version: {local_gpd.__version__} is fully initialized.")
        return local_gpd, LocalPoint
    except ImportError as e:
        print(f"[HEALTH CHECK FAILED] Critical GIS dependencies missing! Error: {str(e)}")
        sys.exit(1)


# השמה גלובלית נקייה
gpd, Point = load_gis_libraries()


def execute_vector_sample_analysis():
    """הדגמת יכולת ניתוח ועיבוד של קובץ וקטורי גיאוגרפי מקומי בתוך סביבת ה-PaaS המבודדת"""
    print("[ANALYSIS] Running local geospatial vector processing job...")

    mock_data = {'name': ['Asterra_HQ', 'Tel_Aviv_Port'], 'geometry': [Point(34.90, 32.18), Point(34.77, 32.09)]}
    gdf = gpd.GeoDataFrame(mock_data, crs="EPSG:4326")

    print("[ANALYSIS OUTPUT] Vector matrix layout calculated successfully:")
    print(gdf)


if __name__ == "__main__":
    execute_vector_sample_analysis()