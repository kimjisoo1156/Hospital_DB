CREATE OR REPLACE TRIGGER trg_evt_time_guard
BEFORE INSERT OR UPDATE ON patient_event
FOR EACH ROW
DECLARE
  v_type  encounter.encounter_type%TYPE;
  v_visit encounter.visit_dt%TYPE;
  v_admit encounter.admit_dt%TYPE;
  v_dis   encounter.discharge_dt%TYPE;
BEGIN

  SELECT encounter_type, visit_dt, admit_dt, discharge_dt
    INTO v_type, v_visit, v_admit, v_dis
    FROM encounter
   WHERE encounter_id = :NEW.encounter_id
     AND patient_id    = :NEW.patient_id;

  IF v_type = 'OP' THEN
    IF :NEW.event_dt < v_visit THEN
      RAISE_APPLICATION_ERROR(-20130, 'OP 이벤트시간은 visit_dt 이전일 수 없습니다.');
    END IF;
  ELSE 
    IF :NEW.event_dt < v_admit THEN
      RAISE_APPLICATION_ERROR(-20131, 'IP 이벤트시간은 admit_dt 이전일 수 없습니다.');
    END IF;
    IF v_dis IS NOT NULL AND :NEW.event_dt > v_dis THEN
       RAISE_APPLICATION_ERROR(-20132, 'IP 이벤트시간은 discharge_dt 이후일 수 없습니다.');
    END IF;
  END IF;
END;
/
