   

    WITH j AS ( 
      SELECT pe.patient_id,
             pe.encounter_id,
             e.provider_id,
             CAST(NVL(e.discharge_dt, SYSTIMESTAMP) AS DATE) AS baseline_d, -- 퇴원없으면 현재시각
             CAST(pe.event_dt AS DATE) AS event_d  -- 이벤트 시각
      FROM   patient_event pe
      JOIN   encounter     e
        ON   e.patient_id   = pe.patient_id
       AND   e.encounter_id = pe.encounter_id
      WHERE  e.encounter_type = 'IP'
    )
--    select * from j
--    -- 퇴원일이  있으면 퇴원일이 baseline_dt
--    -- 퇴원일이 없으면 오늘날짜 
--    select * from encounter where patient_id in(401,402)
--    
    select *
    
    from (
    SELECT j.*,
               (baseline_d - event_d) AS diff_days
        FROM   j
    ) sub 
    where diff_days >= 30
        
    ,over_x AS (
      SELECT patient_id, encounter_id, provider_id, -- 환자, 내원, 의사, p_days일 이상 이전인 이벤트수 over_cnt
             COUNT(*) AS over_cnt
      FROM (
        SELECT j.*,
               (baseline_d - event_d) AS diff_days
        FROM   j
      )
      WHERE  diff_days >= 25
      GROUP BY patient_id, encounter_id, provider_id
    )
    
    SELECT patient_id, encounter_id, provider_id, over_cnt
    FROM   over_x
    ORDER  BY over_cnt DESC, patient_id, encounter_id


-------------------------------------------------------------------------
    WITH day_cnt AS ( 
        SELECT TRUNC(pe.event_dt) AS day, 
        COUNT(*) AS cnt FROM patient_event pe 
        GROUP BY TRUNC(pe.event_dt) 

    ), rolling AS ( 
        SELECT day, 
               SUM(cnt) OVER ( ORDER BY day RANGE BETWEEN INTERVAL '6' DAY PRECEDING AND CURRENT ROW ) AS sum7 
        FROM day_cnt 
     
    ), maxval AS ( SELECT MAX(sum7) AS mx FROM rolling )
    , top_windows AS ( 
        SELECT 
            r.day - INTERVAL '6' DAY AS start_day, 
            r.day + INTERVAL '1' DAY AS end_day, 
            r.sum7 AS win_count 
        FROM rolling r 
        JOIN maxval m ON r.sum7 = m.mx 
    ) SELECT pe.patient_id, a.appt_dt, pe.event_dt, pe.event_type, p.provider_name, d.dept_name, pe.note 
    FROM top_windows t 
    JOIN patient_event pe 
         ON pe.event_dt >= CAST(t.start_day AS TIMESTAMP) AND pe.event_dt < CAST(t.end_day AS TIMESTAMP) 
    JOIN encounter e 
        ON e.patient_id = pe.patient_id AND e.encounter_id = pe.encounter_id 
    JOIN provider p 
        ON p.provider_id = e.provider_id 
    JOIN department d 
        ON d.dept_id = p.dept_id 
    JOIN appointment a 
        ON a.appt_id = e.appt_id AND a.cancel_yn = 'N' 
    ORDER BY pe.patient_id, pe.event_dt;
  
  
  
