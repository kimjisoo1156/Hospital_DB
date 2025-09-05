SET SERVEROUTPUT ON
DECLARE
  v_patient_id patient.patient_id%TYPE;
  v_name       patient.full_name%TYPE;
  v_birth      patient.birth_dt%TYPE;
  v_gender     patient.gender%TYPE;

  PROCEDURE print_patient(p_id IN NUMBER) IS
  BEGIN
    BEGIN
      SELECT full_name, birth_dt, gender
        INTO v_name, v_birth, v_gender
        FROM patient
       WHERE patient_id = p_id;

      DBMS_OUTPUT.PUT_LINE(
        '조회됨 -> ID='||p_id||
        ', NAME='||v_name||
        ', BIRTH='||TO_CHAR(v_birth,'YYYY-MM-DD')||
        ', GENDER='||NVL(v_gender,'NULL')
      );
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('조회 실패 (NO_DATA_FOUND): ID='||p_id);
    END;
  END;
BEGIN

  DBMS_OUTPUT.PUT_LINE(' 환자 CRUD 데모 시작 ');

  -- INSERT
  INSERT INTO patient (full_name, birth_dt, gender)
  VALUES ('홍길동', DATE '1990-01-01', 'M')
  RETURNING patient_id INTO v_patient_id;
  DBMS_OUTPUT.PUT_LINE('INSERT 완료: patient_id='||v_patient_id);
  print_patient(v_patient_id);

  -- UPDATE
  UPDATE patient
     SET full_name = '김철수'
   WHERE patient_id = v_patient_id;
  DBMS_OUTPUT.PUT_LINE('UPDATE 완료');
  print_patient(v_patient_id);

  -- DELETE
  DELETE FROM patient WHERE patient_id = v_patient_id;
  DBMS_OUTPUT.PUT_LINE('DELETE 완료');

  -- COMMIT → patient_history에 감사로그 영구 반영
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('patient_history 확인');
  FOR rec IN (
    SELECT hist_id, action, changed_at, old_values, new_values
      FROM patient_history
     WHERE patient_id = v_patient_id
     ORDER BY hist_id
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(
      '[HIST] action='||rec.action||
      ', at='||TO_CHAR(rec.changed_at,'YYYY-MM-DD HH24:MI:SS')||
      ', old={'||NVL(rec.old_values,'NULL')||'}'||
      ', new={'||NVL(rec.new_values,'NULL')||'}'
    );
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('데모 종료');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
/
