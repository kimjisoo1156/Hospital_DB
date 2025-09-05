SET SERVEROUTPUT ON
DECLARE

  TYPE t_numtab IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;   -- 정수 인덱스 기반 숫자 배열 타입
  TYPE t_tstab IS TABLE OF TIMESTAMP     INDEX BY PLS_INTEGER;   -- 타임스탬프 배열 타입
  TYPE t_v2tab IS TABLE OF VARCHAR2(2)   INDEX BY PLS_INTEGER;   -- 짧은 문자열 배열 타입

  c_depts    CONSTANT PLS_INTEGER := 3;    -- 부서 수: 내과/외과/피부과
  c_prov_pd  CONSTANT PLS_INTEGER := 4;    -- 부서당 의사 수
  c_pat      CONSTANT PLS_INTEGER := 500;  -- 생성할 환자 수
  c_appt     CONSTANT PLS_INTEGER := 600;  -- 생성할 예약 수
  c_enc      CONSTANT PLS_INTEGER := 500;  -- 생성할 encounter 수
  c_evt      CONSTANT PLS_INTEGER := 1000;   -- 생성할 이벤트 수

  dept_ids     t_numtab;    -- 생성된 department_id 저장
  prov_ids     t_numtab;    -- 생성된 provider_id 저장
  pat_ids      t_numtab;    -- 생성된 patient_id 저장

  appt_ids     t_numtab;    -- 생성된 appt_id 저장
  appt_pid     t_numtab;    -- 해당 appt의 patient_id 저장
  appt_prv     t_numtab;    -- 해당 appt의 provider_id 저장
  appt_dt_tab  t_tstab;     -- 해당 appt의 날짜/시간 저장

  enc_ids      t_numtab;    -- 생성된 encounter_id 저장
  enc_pid      t_numtab;    -- encounter의 patient_id 저장
  enc_type     t_v2tab;     -- encounter 유형('OP'/'IP') 저장
  enc_visit    t_tstab;     -- OP의 visit_dt 저장 (이벤트 생성 기준)
  enc_admit    t_tstab;     -- IP의 admit_dt 저장
  enc_dis      t_tstab;     -- IP의 discharge_dt 저장

  v            PLS_INTEGER; -- 범용 카운터 변수
  t0           TIMESTAMP := TIMESTAMP '2025-08-25 09:00:00'; -- 기준 시작 시각
  dept_names   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('내과','외과','피부과'); -- 부서명 리스트 
  prov_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('김민수','이지은','박영희','최철수','정현우','한수진','오승현');   -- 의사이름 리스트
  
  seoul_d SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
  '강남구','서초구','송파구','마포구','성동구','광진구','용산구','영등포구',
  '강서구','노원구','관악구','동작구','성북구','양천구','은평구','서대문구',
  '중구','종로구','중랑구','도봉구','강동구','금천구','구로구','동대문구'
  );

  gyeonggi_d SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
   '성남시 분당구','성남시 수정구','수원시 영통구','수원시 권선구','고양시 일산동구',
   '고양시 일산서구','용인시 수지구','용인시 기흥구','안산시 단원구','안양시 동안구'
  );

  other_addrs SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
  '부산광역시 해운대구','부산광역시 동래구',
  '대구광역시 수성구','광주광역시 북구',
  '대전광역시 서구','울산광역시 남구',
  '강원도 춘천시','전라북도 전주시','충청남도 태안군','경상북도 포항시'
  );

  -- SYS.ODCIVARCHAR2LIST는 오라클 내장 컬렉션 타입(문자열 리스트)
  g            CHAR(1);     -- 성별 임시 저장 ('M'/'W' 사용)
  v_dept_id    NUMBER;      -- department
  v_prov_id    NUMBER;      -- provider
  v_pat_id     NUMBER;      -- patient
  v_appt_id    NUMBER;      -- appointment
  v_enc_id     NUMBER;      -- encounter
  v_name    VARCHAR2(100);
  v_addr    VARCHAR2(200);
  v_cnt     PLS_INTEGER;
  v_age     PLS_INTEGER;
  v_birth   DATE;
  ------------------------------------------------------------------
  
  -- 30분 슬롯 시각 계산 함수 (보조)
  -- p_day_offset : p_base로부터 며칠 뒤인지 (0 = 같은날, 1 = 다음날)
  -- p_slot_idx : 30분 슬롯 인덱스 (정수, 0이면 p_base 그대로, 1이면 +30분, 2이면 +60분 등)

  ------------------------------------------------------------------
  FUNCTION slot_time(p_base TIMESTAMP, p_day_offset PLS_INTEGER, p_slot_idx PLS_INTEGER)
    RETURN TIMESTAMP
  IS
  BEGIN
    -- 기준 시각에 일(offset)과 30분 단위 슬롯 인덱스를 더해 슬롯 시각 반환
    RETURN p_base
           + NUMTODSINTERVAL(p_day_offset, 'DAY')
           + NUMTODSINTERVAL(p_slot_idx*30, 'MINUTE');
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('데이터 생성 시작'); -- 시작 메시지 출력

  -- DEPARTMENT 생성
  FOR d IN 1..c_depts LOOP -- 
    -- 부서명으로 department 레코드 삽입
    INSERT INTO department(dept_name)
    VALUES (dept_names(d))
    RETURNING dept_id INTO v_dept_id;    -- 생성된 PK를 v_dept_id에 받음
    dept_ids(d) := v_dept_id;            -- 컬렉션에 저장(나중에 provider의사 테이블의 dept_id참조해야 하므로)
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('department: '||c_depts); -- 생성된 부서 수 출력

  -- PROVIDER 생성
  
  v := 0; -- 총 의사 카운터 초기화
  FOR d IN 1..c_depts LOOP
    FOR k IN 1..c_prov_pd LOOP
      v := v + 1;
      v_name := prov_names( MOD(v-1, prov_names.COUNT) + 1 );
      INSERT INTO provider(provider_name, dept_id)
      VALUES ('Dr_'||dept_names(d)||'_'||TO_CHAR(k,'FM00')||'_'||v_name, dept_ids(d))
      RETURNING provider_id INTO v_prov_id; -- 생성된 pk provider_id 를 v_prov_id에 받기
      prov_ids(v) := v_prov_id;             -- prov_ids 배열에 저장
    END LOOP;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('provider: '||v); -- 총 생성된 provider 수 출력

  -- PATIENT 생성
  
  FOR p IN 1..c_pat LOOP
  
      -- 짝수는 'M', 홀수는 'F'로 성별 지정
      g := CASE WHEN MOD(p,2)=0 THEN 'M' ELSE 'F' END; 
    
      -- 주소 할당
      v_cnt := MOD(p-1, 100) + 1;
      IF v_cnt <= 60 THEN
        v_addr := '서울특별시 ' || seoul_d( MOD(p-1, seoul_d.COUNT) + 1 );
      ELSIF v_cnt <= 85 THEN
        v_addr := '경기도 ' || gyeonggi_d( MOD(p-1, gyeonggi_d.COUNT) + 1 );
      ELSE
        v_addr := other_addrs( MOD(p-1, other_addrs.COUNT) + 1 );
      END IF;

      -- 10~80살 생년월일 생성
      v_age := MOD(p-1, 71) + 10; --mod 값1을 값2로 나누었을때의 나머지 그값에 +10을 하면 결과가 10..80 /  p=1 → 10세, p=71 → 80세, p=72 → 다시 10세
      
      v_birth := ADD_MONTHS(TRUNC(t0), -12 * v_age)- NUMTODSINTERVAL(MOD(p*7, 365), 'DAY'); 
      -- v_age년 전 같은 달 에서 며칠을 빼서 다양한 생년월일 구하기
      -- Oracle 함수로 숫자를 기간으로 바꿔줌 NUMTODSINTERVAL
    
      INSERT INTO patient(full_name, birth_dt, gender, address)
      VALUES (
        '환자_'||TO_CHAR(p,'FM000'),
        v_birth,
        g,
        v_addr
      )
      RETURNING patient_id INTO v_pat_id;  --pk patient_id에 보관
    
      pat_ids(p) := v_pat_id;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('patient: '||c_pat); -- 생성된 patient 수 출력
  
-- APPOINTMENT 생성 (최종: 유니크 0%, 재실행에도 안전)
-- provider별로 '마지막 활성예약(N)' 다음 30분 슬롯부터 단조 증가
-- 충돌나면 다음 30분으로 자동 밀면서 성공할 때까지 시도
-- 샘플은 취소 없이 전부 N 

DECLARE
  per_prov        PLS_INTEGER := FLOOR(c_appt / prov_ids.COUNT);
  extra           PLS_INTEGER := MOD(c_appt, prov_ids.COUNT);
  slots_per_day   CONSTANT PLS_INTEGER := 48; -- 30분 × 24h
  idx             PLS_INTEGER := 0;           -- 전체 appt 인덱스(배열 캐시용)
BEGIN
  FOR pidx IN 1..prov_ids.COUNT LOOP
    DECLARE
      gen_count      PLS_INTEGER := per_prov + CASE WHEN pidx <= extra THEN 1 ELSE 0 END;
      prov_day_bias  PLS_INTEGER := MOD(pidx-1, 5);      -- 의사별 시작일 분산(0..4일)
      base_ts        TIMESTAMP   := slot_time(t0, prov_day_bias, 0);
      last_active_ts TIMESTAMP;
      start_slot     PLS_INTEGER := 0;                   -- 이 의사의 시작 슬롯 번호
    BEGIN
      -- 1) 기존 '취소=N'의 최대 시각을 찾아 그 다음 슬롯부터 시작
      SELECT MAX(appt_dt)
        INTO last_active_ts
        FROM appointment
       WHERE provider_id = prov_ids(pidx)
         AND cancel_yn   = 'N';

      IF last_active_ts IS NOT NULL THEN
        start_slot := FLOOR(((CAST(last_active_ts AS DATE) - CAST(base_ts AS DATE)) * 1440) / 30) + 1;
        IF start_slot < 0 THEN start_slot := 0; END IF;
      END IF;

      -- 충돌 시 다음 30분으로 밀기
      FOR j IN 1..gen_count LOOP
        v_pat_id := pat_ids(1 + MOD(idx, c_pat));

        DECLARE
          abs_slot    PLS_INTEGER := start_slot + (j-1); 
          day_off     PLS_INTEGER;
          minute_slot PLS_INTEGER;
          ts          TIMESTAMP;
          cny         CHAR(1) := 'N';   -- 샘플은 전부 활성N
          cdt         TIMESTAMP := NULL;
        BEGIN
          -- 충돌이면 30분씩 뒤로 밀어서 재시도
          LOOP
            day_off     := prov_day_bias + FLOOR(abs_slot / slots_per_day);
            minute_slot := MOD(abs_slot, slots_per_day);           -- 0..47
            ts          := slot_time(t0, day_off, minute_slot);    -- 정각/30분 보장

            BEGIN
              INSERT INTO appointment(patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
              VALUES (v_pat_id, prov_ids(pidx), ts, cny, cdt)
              RETURNING appt_id INTO v_appt_id;
              EXIT;  -- 성공 시 루프 탈출
            EXCEPTION
              WHEN DUP_VAL_ON_INDEX THEN
                abs_slot := abs_slot + 1;  -- 같은 슬롯 점유 중 → 다음 30분으로
            END;
          END LOOP;

          -- 배열 캐시(뒤 ENCOUNTER에서 사용)
          idx               := idx + 1;
          appt_ids(idx)     := v_appt_id;
          appt_pid(idx)     := v_pat_id;
          appt_prv(idx)     := prov_ids(pidx);
          appt_dt_tab(idx)  := ts;
        END;
      END LOOP;
    END;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('appointment: '||idx);
END;

  -- ENCOUNTER 생성
  DECLARE
    n_ip       PLS_INTEGER := ROUND(c_enc * 0.20);   -- IP 20%
    n_op       PLS_INTEGER := c_enc - n_ip;          -- 나머지 OP
    ap_i       PLS_INTEGER := 1;                     -- OP 스캔 인덱스
    made_op    PLS_INTEGER := 0;                     -- 만든 OP 수
    made_total PLS_INTEGER := 0;                     -- 만든 Encounter 총합(OP+IP)

    TYPE bool_map IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    used_appt  bool_map;

    idx_enc    PLS_INTEGER;                          -- enc_* 배열 저장용 인덱스(1-based)
  BEGIN
    --  OP 생성 (예약 기반)
    WHILE made_op < n_op LOOP
      EXIT WHEN ap_i > c_appt;

      IF appt_ids.EXISTS(ap_i) THEN
        DECLARE
          apid     NUMBER := appt_ids(ap_i);
          cny      CHAR(1);
          ts       TIMESTAMP;
          pv       NUMBER;
          pt       NUMBER;
          visit_ts TIMESTAMP;
        BEGIN
          SELECT cancel_yn, appt_dt, provider_id, patient_id
            INTO cny, ts, pv, pt
            FROM appointment
           WHERE appt_id = apid;

          IF cny = 'Y' OR (used_appt.EXISTS(apid) AND used_appt(apid)) THEN
            ap_i := ap_i + 1;
            CONTINUE;
          END IF;

          visit_ts := ts + NUMTODSINTERVAL(TRUNC(DBMS_RANDOM.VALUE(0,11)), 'MINUTE');

          INSERT INTO encounter(patient_id, provider_id, encounter_type, visit_dt, appt_id)
          VALUES (pt, pv, 'OP', visit_ts, apid)
          RETURNING encounter_id INTO v_enc_id;

          used_appt(apid) := TRUE;

          made_op    := made_op + 1;
          made_total := made_total + 1;

          idx_enc := enc_ids.COUNT + 1;
          enc_ids(idx_enc)   := v_enc_id;
          enc_pid(idx_enc)   := pt;
          enc_type(idx_enc)  := 'OP';
          enc_visit(idx_enc) := visit_ts;

          ap_i := ap_i + 1;
        END;
      ELSE
        EXIT;
      END IF;
    END LOOP;

    --  IP 생성 (예약 기반)
    DECLARE
      ap_j    PLS_INTEGER := 1;   -- IP용 예약 스캔 인덱스
      made_ip PLS_INTEGER := 0;
    BEGIN
      WHILE made_ip < n_ip LOOP
        EXIT WHEN ap_j > c_appt;

        IF NOT appt_ids.EXISTS(ap_j) THEN
          ap_j := ap_j + 1;
          CONTINUE;
        END IF;

        DECLARE
          apid     NUMBER := appt_ids(ap_j);
          cny      CHAR(1);
          ts       TIMESTAMP;
          pv       NUMBER;
          pt       NUMBER;
          visit_ts TIMESTAMP;
          ad       TIMESTAMP;
          dd       TIMESTAMP;
        BEGIN
          ap_j := ap_j + 1;

          IF used_appt.EXISTS(apid) THEN
            CONTINUE;
          END IF;

          SELECT cancel_yn, appt_dt, provider_id, patient_id
            INTO cny, ts, pv, pt
            FROM appointment
           WHERE appt_id = apid;

          IF cny = 'Y' THEN
            CONTINUE;
          END IF;

          visit_ts := ts + NUMTODSINTERVAL(TRUNC(DBMS_RANDOM.VALUE(0,11)), 'MINUTE');
          ad       := visit_ts;
          dd       := CASE
                        WHEN MOD(made_total + made_ip, 6) = 0 THEN NULL
                        ELSE ad
                             + NUMTODSINTERVAL(TRUNC(DBMS_RANDOM.VALUE(3, 31)), 'DAY')
                             + NUMTODSINTERVAL(TRUNC(DBMS_RANDOM.VALUE(0, 24)), 'HOUR')
                      END;

          INSERT INTO encounter(patient_id, provider_id, encounter_type, visit_dt, admit_dt, discharge_dt, appt_id)
          VALUES (pt, pv, 'IP', visit_ts, ad, dd, apid)
          RETURNING encounter_id INTO v_enc_id;

          used_appt(apid) := TRUE;

          made_ip    := made_ip + 1;
          made_total := made_total + 1;

          idx_enc := enc_ids.COUNT + 1;
          enc_ids(idx_enc)   := v_enc_id;
          enc_pid(idx_enc)   := pt;
          enc_type(idx_enc)  := 'IP';
          enc_visit(idx_enc) := visit_ts;
          enc_admit(idx_enc) := ad;
          enc_dis(idx_enc)   := dd;
        END;
      END LOOP;
    END;

    DBMS_OUTPUT.PUT_LINE(
      'encounter: '||made_total||' (예약OP ~'||ROUND(100*n_op/GREATEST(c_enc,1))
      ||'%, IP ~'||ROUND(100*n_ip/GREATEST(c_enc,1))||')'
    );
  END;

-- PATIENT_EVENT 
-- - OP: visit+0~5분 시작, 1~2건(검사/처방), 2건이면 10분 간격
-- - IP: admit(없으면 visit)+0~5분 시작, 3~4건(처/수/(투)/검)
--       퇴원 있으면 마지막=검사(퇴원 8분 전), 없으면 입원 2~7일 랜덤 끝-8분
--       나머지는 첫 시작~마지막 사이 균등 간격(분)
DECLARE
  made        PLS_INTEGER := 0;
  base        TIMESTAMP;
  t0          TIMESTAMP;
  last_start  TIMESTAMP;
  n           PLS_INTEGER;
  step_min    PLS_INTEGER;
  tp          VARCHAR2(10);

  -- 정수 랜덤
  FUNCTION r(lo PLS_INTEGER, hi PLS_INTEGER) RETURN PLS_INTEGER IS
  BEGIN RETURN TRUNC(DBMS_RANDOM.VALUE(lo, hi+1)); END;
BEGIN
  FOR i IN 1..enc_ids.COUNT LOOP
    EXIT WHEN made >= c_evt;

    IF enc_type(i) = 'OP' THEN
      -- OP: 1~2건, 0~5분 시작
      base := NVL(enc_visit(i), SYSTIMESTAMP);
      t0   := base + NUMTODSINTERVAL(r(0,5), 'MINUTE');

      IF r(1,2) = 1 THEN
        tp := CASE WHEN r(1,2)=1 THEN '검사' ELSE '처방' END;
        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i), t0, tp, 'OP 자동생성');
        made := made + 1;
      ELSE
        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i), t0, '검사', 'OP 자동생성');
        made := made + 1; EXIT WHEN made >= c_evt;

        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i), t0 + INTERVAL '10' MINUTE, '처방', 'OP 자동생성');
        made := made + 1;
      END IF;

    ELSE
      -- IP: 3~4건, 마지막은 반드시 '검사'
      base := NVL(enc_admit(i), enc_visit(i));
      t0   := base + NUMTODSINTERVAL(r(0,5), 'MINUTE');

      IF enc_dis.EXISTS(i) AND enc_dis(i) IS NOT NULL THEN
        last_start := enc_dis(i) - INTERVAL '8' MINUTE;                 -- 퇴원 8분 전
      ELSE
        last_start := base + NUMTODSINTERVAL(r(2,7), 'DAY') - INTERVAL '8' MINUTE; -- 2~7일 랜덤
      END IF;
      IF last_start < t0 THEN last_start := t0; END IF;                 -- 안전장치

      n := r(3,4);                                                       -- 3 or 4
      -- t0~last_start 사이를 (n-1)등분(분 단위, 음수면 0으로)
      step_min := GREATEST(0, FLOOR( ((CAST(last_start AS DATE) - CAST(t0 AS DATE)) * 1440)
                                     / GREATEST(n-1,1) ));

      -- 앞쪽 n-1건: 처방 → 수술 → (투약)
      INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
      VALUES (enc_pid(i), enc_ids(i), t0, '처방', 'IP 자동생성');
      made := made + 1; EXIT WHEN made >= c_evt;

      IF n >= 3 THEN
        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i),
                t0 + NUMTODSINTERVAL(step_min, 'MINUTE'), '수술', 'IP 자동생성');
        made := made + 1; EXIT WHEN made >= c_evt;
      END IF;

      IF n = 4 THEN
        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i),
                t0 + NUMTODSINTERVAL(2*step_min, 'MINUTE'), '투약', 'IP 자동생성');
        made := made + 1; EXIT WHEN made >= c_evt;
      END IF;

      -- 마지막: '검사'를 last_start에 확정
      INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
      VALUES (enc_pid(i), enc_ids(i), last_start, '검사', 'IP 자동생성');
      made := made + 1;
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('patient_event: '||made);
END;

END;
/