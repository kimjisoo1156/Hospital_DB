SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE

  p_days        NUMBER    := 25;            -- 임계값
  p_asof_ts     TIMESTAMP := SYSTIMESTAMP;  -- 현재시각
  p_max_print   PLS_INTEGER := 30;          -- 각 섹션 최대 출력 행수

  -- 섹션 A 출력 카운터
  i1 PLS_INTEGER := 0;
  
  -- 섹션 B 출력 카운터
  i2 PLS_INTEGER := 0;

  -- B 섹션: 앵커 최대 7일 상세 정보 변수
  -- 앵커 
  v_anchor_patient  NUMBER;  -- 가장 이벤트가 많았던 환자 id
  v_anchor_end      TIMESTAMP;  -- 그 환자의 앵커 끝시각
  v_anchor_cnt      NUMBER; -- 그때의 이벤트 개수
BEGIN
  ---------------------------------------------------------------------------
  /*
      입원건에서 이벤트가 퇴원일 
      최소 p_days일 이상 이전인 이벤트가 몇 개나 있는지를 
      (환자, 내원, 의사) 단위로 집계해서 많이 나온 순으로 최대 p_max_print개 출력
      단, 퇴원일이 없으면 현재 시각을 기준으로 p_days일 이상인 이벤트를 센다.
      
  */
  ---------------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('A 임계 초과 집계');

  FOR r IN (
    WITH j AS ( 
      SELECT pe.patient_id,
             pe.encounter_id,
             e.provider_id,
             CAST(NVL(e.discharge_dt, p_asof_ts) AS DATE) AS baseline_d, -- 퇴원없으면 현재시각
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
      WHERE  diff_days >= p_days
      GROUP BY patient_id, encounter_id, provider_id
    )
    SELECT patient_id, encounter_id, provider_id, over_cnt
    FROM   over_x
    ORDER  BY over_cnt DESC, patient_id, encounter_id
      
  ) LOOP
    EXIT WHEN i1 >= p_max_print;
    i1 := i1 + 1;
    DBMS_OUTPUT.PUT_LINE(
      LPAD(i1,3)||'  patient='||r.patient_id||
      ', encounter='||r.encounter_id||
      ', provider='||r.provider_id||
      ', over_cnt='||r.over_cnt
    );
  END LOOP;

  IF i1 = 0 THEN
    DBMS_OUTPUT.PUT_LINE('결과 없음');
  END IF;

  ---------------------------------------------------------------------------
/*
    입원 이벤트 중 어떤 환자의 7일(=당일 포함 6일 전 ~ 앵커시점) 구간이 가장 바빴는지를 찾고, 
    그 환자의 그 7일 구간 이벤트 상세를 최대 p_max_print개 출력
    
    앵커시점: 어떤 이벤트 시각 t(그 시각이 창의 오른쪽 끝)
    7일 창: [t−6일, t] (당일 포함 7일)
    
    각 환자에 대해 모든 이벤트 시각을 앵커 후보로 삼아, 그 7일 창 안의 이벤트 개수(cnt_7d)를 계산
    그중 가장 큰 개수를 갖는 창(=가장 붐볐던 7일)을 뽑고, 동률이면 더 늦은 시각을 우선

*/
  ---------------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('B 가장 활발한 7일 구간 상세');

  -- 앵커(환자/구간 종료시각/카운트) 구하기
  WITH ip_events AS (  -- patient_event와 encounter를 조인한 뒤 입원인 건만 남김
    SELECT pe.patient_id, pe.encounter_id, pe.event_dt, pe.event_type
    FROM   patient_event pe
    JOIN   encounter e
      ON   e.patient_id   = pe.patient_id
     AND   e.encounter_id = pe.encounter_id
    WHERE  e.encounter_type = 'IP'
  ),
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
  ),
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

  DBMS_OUTPUT.PUT_LINE(
    '  anchor_patient='||v_anchor_patient||
    ', window=['||TO_CHAR(v_anchor_end - INTERVAL '6' DAY, 'YYYY-MM-DD HH24:MI')||
    ' ~ '||TO_CHAR(v_anchor_end, 'YYYY-MM-DD HH24:MI')||
    '], cnt_7d='||v_anchor_cnt
  );

  -- 해당 환자의 그 7일 구간 상세
  FOR d IN (
    WITH sel AS (  -- 방금 구한 앵커 환자/시각을 1행 테이블로 만듦
      SELECT v_anchor_patient AS patient_id,
             v_anchor_end     AS anchor_dt
      FROM   dual
    )
    SELECT d.patient_id,
           d.encounter_id,
           e.provider_id,
           d.event_dt,
           d.event_type
    FROM   sel s
    JOIN   patient_event d -- 환자 이벤트에서 id가 같고 이벤트 시각이 6일 전부터 앵커시점까지의 7일 구간에 포함된 이벤트만 선택
      ON   d.patient_id = s.patient_id
     AND   d.event_dt BETWEEN s.anchor_dt - INTERVAL '6' DAY AND s.anchor_dt
    JOIN   encounter e -- 내원 테이블에서 환자id같고 내원id같고 입원인 것과 조인
      ON   e.patient_id   = d.patient_id
     AND   e.encounter_id = d.encounter_id
    WHERE  e.encounter_type = 'IP'
    ORDER  BY d.event_dt
   
  ) LOOP
    EXIT WHEN i2 >= p_max_print;
    i2 := i2 + 1;
    DBMS_OUTPUT.PUT_LINE(
      LPAD(i2,3)||'  patient='||d.patient_id||
      ', encounter='||d.encounter_id||
      ', provider='||d.provider_id||
      ', event_dt='||TO_CHAR(d.event_dt,'YYYY-MM-DD HH24:MI')||
      ', type='||d.event_type
    );
  END LOOP;

  IF i2 = 0 THEN
    DBMS_OUTPUT.PUT_LINE('상세 결과 없음');
  END IF;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('B: Top 7일 구간을 계산할 IP 이벤트가 없습니다.');
END;
/
