DECLARE
  p_days     NUMBER    := 30;            -- A 임계일
  p_asof_ts  TIMESTAMP := SYSTIMESTAMP;  -- 퇴원 없을 때 기준시각
  rc1 SYS_REFCURSOR;
  rc2 SYS_REFCURSOR;
BEGIN
-- A 임계 초과 집계 
--    (입원 IP만): 환자/내원/의사 단위로 건수 집계
--     조건: (퇴원일 또는 현재시각) - 이벤트일 >= p_days
  OPEN rc1 FOR
    WITH params AS (
      SELECT p_days AS p_days, p_asof_ts AS p_asof_ts FROM dual
    )
    , j AS (
      SELECT
        pe.patient_id,
        pe.encounter_id,
        e.provider_id,
        CAST(NVL(e.discharge_dt, (SELECT p_asof_ts FROM params)) AS DATE) AS baseline_d,
        CAST(pe.event_dt AS DATE) AS event_d
      FROM patient_event pe
      JOIN encounter e
        ON e.patient_id   = pe.patient_id
       AND e.encounter_id = pe.encounter_id
      WHERE e.encounter_type = 'IP'
    )
    SELECT
      j.patient_id, j.encounter_id, j.provider_id,
      COUNT(*) AS over_cnt
    FROM j, params
    WHERE (j.baseline_d - j.event_d) >= params.p_days
    GROUP BY j.patient_id, j.encounter_id, j.provider_id
    ORDER BY over_cnt DESC, j.patient_id, j.encounter_id;

  DBMS_SQL.RETURN_RESULT(rc1);  

  -- B 전역 캘린더 7일 최빈 구간 상세 
  OPEN rc2 FOR
    WITH day_cnt AS (
      SELECT TRUNC(pe.event_dt) AS day, COUNT(*) AS cnt
      FROM   patient_event pe
      GROUP  BY TRUNC(pe.event_dt)
    ),
    rolling AS (
      SELECT day,
             SUM(cnt) OVER (
               ORDER BY day
               RANGE BETWEEN INTERVAL '6' DAY PRECEDING AND CURRENT ROW
             ) AS sum7
      FROM day_cnt
    ),
    maxval AS ( SELECT MAX(sum7) AS mx FROM rolling ),
    top_windows AS (
      SELECT r.day - INTERVAL '6' DAY AS start_day,
             r.day + INTERVAL '1' DAY AS end_day,
             r.sum7 AS win_count
      FROM   rolling r
      JOIN   maxval  m ON r.sum7 = m.mx
    )
    SELECT
      pe.patient_id,
      a.appt_dt,
      pe.event_dt,
      pe.event_type,
      p.provider_name,
      d.dept_name,
      pe.note
    FROM   top_windows t
    JOIN   patient_event pe
           ON pe.event_dt >= CAST(t.start_day AS TIMESTAMP)
          AND pe.event_dt <  CAST(t.end_day  AS TIMESTAMP)
    JOIN   encounter e
           ON e.patient_id   = pe.patient_id
          AND e.encounter_id = pe.encounter_id
    JOIN   provider  p ON p.provider_id = e.provider_id
    JOIN   department d ON d.dept_id    = p.dept_id
    JOIN   appointment a
           ON a.appt_id = e.appt_id
          AND a.cancel_yn = 'N'
    ORDER  BY pe.patient_id, pe.event_dt;

  DBMS_SQL.RETURN_RESULT(rc2);  
END;
/

