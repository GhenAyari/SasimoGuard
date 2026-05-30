create table gold.dim_waktu (
  id_waktu serial not null,
  tanggal date null,
  tahun integer null,
  bulan integer null,
  hari integer null,
  constraint dim_waktu_pkey primary key (id_waktu)
) TABLESPACE pg_default;