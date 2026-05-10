    -- 1.1 Zakres danych: lata 1961-1962, kraje US, CA, UK, FR

    -- 1.2 + 1.3 + 1.6
    -- Etap 1: filtrowanie i wybór kolumn pogodowych (10 kolumn, bez limitu rekordow)
    CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v_weather_daily_filtered` AS
    SELECT
      stn,
      country,
      obs_date,
      year,
      month,
      avg_temp_c,
      max_temp_c,
      min_temp_c,
      dewp_c,
      prcp_mm,
      visibility_miles
    FROM (
      SELECT
        g.stn,
        s.country,
        DATE(CAST(g.year AS INT64), CAST(g.mo AS INT64), CAST(g.da AS INT64)) AS obs_date,
        CAST(g.year AS INT64) AS year,
        CAST(g.mo AS INT64) AS month,
        IF(CAST(g.temp AS FLOAT64) = 9999.9, NULL, (CAST(g.temp AS FLOAT64) - 32) * 5 / 9) AS avg_temp_c,
        IF(CAST(g.max AS FLOAT64) = 9999.9, NULL, (CAST(g.max AS FLOAT64) - 32) * 5 / 9) AS max_temp_c,
        IF(CAST(g.min AS FLOAT64) = 9999.9, NULL, (CAST(g.min AS FLOAT64) - 32) * 5 / 9) AS min_temp_c,
        IF(CAST(g.dewp AS FLOAT64) = 9999.9, NULL, (CAST(g.dewp AS FLOAT64) - 32) * 5 / 9) AS dewp_c,
        IF(CAST(g.prcp AS FLOAT64) = 99.99, NULL, CAST(g.prcp AS FLOAT64) * 25.4) AS prcp_mm,
        CAST(g.visib AS FLOAT64) AS visibility_miles
      FROM (
        SELECT * FROM `bigquery-public-data.noaa_gsod.gsod1961`
        UNION ALL
        SELECT * FROM `bigquery-public-data.noaa_gsod.gsod1962`
      ) g
      LEFT JOIN `bigquery-public-data.noaa_gsod.stations` s
        ON g.stn = s.usaf AND g.wban = s.wban
      WHERE s.country IN ('US', 'CA', 'UK', 'FR')
    );

    -- 1.4 + 1.5 + 1.6
    -- Etap 2: agregacja miesieczna + zmienne dodatkowe
    CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v_weather_monthly_agg` AS
WITH station_stats AS (
    SELECT
      country,
      stn,
      year,
      month,
      AVG(avg_temp_c) AS stn_avg_temp,
      SUM(prcp_mm) AS stn_total_prcp,
      MAX(max_temp_c) - MIN(min_temp_c) AS stn_amplitude,
      COUNTIF(max_temp_c >= 30) AS stn_hot_days,
      COUNTIF(min_temp_c <= 0) AS stn_frost_days
    FROM `splendid-binder-280014.rolnicze.v_weather_daily_filtered`
    GROUP BY country, stn, year, month
)
SELECT
  country,
  year,
  month,
  AVG(stn_avg_temp) AS mean_temp_c,
  AVG(stn_total_prcp) AS total_prcp_mm,
  AVG(stn_amplitude) AS temp_amplitude_c,
  AVG(stn_hot_days) AS hot_days_30c, -- Tu powstaje średnia (np. 2.5 dnia)
  AVG(stn_frost_days) AS frost_days_0c
FROM station_stats
GROUP BY country, year, month;

    -- 1.4 + 1.6 + 1.7
    -- Etap 3: agregacja roczna
  CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v_weather_yearly_agg` AS
SELECT
  country,
  year,
  ROUND(AVG(mean_temp_c), 2) AS yearly_mean_temp_c,
  ROUND(SUM(total_prcp_mm), 2) AS yearly_total_prcp_mm, 
  ROUND(AVG(temp_amplitude_c), 2) AS yearly_avg_temp_amplitude_c,
  ROUND(SUM(hot_days_30c), 1) AS yearly_hot_days_30c, 
  ROUND(SUM(frost_days_0c), 1) AS yearly_frost_days_0c
FROM `splendid-binder-280014.rolnicze.v_weather_monthly_agg`
GROUP BY country, year;

    -- 1.2 + 1.3 + 1.6
    -- Etap 4: filtrowanie danych rolniczych (Wheat Yield, 1961-1962, US/CA/UK/FR)
    CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v_agri_filtered` AS
    SELECT
      CASE
        WHEN UPPER(Area) IN ('UNITED STATES OF AMERICA', 'UNITED STATES', 'USA') THEN 'US'
        WHEN UPPER(Area) = 'CANADA' THEN 'CA'
        WHEN UPPER(Area) IN ('UNITED KINGDOM', 'GREAT BRITAIN', 'UK') THEN 'UK'
        WHEN UPPER(Area) = 'FRANCE' THEN 'FR'
        ELSE NULL
      END AS country,
      CAST(Year AS INT64) AS year,
      Item AS agri_item,
      Element AS agri_variable,
      Value AS agri_value,
      Unit AS agri_unit
    FROM `splendid-binder-280014.rolnicze.rolnicze`
    WHERE CAST(Year AS INT64) BETWEEN 1961 AND 1962
      AND UPPER(Area) IN (
        'UNITED STATES OF AMERICA', 'UNITED STATES', 'USA',
        'CANADA',
        'UNITED KINGDOM', 'GREAT BRITAIN', 'UK',
        'FRANCE'
      )
      AND Item = 'Wheat'
      AND Element = 'Yield';

    -- 1.7 + 1.8
    -- Etap 5: polaczenie pogody z rolnictwem
    CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v_final_weather_agri` AS
    SELECT
      w.country,
      w.year,
      w.yearly_mean_temp_c,
      w.yearly_total_prcp_mm,
      w.yearly_avg_temp_amplitude_c,
      w.yearly_hot_days_30c,
      w.yearly_frost_days_0c,
      a.agri_item,
      a.agri_variable,
      a.agri_value,
      a.agri_unit
    FROM `splendid-binder-280014.rolnicze.v_weather_yearly_agg` w
    LEFT JOIN `splendid-binder-280014.rolnicze.v_agri_filtered` a
      ON w.country = a.country
     AND w.year = a.year;

    -- 1.6 + 1.8
    -- Etap 6: tabela koncowa
    CREATE OR REPLACE TABLE `splendid-binder-280014.rolnicze.t_final_weather_agri_1961_1962` AS
    SELECT *
    FROM `splendid-binder-280014.rolnicze.v_final_weather_agri`;

    -- 1.9
    -- Zbior jest spojny i nadaje sie do analizy wstepnej.
    -- Ograniczenia: 2 lata, 4 kraje,
    -- 1 zmienna rolnicza i agregacja do poziomu kraju.


-- ==============================
-- CZESC 3
-- ==============================
-- 3.1 + 3.2 + 3.3
-- Wariant A: roczny (1961-1962, US/CA/UK/FR)
-- Ten wariant korzysta z widoków utworzonych w części 1: roczne agregaty i przefiltrowane dane rolnicze.
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v3_variant_a_final` AS
SELECT
  w.country,
  w.year,
  w.yearly_mean_temp_c,
  w.yearly_total_prcp_mm,
  w.yearly_avg_temp_amplitude_c,
  w.yearly_hot_days_30c,
  w.yearly_frost_days_0c,
  a.agri_value
FROM `splendid-binder-280014.rolnicze.v_weather_yearly_agg` w
LEFT JOIN `splendid-binder-280014.rolnicze.v_agri_filtered` a
  ON w.country = a.country AND w.year = a.year;

-- 3.3
-- (Wariant A) miesięczny widok — używa wcześniej zdefiniowanej agregacji miesięcznej
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v3_variant_a_weather_monthly` AS
SELECT
  country,
  year,
  month,
  mean_temp_c,
  total_prcp_mm,
  temp_amplitude_c,
  hot_days_30c,
  frost_days_0c
FROM `splendid-binder-280014.rolnicze.v_weather_monthly_agg`;

-- 3.4
-- Wariant B: miesięczny (1962, US/FR) — mniejszy zakres i dodatkowe zmienne statystyczne
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v3_variant_b_final` AS
SELECT
  m.country,
  m.year,
  m.month,
  m.mean_temp_c,
  m.total_prcp_mm,
  m.temp_stddev_c,
  a.agri_value
FROM (
  SELECT
    country,
    year,
    month,
    mean_temp_c,
    total_prcp_mm,
    STDDEV_POP(mean_temp_c) OVER (PARTITION BY country, year) AS temp_stddev_c
  FROM `splendid-binder-280014.rolnicze.v_weather_monthly_agg`
  WHERE year = 1962 AND country IN ('US', 'FR')
) m
LEFT JOIN `splendid-binder-280014.rolnicze.v_agri_filtered` a
  ON m.country = a.country AND m.year = a.year;

-- 3.5
-- Porównanie wariantów
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v3_variants_comparison` AS
SELECT
  'A_yearly_1961_1962_4countries' AS variant,
  COUNT(*) AS rows_total,
  COUNTIF(agri_value IS NULL) AS null_agri,
  AVG(yearly_mean_temp_c) AS avg_temp_metric,
  AVG(yearly_total_prcp_mm) AS avg_prcp_metric
FROM `splendid-binder-280014.rolnicze.v3_variant_a_final`
UNION ALL
SELECT
  'B_monthly_1962_2countries' AS variant,
  COUNT(*) AS rows_total,
  COUNTIF(agri_value IS NULL) AS null_agri,
  AVG(mean_temp_c) AS avg_temp_metric,
  AVG(total_prcp_mm) AS avg_prcp_metric
FROM `splendid-binder-280014.rolnicze.v3_variant_b_final`;

-- 3.6
-- Uproszczenie: można pominąć zmienne ekstremalne przy szybkim modelu bazowym (temp + opady + plon).

-- 3.7
-- Wnioski: korzystanie z widoków z części 1 (filtrowanie i agregacja) zapobiega
-- duplikacji logiki, ułatwia testowanie i porównania wariantów; wariant A jest
-- najprostszy do interpretacji (roczne agregaty), wariant B daje lepszą
-- rozdzielczość czasową (miesięczną) kosztem większej złożoności.


-- CZESC 5

-- 5.1 Obliczanie zmian względem poprzedniego okresu (miesięcznie i rocznie)
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v5_monthly_changes` AS
SELECT
  country,
  year,
  month,
  mean_temp_c,
  total_prcp_mm,
  LAG(mean_temp_c) OVER(PARTITION BY country ORDER BY year, month) AS mean_temp_prev,
  mean_temp_c - LAG(mean_temp_c) OVER(PARTITION BY country ORDER BY year, month) AS mean_temp_diff_abs,
  SAFE_DIVIDE(mean_temp_c - LAG(mean_temp_c) OVER(PARTITION BY country ORDER BY year, month), LAG(mean_temp_c) OVER(PARTITION BY country ORDER BY year, month)) AS mean_temp_diff_pct,
  LAG(total_prcp_mm) OVER(PARTITION BY country ORDER BY year, month) AS prcp_prev,
  total_prcp_mm - LAG(total_prcp_mm) OVER(PARTITION BY country ORDER BY year, month) AS prcp_diff_abs,
  SAFE_DIVIDE(total_prcp_mm - LAG(total_prcp_mm) OVER(PARTITION BY country ORDER BY year, month), NULLIF(LAG(total_prcp_mm) OVER(PARTITION BY country ORDER BY year, month),0)) AS prcp_diff_pct
FROM `splendid-binder-280014.rolnicze.v_weather_monthly_agg`;


-- 5.2 Analiza dynamiki zmian: wariancja / odchylenie zmian
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v5_dynamics_summary` AS
SELECT
  country,
  COUNT(*) AS obs_count,
  AVG(ABS(mean_temp_diff_abs)) AS avg_abs_monthly_temp_change,
  STDDEV_POP(mean_temp_diff_abs) AS stddev_monthly_temp_change,
  AVG(ABS(prcp_diff_abs)) AS avg_abs_monthly_prcp_change,
  STDDEV_POP(prcp_diff_abs) AS stddev_monthly_prcp_change,
  MAX(ABS(mean_temp_diff_abs)) AS max_abs_monthly_temp_change,
  MAX(ABS(prcp_diff_abs)) AS max_abs_monthly_prcp_change
FROM `splendid-binder-280014.rolnicze.v5_monthly_changes`
WHERE mean_temp_diff_abs IS NOT NULL OR prcp_diff_abs IS NOT NULL
GROUP BY country
ORDER BY stddev_monthly_temp_change DESC;


-- 5.3 Obliczanie srednich kroczacych (3-okresowe) - miesięczne
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v5_monthly_moving_avg_3` AS
SELECT
  country,
  year,
  month,
  mean_temp_c,
  AVG(mean_temp_c) OVER(PARTITION BY country ORDER BY year, month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma3_mean_temp_c,
  total_prcp_mm,
  AVG(total_prcp_mm) OVER(PARTITION BY country ORDER BY year, month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma3_total_prcp_mm
FROM `splendid-binder-280014.rolnicze.v_weather_monthly_agg`;



-- 5.4 Porownanie klasycznej agregacji i metod czasowych
-- Zestawienie: agregat miesieczny vs zmiana % do poprzedniego miesiaca + srednia kroczaca
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v5_compare_aggregation_vs_dynamic` AS
SELECT
  m.country,
  m.year,
  m.month,
  m.mean_temp_c AS agg_mean_temp,
  c.mean_temp_diff_pct AS pct_change_vs_prev,
  ma.ma3_mean_temp_c AS ma3_mean_temp
FROM `splendid-binder-280014.rolnicze.v_weather_monthly_agg` m
LEFT JOIN `splendid-binder-280014.rolnicze.v5_monthly_changes` c
  ON m.country = c.country AND m.year = c.year AND m.month = c.month
LEFT JOIN `splendid-binder-280014.rolnicze.v5_monthly_moving_avg_3` ma
  ON m.country = ma.country AND m.year = ma.year AND m.month = ma.month;


-- 5.5 Wykrywanie nietypowych okresow (anomalie): ostre zmiany
-- Proste reguły: |pct_change| > 20% dla temperatury lub > 100% dla opadów
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v5_anomalies` AS
SELECT
  country,
  year,
  month,
  mean_temp_c,
  mean_temp_prev,
  mean_temp_diff_abs,
  mean_temp_diff_pct,
  total_prcp_mm,
  prcp_prev,
  prcp_diff_abs,
  prcp_diff_pct,
  CASE
    WHEN ABS(mean_temp_diff_pct) > 0.20 THEN 'TEMP_SPIKE'
    WHEN ABS(prcp_diff_pct) > 1.0 THEN 'PRCP_SPIKE'
    ELSE NULL
  END AS anomaly_type
FROM `splendid-binder-280014.rolnicze.v5_monthly_changes`
WHERE (ABS(mean_temp_diff_pct) > 0.20 OR ABS(prcp_diff_pct) > 1.0)
ORDER BY year, month, country;


-- 5.6 Korelacja zmian pogodowych z plonami rolnymi (roczne)
-- Przy 2 latach nie da sie liczyc sensownej korelacji osobno dla kazdego kraju,
-- bo po LAG zostaje tylko 1 para obserwacji na kraj. Dlatego laczymy wszystkie kraje
-- w jeden zbior obserwacji i liczymy korelacje na poziomie calego zestawu.
CREATE OR REPLACE VIEW `splendid-binder-280014.rolnicze.v5_weather_agri_correlation` AS
WITH weather_changes AS (
  SELECT
    country,
    year,
    yearly_mean_temp_c - LAG(yearly_mean_temp_c) OVER(PARTITION BY country ORDER BY year) AS yearly_temp_diff,
    yearly_total_prcp_mm - LAG(yearly_total_prcp_mm) OVER(PARTITION BY country ORDER BY year) AS yearly_prcp_diff
  FROM `splendid-binder-280014.rolnicze.v_weather_yearly_agg`
), agri_changes AS (
  SELECT
    country,
    year,
    agri_value - LAG(agri_value) OVER(PARTITION BY country ORDER BY year) AS agri_value_diff
  FROM `splendid-binder-280014.rolnicze.v_agri_filtered`
), paired_changes AS (
  SELECT
    w.country,
    w.year,
    w.yearly_temp_diff,
    w.yearly_prcp_diff,
    a.agri_value_diff
  FROM weather_changes w
  JOIN agri_changes a
    ON w.country = a.country AND w.year = a.year
  WHERE w.yearly_temp_diff IS NOT NULL
    AND w.yearly_prcp_diff IS NOT NULL
    AND a.agri_value_diff IS NOT NULL
)
SELECT
  CORR(yearly_temp_diff, agri_value_diff) AS corr_temp_vs_yield_change,
  CORR(yearly_prcp_diff, agri_value_diff) AS corr_prcp_vs_yield_change,
  COUNT(*) AS obs
FROM paired_changes;


-- 5.7 Wnioski:
-- - Funkcje okienkowe (LAG, LEAD, AVG() OVER) pozwalaja analizowac dynamike bez agregowania do jednego wiersza.
-- - Srednie kroczace wygładzaja krótkoterminowe wahania i ułatwiają identyfikację trendu.
-- - Klasyczna agregacja (np. srednie roczne) jest przydatna do porownan statycznych, ale tracimy informacje o sekwencji i naglych zmianach.
-- - Detekcja anomalii prostymi progami pomaga wychwycic ostre okresy do dalszej inspekcji.
-- - Korelacje miedzy roznicami rocznymi pogody i plonow moga wskazac na zaleznosci, ale wymagaja wiekszej liczby lat i kontroli czynnikow (gleba, odmiany, zabiegi), by wnioskowac o przyczynowosci.
