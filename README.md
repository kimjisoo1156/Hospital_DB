## 🏥 Hospital DB (Oracle)
환자→예약→방문(OP/IP)→이벤트→퇴원 흐름을 Oracle로 구현한 병원 정보 관리 시스템입니다.<br>
데이터 무결성(참조, 값 범위, 시간 선후관계)은 DB 제약으로 보장하고, 변경 이력·입력 전·후 처리는 트리거로 수행했으며, <br>
퇴원 검증 등 복합 규칙은 프로시저로 구현했습니다. 멀티테넌트(CDB/PDB)는 Oracle 12c부터 도입되었고, 
<br> 본 프로젝트는 Oracle 21c의 PDB 환경에서 수행했습니다.<br>
(세부 설계 이유와 제약조건 선정 배경은 [Notion 문서](https://jskim1156.notion.site/Hospital-DB-264f0a49d3928038824acc47c7e862b6)에 상세히 기록해 두었습니다.)

---

### 프로젝트 목적
- 멀티테넌트(CDB/PDB) 개념을 이해하고 Oracle 아키텍처 기초를 파악한다.
- 의료 도메인 규칙을 DB 레벨에서 안전하게 모델링하고 검증한다.
- PL/SQL 문법(프로시저, 트리거, 커서, 동적 SQL, 예외 처리)을 실전 적용한다.
- 인덱스 설계 감각을 체득한다.
- 인덱스 유무에 따른 실행계획·실행통계 비교로 기초 튜닝 감각을 확보한다.
- ERwin으로 논리/물리 ERD를 설계하고, SQL Developer에 적응하며, Oracle 백업/복원을 실습한다

### ERD_논리
<img width="841" height="643" alt="ERD_논리2" src="https://github.com/user-attachments/assets/db968d75-44cd-43b9-a45d-71c134a3dbe2" />


### ERD_물리
<img width="1015" height="596" alt="ERD_물리2" src="https://github.com/user-attachments/assets/36b855c0-30c4-4271-a38c-9e554769638f" />


### 기능 구현
1. **스토어드 프로시저**
   - patient_curd : 환자 insert/update/select/delete 처리 - plsql 익명 블록
   - sp_finalize_discharge: 퇴원 처리 및 데이터 정합성 검증 - 사용자 정의 예외, Savepoint / Rollback 처리  
   - sp_search_patient_events_dyn: patient_event에서 기간/환자/내원/이벤트타입/퇴원여부 옵션 필터 후 최신순 상위 N건 조회 – REF CURSOR + 동적 SQL
    최신순으로 상위 N건만 동적 조회
2. **커서 /동적 SQL 활용**
   - tree_day_rang_cursor: 환자 이벤트를 3일치씩, 10건 단위로 반복 처리 – 명시적 커서 사용 및 NO_DATA_FOUND 예외처리
   - ip_threshold_peak : 입원 이벤트 중 특정 기간(p_days) 이상 남은 이벤트 건수 집계 + 가장 바빴던 7일 구간 식별 - JOIN, 날짜 연산, 윈도우 함수, 복합쿼리
3. **트리거**
   - trg_patient_audit: 환자 정보 변경 시 HistoryTable에 로그 기록 - AFTER insert/update/delete 
   - trg_enc_start_vs_birth: 방문 정보 입력 전, 사용자 정의 함수 호출로 환자 생년월일 이후인지 검증 – BEFORE INSERT/UPDATE
4. **함수**
   - fn_valid_start_vs_birth: 방문일시가 환자 생년월일 이후인지 검증 - 사용자 정의 함수 작성
5. **성능 고려**
   - explain_xplan_index : IX_PH_PAT_TIME 인덱스 유무에 따른 성능 차이 분석 - explain plan + /*+ gather_plan_statistics */ 활용
6. **테스트 및 단위 검증**
   - TEST 폴더에 각 기능별 SQL 스크립트 작성 (트리거 동작 검증, 예외 처리 테스트, 인덱스 성능 비교 등)

### 🗂️ 프로젝트 구조
<img width="308" height="495" alt="프로젝트 구조3" src="https://github.com/user-attachments/assets/0ecff1c0-e562-4346-99ac-ef21e82959fc" />

### ⚙️ 개발 환경
- **DBMS**: Oracle XE 21c  
- **Tool**: SQL Developer, ERwin Data Modeler
- **언어**: Oracle SQL, PL/SQL  
- **OS**: Windows 11  
---
