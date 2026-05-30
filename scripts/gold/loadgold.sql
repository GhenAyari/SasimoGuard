-- 1. Mengisi Dimensi Waktu
INSERT INTO gold.dim_waktu (tanggal, tahun, bulan, hari)
SELECT DISTINCT 
    tanggal, 
    EXTRACT(YEAR FROM tanggal), 
    EXTRACT(MONTH FROM tanggal), 
    EXTRACT(DAY FROM tanggal)
FROM silver.crm_gempa_cleaned;

-- 2. Mengisi Dimensi Lokasi
INSERT INTO gold.dim_lokasi (latitude, longitude, wilayah)
SELECT DISTINCT latitude, longitude, wilayah
FROM silver.crm_gempa_cleaned;

-- 3. Mengisi Tabel Fakta (Menghubungkan ID)
INSERT INTO gold.fact_gempa (id_waktu, id_lokasi, magnitudo, kedalaman, status_gempa)
SELECT 
    w.id_waktu,
    l.id_lokasi,
    s.magnitudo,
    s.kedalaman,
    s.status_gempa
FROM silver.crm_gempa_cleaned s
JOIN gold.dim_waktu w ON s.tanggal = w.tanggal
JOIN gold.dim_lokasi l ON s.latitude = l.latitude 
                      AND s.longitude = l.longitude 
                      AND s.wilayah = l.wilayah;