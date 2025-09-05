/*
목표 : 환자 이벤트에서 현재 날짜로 부터 3일전의 이벤트 날짜로 부터 3일치의 건수를 10건씩 끊어서 다중행 결과집합을 반복처리

명시적 커서가 SELECT 결과(다중 행)를 내놓고,
그 행들을 BULK COLLECT로 한 번에 최대 p_page_size개씩 v_tab에 담고,
v_tab을 한 줄씩 돌면서 출력하는 구조

*/

SET SERVEROUTPUT ON 

DECLARE
  ------------------------------------------------------------------------------
  -- 고정 3일 구간
  ------------------------------------------------------------------------------
  p_from_ts   TIMESTAMP := TIMESTAMP '2025-08-27 00:00:00';
  p_to_ts     TIMESTAMP := TIMESTAMP '2025-08-30 00:00:00'; -- 상한 미만
  p_page_size PLS_INTEGER := 10;                 -- 10건씩 끊어서 처리

  ------------------------------------------------------------------------------
  -- TOO_MANY_ROWS/NO_DATA_FOUND 시연용 
  ------------------------------------------------------------------------------
  v_dept_id   department.dept_id%TYPE;
  ------------------------------------------------------------------------------
  -- 명시적 커서: 고정 3일 구간의 IP 이벤트를 (일자, 환자)별로 집계
  ------------------------------------------------------------------------------
  CURSOR cur_ev_cnt(p_from TIMESTAMP, p_to TIMESTAMP) IS
    SELECT TRUNC(pe.event_dt) AS event_day -- 시분초제거 날짜만
         , pe.patient_id
         , COUNT(*) AS cnt -- 이벤트건수
    FROM   patient_event pe
    JOIN   encounter e
           ON e.patient_id   = pe.patient_id
          AND e.encounter_id = pe.encounter_id
    WHERE  e.encounter_type = 'IP'
      AND  pe.event_dt >= p_from
      AND  pe.event_dt <  p_to
    GROUP  BY TRUNC(pe.event_dt), pe.patient_id
    ORDER  BY TRUNC(pe.event_dt), pe.patient_id;

  ------------------------------------------------------------------------------
  -- BULK 수신용 타입/변수
  -- t_row  : 커서 한 행의 모양(날짜, 환자, 건수)
  -- t_tab  : t_row를 담는 연관배열(associative array). 메모리 컬렉션, DB 테이블 아님!
  -- v_tab  : 실제 컬렉션 변수
  ------------------------------------------------------------------------------
  TYPE t_row IS RECORD (  -- 커서가 뱉는 한줄 모양 날짜, 환자id, 건수
    event_day   DATE,
    patient_id  NUMBER,
    cnt         PLS_INTEGER
  );
  TYPE t_tab IS TABLE OF t_row INDEX BY PLS_INTEGER; -- 연관배열 타입 선언
  v_tab t_tab;

  -- 총 건수 확인(없을 때 NO_DATA_FOUND 발생시키기 위함)
  v_total PLS_INTEGER := 0;

BEGIN
  DBMS_OUTPUT.PUT_LINE('범위: '||
    TO_CHAR(CAST(p_from_ts AS DATE), 'YYYY-MM-DD HH24:MI')||' ~ '||
    TO_CHAR(CAST(p_to_ts   AS DATE), 'YYYY-MM-DD HH24:MI')||' (상한 미만)'
  );

  -- 총 건수 확인 (0이면 NO_DATA_FOUND 유발)
  SELECT COUNT(*) INTO v_total
  FROM   patient_event pe
  JOIN   encounter e
         ON e.patient_id   = pe.patient_id
        AND e.encounter_id = pe.encounter_id
  WHERE  e.encounter_type = 'IP'
    AND  pe.event_dt >= p_from_ts
    AND  pe.event_dt <  p_to_ts;

  -- 위 쿼리문은 항상 1행을 발행 하므로 데이터가 없어도 0이 나오니깐, 명시적 발생으로 예외처리
  IF v_total = 0 THEN
    RAISE NO_DATA_FOUND;
  END IF;

  DBMS_OUTPUT.PUT_LINE('대상 이벤트 총건수='||v_total||' (IP, 고정 3일 구간)');

  ------------------------------------------------------------------------------
  -- 명시적 커서 + BULK COLLECT LIMIT
  -- 커서를 연 뒤, LIMIT p_page_size(=10)로 최대 10행씩 묶어서 가져온다.
  -- v_tab.COUNT = 이번 묶음 페이지의 행 수
  -- v_tab(i).cnt = 그 행의 집계 건수(날짜,환자 조합별 건수)
  ------------------------------------------------------------------------------
  OPEN cur_ev_cnt(p_from_ts, p_to_ts);
  LOOP
    FETCH cur_ev_cnt BULK COLLECT INTO v_tab LIMIT p_page_size;
    EXIT WHEN v_tab.COUNT = 0;

    FOR i IN 1..v_tab.COUNT LOOP
      DBMS_OUTPUT.PUT_LINE(
        TO_CHAR(v_tab(i).event_day, 'YYYY-MM-DD')|| --날짜
        ' | patient='||v_tab(i).patient_id||  -- 환자id
        ' | cnt='||v_tab(i).cnt -- 해당 날짜 환자의 이벤트 건수
      );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('--- page end ('||LEAST(p_page_size, v_tab.COUNT)||' rows) ---');
  END LOOP;
  CLOSE cur_ev_cnt;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('해당 고정 3일 구간에 IP 이벤트가 없습니다.');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('예상치 못한 예외: '||SQLCODE||' / '||SQLERRM);
END;
/
