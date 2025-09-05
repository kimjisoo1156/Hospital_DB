-- 인덱스 안보이게 변경
ALTER INDEX IX_PH_PAT_TIME INVISIBLE;

-- 옵티마이저가 예상한 계획
EXPLAIN PLAN FOR
SELECT *
FROM (
    SELECT hist_id
    FROM   patient_history
    WHERE  patient_id = 1
    ORDER  BY changed_at DESC
)WHERE ROWNUM <= 100;

-- 출력
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());

-- 실제로 쿼리를 돌린 후에 실행계획과 실행통계를 생성
SELECT *
FROM(
    SELECT /*+ gather_plan_statistics */ hist_id, changed_at
    FROM   patient_history ph
    WHERE  patient_id = 1
    ORDER  BY changed_at DESC
)WHERE ROWNUM <= 100;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));


-- 인덱스 보이게 변경 
ALTER INDEX IX_PH_PAT_TIME VISIBLE;

EXPLAIN PLAN FOR
SELECT *
FROM (
    SELECT hist_id
    FROM   patient_history
    WHERE  patient_id = 1
    ORDER  BY changed_at DESC
)
WHERE ROWNUM <= 100;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());

SELECT *
FROM (
    SELECT /*+ gather_plan_statistics */ hist_id, changed_at
    FROM   patient_history ph
    WHERE  patient_id = 1
    ORDER  BY changed_at DESC
)
WHERE ROWNUM <= 100;
--FETCH FIRST 100 ROWS ONLY;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));









