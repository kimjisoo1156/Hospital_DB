SELECT
  pe.patient_id,
  pe.encounter_id,
  pe.event_dt,
  pe.event_type,
  pe.note
FROM patient_event pe
JOIN encounter e
  ON e.patient_id   = pe.patient_id
 AND e.encounter_id = pe.encounter_id
WHERE e.encounter_type = 'IP'                             
  AND pe.event_dt >= TIMESTAMP '2025-08-27 00:00:00'
  AND pe.event_dt <  TIMESTAMP '2025-08-30 00:00:00'       
ORDER BY pe.event_dt, pe.patient_id, pe.encounter_id;
