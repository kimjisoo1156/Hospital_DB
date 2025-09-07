SET SERVEROUTPUT ON

-- 함수 테스트
BEGIN
IF fn_valid_start_vs_birth(1, '2025-09-01') THEN
    DBMS_OUTPUT.PUT_LINE('OK');
  ELSE
    DBMS_OUTPUT.PUT_LINE('NO');
  END IF;
END  ;

-- 트리거 테스트 OP


SELECT patient_id, birth_dt FROM patient WHERE patient_id = 1;



INSERT INTO appointment (patient_id, provider_id, appt_dt)
VALUES (1, 1, SYSTIMESTAMP);


SELECT * FROM APPOINTMENT WHERE patient_id = 1;


select count(*) from appointment
select * from appointment order by appt_id desc

--같은시간대 같은  환자 같은 의사 예약 넣기



INSERT INTO appointment (patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
VALUES (1, 1, TIMESTAMP '2025-09-07 09:00:00', 'N', NULL);





INSERT INTO appointment (patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
VALUES (1, 88, TIMESTAMP '2025-09-05 09:00:00', 'N', NULL);

--정상적으로 예약건 새롭게 만들고
-- 해당건을 취소건으로 만든 다음에
--거기에 다시 새 예약건이 정상동작하는지 확인

INSERT INTO appointment (patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
VALUES (1, 1, TIMESTAMP '2025-09-07 09:00:00', 'N', NULL);

UPDATE appointment
   SET cancel_yn = 'Y',
       cancel_dt = appt_dt - INTERVAL '10' MINUTE   -- 예약 10분 전으로 기록
 WHERE appt_id = 702
 
   
SELECT * FROM appointment WHERE patient_id = 1;

INSERT INTO appointment (patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
VALUES (1, 1, TIMESTAMP '2025-09-05 09:00:00', 'N', NULL);



select * from encounter where patient_id = 1



-- 취소된 예약
INSERT INTO encounter (patient_id, provider_id, encounter_type, visit_dt, appt_id)
SELECT 1, 1, 'OP',
       CAST(birth_dt AS TIMESTAMP) + INTERVAL '1' DAY,
       702
FROM patient 
WHERE patient_id = 1;





-- 예약시간 15분뒤로...
INSERT INTO encounter (patient_id, provider_id, encounter_type, visit_dt, appt_id)
SELECT a.patient_id, a.provider_id, 'OP',
       a.appt_dt + INTERVAL '15' MINUTE,  
       a.appt_id
FROM appointment a
WHERE a.appt_id   = 703;


INSERT INTO encounter (patient_id, provider_id, encounter_type, visit_dt, appt_id)
SELECT a.patient_id, a.provider_id, 'OP',
       '2015-08-17 09:00:00',
       a.appt_id
FROM appointment a
WHERE a.appt_id   = 703;




-- 예약시간 10분뒤로...
INSERT INTO encounter (patient_id, provider_id, encounter_type, visit_dt, appt_id)
SELECT a.patient_id, a.provider_id, 'OP',
       a.appt_dt + INTERVAL '10' MINUTE,
       a.appt_id
FROM appointment a
WHERE a.appt_id   = 703;


-----------------------------------------------------------------------------------------------
-- ip
SELECT patient_id, birth_dt FROM patient WHERE patient_id = 2;

select * from appointment where patient_id = 2


-- 같은 의사가 아니니 예약 성공
INSERT INTO appointment (patient_id, provider_id, appt_dt, cancel_yn, cancel_dt)
VALUES (2, 3, TIMESTAMP '2025-09-07 09:00:00', 'N', NULL);

SELECT *
FROM appointment
WHERE appt_dt >= TIMESTAMP '2025-09-07 00:00:00'
  AND appt_dt <  TIMESTAMP '2025-09-08 00:00:00';


select * from encounter where patient_id = 2
  
-- 방문은 예약시간 5분뒤 입원은 예약시간 7분뒤
INSERT INTO encounter (patient_id, provider_id, encounter_type, visit_dt,admit_dt, discharge_dt, appt_id)
SELECT a.patient_id, 
       a.provider_id, 'IP',
       a.appt_dt + INTERVAL '5'  MINUTE, 
       a.appt_dt + INTERVAL '7'  MINUTE,   
       NULL,                                
       a.appt_id
FROM appointment a
WHERE a.appt_id   = 704;


  
  
-- 환자 이벤트 추가 

INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
SELECT e.patient_id, e.encounter_id, e.admit_dt - INTERVAL '15' MINUTE, '처방', 'T1'
FROM   encounter e
WHERE  e.appt_id = 704;


INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
SELECT e.patient_id, e.encounter_id, e.admit_dt + INTERVAL '15' MINUTE, '처방', 'T1'
FROM   encounter e
WHERE  e.appt_id = 704;


INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
SELECT e.patient_id, e.encounter_id, e.admit_dt + INTERVAL '30' MINUTE, '검사', 'T2'
FROM   encounter e
WHERE  e.appt_id = 704;


select * from patient_event where patient_id = 2

select * from encounter where encounter_id = 506



-- 퇴원일자가 입원한 시각보다 이른경우 
BEGIN
  sp_finalize_discharge(
    p_encounter_id => 506,
    p_discharge_dt => TIMESTAMP '2025-09-05 09:17:00'    
  );
END;
/

-- 퇴원시각 이후 환자 이벤트 존재하는 경우 
-- 입원보다 는 늦고 이벤트 시작보다는 전인 

BEGIN
  sp_finalize_discharge(
    p_encounter_id => 506,
    p_discharge_dt => TIMESTAMP '2025-09-07 09:17:00'    
  );
END;
/


-- 성공
BEGIN
  sp_finalize_discharge(
    p_encounter_id => 506,
    p_discharge_dt => TIMESTAMP '2025-09-07 09:40:00'
  );
END;
/



-- 퇴원시각 이후 환자 이벤트 추가 

INSERT INTO patient_event(patient_id, encounter_id, event_dt, event_type, note)
SELECT e.patient_id, e.encounter_id, e.discharge_dt + INTERVAL '15' MINUTE, '처방', 'T1'
FROM   encounter e
WHERE  e.appt_id = 704;




