create table gold.fact_gempa (
  id_fakta serial not null,
  id_waktu integer null,
  id_lokasi integer null,
  magnitudo numeric(3, 1) null,
  kedalaman integer null,
  status_gempa text null,
  constraint fact_gempa_pkey primary key (id_fakta),
  constraint fact_gempa_id_lokasi_fkey foreign KEY (id_lokasi) references gold.dim_lokasi (id_lokasi),
  constraint fact_gempa_id_waktu_fkey foreign KEY (id_waktu) references gold.dim_waktu (id_waktu)
) TABLESPACE pg_default;