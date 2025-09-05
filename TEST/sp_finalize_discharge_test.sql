-- 퇴원일자 바뀜

-- auto_fix는 마지막 이벤트 타입이 검사가 아닐 때만 같은 시각에 검사를 추가해 주는 옵션

BEGIN
  sp_finalize_discharge(
    p_encounter_id => 455,
    p_discharge_dt => TIMESTAMP '2025-09-21 20:50:00',
    p_auto_fix     => FALSE
  );
END;
/

-- select * from encounter where encounter_id = 455

-- 퇴원시각보다 늦은 이벤트 존재 예외
BEGIN
  sp_finalize_discharge(
    p_encounter_id => 455,
    p_discharge_dt => SYSTIMESTAMP,
    p_auto_fix     => TRUE
  );
END;
/

-- select * from patient_event where encounter_id = 455