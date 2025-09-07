SET SERVEROUTPUT ON
DECLARE
  TYPE t_numtab IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
  TYPE t_tstab IS TABLE OF TIMESTAMP     INDEX BY PLS_INTEGER;
  TYPE t_v2tab IS TABLE OF VARCHAR2(2)   INDEX BY PLS_INTEGER;

  c_depts    CONSTANT PLS_INTEGER := 3;    -- 부서 수: 내과/외과/피부과
  c_prov_pd  CONSTANT PLS_INTEGER := 4;    -- 부서당 의사 수
  c_pat      CONSTANT PLS_INTEGER := 500;  -- 생성할 환자 수
  c_appt     CONSTANT PLS_INTEGER := 600;  -- 생성할 예약 수
  c_enc      CONSTANT PLS_INTEGER := 500;  -- 생성할 encounter 수
  c_evt      CONSTANT PLS_INTEGER := 1000; -- 생성할 이벤트 수

  dept_ids     t_numtab;
  prov_ids     t_numtab;
  pat_ids      t_numtab;

  appt_ids     t_numtab;
  appt_pid     t_numtab;
  appt_prv     t_numtab;
  appt_dt_tab  t_tstab;

  enc_ids      t_numtab;
  enc_pid      t_numtab;
  enc_type     t_v2tab;
  enc_visit    t_tstab;
  enc_admit    t_tstab;
  enc_dis      t_tstab;

  v            PLS_INTEGER;
  t0           TIMESTAMP := TIMESTAMP '2025-08-25 09:00:00';

  dept_names   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('내과','외과','피부과');
  prov_names   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('김민수','이지은','박영희','최철수','정현우','한수진','오승현');

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

  g            CHAR(1);
  v_dept_id    NUMBER;
  v_prov_id    NUMBER;
  v_pat_id     NUMBER;
  v_appt_id    NUMBER;
  v_enc_id     NUMBER;

  v_name    VARCHAR2(100);
  v_addr    VARCHAR2(200);
  v_cnt     PLS_INTEGER;
  v_age     PLS_INTEGER;
  v_birth   DATE;

  FUNCTION slot_time(p_base TIMESTAMP, p_day_offset PLS_INTEGER, p_slot_idx PLS_INTEGER)
    RETURN TIMESTAMP
  IS
  BEGIN
    RETURN p_base
           + NUMTODSINTERVAL(p_day_offset, 'DAY')
           + NUMTODSINTERVAL(p_slot_idx*30, 'MINUTE');
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('데이터 생성 시작');

  -- DEPARTMENT
  FOR d IN 1..c_depts LOOP
    INSERT INTO department(dept_name)
    VALUES (dept_names(d))
    RETURNING dept_id INTO v_dept_id;
    dept_ids(d) := v_dept_id;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('department: '||c_depts);

  -- PROVIDER
  v := 0;
  FOR d IN 1..c_depts LOOP
    FOR k IN 1..c_prov_pd LOOP
      v := v + 1;
      v_name := prov_names( MOD(v-1, prov_names.COUNT) + 1 );
      INSERT INTO provider(provider_name, dept_id)
      VALUES ('Dr_'||dept_names(d)||'_'||TO_CHAR(k,'FM00')||'_'||v_name, dept_ids(d))
      RETURNING provider_id INTO v_prov_id;
      prov_ids(v) := v_prov_id;
    END LOOP;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('provider: '||v);

  -- PATIENT
  FOR p IN 1..c_pat LOOP
    g := CASE WHEN MOD(p,2)=0 THEN 'M' ELSE 'F' END;

    v_cnt := MOD(p-1, 100) + 1;
    IF v_cnt <= 60 THEN
      v_addr := '서울특별시 ' || seoul_d( MOD(p-1, seoul_d.COUNT) + 1 );
    ELSIF v_cnt <= 85 THEN
      v_addr := '경기도 ' || gyeonggi_d( MOD(p-1, gyeonggi_d.COUNT) + 1 );
    ELSE
      v_addr := other_addrs( MOD(p-1, other_addrs.COUNT) + 1 );
    END IF;

    v_age   := MOD(p-1, 71) + 10; -- 10..80
    v_birth := ADD_MONTHS(TRUNC(t0), -12 * v_age) - NUMTODSINTERVAL(MOD(p*7, 365), 'DAY');

    INSERT INTO patient(full_name, birth_dt, gender, address)
    VALUES ('환자_'||TO_CHAR(p,'FM000'), v_birth, g, v_addr)
    RETURNING patient_id INTO v_pat_id;

    pat_ids(p) := v_pat_id;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('patient: '||c_pat);

  ------------------------------------------------------------------
  -- APPOINTMENT
  --  - 같은 provider 같은 시각은 유니크(슬롯 충돌 시 30분 뒤로 밀어 재시도)
  --  - 같은 환자 같은 시각에 이미 활성예약(N)이 있으면, 즉시 취소(Y)로 INSERT
  --    (cancel_dt = appt_dt - 1시간)
  ------------------------------------------------------------------
  DECLARE
    per_prov        PLS_INTEGER := FLOOR(c_appt / prov_ids.COUNT);
    extra           PLS_INTEGER := MOD(c_appt, prov_ids.COUNT);
    slots_per_day   CONSTANT PLS_INTEGER := 48;
    idx_ap          PLS_INTEGER := 0;
  BEGIN
    FOR pidx IN 1..prov_ids.COUNT LOOP
      DECLARE
        gen_count      PLS_INTEGER := per_prov + CASE WHEN pidx <= extra THEN 1 ELSE 0 END;
        prov_day_bias  PLS_INTEGER := MOD(pidx-1, 5);
        base_ts        TIMESTAMP   := slot_time(t0, prov_day_bias, 0);
        last_active_ts TIMESTAMP;
        start_slot     PLS_INTEGER := 0;
      BEGIN
        SELECT MAX(appt_dt)
          INTO last_active_ts
          FROM appointment
         WHERE provider_id = prov_ids(pidx)
           AND cancel_yn   = 'N';

        IF last_active_ts IS NOT NULL THEN
          start_slot := FLOOR(((CAST(last_active_ts AS DATE) - CAST(base_ts AS DATE)) * 1440) / 30) + 1;
          IF start_slot < 0 THEN start_slot := 0; END IF;
        END IF;

        FOR j IN 1..gen_count LOOP
          v_pat_id := pat_ids(1 + MOD(idx_ap, c_pat));

          DECLARE
            abs_slot    PLS_INTEGER := start_slot + (j-1);
            day_off     PLS_INTEGER;
            minute_slot PLS_INTEGER;
            ts          TIMESTAMP;
            v_exists    NUMBER;
          BEGIN
            -- 슬롯 충돌이면 30분씩 뒤로 밀면서 재시도
            LOOP
              day_off     := prov_day_bias + FLOOR(abs_slot / slots_per_day);
              minute_slot := MOD(abs_slot, slots_per_day);
              ts          := slot_time(t0, day_off, minute_slot);

              -- 같은 환자 같은 시각에 이미 활성 예약(N)이 있는지 확인
              SELECT COUNT(*)
                INTO v_exists
                FROM appointment
               WHERE patient_id = v_pat_id
                 AND appt_dt    = ts
                 AND cancel_yn  = 'N';

              BEGIN
                IF v_exists > 0 THEN
                  -- 이미 같은 환자·같은 시각에 활성예약 존재 → 취소로 즉시 기록
                  INSERT INTO appointment(patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
                  VALUES (v_pat_id, prov_ids(pidx), ts, 'Y', ts - INTERVAL '1' HOUR)
                  RETURNING appt_id INTO v_appt_id;
                ELSE
                  -- 정상 활성 예약
                  INSERT INTO appointment(patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
                  VALUES (v_pat_id, prov_ids(pidx), ts, 'N', NULL)
                  RETURNING appt_id INTO v_appt_id;
                END IF;
                EXIT; -- 성공 시 루프 탈출
              EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                  -- 같은 provider가 이미 그 30분 슬롯을 점유 → 다음 슬롯으로 이동
                  abs_slot := abs_slot + 1;
              END;
            END LOOP;

            idx_ap             := idx_ap + 1;
            appt_ids(idx_ap)   := v_appt_id;
            appt_pid(idx_ap)   := v_pat_id;
            appt_prv(idx_ap)   := prov_ids(pidx);
            appt_dt_tab(idx_ap):= ts;
          END;
        END LOOP;
      END;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('appointment: '||idx_ap);
  END;

  ------------------------------------------------------------------
  -- ENCOUNTER (cancel_yn = 'N'만 대상)
  ------------------------------------------------------------------
  DECLARE
    n_ip       PLS_INTEGER := ROUND(c_enc * 0.20);
    n_op       PLS_INTEGER := c_enc - n_ip;
    ap_i       PLS_INTEGER := 1;
    made_op    PLS_INTEGER := 0;
    made_total PLS_INTEGER := 0;

    TYPE bool_map IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    used_appt  bool_map;

    idx_enc    PLS_INTEGER;
  BEGIN
    -- OP
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

    -- IP
    DECLARE
      ap_j    PLS_INTEGER := 1;
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

  ------------------------------------------------------------------
  -- PATIENT_EVENT
  ------------------------------------------------------------------
  DECLARE
    made        PLS_INTEGER := 0;
    base        TIMESTAMP;
    t0_         TIMESTAMP;
    last_start  TIMESTAMP;
    n           PLS_INTEGER;
    step_min    PLS_INTEGER;
    tp          VARCHAR2(10);

    FUNCTION r(lo PLS_INTEGER, hi PLS_INTEGER) RETURN PLS_INTEGER IS
    BEGIN RETURN TRUNC(DBMS_RANDOM.VALUE(lo, hi+1)); END;
  BEGIN
    FOR i IN 1..enc_ids.COUNT LOOP
      EXIT WHEN made >= c_evt;

      IF enc_type(i) = 'OP' THEN
        base := NVL(enc_visit(i), SYSTIMESTAMP);
        t0_  := base + NUMTODSINTERVAL(r(0,5), 'MINUTE');

        IF r(1,2) = 1 THEN
          tp := CASE WHEN r(1,2)=1 THEN '검사' ELSE '처방' END;
          INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
          VALUES (enc_pid(i), enc_ids(i), t0_, tp, 'OP 자동생성');
          made := made + 1;
        ELSE
          INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
          VALUES (enc_pid(i), enc_ids(i), t0_, '검사', 'OP 자동생성');
          made := made + 1; EXIT WHEN made >= c_evt;

          INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
          VALUES (enc_pid(i), enc_ids(i), t0_ + INTERVAL '10' MINUTE, '처방', 'OP 자동생성');
          made := made + 1;
        END IF;

      ELSE
        base := NVL(enc_admit(i), enc_visit(i));
        t0_  := base + NUMTODSINTERVAL(r(0,5), 'MINUTE');

        IF enc_dis.EXISTS(i) AND enc_dis(i) IS NOT NULL THEN
          last_start := enc_dis(i) - INTERVAL '8' MINUTE;
        ELSE
          last_start := base + NUMTODSINTERVAL(r(2,7), 'DAY') - INTERVAL '8' MINUTE;
        END IF;
        IF last_start < t0_ THEN last_start := t0_; END IF;

        n := r(3,4);
        step_min := GREATEST(0,
          FLOOR(((CAST(last_start AS DATE) - CAST(t0_ AS DATE)) * 1440) / GREATEST(n-1,1)));

        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i), t0_, '처방', 'IP 자동생성');
        made := made + 1; EXIT WHEN made >= c_evt;

        IF n >= 3 THEN
          INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
          VALUES (enc_pid(i), enc_ids(i), t0_ + NUMTODSINTERVAL(step_min, 'MINUTE'), '수술', 'IP 자동생성');
          made := made + 1; EXIT WHEN made >= c_evt;
        END IF;

        IF n = 4 THEN
          INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
          VALUES (enc_pid(i), enc_ids(i), t0_ + NUMTODSINTERVAL(2*step_min, 'MINUTE'), '투약', 'IP 자동생성');
          made := made + 1; EXIT WHEN made >= c_evt;
        END IF;

        INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
        VALUES (enc_pid(i), enc_ids(i), last_start, '검사', 'IP 자동생성');
        made := made + 1;
      END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('patient_event: '||made);
  END;

END;
/

