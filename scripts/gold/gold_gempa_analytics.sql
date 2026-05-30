create view gold.gold_gempa_analytics as
select
  f.id_fakta,
  f.magnitudo as magnitude,
  f.kedalaman,
  f.status_gempa,
  w.tanggal::text as waktu,
  w.tahun,
  w.bulan,
  w.hari,
  l.wilayah,
  l.latitude,
  l.longitude
from
  gold.fact_gempa f
  join gold.dim_waktu w on f.id_waktu = w.id_waktu
  join gold.dim_lokasi l on f.id_lokasi = l.id_lokasi;