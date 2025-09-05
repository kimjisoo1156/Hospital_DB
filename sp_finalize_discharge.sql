CREATE OR REPLACE PROCEDURE sp_finalize_discharge(
  p_encounter_id IN encounter.encounter_id%TYPE,
  p_discharge_dt IN TIMESTAMP
) IS
  c_not_ip          CONSTANT PLS_INTEGER := -20101; -- IP 아님
  c_bad_order       CONSTANT PLS_INTEGER := -20102; -- 퇴원 < 입원
  c_event_after_dis CONSTANT PLS_INTEGER := -20104; -- 퇴원 이후 이벤트 존재

  v_patient_id encounter.patient_id%TYPE;
  v_type       encounter.encounter_type%TYPE;
  v_admit      encounter.admit_dt%TYPE;
  v_cnt        PLS_INTEGER;
BEGIN
  -- 부분 롤백 지점
  SAVEPOINT sp0;

  -- 대상 행 잠금(동시성 제어)
  SELECT patient_id, encounter_type, admit_dt
    INTO v_patient_id, v_type, v_admit
    FROM encounter
   WHERE encounter_id = p_encounter_id
   FOR UPDATE;

  -- 1 기본 검증
  IF v_type <> 'IP' THEN
    RAISE_APPLICATION_ERROR(c_not_ip, '입원(IP) 건이 아닙니다.');
  END IF;

  IF p_discharge_dt < v_admit THEN
    RAISE_APPLICATION_ERROR(c_bad_order, '퇴원시각이 입원시각보다 빠릅니다.');
  END IF;

  -- 2 퇴원일 업데이트(먼저 적용)
  UPDATE encounter
     SET discharge_dt = p_discharge_dt
   WHERE encounter_id = p_encounter_id;

  -- 3 사후 검증: 퇴원 이후 이벤트가 있으면 원복
  SELECT COUNT(*)
    INTO v_cnt
    FROM patient_event
   WHERE encounter_id = p_encounter_id
     AND event_dt > p_discharge_dt;

  IF v_cnt > 0 THEN
    ROLLBACK TO sp0;  -- 2에서 바꾼 값 되돌림
    RAISE_APPLICATION_ERROR(c_event_after_dis, '퇴원시각 이후의 환자 이벤트가 존재합니다.');
  END IF;

  -- COMMIT은 호출자가 제어
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO sp0;  -- 어떤 오류든 안전 복구
    RAISE;
END;
/
