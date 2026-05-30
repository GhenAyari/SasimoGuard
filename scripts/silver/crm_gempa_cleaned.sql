create table silver.crm_gempa_cleaned (
  tanggal date null,
  waktu_origin time without time zone null,
  latitude numeric(10, 8) null,
  longitude numeric(11, 8) null,
  kedalaman integer null,
  magnitudo numeric(3, 1) null,
  wilayah text null,
  status_gempa text null
) TABLESPACE pg_default;