CREATE OR REPLACE TRIGGER trg_enc_start_vs_birth
BEFORE INSERT OR UPDATE ON encounter
FOR EACH ROW
DECLARE
  v_appt_dt  appointment.appt_dt%TYPE;
  v_cancel   appointment.cancel_yn%TYPE;
BEGIN


  IF NOT fn_valid_start_vs_birth(:NEW.patient_id, :NEW.visit_dt) THEN
    RAISE_APPLICATION_ERROR(-20001, '방문 시각(visit_dt)이 환자 생년월일 이전입니다.');
  END IF;

 
  IF :NEW.encounter_type = 'IP' THEN
    IF NOT fn_valid_start_vs_birth(:NEW.patient_id, :NEW.admit_dt) THEN
      RAISE_APPLICATION_ERROR(-20002, '입원 시각(admit_dt)이 환자 생년월일 이전입니다.');
    END IF;
  END IF;
  
  SELECT appt_dt, cancel_yn
  INTO v_appt_dt, v_cancel
  FROM appointment
  WHERE appt_id = :NEW.appt_id;
  
  IF v_cancel = 'Y' THEN
    RAISE_APPLICATION_ERROR(-20010, '취소된 예약에는 encounter를 생성할 수 없습니다.');
  END IF;

  IF :NEW.visit_dt < v_appt_dt
     OR :NEW.visit_dt > v_appt_dt + INTERVAL '10' MINUTE THEN
    RAISE_APPLICATION_ERROR(-20011, 'visit_dt는 예약시각 이후 0~10분 이내여야 합니다.');
  END IF;

  -- IP이면 admit도 0~10분 윈도우
  IF :NEW.encounter_type = 'IP' THEN
    IF :NEW.admit_dt < v_appt_dt
       OR :NEW.admit_dt > v_appt_dt + INTERVAL '10' MINUTE THEN
      RAISE_APPLICATION_ERROR(-20012, 'admit_dt는 예약시각 이후 0~10분 이내여야 합니다.');
    END IF;
    -- visit ≤ admit
    IF :NEW.visit_dt > :NEW.admit_dt THEN
      RAISE_APPLICATION_ERROR(-20013, 'IP는 visit_dt가 admit_dt 이후일 수 없습니다.');
    END IF;
  END IF;

END;
/
