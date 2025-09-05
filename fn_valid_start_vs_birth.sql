CREATE OR REPLACE FUNCTION fn_valid_start_vs_birth(
  p_patient_id IN NUMBER,   -- 검사할 환자 PK
  p_start_ts   IN TIMESTAMP -- 검증 대상 시각(visit_dt/admit_dt)
) RETURN BOOLEAN
IS
  v_birth_dt patient.birth_dt%TYPE; -- 환자 생년월일
BEGIN
  -- 시작 시각이 없으면 실패
  IF p_start_ts IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 환자 생년월일 조회 없으면 NO_DATA_FOUND 발생
  SELECT birth_dt
    INTO v_birth_dt
    FROM patient
   WHERE patient_id = p_patient_id;

  -- 시작시각 >= 생년월일 이후면 통과
  RETURN (p_start_ts >= CAST(v_birth_dt AS TIMESTAMP));

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    -- 없는 환자면 실패 
    RETURN FALSE;
END;
/
