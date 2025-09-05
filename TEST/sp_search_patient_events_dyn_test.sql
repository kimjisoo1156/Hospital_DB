VAR rc REFCURSOR 
BEGIN 
    sp_search_patient_events_dyn( 
    p_from_dt => DATE '2025-08-20', 
    p_to_dt => DATE '2025-08-31', 
    p_patient_id => NULL, 
    p_encounter_id => NULL, 
    p_ev1 => '검사', 
    p_ev2 => '투약', 
    p_ev3 => NULL, 
    p_ev4 => NULL, 
    p_discharged_only => 0, 
    p_row_limit => 100, 
    p_rc => :rc 
    );    
END; 
/ 
PRINT rc;