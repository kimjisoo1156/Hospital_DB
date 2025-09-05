create or replace TRIGGER trg_patient_audit
AFTER INSERT OR UPDATE OR DELETE ON patient
FOR EACH ROW
DECLARE
  v_old_values CLOB;
  v_new_values CLOB;
  v_action VARCHAR2(10);
BEGIN

  IF INSERTING THEN
    v_action := 'INSERT';
  ELSIF UPDATING THEN
    v_action := 'UPDATE';
  ELSIF DELETING THEN
    v_action := 'DELETE';
  END IF;

  -- old_values 문자열 
  IF DELETING OR UPDATING THEN
    v_old_values := 'ID='||:OLD.patient_id
                 || ', NAME='||:OLD.full_name
                 || ', BIRTH='||TO_CHAR(:OLD.birth_dt,'YYYY-MM-DD')
                 || ', GENDER='||NVL(:OLD.gender,'NULL');
  END IF;

  -- new_values 문자열 
  IF INSERTING OR UPDATING THEN
    v_new_values := 'ID='||:NEW.patient_id
                 || ', NAME='||:NEW.full_name
                 || ', BIRTH='||TO_CHAR(:NEW.birth_dt,'YYYY-MM-DD')
                 || ', GENDER='||NVL(:NEW.gender,'NULL');
  END IF;

  -- 히스토리 테이블에 이력 남기기
  INSERT INTO patient_history (patient_id, action, old_values, new_values)
  VALUES (
    NVL(:NEW.patient_id, :OLD.patient_id),
    v_action,
    v_old_values,
    v_new_values
  );
END;
