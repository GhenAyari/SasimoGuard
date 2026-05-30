create table gold.dim_lokasi (
  id_lokasi serial not null,
  latitude numeric(10, 8) null,
  longitude numeric(11, 8) null,
  wilayah text null,
  constraint dim_lokasi_pkey primary key (id_lokasi)
) TABLESPACE pg_default;