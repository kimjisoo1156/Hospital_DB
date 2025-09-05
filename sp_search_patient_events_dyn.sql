/*
    patient_event에서 '기간/환자/내원/이벤트타입/퇴원여부' 옵션으로 필터해서, 
    최신순으로 상위 N건만 REF CURSOR로 돌려주는 동적 조회
*/
CREATE OR REPLACE PROCEDURE sp_search_patient_events_dyn
(
  /*  둘 다 NULL이면 올해 8/1 00:00 ~ 9/1 00:00 자동 적용 */
  p_from_dt         IN DATE                DEFAULT NULL,      -- 포함
  p_to_dt           IN DATE                DEFAULT NULL,      -- 미포함

  /*  NULL 이면 미적용 */
  p_patient_id      IN NUMBER              DEFAULT NULL,      -- 특정 환자만
  p_encounter_id    IN NUMBER              DEFAULT NULL,      -- 특정 내원만

  /* 이벤트 타입 최대 4개 전부 NULL이면 타입 필터 미적용 */
  p_ev1             IN VARCHAR2            DEFAULT NULL,      -- '검사'
  p_ev2             IN VARCHAR2            DEFAULT NULL,      -- '투약'
  p_ev3             IN VARCHAR2            DEFAULT NULL,      -- '처방'
  p_ev4             IN VARCHAR2            DEFAULT NULL,      -- '수술'

  /* 퇴원자 포함해서 구하고 싶을 경우 (encounter 조인 + discharge_dt IS NOT NULL) */
  p_discharged_only IN NUMBER              DEFAULT 0,

  /* 최대 반환 행수 */
  p_row_limit       IN PLS_INTEGER         DEFAULT 100,

  p_rc              OUT SYS_REFCURSOR
)
AS
  /* 내부 사용 변수 */
  l_sql        CLOB;   -- 동적 SELECT 텍스트
  l_from_dt    DATE;   -- 최종 적용 포함
  l_to_dt      DATE;   -- 최종 적용 미포함
  l_has_types  NUMBER := 0;  -- 0: 타입 필터 X, 1: 타입 필터 O
BEGIN
  /* 기본 기간 계산 */
  IF p_from_dt IS NULL AND p_to_dt IS NULL THEN
    /* 올해 8월 1일 00:00 ~ 9월 1일 00:00 */
    l_from_dt := TO_DATE(TO_CHAR(EXTRACT(YEAR FROM SYSDATE)) || '0801', 'YYYYMMDD');
    l_to_dt   := ADD_MONTHS(l_from_dt, 1);
  ELSE
    /* 한쪽만 주면 다른 한쪽은 열린 구간 */
    l_from_dt := NVL(p_from_dt, DATE '0001-01-01');
    l_to_dt   := NVL(p_to_dt,   DATE '9999-12-31');
  END IF;

  /* 이벤트 타입 필터 ON/OFF 판단 */
  IF p_ev1 IS NOT NULL OR p_ev2 IS NOT NULL OR p_ev3 IS NOT NULL OR p_ev4 IS NOT NULL THEN
    l_has_types := 1;
  END IF;

  /* 동적 SELECT 조립
     정렬은 event_dt DESC 고정
     
     :로 시작하는 건 바인드 변수
     
     param IS NULL OR col = :param 패턴으로 옵션 필터 ON/OFF
     파라미터가 비어 있으면 필터 끄고, 값이 있으면 그 값으로 필터 킴
     
     이벤트 타입은 has_types=1 일 때만 IN 절 평가
     
     FETCH FIRST n ROWS ONLY절은 바인드 변수로 n을 줄 수 없는 경우가 많아서
     바인드로 제한 개수를 넣기 위해 고전 방식인 ROWNUM 사용
     
     :b_patient_id = 네가 넣은 환자 번호(입력값)
     pe.patient_id = SELECT로 읽는 각 행의 환자 번호
     입력값이 NULL이면 → TRUE OR ... → 모든 행 통과(필터 꺼짐)
     입력값이 있으면 → pe.patient_id = :b_patient_id와 같은 행만 통과(필터 켜짐)
     
     퇴원 완료건만 보여주려면 encounter.discharge_dt가 필요
     그래서 encounter를 조인
     
     환자id가 있고 없고 내원id가 있고 없고의 조합

   */
     l_sql := q'[
        SELECT *
        FROM (
          SELECT pe.event_id,
                 pe.patient_id,
                 pe.encounter_id,
                 pe.event_type,
                 pe.event_dt,
                 pe.note
            FROM patient_event pe
            LEFT JOIN encounter en
              ON en.encounter_id = pe.encounter_id
           WHERE pe.event_dt >= :b_from_dt              -- (1)
             AND pe.event_dt <  :b_to_dt                -- (2)
             AND ( :b_patient_id   IS NULL OR pe.patient_id   = :b_patient_id )   -- (3)(4)
             AND ( :b_encounter_id IS NULL OR pe.encounter_id = :b_encounter_id ) -- (5)(6)
             AND ( :b_has_types = 0 OR pe.event_type IN (:b_ev1, :b_ev2, :b_ev3, :b_ev4) ) -- (7)~(11)
             AND ( :b_disch = 0 OR en.discharge_dt IS NOT NULL )                  -- (11) 
           ORDER BY pe.event_dt DESC
        )
        WHERE ROWNUM <= :b_row_limit   -- (12)
        ]';

   /* 커서 열기
      USING은 이름이 아니라 등장 순서로 매핑
      아래 주석의 (n)은 위 SQL 안 바인드 등장 순서와 1:1.
   */
    OPEN p_rc FOR l_sql USING
      l_from_dt,          -- (1)  :b_from_dt
      l_to_dt,            -- (2)  :b_to_dt
      p_patient_id,       -- (3)  :b_patient_id
      p_patient_id,       -- (4)  :b_patient_id 
      p_encounter_id,     -- (5)  :b_encounter_id
      p_encounter_id,     -- (6)  :b_encounter_id 
      l_has_types,        -- (7)  :b_has_types  (0/1)
      p_ev1,              -- (8)  :b_ev1
      p_ev2,              -- (9)  :b_ev2
      p_ev3,              -- (10) :b_ev3
      p_ev4,                 -- (11) :b_ev4
      NVL(p_discharged_only,0), -- (12) :b_disch 
      NVL(p_row_limit, 500);    -- (13) :b_row_limit

EXCEPTION
  WHEN OTHERS THEN
    RAISE; 
END;
/
