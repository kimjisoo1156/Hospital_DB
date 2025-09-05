CREATE OR REPLACE TRIGGER trg_after_discharge
BEFORE INSERT OR UPDATE OF event_dt ON patient_event
FOR EACH ROW
DECLARE v_dis encounter.discharge_dt%TYPE; v_type encounter.encounter_type%TYPE;
BEGIN
  SELECT encounter_type, discharge_dt INTO v_type, v_dis
  FROM encounter WHERE encounter_id = :NEW.encounter_id;
  IF v_type='IP' AND v_dis IS NOT NULL AND :NEW.event_dt > v_dis THEN
    RAISE_APPLICATION_ERROR(-20106, '퇴원 시각 이후의 이벤트는 허용하지 않습니다.');
  END IF;
END;
/
