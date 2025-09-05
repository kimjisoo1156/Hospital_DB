   

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
    ),
    over_x AS (
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
    
    
select * from patient_event where patient_id = 455
635	455	413	25/08/25 11:02:00.000000000	처방	IP 자동생성
636	455	413	25/09/03 14:19:00.000000000	수술	IP 자동생성
637	455	413	25/09/12 17:36:00.000000000	투약	IP 자동생성
638	455	413	25/09/21 20:54:00.000000000	검사	IP 자동생성

select * from encounter where encounter_id = 413 -- 9월21일이 퇴원일 



 WITH ip_events AS (  -- patient_event와 encounter를 조인한 뒤 입원인 건만 남김
    SELECT pe.patient_id, pe.encounter_id, pe.event_dt, pe.event_type
    FROM   patient_event pe
    JOIN   encounter e
      ON   e.patient_id   = pe.patient_id
     AND   e.encounter_id = pe.encounter_id
    WHERE  e.encounter_type = 'IP'
  )
--  442	401	25/08/27 05:41:00.000000000	처방
--442	401	25/09/08 19:36:00.000000000	수술
--442	401	25/09/21 09:32:00.000000000	검사
--443	402	25/08/28 06:06:00.000000000	처방
--443	402	25/08/31 05:59:00.000000000	수술
--443	402	25/09/03 05:53:00.000000000	검사
--444	403	25/08/29 06:40:00.000000000	처방
--444	403	25/09/02 19:35:00.000000000	수술
select * from ip_events where encounter_id = 457

-- 환자 가 발생한 이벤트가 서로 차이일수가 7일 이내인것을 새는거네 cnt_7d인거고
  ,
  win AS ( -- 환자별(PARTITION BY patient_id)로 시간순(ORDER BY event_dt) 정렬한 뒤,
           -- 현재 행의 event_dt를 오른쪽 끝(=앵커)로 보고 
           -- 그로부터 6일 전 ~ 현재 시각까지(즉, 최근 7일)의 이벤트 개수를 윈도우 COUNT로 계산
    SELECT ie.*,
           COUNT(*) OVER (
             PARTITION BY ie.patient_id
             ORDER BY     ie.event_dt
             RANGE BETWEEN INTERVAL '6' DAY PRECEDING AND CURRENT ROW
           ) AS cnt_7d
    FROM   ip_events ie
  )

  select * from win
  
  ,
  top_anchor AS ( -- 7일 누적건수(cnt_7d)를 내림차순(동률 시 더 최근 event_dt)으로 순위 매김
                  -- 가장 붐볐던 7일 창의 앵커 시점과 환자건수를 뽑아내는 CTE
    SELECT patient_id,
           event_dt  AS anchor_dt,
           cnt_7d,
           ROW_NUMBER() OVER (ORDER BY cnt_7d DESC, event_dt DESC) AS rn
    FROM   win
  )
  -- 가장 붐볐던 7일 기간의 주인공 환자 변수에 담아 놓음.
  SELECT patient_id, anchor_dt, cnt_7d
    INTO v_anchor_patient, v_anchor_end, v_anchor_cnt
  FROM  top_anchor
  WHERE rn = 1;
  
    
  
  
  