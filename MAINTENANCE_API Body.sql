create or replace PACKAGE BODY "MAINTENANCE_API" AS

   g_bResult      boolean;
   g_strText      varchar2(512);
   g_dtStartTime  date;
   g_dtEndTime    date;
   g_strTimeUsage varchar2(20);

PROCEDURE UpdateAccount AS
  
    l_iIndexCount NUMBER;
  
  BEGIN
    INSERT INTO account (account_id,account_name,account_group_id,account_type, created_date)
    SELECT account, description, account_grp, decode(res_bal,'R',1,'B',2,NULL), sysdate 
      FROM g_agrles.MV_AGLACCOUNTS
     WHERE client = 'XS' 
       AND status = 'N'
       AND account NOT IN (SELECT account_id FROM account);
  
     COMMIT;
     
     UPDATE account SET account_name = (SELECT description FROM g_agrles.MV_AGLACCOUNTS mv WHERE mv.client = 'XS' AND mv.account = account.account_id);
     
     COMMIT;
  END UpdateAccount;

PROCEDURE UpdateGeneralLedger AS
    l_iIndexCount NUMBER;
    l_iTblExists  NUMBER;
    l_iStatement  NUMBER;
    i_jobbID      VARCHAR2(50); 
   
BEGIN
  SELECT sysdate INTO g_dtStartTime from dual;

  -- Oppretter en jobbID
  SELECT sys_guid() INTO i_jobbID from dual;
  
  g_bResult := false;
  g_strText := 'START: UpdateGeneralLedger';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 0, i_jobbID);
    
    --Oppdaterer konto
    MAINTENANCE_API.UpdateAccount;
  g_strText := 'UpdateGeneralLedger: Account updated';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    
    -- Fjerner data for i år og i fjor
    DELETE FROM general_ledger 
     WHERE TO_NUMBER(SUBSTR(period,0,4)) >= to_number(to_char(SYSDATE,'YYYY'))-1
    AND source_id = 1;

    COMMIT;

    g_strText := 'UpdateGeneralLedger: DELETE rows from GL';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);


    -- Sletter indekser
    SELECT count(*) INTO l_iIndexCount FROM USER_INDEXES
      WHERE INDEX_NAME = 'GL_COMPANY_ID';
    IF l_iIndexCount > 0 THEN EXECUTE IMMEDIATE('DROP INDEX GL_COMPANY_ID'); END IF;
    
    SELECT count(*) INTO l_iIndexCount FROM USER_INDEXES
      WHERE INDEX_NAME = 'GL_PERIOD';
    IF l_iIndexCount > 0 THEN EXECUTE IMMEDIATE('DROP INDEX GL_PERIOD'); END IF;
    
    SELECT count(*) INTO l_iIndexCount FROM USER_INDEXES
      WHERE INDEX_NAME = 'GL_ACCOUNT';
    IF l_iIndexCount > 0 THEN EXECUTE IMMEDIATE('DROP INDEX GL_ACCOUNT'); END IF;
    
    SELECT count(*) INTO l_iIndexCount FROM USER_INDEXES
      WHERE INDEX_NAME = 'BIX_GL_SOURCE_ID';
    IF l_iIndexCount > 0 THEN EXECUTE IMMEDIATE('DROP INDEX BIX_GL_SOURCE_ID'); END IF;

    g_strText := 'UpdateGeneralLedger: Indexes deleted ';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);



    --Laster hovedbokstranser fra det materialiserte viewet i AGRLES.
    INSERT INTO general_ledger
    (company_id
    ,contra_company_id
    ,account_id
    ,responsible_id
    ,project_id
    ,work_order_id
    ,project_activity_id
    ,voob_id
    ,activity_id
    ,voucher_date
    ,period
    ,amount
    ,description
    ,voucher_no
    ,vouchertype_id
    ,ext_inv_ref
    ,apar_id
    ,source_id)
    SELECT
      client           -- Selskap
      ,dim_3            -- Melregn; Hvor att_3_id = 'U9' (Det forutsettes helhetlig bruk av denne nå, jfr H. Nøklegård)
      ,account          -- Konto
      ,decode(nvl(dim_1,' '),' ',null, dim_1 || client)   --ANSVAR
      ,decode(nvl(dim_2,' '),' ',null, dim_2 || client)   --Prosjekt
      ,decode(nvl(dim_4,' '),' ',null, dim_4 || client)   -- Arbordre
      ,dim_6            -- Proakt
      ,decode(nvl(dim_5,' '),' ',null, dim_5 || client)   --Prosjekt
      ,dim_7            -- Aktivitet
      ,voucher_date     -- Periode (bilagsdato)
      ,period           -- Regnskapsperiode
      ,amount           -- Beløp
      ,description      -- Bilagstekst
      ,voucher_no       -- Bilagsnummer
      ,voucher_type     -- Bilagsart
      ,ext_inv_ref      -- Fakturanummer
      ,apar_id          -- Kunde / Lev nr
      ,1                -- Kilde; 1=ERP
    FROM G_AGRLES.mv_agltransact
    WHERE client IN (SELECT company_id FROM company WHERE company_type_id IN (1,2,6,7,8,20))
      AND TO_NUMBER(SUBSTR(period,0,4)) >= to_number(to_char(SYSDATE,'YYYY'))-1;
  
    COMMIT;
    
    g_strText := 'UpdateGeneralLedger: INSERTED rows into GL';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    EXECUTE IMMEDIATE('CREATE INDEX GL_COMPANY_ID ON GENERAL_LEDGER ("COMPANY_ID")
      PCTFREE 10 INITRANS 2 MAXTRANS 255 COMPUTE STATISTICS 
      STORAGE ( INITIAL 65536 NEXT 1048576 MINEXTENTS 1 MAXEXTENTS 2147483645 PCTINCREASE 0 FREELISTS 1 FREELIST GROUPS 1 BUFFER_POOL DEFAULT )
      TABLESPACE "USERS"');

    g_strText := 'UpdateGeneralLedger: Index GL_COMPANY_ID created ';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    EXECUTE IMMEDIATE('CREATE INDEX GL_PERIOD ON GENERAL_LEDGER ("PERIOD")
      PCTFREE 10 INITRANS 2 MAXTRANS 255 COMPUTE STATISTICS 
      STORAGE ( INITIAL 65536 NEXT 1048576 MINEXTENTS 1 MAXEXTENTS 2147483645 PCTINCREASE 0 FREELISTS 1 FREELIST GROUPS 1 BUFFER_POOL DEFAULT )
      TABLESPACE "USERS"');
  
    g_strText := 'UpdateGeneralLedger: Index GL_PERIOD created';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    EXECUTE IMMEDIATE('CREATE INDEX GL_ACCOUNT ON GENERAL_LEDGER ("ACCOUNT_ID")
      PCTFREE 10 INITRANS 2 MAXTRANS 255 COMPUTE STATISTICS 
      STORAGE ( INITIAL 65536 NEXT 1048576 MINEXTENTS 1 MAXEXTENTS 2147483645 PCTINCREASE 0 FREELISTS 1 FREELIST GROUPS 1 BUFFER_POOL DEFAULT )
      TABLESPACE "USERS"');
 
    g_strText := 'UpdateGeneralLedger: Index GL_ACCOUNT created';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    EXECUTE IMMEDIATE('CREATE BITMAP INDEX BIX_GL_SOURCE_ID ON GENERAL_LEDGER ("SOURCE_ID")
      PCTFREE 10 INITRANS 2 MAXTRANS 255 COMPUTE STATISTICS 
      STORAGE ( INITIAL 65536 NEXT 1048576 MINEXTENTS 1 MAXEXTENTS 2147483645 PCTINCREASE 0 FREELISTS 1 FREELIST GROUPS 1 BUFFER_POOL DEFAULT )
      TABLESPACE "USERS"');

    g_strText := 'UpdateGeneralLedger: Index BIX_GL_SOURCE_ID created';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    UPDATE general_ledger SET contra_company_id = null WHERE contra_company_id NOT IN ( SELECT contra_company_id FROM company)
     AND TO_NUMBER(SUBSTR(period,0,4)) >= to_number(to_char(SYSDATE,'YYYY'))-1;

    g_strText := 'UpdateGeneralLedger: UPDATED GL with valid contra company';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

    EXECUTE IMMEDIATE('ANALYZE TABLE GENERAL_LEDGER ESTIMATE STATISTICS SAMPLE 40 PERCENT');

    g_strText := 'UpdateGeneralLedger: GL analyzed';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);
    
    INSERT INTO UPDATE_STATUS_SYSTEM_OBJECTS (SYSTEM_OBJECTS_ID,LAST_UPDATE) SELECT 1000, sysdate FROM dual;
    
    COMMIT;

    g_strText := 'UpdateGeneralLedger: Inserted row into UPDATE_STATUS_SYSTEM_OBJECTS';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);

  
    UpdateGeneralLedgerMatching(i_jobbID);

    g_strText := 'UpdateGeneralLedger: UpdateGeneralLedgerMatching() executed ';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 5, i_jobbID);
  
  SELECT sysdate INTO g_dtEndTime FROM dual;
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );

  g_strText := 'FINISH: UpdateGeneralLedger - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 0, i_jobbID);

EXCEPTION WHEN OTHERS THEN
   g_strText := 'ERROR: UpdateGeneralLedger:  - ErrorMessage: '|| SQLERRM || ' - Error in statement: ' || l_iStatement;
   g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedger', 0, i_jobbID);
    
END UpdateGeneralLedger;

PROCEDURE UpdateGeneralLedgerMatching (i_jobbID varchar2 default '') IS
    l_iPreviousPeriod NUMBER;
    l_iTblExists      NUMBER;
    l_iStatement      NUMBER;  -- Brukes i feilsøking - viser hvor vi er i koden
BEGIN
  SELECT sysdate INTO g_dtStartTime from dual;

  g_strText := 'START: UpdateGeneralLedgerMatching';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerMatching', 0, i_jobbID);

    -- Oppdatering av GL Matching 
    
    -- Går tilbake to måneder, dette er perioden det oppdateres data for. Hvis Januar benyttes periode åååå00.
    -- Endret 29.09.2015 fra å gå tilbake en måned, til to måneder. Dette pga at de innimellom slår sammen og rapporterer for to måneder (Brit).
    l_iStatement := 1;
    SELECT MIN(acc_period) INTO l_iPreviousPeriod 
      FROM period 
     WHERE date_from = ( SELECT to_date('01' || to_char(add_months(sysdate,-2),'MMYYYY'),'DDMMYYYY') FROM dual )
       AND substr(acc_period,5,2) NOT IN ('13');
    
    -- Slett midlertidig tabell
    l_iStatement := 2;
    SELECT count(*) INTO l_iTblExists FROM user_tables WHERE lower(table_name) = 'general_ledger_matching_period';
    IF l_iTblExists <> 0 THEN EXECUTE IMMEDIATE ('DROP TABLE general_ledger_matching_period'); END IF;
    
    l_iStatement := 3;
    EXECUTE IMMEDIATE ('CREATE TABLE general_ledger_matching_period AS SELECT * FROM general_ledger_matching WHERE period >= ' || l_iPreviousPeriod || ' AND highlight_code IS NOT NULL');
    
    -- Slett poster fra matching for inneværende periode
    l_iStatement := 4;
    DELETE general_ledger_matching WHERE period >= l_iPreviousPeriod;
    
    -- Laster poster fra GL for inneværende periode
    l_iStatement := 5;
    INSERT INTO general_ledger_matching ( id,company_id,contra_company_id,period,account_id,amount,responsible_id,voob_id,project_id,project_activity_id,activity_id,description,ext_inv_ref)
    SELECT gl_transact_guid,company_id,contra_company_id,period,account_id,amount,responsible_id,voob_id,project_id,project_activity_id,activity_id,description,ext_inv_ref
      FROM general_ledger WHERE period >= l_iPreviousPeriod;
    
    -- De følgende create og update statementene er laget for å håndere duplikate posteringer i GL slik at vi kan finne igjen evt avstemmede poster
    -- Denne situasjonen oppstod ved årskiftet 2014/15
    -- Slett midlertidige tabeller
    l_iStatement := 6;
    SELECT count(*) INTO l_iTblExists FROM user_tables WHERE lower(table_name) = 'glm_duplicates_count';
    IF l_iTblExists <> 0 THEN EXECUTE IMMEDIATE ('DROP TABLE glm_duplicates_count'); END IF;
    SELECT count(*) INTO l_iTblExists FROM user_tables WHERE lower(table_name) = 'glm_duplicates_rows';
    IF l_iTblExists <> 0 THEN EXECUTE IMMEDIATE ('DROP TABLE glm_duplicates_rows'); END IF;
    
    l_iStatement := 7;
    EXECUTE IMMEDIATE (
    'CREATE TABLE glm_duplicates_count AS 
    SELECT
        count(*)                            as "count"
      , nvl(gpm.company_id,''-1'')          as company_id
      , nvl(gpm.contra_company_id,''-1'')   as contra_company_id
      , nvl(gpm.period,0)                   as period
      , nvl(gpm.account_id,0)               as account_id
      , nvl(gpm.amount,0)                   as amount
      , nvl(gpm.responsible_id,''-1'')      as responsible_id
      , nvl(gpm.voob_id,''-1'')             as voob_id
      , nvl(gpm.project_id,''-1'')          as project_id
      , nvl(gpm.project_activity_id,''-1'') as project_activity_id
      , nvl(gpm.activity_id,''-1'')         as ACTIVITY_ID
      , nvl(gpm.description,''-1'')         as description
      , nvl(gpm.ext_inv_ref,''-1'')         as ext_inv_ref
     FROM general_ledger_matching gpm
    WHERE period >= ( SELECT MIN(acc_period) 
                        FROM period 
                       WHERE date_from = ( SELECT TO_DATE(''01'' || to_char(add_months(sysdate,-1),''MMYYYY''),''DDMMYYYY'') FROM dual )
                         AND substr(acc_period,5,2) NOT IN (''13''))
      AND gpm.contra_company_id IS NOT NULL                                   
    GROUP BY 
        nvl(gpm.company_id,''-1'')
      , nvl(gpm.contra_company_id,''-1'')
      , nvl(gpm.period,0)                             
      , nvl(gpm.account_id,0)                  
      , nvl(gpm.amount,0)                                          
      , nvl(gpm.responsible_id,''-1'')   
      , nvl(gpm.voob_id,''-1'')                  
      , nvl(gpm.project_id,''-1'')         
      , nvl(gpm.project_activity_id,''-1'')
      , nvl(gpm.activity_id,''-1'')          
      , nvl(gpm.description,''-1'')       
      , nvl(gpm.ext_inv_ref,''-1'')
    HAVING COUNT(*) > 1');
    
    l_iStatement := 8;
    EXECUTE IMMEDIATE ('
    CREATE TABLE glm_duplicates_rows AS 
    SELECT 
        rownum                          as rnum 
      , id                              as id
      , nvl(company_id,''-1'')          as company_id
      , nvl(contra_company_id,''-1'')   as contra_company_id
      , nvl(period,0)                   as period
     , nvl(account_id,0)                as account_id
      , nvl(amount,0)                   as amount
      , nvl(responsible_id,''-1'')      as responsible_id
      , nvl(voob_id,''-1'')             as voob_id
      , nvl(project_id,''-1'')          as project_id
      , nvl(project_activity_id,''-1'') as project_activity_id
      , nvl(activity_id,''-1'')         as activity_id
      , nvl(description,''-1'')         as description
      , nvl(ext_inv_ref,''-1'')         as ext_inv_ref
    FROM general_ledger_matching
   WHERE nvl(company_id,''-1'')          IN (SELECT company_id          FROM glm_duplicates_count)
     AND nvl(contra_company_id,''-1'')   IN (SELECT contra_company_id   FROM glm_duplicates_count)
     AND nvl(period,''0'')               IN (SELECT period              FROM glm_duplicates_count)
     AND nvl(account_id,''0'')           IN (SELECT account_id          FROM glm_duplicates_count)
     AND nvl(amount,''0'')               IN (SELECT amount              FROM glm_duplicates_count)
     AND nvl(responsible_id,''-1'')      IN (SELECT responsible_id      FROM glm_duplicates_count)
     AND nvl(voob_id,''-1'')             IN (SELECT voob_id             FROM glm_duplicates_count)
     AND nvl(project_id,''-1'')          IN (SELECT project_id          FROM glm_duplicates_count)
     AND nvl(project_activity_id,''-1'') IN (SELECT project_activity_id FROM glm_duplicates_count)
     AND nvl(activity_id,''-1'')         IN (SELECT activity_id         FROM glm_duplicates_count)
     AND nvl(description,''-1'')         IN (SELECT description         FROM glm_duplicates_count)
     AND nvl(ext_inv_ref,''-1'')         IN (SELECT ext_inv_ref         FROM glm_duplicates_count)
  ORDER BY
       nvl(company_id,''-1'')           
      ,nvl(contra_company_id,''-1'')            
      ,nvl(period,''0'')                         
      ,nvl(account_id,''0'')                
      ,nvl(amount,''0'')                      
      ,nvl(responsible_id,''-1'')       
      ,nvl(voob_id,''-1'')                    
      ,nvl(project_id,''-1'')         
      ,nvl(project_activity_id,''-1'')
      ,nvl(activity_id,''-1'')                                
      ,nvl(description,''-1'')                              
      ,nvl(ext_inv_ref,''-1'')');
    
    l_iStatement := 9;  
    UPDATE general_ledger_matching glm 
       SET description = ( SELECT description || ' ' || rnum
                             FROM glm_duplicates_rows
          WHERE glm.id =  glm_duplicates_rows.id
          
          /*nvl(glm.company_id,'-1')          = glm_duplicates_rows.company_id
            AND nvl(glm.contra_company_id,'-1')   = glm_duplicates_rows.contra_company_id
            AND nvl(glm.period,'0')               = glm_duplicates_rows.period
            AND nvl(glm.account_id,'0')           = glm_duplicates_rows.account_id
            AND nvl(glm.amount,'0')               = glm_duplicates_rows.amount
            AND nvl(glm.responsible_id,'-1')      = glm_duplicates_rows.responsible_id
            AND nvl(glm.voob_id,'-1')             = glm_duplicates_rows.voob_id
            AND nvl(glm.project_id,'-1')          = glm_duplicates_rows.project_id
            AND nvl(glm.project_activity_id,'-1') = glm_duplicates_rows.project_activity_id
            AND nvl(glm.activity_id,'-1')         = glm_duplicates_rows.activity_id
            AND nvl(glm.description,'-1')         = glm_duplicates_rows.description
            AND nvl(glm.ext_inv_ref,'-1')         = glm_duplicates_rows.ext_inv_ref 
            */
              )
       WHERE nvl(company_id,'-1')          IN (SELECT company_id          FROM glm_duplicates_count)
         AND nvl(contra_company_id,'-1')   IN (SELECT contra_company_id   FROM glm_duplicates_count)
         AND nvl(period,'0')               IN (SELECT period              FROM glm_duplicates_count)
         AND nvl(account_id,'0')           IN (SELECT account_id          FROM glm_duplicates_count)
         AND nvl(amount,'0')               IN (SELECT amount              FROM glm_duplicates_count)
         AND nvl(responsible_id,'-1')      IN (SELECT responsible_id      FROM glm_duplicates_count)
         AND nvl(voob_id,'-1')             IN (SELECT voob_id             FROM glm_duplicates_count)
         AND nvl(project_id,'-1')          IN (SELECT project_id          FROM glm_duplicates_count)
         AND nvl(project_activity_id,'-1') IN (SELECT project_activity_id FROM glm_duplicates_count)
         AND nvl(activity_id,'-1')         IN (SELECT activity_id         FROM glm_duplicates_count)
         AND nvl(description,'-1')         IN (SELECT description         FROM glm_duplicates_count)
         AND nvl(ext_inv_ref,'-1')         IN (SELECT ext_inv_ref         FROM glm_duplicates_count);      

    
    
    -- Oppdater poster med matching info for inneværende periode
    l_iStatement := 10;
    UPDATE general_ledger_matching gl SET highlight_code = 
      (SELECT highlight_code 
         FROM general_ledger_matching_period gpm 
        WHERE nvl(gpm.company_id,'-1')          =  nvl(gl.company_id,'-1')
          AND nvl(gpm.contra_company_id,'-1')   =  nvl(gl.contra_company_id,'-1')
          AND nvl(gpm.period,0)                 =  nvl(gl.period,0)
          AND nvl(gpm.account_id,0)             =  nvl(gl.account_id,0)
          AND nvl(gpm.amount,0)                 =  nvl(gl.amount,0)
          AND nvl(gpm.responsible_id,'-1')      =  nvl(gl.responsible_id,'-1')
          AND nvl(gpm.voob_id,'-1')             =  nvl(gl.voob_id,'-1')
          AND nvl(gpm.project_id,'-1')          =  nvl(gl.project_id,'-1')
          AND nvl(gpm.project_activity_id,'-1') =  nvl(gl.project_activity_id,'-1')
          AND nvl(gpm.activity_id,'-1')         =  nvl(gl.activity_id,'-1')
          AND nvl(gpm.description,'-1')         =  nvl(gl.description,'-1')
          AND nvl(gpm.ext_inv_ref,'-1')         =  nvl(gl.ext_inv_ref,'-1'))
      WHERE  period >= l_iPreviousPeriod ;

    l_iStatement := 11;
    UPDATE general_ledger_matching gl SET match_id = 
      (SELECT match_id 
         FROM general_ledger_matching_period gpm 
        WHERE nvl(gpm.company_id,'-1')          = nvl(gl.company_id,'-1')
          AND nvl(gpm.contra_company_id,'-1')   = nvl(gl.contra_company_id,'-1')
          AND nvl(gpm.period,0)                 = nvl(gl.period,0)
          AND nvl(gpm.account_id,0)             = nvl(gl.account_id,0)
          AND nvl(gpm.amount,0)                 = nvl(gl.amount,0)
          AND nvl(gpm.responsible_id,'-1')      = nvl(gl.responsible_id,'-1')
          AND nvl(gpm.voob_id,'-1')             = nvl(gl.voob_id,'-1')
          AND nvl(gpm.project_id,'-1')          = nvl(gl.project_id,'-1')
          AND nvl(gpm.project_activity_id,'-1') = nvl(gl.project_activity_id,'-1')
          AND nvl(gpm.activity_id,'-1')         = nvl(gl.activity_id,'-1')
          AND nvl(gpm.description,'-1')         = nvl(gl.description,'-1')
          AND nvl(gpm.ext_inv_ref,'-1')         = nvl(gl.ext_inv_ref,'-1'))
      WHERE  period >= l_iPreviousPeriod ;

    -- Rydd opp i matchede poster som ikke har en eller flere "motposter" og beløp stemmer
    l_iStatement := 12;
    UPDATE general_ledger_matching gl SET highlight_code= NULL, match_id = NULL
     WHERE match_id IN ( SELECT match_id FROM general_ledger_matching group by match_id having count(*) = 1 );
    l_iStatement := 13;   
    UPDATE general_ledger_matching gl SET highlight_code= NULL, match_id = NULL
     WHERE match_id IN ( SELECT match_id 
                           FROM ( SELECT match_id, sum(amount) AS amount FROM general_ledger_matching group by match_id)
                          WHERE amount <> 0
                            AND match_id IS NOT NULL
                         );
   COMMIT;
   l_iStatement := 14;
   SELECT sysdate INTO g_dtEndTime FROM dual;
   --Script for å finne tidsforbruk...
   SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
     FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );

   l_iStatement := 15;
   g_strText := 'FINISH: UpdateGeneralLedgerMatching - TIME USAGE: ' || g_strTimeUsage ;
   g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerMatching', 0, i_jobbID);

EXCEPTION WHEN OTHERS THEN
   g_strText := 'ERROR: UpdateGeneralLedgerMatching:  - ErrorMessage: '|| SQLERRM || ' - Error in statement: ' || l_iStatement;
   g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerMatching', 0, i_jobbID);

END UpdateGeneralLedgerMatching;

PROCEDURE UpdateSnapshotRefreshgroup ( i_strRefreshGroup IN VARCHAR) AS
  l_strRefreshGroup VARCHAR(300);
  l_strOwner        VARCHAR(100);
BEGIN
  l_strOwner        := 'G_AGRLES';
  l_strRefreshGroup := i_strRefreshGroup;
  
  dbms_refresh.refresh ( l_strOwner || '.' || l_strRefreshGroup ); 

END UpdateSnapshotRefreshgroup;

PROCEDURE TransformVimsaBalanceData IS
BEGIN
  DELETE FROM visma_balance_tmp; 
  DELETE FROM visma_balance; 
  COMMIT;
  -- Januar
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_1, to_date('0101' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Februar
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_2, to_date('0102' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Mars
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_3, to_date('0103' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- April
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_4, to_date('0104' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Mai
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_5, to_date('0105' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Juni
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_6, to_date('0106' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Juli
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_7, to_date('0107' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- August
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_8, to_date('0108' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- September
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_9, to_date('0109' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Oktober
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_10, to_date('0110' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- November
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_11, to_date('0111' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;
  -- Desember
  INSERT INTO visma_balance_tmp (company_id, responsible_id, account_id, amount, balance_date)
    SELECT 'EL', decode(hsa_avd,'10','30','11','30','20','30','50','30','6','40','8','30','9','60',hsa_avd)|| 'EL', hsa_knr, hsa_per_saldo_12, to_date('0112' || hsa_aar,'DDMMYYYY')
   FROM g_vismales.load_hsal;


  INSERT INTO visma_balance (visma_balance_id, company_id, responsible_id, account_id, amount, balance_date)
  SELECT -1, company_id, responsible_id, account_id, SUM(amount), balance_date
    FROM visma_balance_tmp
    GROUP BY -1,company_id, responsible_id, account_id, balance_date;
    
  DELETE visma_balance WHERE amount = 0;  

  UPDATE visma_balance SET visma_balance_id = rownum;

  COMMIT;

END TransformVimsaBalanceData;

PROCEDURE ValidateVismaData AS
  CURSOR l_curAccount IS SELECT DISTINCT hpo_konto FROM g_vismales.load_public_vismacontr_hpos;
  
  l_iAccount       VARCHAR2(25);
  l_iPeriod        NUMBER(11,0);
  l_iErrorCount    NUMBER(11,0);
  l_iPeriodCounter NUMBER(11,0);
  l_iYear          NUMBER(11,0);
  l_rTotHPOS       NUMBER(18,2);
  l_rTotHSAL       NUMBER(18,2);
  
  l_eTotalNotEqual EXCEPTION;
BEGIN
  -- TÃ¸m temp tabell
  EXECUTE IMMEDIATE ('TRUNCATE TABLE VALIDATE_VISMA_GL');
  l_iErrorCount := 0;
  -- Hent periode
  SELECT to_number(to_char(sysdate,'MM')) INTO l_iPeriod FROM DUAL;
  -- Hent Ã¥r
  SELECT to_number(to_char(sysdate,'YYYY')) INTO l_iYear FROM DUAL;
  
  IF l_iPeriod = 1 THEN l_iYear := l_iYear-1; END IF;
  IF l_iPeriod = 1 THEN l_iPeriod := 12;      END IF;
  
  OPEN l_curAccount;
  FETCH l_curAccount INTO l_iAccount;
  WHILE l_curAccount%FOUND LOOP

    FOR l_iCounter IN 1..l_iPeriod
    LOOP
        SELECT NVL(SUM(amount),0) INTO l_rTotHPOS   
         FROM general_ledger
        WHERE company_id = 'EL'
          AND to_number(substr(period,0,4)) = l_iYear
          AND to_number(substr(period,5,2)) = l_iCounter
          AND account_id = l_iAccount;

/*      SELECT NVL(SUM(hpo_belop),0) INTO l_rTotHPOS
        FROM g_vismales.load_public_vismacontr_hpos 
       WHERE hpo_post_aar = l_iYear 
         AND hpo_post_per = l_iCounter 
         AND hpo_konto    = l_iAccount;*/         
         
      CASE l_iCounter
        WHEN 1 THEN SELECT NVL(sum(hsa_per_saldo_1),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 2 THEN SELECT NVL(sum(hsa_per_saldo_2),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 3 THEN SELECT NVL(sum(hsa_per_saldo_3),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 4 THEN SELECT NVL(sum(hsa_per_saldo_4),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 5 THEN SELECT NVL(sum(hsa_per_saldo_5),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 6 THEN SELECT NVL(sum(hsa_per_saldo_6),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 7 THEN SELECT NVL(sum(hsa_per_saldo_7),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 8 THEN SELECT NVL(sum(hsa_per_saldo_8),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 9 THEN SELECT NVL(sum(hsa_per_saldo_9),0)   INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 10 THEN SELECT NVL(sum(hsa_per_saldo_10),0) INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 11 THEN SELECT NVL(sum(hsa_per_saldo_11),0) INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        WHEN 12 THEN SELECT NVL(sum(hsa_per_saldo_12),0) INTO l_rTotHSAL FROM g_vismales.load_hsal WHERE hsa_aar = l_iYear AND hsa_knr = l_iAccount AND hsa_avd = 0;
        ELSE null;
      END CASE;
      
      l_iPeriodCounter := l_iCounter; 
      
      IF l_rTotHPOS <> l_rTotHSAL THEN 
        insert into validate_visma_gl (account_id, year, period, tot_hsal, tot_hpos) values ( l_iAccount, l_iYear, l_iPeriodCounter, l_rTotHSAL, l_rTotHPOS); 
        commit;
      END IF;
    
    END LOOP;
    
  FETCH l_curAccount INTO l_iAccount;
  END LOOP;
  CLOSE l_curAccount;
  
  SELECT count(*) INTO l_iErrorCount FROM validate_visma_gl;
  
  IF l_iErrorCount > 0 THEN raise l_eTotalNotEqual; END IF;
  
  EXCEPTION WHEN l_eTotalNotEqual THEN 
    raise_application_error (-20010,'Feil funnet i hovedbok og saldotabell. Sjekk tabell: "validate_visma_gl" for mer info.' || chr(13) || chr(10)|| chr(13) || chr(10));
  
END ValidateVismaData;

PROCEDURE ValidateVismaKolibriData AS
  CURSOR l_curAccount IS SELECT DISTINCT account_id FROM visma_balance;
  
  l_iAccount       VARCHAR2(25);
  l_iPeriod        NUMBER(11,0);
  l_iErrorCount    NUMBER(11,0);
  l_iPeriodCounter NUMBER(11,0);
  l_iYear          NUMBER(11,0);
  l_rTotHPOS       NUMBER(18,2);
  l_rTotHSAL       NUMBER(18,2);
  l_iUseZeroResponsible NUMBER(11,0);
  
  l_eTotalNotEqual EXCEPTION;
BEGIN
  -- TÃ¸m temp tabell
  EXECUTE IMMEDIATE ('TRUNCATE TABLE VALIDATE_VISMA_GL');
  l_iErrorCount := 0;
  -- Hent periode
  SELECT to_number(to_char(sysdate,'MM')) INTO l_iPeriod FROM DUAL;
  -- Hent Ã¥r
  SELECT to_number(to_char(sysdate,'YYYY')) INTO l_iYear FROM DUAL;
  
  IF l_iPeriod = 1 THEN l_iYear := l_iYear-1; END IF;
  IF l_iPeriod = 1 THEN l_iPeriod := 12; ELSE l_iPeriod := l_iPeriod - 1;   END IF;
  
  OPEN l_curAccount;
  FETCH l_curAccount INTO l_iAccount;
  WHILE l_curAccount%FOUND LOOP

    FOR l_iCounter IN 1..l_iPeriod
    LOOP
        SELECT NVL(SUM(amount),0) INTO l_rTotHPOS   
         FROM general_ledger
        WHERE company_id = 'EL'
          AND to_number(substr(period,0,4)) = l_iYear
          AND to_number(substr(period,5,2)) = l_iCounter
          AND account_id = l_iAccount
          AND responsible_id IN (SELECT responsible_id FROM responsible WHERE company_id = 'EL');

       SELECT count(*) INTO l_iUseZeroResponsible
       FROM (SELECT count(*) ANTALL 
         FROM visma_balance 
        WHERE account_id = l_iAccount
          AND to_number(to_char(balance_date,'YYYY')) = l_iYear
          AND to_number(to_char(balance_date,'MM'))   = l_iCounter
       GROUP BY responsible_id) ;
       
      IF l_iUseZeroResponsible > 1 THEN
       
        SELECT NVL(SUM(amount),0) INTO l_rTotHSAL   
         FROM visma_balance
        WHERE company_id = 'EL'
          AND to_number(to_char(balance_date,'YYYY')) = l_iYear
          AND to_number(to_char(balance_date,'MM')) = l_iCounter
          AND account_id = l_iAccount
          AND responsible_id IN (SELECT responsible_id FROM responsible WHERE company_id = 'EL');
      
      ELSE
        SELECT NVL(SUM(amount),0) INTO l_rTotHSAL   
         FROM visma_balance
        WHERE company_id = 'EL'
          AND to_number(to_char(balance_date,'YYYY')) = l_iYear
          AND to_number(to_char(balance_date,'MM')) = l_iCounter
          AND account_id = l_iAccount
          AND responsible_id = '0EL';
      
      END IF;
      
      l_iPeriodCounter := l_iCounter; 
      
      IF l_rTotHPOS <> l_rTotHSAL THEN 
        insert into validate_visma_gl (account_id, year, period, tot_hsal, tot_hpos) values ( l_iAccount, l_iYear, l_iPeriodCounter, l_rTotHSAL, l_rTotHPOS); 
        commit;
      END IF;
    
    END LOOP;
  FETCH l_curAccount INTO l_iAccount;
  END LOOP;
  CLOSE l_curAccount;
  
  SELECT count(*) INTO l_iErrorCount FROM validate_visma_gl;
  
  IF l_iErrorCount > 0 THEN raise l_eTotalNotEqual; END IF;
  
  EXCEPTION WHEN l_eTotalNotEqual THEN 
    raise_application_error (-20010,'Feil funnet i hovedbok og saldotabell. Sjekk tabell: "validate_visma_gl" for mer info.' || chr(13) || chr(10)|| chr(13) || chr(10));
  
END ValidateVismaKolibriData;

PROCEDURE UpdateOrderVisma AS
BEGIN
  null;
END UpdateOrderVisma;

PROCEDURE UpdateOrderLineVisma AS
BEGIN
  null;
END UpdateOrderLineVisma;

PROCEDURE UpdatePersonVisma AS
BEGIN
  null;
END UpdatePersonVisma;

PROCEDURE UpdateGeneralLedgerVisma (i_jobbID varchar2 default '') AS

  tbl_exists NUMBER(11,0);

BEGIN

  SELECT sysdate INTO g_dtStartTime from dual;

  g_bResult := false;
  g_strText := 'START: UpdateGeneralLedgerVisma';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 0, i_jobbID );
      
      -- Fjerner data for inneværende år og i fjor
      DELETE general_ledger WHERE company_id = 'EL' AND TO_NUMBER(SUBSTR(period,0,4)) >= to_number(to_char(SYSDATE,'YYYY'))-1; --substr(period,0,4) IN ('2013','2014');

       g_strText := 'UpdateGeneralLedgerVisma: Deleted rows from general_ledger';
       g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 5, i_jobbID );

      -- Hent data frem til og med 2014
      INSERT INTO general_ledger (
      COMPANY_ID,
      CONTRA_COMPANY_ID,
      ACCOUNT_ID,
      RESPONSIBLE_ID,
      PROJECT_ID,
      WORK_ORDER_ID,
      PROJECT_ACTIVITY_ID,
      VOOB_ID,
      ACTIVITY_ID,
      VOUCHER_DATE,
      PERIOD,
      AMOUNT,
      SOURCE_ID,
      DESCRIPTION,
      VOUCHER_NO,
      EXT_INV_REF,
      APAR_ID,
      VOUCHERTYPE_ID )
      SELECT
       'EL',   --SELSKAP Elektro
       DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),   --hpo_motkonto (MELREGN),
       hpo_konto,
       DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','30'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','30'              
                   ,hpo_avdeling) || 'EL', --ANSVAR (AVDELING),
       null, --PROSJEKT
       null, --ARBEIDSORDRE
       null, --PROSJEKTAKTIVITET
       null, --VOOB
       ' ',    --AKTIVITET
       to_date(case when length(hpo_dato) = 5 then '0' || substr(hpo_dato,length(hpo_dato)-5,1)
                   when length(hpo_dato) = 6 then substr(hpo_dato,length(hpo_dato)-5,2)
              else '1' end
              ||substr(hpo_dato,length(hpo_dato)-3,2)
              || '20' || substr(hpo_dato,length(hpo_dato)-1,2),'DDMMYYYY'), -- BILAGSDATO
       to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))), --PERIODE
       sum(to_number(REPLACE(hpo_belop,'.',','))) AS "BELØP",
      /* 
       SUM(CASE substr(hpo_belop,0,1) 
         WHEN '.' THEN to_number('0'||hpo_belop)
         WHEN '-' THEN 
           CASE substr(hpo_belop,1,1) 
             WHEN '.' THEN to_number('-0'||hpo_belop) ELSE to_number(hpo_belop)  END
         ELSE to_number(hpo_belop)  END) "BELOP", 
         */
       6, --KILDE
       hpo_tekst, --BESKRIVELSE
       hpo_bilag,
       hpo_bilag, --FAKTURANR /* 05112014 Endret ut i fra en hypotese om at bilag=fakturanr i Visma*/
       null, --APAR_ID
       '100' --VOUCHERTYPE_ID
      FROM g_vismales.visma_hpos_external
      WHERE hpo_post_aar >= to_number(to_char(SYSDATE,'YYYY'))-1
        AND hpo_post_aar < 2015  -- Avdeling 10 skal flyttes til 30 frem til og med 2014
      GROUP BY 
        DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),
        hpo_konto,  
        DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','30'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','30'
                   ,hpo_avdeling) || 'EL',
        to_date(CASE WHEN LENGTH(hpo_dato) = 5 THEN '0' || substr(hpo_dato,LENGTH(hpo_dato)-5,1)
                     WHEN LENGTH(hpo_dato) = 6 THEN substr(hpo_dato,LENGTH(hpo_dato)-5,2)
                else '1' end
                ||substr(hpo_dato,LENGTH(hpo_dato)-3,2)
                || '20' || substr(hpo_dato,LENGTH(hpo_dato)-1,2),'DDMMYYYY'),
        to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))),
        hpo_tekst,
        hpo_bilag;
       
      -- Hent data fra og med 2015 til og med oktober 2015. Fra og med november skal ikke melregn tas med.
      INSERT INTO general_ledger (
      COMPANY_ID,
      CONTRA_COMPANY_ID,
      ACCOUNT_ID,
      RESPONSIBLE_ID,
      PROJECT_ID,
      WORK_ORDER_ID,
      PROJECT_ACTIVITY_ID,
      VOOB_ID,
      ACTIVITY_ID,
      VOUCHER_DATE,
      PERIOD,
      AMOUNT,
      SOURCE_ID,
      DESCRIPTION,
      VOUCHER_NO,
      EXT_INV_REF,
      APAR_ID,
      VOUCHERTYPE_ID )
      SELECT
       'EL',   --SELSKAP Elektro
       DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),   --hpo_motkonto (MELREGN),
       hpo_konto,
       DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','10'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','60'              
                   ,hpo_avdeling) || 'EL', --ANSVAR (AVDELING),
       null, --PROSJEKT
       null, --ARBEIDSORDRE
       null, --PROSJEKTAKTIVITET
       null, --VOOB
       ' ',    --AKTIVITET
       to_date(case when length(hpo_dato) = 5 then '0' || substr(hpo_dato,length(hpo_dato)-5,1)
                   when length(hpo_dato) = 6 then substr(hpo_dato,length(hpo_dato)-5,2)
              else '1' end
              ||substr(hpo_dato,length(hpo_dato)-3,2)
              || '20' || substr(hpo_dato,length(hpo_dato)-1,2),'DDMMYYYY'), -- BILAGSDATO
       to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))), --PERIODE
       sum(to_number(REPLACE(hpo_belop,'.',','))) AS "BELØP",
      /* 
       SUM(CASE substr(hpo_belop,0,1) 
         WHEN '.' THEN to_number('0'||hpo_belop)
         WHEN '-' THEN 
           CASE substr(hpo_belop,1,1) 
             WHEN '.' THEN to_number('-0'||hpo_belop) ELSE to_number(hpo_belop)  END
         ELSE to_number(hpo_belop)  END) "BELOP", 
         */
       6, --KILDE
       hpo_tekst, --BESKRIVELSE
       hpo_bilag,
       hpo_bilag, --FAKTURANR /* 05112014 Endret ut i fra en hypotese om at bilag=fakturanr i Visma*/
       null, --APAR_ID
       '100' --VOUCHERTYPE_ID
      FROM g_vismales.visma_hpos_external
      WHERE hpo_post_aar >= to_number(to_char(SYSDATE,'YYYY'))-1
        AND hpo_post_aar >= 2015  -- Avdeling 10 skal være egen avdeling fra og med 2015
        AND hpo_post_per <= 10 -- Melregn skal bare tas med tom 10.2015
      GROUP BY 
        DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),
        hpo_konto,  
        DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','10'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','60'
                   ,hpo_avdeling) || 'EL',
        to_date(CASE WHEN LENGTH(hpo_dato) = 5 THEN '0' || substr(hpo_dato,LENGTH(hpo_dato)-5,1)
                     WHEN LENGTH(hpo_dato) = 6 THEN substr(hpo_dato,LENGTH(hpo_dato)-5,2)
                else '1' end
                ||substr(hpo_dato,LENGTH(hpo_dato)-3,2)
                || '20' || substr(hpo_dato,LENGTH(hpo_dato)-1,2),'DDMMYYYY'),
        to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))),
        hpo_tekst,
        hpo_bilag;

      --Hente data fra og med november 2015 og ut 2015
      INSERT INTO general_ledger (
      COMPANY_ID,
      CONTRA_COMPANY_ID,
      ACCOUNT_ID,
      RESPONSIBLE_ID,
      PROJECT_ID,
      WORK_ORDER_ID,
      PROJECT_ACTIVITY_ID,
      VOOB_ID,
      ACTIVITY_ID,
      VOUCHER_DATE,
      PERIOD,
      AMOUNT,
      SOURCE_ID,
      DESCRIPTION,
      VOUCHER_NO,
      EXT_INV_REF,
      APAR_ID,
      VOUCHERTYPE_ID )
      SELECT
       'EL',   --SELSKAP Elektro
       null, --DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),   --hpo_motkonto (MELREGN),
       hpo_konto,
       DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','10'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','60'              
                   ,hpo_avdeling) || 'EL', --ANSVAR (AVDELING),
       null, --PROSJEKT
       null, --ARBEIDSORDRE
       null, --PROSJEKTAKTIVITET
       null, --VOOB
       ' ',    --AKTIVITET
       to_date(case when length(hpo_dato) = 5 then '0' || substr(hpo_dato,length(hpo_dato)-5,1)
                   when length(hpo_dato) = 6 then substr(hpo_dato,length(hpo_dato)-5,2)
              else '1' end
              ||substr(hpo_dato,length(hpo_dato)-3,2)
              || '20' || substr(hpo_dato,length(hpo_dato)-1,2),'DDMMYYYY'), -- BILAGSDATO
       to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))), --PERIODE
       sum(to_number(REPLACE(hpo_belop,'.',','))) AS "BELØP",
      /* 
       SUM(CASE substr(hpo_belop,0,1) 
         WHEN '.' THEN to_number('0'||hpo_belop)
         WHEN '-' THEN 
           CASE substr(hpo_belop,1,1) 
             WHEN '.' THEN to_number('-0'||hpo_belop) ELSE to_number(hpo_belop)  END
         ELSE to_number(hpo_belop)  END) "BELOP", 
         */
       6, --KILDE
       hpo_tekst, --BESKRIVELSE
       hpo_bilag,
       hpo_bilag, --FAKTURANR /* 05112014 Endret ut i fra en hypotese om at bilag=fakturanr i Visma*/
       null, --APAR_ID
       '100' --VOUCHERTYPE_ID
      FROM g_vismales.visma_hpos_external
      WHERE hpo_post_aar >= to_number(to_char(SYSDATE,'YYYY'))-1
        AND hpo_post_aar = 2015  -- Avdeling 10 skal være egen avdeling fra og med 2015
        AND hpo_post_per >= 11 -- Melregn skal bare tas med tom 10.2015
      GROUP BY 
        hpo_konto,  
        DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','10'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','60'
                   ,hpo_avdeling) || 'EL',
        to_date(CASE WHEN LENGTH(hpo_dato) = 5 THEN '0' || substr(hpo_dato,LENGTH(hpo_dato)-5,1)
                     WHEN LENGTH(hpo_dato) = 6 THEN substr(hpo_dato,LENGTH(hpo_dato)-5,2)
                else '1' end
                ||substr(hpo_dato,LENGTH(hpo_dato)-3,2)
                || '20' || substr(hpo_dato,LENGTH(hpo_dato)-1,2),'DDMMYYYY'),
        to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))),
        hpo_tekst,
        hpo_bilag;

      -- Henter data fra og med 2016
      INSERT INTO general_ledger (
      COMPANY_ID,
      CONTRA_COMPANY_ID,
      ACCOUNT_ID,
      RESPONSIBLE_ID,
      PROJECT_ID,
      WORK_ORDER_ID,
      PROJECT_ACTIVITY_ID,
      VOOB_ID,
      ACTIVITY_ID,
      VOUCHER_DATE,
      PERIOD,
      AMOUNT,
      SOURCE_ID,
      DESCRIPTION,
      VOUCHER_NO,
      EXT_INV_REF,
      APAR_ID,
      VOUCHERTYPE_ID )
      SELECT
       'EL',   --SELSKAP Elektro
       null, --DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),   --hpo_motkonto (MELREGN),
       hpo_konto,
       DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','10'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','60'              
                   ,hpo_avdeling) || 'EL', --ANSVAR (AVDELING),
       null, --PROSJEKT
       null, --ARBEIDSORDRE
       null, --PROSJEKTAKTIVITET
       null, --VOOB
       ' ',    --AKTIVITET
       to_date(case when length(hpo_dato) = 5 then '0' || substr(hpo_dato,length(hpo_dato)-5,1)
                   when length(hpo_dato) = 6 then substr(hpo_dato,length(hpo_dato)-5,2)
              else '1' end
              ||substr(hpo_dato,length(hpo_dato)-3,2)
              || '20' || substr(hpo_dato,length(hpo_dato)-1,2),'DDMMYYYY'), -- BILAGSDATO
       to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))), --PERIODE
       sum(to_number(REPLACE(hpo_belop,'.',','))) AS "BELØP",
      /* 
       SUM(CASE substr(hpo_belop,0,1) 
         WHEN '.' THEN to_number('0'||hpo_belop)
         WHEN '-' THEN 
           CASE substr(hpo_belop,1,1) 
             WHEN '.' THEN to_number('-0'||hpo_belop) ELSE to_number(hpo_belop)  END
         ELSE to_number(hpo_belop)  END) "BELOP", 
         */
       6, --KILDE
       hpo_tekst, --BESKRIVELSE
       hpo_bilag,
       hpo_bilag, --FAKTURANR /* 05112014 Endret ut i fra en hypotese om at bilag=fakturanr i Visma*/
       null, --APAR_ID
       '100' --VOUCHERTYPE_ID
      FROM g_vismales.visma_hpos_external
      WHERE hpo_post_aar >= to_number(to_char(SYSDATE,'YYYY'))-1
        AND hpo_post_aar >= 2016  
      GROUP BY 
        hpo_konto,  
        DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','10'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','60'
                   ,hpo_avdeling) || 'EL',
        to_date(CASE WHEN LENGTH(hpo_dato) = 5 THEN '0' || substr(hpo_dato,LENGTH(hpo_dato)-5,1)
                     WHEN LENGTH(hpo_dato) = 6 THEN substr(hpo_dato,LENGTH(hpo_dato)-5,2)
                else '1' end
                ||substr(hpo_dato,LENGTH(hpo_dato)-3,2)
                || '20' || substr(hpo_dato,LENGTH(hpo_dato)-1,2),'DDMMYYYY'),
        to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))),
        hpo_tekst,
        hpo_bilag;


      COMMIT;

       g_strText := 'UpdateGeneralLedgerVisma: Inserted rows into general_ledger';
       g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 5, i_jobbID );

      UPDATE general_ledger SET activity_id = '2' 
       WHERE activity_id = ' ' 
         AND company_id = 'EL'
         AND account_id >= 3000
         AND TO_NUMBER(SUBSTR(period,0,4)) >= to_number(to_char(SYSDATE,'YYYY'))-1;
         
       g_strText := 'UpdateGeneralLedgerVisma: update general_ledger with activity';
       g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 5, i_jobbID );


        /* FJERNER MELREGN PÃ… BALANSEKONTI FOR ELEKTRO */
        UPDATE general_ledger SET contra_company_id = NULL
         WHERE company_id = 'EL'
           AND account_id IN (SELECT account_id FROM ACCOUNT WHERE account_type = 2)
           AND TO_NUMBER(SUBSTR(period,0,4)) >= to_number(to_char(SYSDATE,'YYYY'))-1;

       g_strText := 'UpdateGeneralLedgerVisma: remove contra company for balanceentries in  general_ledger' ;
       g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 5, i_jobbID );

         
        /* Korrigerer feilpostering ved Ã¥ legge til info om melregn  */         
        UPDATE general_ledger SET contra_company_id = 'SE'
           WHERE company_id = 'EL'
             AND period IN (201100,201101,201102,201103,201104,201105,201106,201107,201108,201109,201110,201111,201112)
             AND account_id = 5990
             AND contra_company_id IS NULL
             AND voucher_no = 1262;

       g_strText := 'UpdateGeneralLedgerVisma: Correct rows general_ledger with contra company' ;
       g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 5, i_jobbID );

             
        /* Endre ansvar 100 til 60 dersom Ã¥r 2012, Ansvar 100 er aktivt fra og med 2013 */
        IF SYSDATE < to_date('01.01.2013','DD.MM.YYYY') THEN
          UPDATE general_ledger SET responsible_id = '60EL' WHERE responsible_id = '100EL' AND company_id = 'EL';
        END IF;
         
      COMMIT;
      
      INSERT INTO UPDATE_STATUS_SYSTEM_OBJECTS (SYSTEM_OBJECTS_ID,LAST_UPDATE) SELECT 1001, sysdate FROM dual;

       g_strText := 'UpdateGeneralLedgerVisma: Insert into UPDATE_STATUS_SYSTEM_OBJECTS' ;
       g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 5, i_jobbID );


      COMMIT;

  SELECT sysdate INTO g_dtEndTime FROM dual;
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );

  g_strText := 'FINISH: UpdateGeneralLedgerVisma - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateGeneralLedgerVisma', 0, i_jobbID );
   
  UpdateGeneralLedgerMatching(i_jobbID);
   
 END UpdateGeneralLedgerVisma;

PROCEDURE UpdateGeneralLedgerVismaDD AS
   BEGIN
     -- Fjerner data for innevÃ¦rende Ã¥r
     DELETE general_ledger WHERE company_id = 'EL' AND to_char(voucher_date,'DDMMYYYY') = to_char(sysdate,'DDMMYYYY');
      COMMIT;
      
      INSERT INTO general_ledger (
      COMPANY_ID,
      CONTRA_COMPANY_ID,
      ACCOUNT_ID,
      RESPONSIBLE_ID,
      PROJECT_ID,
      WORK_ORDER_ID,
      PROJECT_ACTIVITY_ID,
      VOOB_ID,
      ACTIVITY_ID,
      VOUCHER_DATE,
      PERIOD,
      AMOUNT,
      SOURCE_ID,
      DESCRIPTION,
      VOUCHER_NO,
      EXT_INV_REF,
      APAR_ID,
      VOUCHERTYPE_ID )
      SELECT
       'EL',   --SELSKAP Elektro
       DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),   --hpo_motkonto (MELREGN),
       hpo_konto,
       DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','30'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','30'
                   ,hpo_avdeling) || 'EL', --ANSVAR (AVDELING),
       null, --PROSJEKT
       null, --ARBEIDSORDRE
       null, --PROSJEKTAKTIVITET
       null, --VOOB
       ' ',    --AKTIVITET
       to_date(case when length(hpo_dato) = 5 then '0' || substr(hpo_dato,length(hpo_dato)-5,1)
                   when length(hpo_dato) = 6 then substr(hpo_dato,length(hpo_dato)-5,2)
              else '1' end
              ||substr(hpo_dato,length(hpo_dato)-3,2)
              || '20' || substr(hpo_dato,length(hpo_dato)-1,2),'DDMMYYYY'), -- BILAGSDATO
       to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))), --PERIODE
       sum(to_number(replace(hpo_belop,'.',','))),
       6, --KILDE
       hpo_tekst, --BESKRIVELSE
       hpo_bilag,
       null, --FAKTURANR
       null, --APAR_ID
       '100' --VOUCHERTYPE_ID
      FROM G_VISMALES.LOAD_PUBLIC_VISMACONTR_HPOS
      WHERE hpo_dato = to_char(sysdate,'DDMMYY')
      GROUP BY 
        DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),
        hpo_konto,  
        DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','30'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','30'
                   ,hpo_avdeling) || 'EL',
        to_date(CASE WHEN LENGTH(hpo_dato) = 5 THEN '0' || substr(hpo_dato,LENGTH(hpo_dato)-5,1)
                     WHEN LENGTH(hpo_dato) = 6 THEN substr(hpo_dato,LENGTH(hpo_dato)-5,2)
                else '1' end
                ||substr(hpo_dato,LENGTH(hpo_dato)-3,2)
                || '20' || substr(hpo_dato,LENGTH(hpo_dato)-1,2),'DDMMYYYY'),
        to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))),
        hpo_tekst,
        hpo_bilag;
      
      
      COMMIT;
      
      UPDATE general_ledger SET activity_id = '2' 
       WHERE activity_id = ' ' 
         AND company_id = 'EL'
         AND account_id >= 3000;
         
        /* FJERNER MELREGN PÃ… BALANSEKONTI FOR ELEKTRO */
        UPDATE general_ledger SET contra_company_id = NULL
          WHERE company_id = 'EL'
         AND account_id IN (SELECT account_id FROM ACCOUNT WHERE account_type = 2); --< 3000;
         
        /* Korrigerer feilpostering ved Ã¥ legge til info om melregn  */         
        UPDATE general_ledger SET contra_company_id = 'SE'
           WHERE company_id = 'EL'
             AND period IN (201100,201101,201102,201103,201104,201105,201106,201107,201108,201109,201110,201111,201112)
             AND account_id = 5990
             AND contra_company_id IS NULL
             AND voucher_no = 1262;
         
      COMMIT;
      
      --UPDATE general_ledger set GL_TRANSACT_ID = (select max(GL_TRANSACT_ID) from general_ledger) + rownum where GL_TRANSACT_ID = -1;
      
      EXECUTE IMMEDIATE('INSERT INTO UPDATE_STATUS_SYSTEM_OBJECTS (SYSTEM_OBJECTS_ID,LAST_UPDATE) SELECT 1001, sysdate FROM dual');

      COMMIT;
   
END UpdateGeneralLedgerVismaDD;

PROCEDURE UpdateGeneralLedgerVismaPeriod AS
   BEGIN
     -- Fjerner data for innevÃ¦rende Ã¥r
     DELETE general_ledger 
      WHERE company_id = 'EL' 
        AND period = to_char(SYSDATE,'YYYY') || to_char(SYSDATE,'MM');
     
     COMMIT;
      
      INSERT INTO general_ledger (
      COMPANY_ID,
      CONTRA_COMPANY_ID,
      ACCOUNT_ID,
      RESPONSIBLE_ID,
      PROJECT_ID,
      WORK_ORDER_ID,
      PROJECT_ACTIVITY_ID,
      VOOB_ID,
      ACTIVITY_ID,
      VOUCHER_DATE,
      PERIOD,
      AMOUNT,
      SOURCE_ID,
      DESCRIPTION,
      VOUCHER_NO,
      EXT_INV_REF,
      APAR_ID,
      VOUCHERTYPE_ID )
      SELECT
       'EL',   --SELSKAP Elektro
       DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),   --hpo_motkonto (MELREGN),
       hpo_konto,
       DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','30'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','30'
                   ,hpo_avdeling) || 'EL', --ANSVAR (AVDELING),
       null, --PROSJEKT
       null, --ARBEIDSORDRE
       null, --PROSJEKTAKTIVITET
       null, --VOOB
       ' ',    --AKTIVITET
       to_date(case when length(hpo_dato) = 5 then '0' || substr(hpo_dato,length(hpo_dato)-5,1)
                   when length(hpo_dato) = 6 then substr(hpo_dato,length(hpo_dato)-5,2)
              else '1' end
              ||substr(hpo_dato,length(hpo_dato)-3,2)
              || '20' || substr(hpo_dato,length(hpo_dato)-1,2),'DDMMYYYY'), -- BILAGSDATO
       to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))), --PERIODE
       sum(to_number(replace(hpo_belop,'.',','))),
       6, --KILDE
       hpo_tekst, --BESKRIVELSE
       hpo_bilag,
       null, --FAKTURANR
       null, --APAR_ID
       '100' --VOUCHERTYPE_ID
      FROM G_VISMALES.LOAD_PUBLIC_VISMACONTR_HPOS
      WHERE hpo_post_aar = to_char(SYSDATE,'YYYY')
        AND HPO_POST_PER = TO_NUMBER(TO_CHAR(sysdate,'MM'))  
      GROUP BY 
        DECODE(hpo_motpart,'0',null,'1','GRKR','2','MET','3','NAGR','4','SE','5','SK','6','SKEL','7','SKFI','8','SN','9','SVAR','10','SKIF',null),
        hpo_konto,  
        DECODE(hpo_avdeling
                   ,'0','30'
                   ,'1','30'
                   ,'10','30'
                   ,'11','30'
                   ,'20','30'
                   ,'5','30'
                   ,'50','30'
                   ,'6','40'
                   ,'7','30'
                   ,'8','30'
                   ,'9','30'
                   ,hpo_avdeling) || 'EL',
        to_date(CASE WHEN LENGTH(hpo_dato) = 5 THEN '0' || substr(hpo_dato,LENGTH(hpo_dato)-5,1)
                     WHEN LENGTH(hpo_dato) = 6 THEN substr(hpo_dato,LENGTH(hpo_dato)-5,2)
                else '1' end
                ||substr(hpo_dato,LENGTH(hpo_dato)-3,2)
                || '20' || substr(hpo_dato,LENGTH(hpo_dato)-1,2),'DDMMYYYY'),
        to_number(to_char(hpo_post_aar) || to_char(lpad(hpo_post_per,2,'0'))),
        hpo_tekst,
        hpo_bilag;
      
      
      COMMIT;
      
      UPDATE general_ledger SET activity_id = '2' 
       WHERE activity_id = ' ' 
         AND company_id = 'EL'
         AND account_id >= 3000;
         
        /* FJERNER MELREGN PÃ… BALANSEKONTI FOR ELEKTRO */
        UPDATE general_ledger SET contra_company_id = NULL
          WHERE company_id = 'EL'
         AND account_id IN (SELECT account_id FROM ACCOUNT WHERE account_type = 2); --< 3000;
         
        /* Korrigerer feilpostering ved Ã¥ legge til info om melregn  */         
        UPDATE general_ledger SET contra_company_id = 'SE'
           WHERE company_id = 'EL'
             AND period IN (201100,201101,201102,201103,201104,201105,201106,201107,201108,201109,201110,201111,201112)
             AND account_id = 5990
             AND contra_company_id IS NULL
             AND voucher_no = 1262;
         
      COMMIT;
      
      EXECUTE IMMEDIATE('INSERT INTO UPDATE_STATUS_SYSTEM_OBJECTS (SYSTEM_OBJECTS_ID,LAST_UPDATE) SELECT 1001, sysdate FROM dual');

      COMMIT;
   
END UpdateGeneralLedgerVismaPeriod;
   
PROCEDURE UpdateAllDimensions IS
    l_jobbGUID     g_kolibri.g_log.job_guid%type;
BEGIN
  SELECT sysdate INTO g_dtStartTime from dual;
  g_bResult := false;
  g_strText := 'START: UpdateAllDimensions';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0 );

  g_bResult := false;
  g_strText := 'START: UpdateResponsible';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateResponsible;
    
  g_bResult := false;
  g_strText := 'START: UpdateSectionDivision';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateSectionDivision;
     
  g_bResult := false;
  g_strText := 'START: UpdateSectionDivision';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateVOOB;
     
  g_bResult := false;
  g_strText := 'START: UpdateSectionDivision';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateProject;
     
  g_bResult := false;
  g_strText := 'START: UpdateWorkOrder';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateWorkOrder;
  
  g_bResult := false;
  g_strText := 'START: UpdateDistributionKey';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateDistributionKey;
  
  g_bResult := false;
  g_strText := 'START: UpdateResourceType';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateResourceType;
     
  g_bResult := false;
  g_strText := 'START: UpdateEmployee';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0, l_jobbGUID );
  UpdateEmployee;
  
  SELECT sysdate INTO g_dtEndTime FROM dual;
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );

  g_strText := 'FINISH: UpdateAllDimensions - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateAllDimensions', 0 );

END UpdateAllDimensions;

PROCEDURE UpdateResponsible AS
  l_iCount NUMBER;
BEGIN
 -- Lag kopi av eksisterende ansvarstabell
 SELECT count(*) INTO l_iCount FROM user_tables WHERE UPPER(table_name) = 'RESPONSIBLE_API';
 IF l_iCount > 0 THEN EXECUTE IMMEDIATE 'DROP TABLE RESPONSIBLE_API'; END IF;
 
 EXECUTE IMMEDIATE 'CREATE TABLE responsible_api AS SELECT * FROM responsible';
 -- Tøm tabell
 DELETE FROM responsible;
 -- Hent alle ansvar
 INSERT INTO responsible ( responsible_id, responsible_ident, responsible_name, responsible_person, section_id, company_id, from_period, to_period,responsible_status)
  SELECT dim_value || client, dim_value, description, NULL, NULL, client,period_from,period_to,status
    FROM g_agrles.MV_AGLDIMVALUE 
   WHERE attribute_id = 'C1'   --ANSVAR
     AND client IN (SELECT company_id FROM company WHERE termination_code_id IS NULL)
    -- AND client <> 'EL' -- Må håndtere Elektro spesielt
  ORDER BY dim_value || client;
  
 -- Rydd opp evt feil i data, sett status til 'C' hvor det er duplikater og til periode er 209912
 UPDATE responsible SET responsible_status = 'C' 
  WHERE responsible_id IN (SELECT responsible_id 
                             FROM responsible 
                             WHERE responsible_status = 'N' 
                             GROUP BY responsible_id
                             HAVING count(*) > 1)
    AND responsible_status = 'N'
    AND to_period <> 209912;

  -- Sett alle Elektro ansvar lik Closed
  UPDATE responsible 
  SET responsible_status = 'C'
  WHERE company_id = 'EL' 
    AND LENGTH(responsible_ident) = 3 
    AND substr(responsible_ident,0,1) = '8';
    
  -- Oppdater navn på ANSVAR
  UPDATE responsible SET responsible_name = 
   ( SELECT description
       FROM g_agrles.MV_AGLDIMVALUE
      WHERE attribute_id = 'C1'   --ANSVAR
        AND status = 'N'
        AND dim_value || client = responsible.responsible_id 
        AND client IN (SELECT company_id FROM company WHERE termination_code_id IS NULL)
    )
  WHERE responsible_id IN ( SELECT dim_value || client
                              FROM g_agrles.MV_AGLDIMVALUE
                             WHERE attribute_id = 'C1'   --ANSVAR
                               AND status = 'N'
                               AND dim_value || client = responsible.responsible_id 
                               AND client IN (SELECT company_id FROM company WHERE termination_code_id IS NULL)
                          )
    AND responsible_status = 'N';
    
  -- Flytt inaktive ansvar til egen tabell og uriktige ansvar for Elektro
  -- OIG 02092015 MULIG DETTE MÅ TAS BORT GRUNNET BRUK AV MARTS OG HELLER HA ALLE ANSVAR I EN TABELL UAVHENGIG AV STATUS
  DELETE FROM responsible_inactive;
  
  -- OIG 02092015 For å håndtere HMS rapportering fra og med august 2015 må vi håndtere ansvar for Nett litt spesielt - Ansvar 344 må tas med selv om det er sperret
  -- OIG/HR 11122015: Vi har oppdaget at det er flere ansvar som må håndteres spesielt i forhold til HMS rapportering. 
  --                  Vi fjerner nå bare ansvar som ikke har status N (Normal) og som IKKE finnes i kapasitetstabellen inneværende år og i fjor
  
  INSERT INTO responsible_inactive(ID,ident,NAME,company_id,from_period,to_period,status) 
    SELECT sys_guid(), responsible_ident, responsible_name,company_id,from_period,to_period,responsible_status 
      FROM responsible 
     WHERE responsible_status <> 'N';
  
  /*     AND responsible_id NOT IN (SELECT DISTINCT responsible_id 
                                      FROM kapasitet_timer_view
                                     WHERE to_char(dato,'YYYY') >= to_char(sysdate,'YYYY')-1 
                                       AND responsible_id IS NOT NULL
                                       AND substr(responsible_id,length(responsible_id)-1,2) IN (SELECT company_id FROM company) 
                                       AND length(responsible_id) > 2);
  */
  DELETE FROM responsible 
   WHERE responsible_status <> 'N';
   /*
 --    AND responsible_id NOT IN (SELECT DISTINCT responsible_id 
                                      FROM kapasitet_timer_view
                                     WHERE to_char(dato,'YYYY') >= to_char(sysdate,'YYYY')-1 
                                       AND responsible_id IS NOT NULL
                                       AND substr(responsible_id,length(responsible_id)-1,2) IN (SELECT company_id FROM company) 
                                       AND length(responsible_id) > 2);
     */                                  
   -- Sett inn inaktive ansvar som ikke finnes i ansvarstabellen, men som finnes i kapasitetstabellen                                          
   INSERT INTO responsible ( responsible_id, responsible_ident, responsible_name, responsible_person, section_id, company_id, from_period, to_period,responsible_status)
    SELECT distinct responsible_id, substr(responsible_id,1, length(responsible_id)-2), 'Sperret ansvar inkludert pga historikk i data mart', NULL, NULL, substr(responsible_id,length(responsible_id)-1,2),null,null,'C'
    FROM kapasitet_timer_view
   WHERE to_char(dato,'YYYY') >= to_char(sysdate,'YYYY')-1 
     AND responsible_id IS NOT NULL
     AND substr(responsible_id,length(responsible_id)-1,2) IN (SELECT company_id FROM company) 
     AND length(responsible_id) > 2
     AND responsible_id NOT IN (SELECT responsible_id FROM RESPONSIBLE);
  
 
  -- Importer ansvar for Elektro
  INSERT INTO responsible SELECT * FROM responsible_api where company_id = 'EL';
  
  -- Oppdater ansvarstabell med Corporater informasjon
  UPDATE responsible SET corporater_org_id = ( SELECT corporater_org_id FROM responsible_api WHERE responsible_api.responsible_id = responsible.responsible_id and rownum < 2)
  WHERE corporater_org_id IS NULL;
 
  COMMIT; 
  
  UpdateSectionDivision();
  
END UpdateResponsible;

PROCEDURE UpdateEmployee IS

  l_iPersonId        NUMBER(11,0);
  l_iRowID           person_parttime_pct_history.person_parttime_pct_history_id%TYPE;
  l_dtDateFrom       person_parttime_pct_history.date_from%TYPE;
  l_dtDateTo         person_parttime_pct_history.date_to%TYPE;
  l_strResponsibleId person_parttime_pct_history.responsible_id%TYPE;
  --l_strStatus  person_parttime_pct_history.status%TYPE;
  
  CURSOR l_curResPersonParttimeHistory IS SELECT DISTINCT person_parttime_pct_history_id FROM person_parttime_pct_history WHERE responsible_id IS NULL; 

BEGIN
  DELETE FROM employee;

  INSERT INTO employee (resource_id,first_name,last_name,short_name,date_of_birth,parttime_pct,man_labour_year,sex,responsible_id,company_id,date_from,date_to,status,resource_type_id,emp_poa_id,voob_id,post_id,employment_type_id)
  SELECT DISTINCT
    res.resource_id
    ,res.first_name
    ,res.surname
    ,res.short_name
    ,res.birth_date
    ,NVL(respost.parttime_pct,res.parttime_pct)
    ,NVL(respost.parttime_pct/100, res.parttime_pct/100)
    ,res.sex
    ,(SELECT rv.rel_value
        FROM G_AGRLES.mv_ahsrelvalue rv 
       WHERE rv.resource_id = res.resource_id 
         AND rv.rel_attr_id = 'C1'
         AND rv.date_from   < SYSDATE
         AND rv.date_to     >= SYSDATE 
   --      AND rv.period_from   < ( SELECT min(acc_period) from period WHERE date_from = TO_DATE( '01' || TO_CHAR(SYSDATE,'MMYYYY' ),'DDMMYYYY'))
   --      AND rv.period_to     >= (SELECT max(acc_period) from period WHERE date_to = last_day( to_date( '01' || TO_CHAR(SYSDATE,'MMYYYY' ),'DDMMYYYY')))
         AND rv.client      = 'A1'
         AND rv.status      = 'N'
         AND rownum < 2 ) AS responsible_id
    ,(SELECT rel_value
        FROM G_AGRLES.mv_ahsrelvalue rv2
       WHERE rv2.resource_id = res.resource_id 
         AND rv2.rel_attr_id = 'MNAC'
         --AND rv2.period_from   < ( SELECT min(acc_period) from period WHERE date_from = TO_DATE( '01' || TO_CHAR(SYSDATE,'MMYYYY' ),'DDMMYYYY'))
        -- AND rv2.period_to     >= (SELECT max(acc_period) from period WHERE date_to = last_day( to_date( '01' || TO_CHAR(SYSDATE,'MMYYYY' ),'DDMMYYYY')))
         AND rv2.date_from   < SYSDATE
         AND rv2.date_to     >= SYSDATE --add_months(SYSDATE,1)
         AND rv2.client      = 'A1'
         AND rv2.status      = 'N'
         AND ROWNUM < 2) AS company_id
    ,res.date_from
    ,res.date_to
    ,res.status
    ,res.resource_typ
    ,(SELECT rel_value
        FROM G_AGRLES.mv_ahsrelvalue rv3
       WHERE rv3.resource_id = res.resource_id 
         AND rv3.rel_attr_id = 'X3'
         AND rv3.date_from   < sysdate
         AND rv3.date_to     >= SYSDATE --add_months(SYSDATE,1)
         AND rv3.client      = 'A1'
         AND rv3.status      = 'N'
         AND ROWNUM < 2) AS emp_poa_id  --Oppmøtested
    ,(SELECT rel_value
        FROM G_AGRLES.mv_ahsrelvalue rv4
       WHERE rv4.resource_id = res.resource_id 
         AND rv4.rel_attr_id = 'U0'
         AND rv4.date_from   < SYSDATE
         AND rv4.date_to     >= add_months(SYSDATE,1)
         AND rv4.client      = 'A1'
         AND rv4.status      = 'N'
         AND ROWNUM < 2) AS voob_id  -- VOOB
    ,respost.post_id
    ,respost.type     AS employment_type_id  
  FROM G_AGRLES.mv_ahsresources res
   LEFT OUTER JOIN g_agrles.mv_aprresourcepost respost
     ON (res.resource_id = respost.resource_id AND 
         res.client = respost.client AND
         respost.date_from <= SYSDATE AND
         respost.date_to  >= add_months(SYSDATE,1) AND 
         respost.status = 'N' AND
         respost.main_position = 1)
  WHERE res.client = 'A1';
  
 /* 
  -- Oppdater med stillingsprosent og årsverk
  UPDATE employee SET parttime_pct = ( SELECT value_1 
                                     FROM g_agrles.MV_AHSRESRATE resrate 
                                    WHERE resrate.resource_id = employee.resource_id 
                                      AND resrate.client = 'A1' 
                                      AND resrate.value_id = 'I001' 
                                      AND resrate.attribute_id IN ('C0','C5')
                                      AND resrate.date_from < SYSDATE 
                                      AND to_char(resrate.date_to,'DDMMYYYY') = '31122099');
                  
  UPDATE employee SET man_labour_year = parttime_pct / 100;                                  
*/
  UPDATE employee SET responsible_id = responsible_id || company_id;

  COMMIT;
  
  SELECT max(person_id) INTO l_iPersonId FROM person WHERE person_id < 100000; -- Id'er over 100000 er fra den interne telleren i Genus
  
  -- Legg til nye person(er) fra Agressos ansattregister
  INSERT INTO person 
    (person_id
    ,first_name
    ,surname
    ,company_id
    ,responsible_id
    ,date_of_birth
    ,resource_id
    ,parttime_pct
    ,emp_date_from
    ,emp_date_to
    ,emp_man_labour_year
    ,resource_type_id
    ,emp_poa_id
    ,status
    ,description
    ,source_id
    ,voob_id
    ,sex
    ,employment_type_id)
  SELECT  
    l_iPersonId + rownum
   ,first_name
   ,last_name
   ,company_id
   ,responsible_id
   ,date_of_birth
   ,resource_id
   ,parttime_pct
   ,date_from
   ,date_to
   ,man_labour_year
   ,resource_type_id
   ,emp_poa_id
   ,status
   ,'Agresso brukernavn: ' || short_name
   ,1 --Agresso (ERP)
   ,voob_id
   ,sex
   ,employment_type_id
  FROM employee 
  WHERE NOT EXISTS ( SELECT null 
                       FROM person 
                      WHERE person.resource_id = employee.resource_id );

  -- Oppdater person med ansattinformasjon fra Agresso
  UPDATE person 
    SET first_name          = (SELECT NVL(first_name,'') FROM employee        WHERE person.resource_id = employee.resource_id),
        surname             = (SELECT last_name          FROM employee        WHERE person.resource_id = employee.resource_id),
        parttime_pct        = (SELECT parttime_pct       FROM employee        WHERE person.resource_id = employee.resource_id),
        emp_man_labour_year = (SELECT man_labour_year    FROM employee        WHERE person.resource_id = employee.resource_id),
        responsible_id      = (SELECT responsible_id     FROM employee        WHERE person.resource_id = employee.resource_id),
        company_id          = (SELECT company_id         FROM employee        WHERE person.resource_id = employee.resource_id),
        emp_date_to         = (SELECT date_to            FROM employee        WHERE person.resource_id = employee.resource_id),
        resource_type_id    = (SELECT resource_type_id   FROM employee        WHERE person.resource_id = employee.resource_id),
        status              = (SELECT status             FROM employee        WHERE person.resource_id = employee.resource_id),
        emp_poa_id          = (SELECT emp_poa_id         FROM employee        WHERE person.resource_id = employee.resource_id),
        voob_id             = (SELECT voob_id            FROM employee        WHERE person.resource_id = employee.resource_id),
        sex                 = (SELECT sex                FROM employee        WHERE person.resource_id = employee.resource_id),
        employment_type_id  = (SELECT employment_type_id FROM employee        WHERE person.resource_id = employee.resource_id)
  WHERE resource_id IS NOT NULL;
  
  UPDATE person SET staff_job_title_id = (SELECT staff_job_title_id 
                                            FROM staff_job_title 
                                           WHERE staff_job_title.staff_job_title_code = ( SELECT employee.post_id FROM employee WHERE person.resource_id = employee.resource_id
                                                                                            AND post_id IS NOT NULL))
  WHERE resource_id IS NOT NULL;
                                           
  -- Oppdater person med lønnsinfo
  UPDATE person
    SET year_salary = (SELECT MAX(NVL(v.value_1,0)) 
                         FROM g_agrles.mv_aprvalues v 
                        WHERE v.dim_value = person.resource_id 
                          AND v.client = 'A1'
                          AND v.value_id = 'I010' --Ã…rslÃ¸nn
                          AND v.attribute_id = 'C0'
                          AND v.status = 'N'
                          AND v.date_from <= SYSDATE
                          AND v.date_to   >= SYSDATE);
                         
  /* GAMMEL, INNEHOLDER IKKE OPPDATERT INFO
  -- Oppdater person med lønnsinfo
  UPDATE person
    SET year_salary = (SELECT NVL(v.value_1,0) 
                         FROM G_AGRLES.mv_ahsresrate v 
                        WHERE v.dim_value = person.resource_id 
                          AND v.client = 'A1'
                          AND v.value_id = 'I010' --Ã…rslÃ¸nn
                          AND v.attribute_id = 'C0'
                          AND to_char(v.date_to,'DDMMYYYY') = '31122099');  --Siste aktive verdi

 */   
 
 /*
 --Denne tar lang tid - skrive om?
  UPDATE person
    SET account_id_year_salary = ( SELECT rule.account
                                     FROM g_agrles.mv_ahsresrate rate, g_agrles.mv_aprrules RULE
                                    WHERE rate.client = RULE.client
                                      AND rate.value_id = RULE.amount_ref
                                      AND rate.resource_id = person.resource_id 
                                      AND rate.client = 'A1'
                                     AND to_char(rate.date_to,'DDMMYYYY') = '31122099'
                                      AND rate.value_id = 'I011'
                                      AND rate.value_1 <> 0
                                      AND RULE.status = 'N' );
  */
  UPDATE person SET account_id_year_salary = NULL;
  UPDATE person SET account_id_year_salary = '5016' WHERE resource_type_id = 'E';
  UPDATE person SET account_id_year_salary = '5010' WHERE account_id_year_salary is NULL;
  
  UPDATE person SET emp_date_to      = ( SELECT date_to FROM employee WHERE employee.resource_id = person.resource_id );
  UPDATE person SET resource_type_id = ( SELECT resource_type_id FROM employee WHERE employee.resource_id = person.resource_id );
  UPDATE person SET status           = ( SELECT status FROM employee WHERE employee.resource_id = person.resource_id );
  
  --Oppdaterer med dummydata for å hindre at personene ikke kommer opp i lønnsbudsjetteringen.
  -- DETTE SKULLE IKKE VÆRE NØDVENDIG
  -- VENTER TILBAKEMELDING FRA SYSTEM (Helge N) 27.09.2013
  UPDATE person SET responsible_id = 'N/A' WHERE responsible_id IS NULL AND status = 'N' AND resource_type_id = 'A' and year_salary IS NOT NULL;
  COMMIT;
  
  --Oppdater selskap- og ansvartilhørighet
  DELETE person_company_assoc;
  INSERT INTO person_company_assoc
  ( person_company_assoc_id,
    company_id,
    person_id,
    date_from,
    date_to,
    period_from,
    period_to,
    last_update,
    status
  )
  SELECT sys_guid(), rv.rel_value, p.person_id, rv.date_from, rv.date_to, rv.period_from, rv.period_to, rv.last_update, rv.status
    FROM G_AGRLES.mv_ahsrelvalue rv, person p
   WHERE rv.resource_id = p.resource_id
     AND rv.rel_attr_id = 'MNAC'
     AND rv.client      = 'A1';
     
  DELETE FROM person_responsible_assoc;
  INSERT INTO person_responsible_assoc
  ( person_responsible_assoc_id,
    responsible_id,
    person_id,
    date_from,
    date_to,
    period_from,
    period_to,
    last_update,
    status
  )
  SELECT sys_guid(), rv.rel_value, p.person_id, rv.date_from, rv.date_to, rv.period_from, rv.period_to, rv.last_update, rv.status
    FROM G_AGRLES.mv_ahsrelvalue rv, 
         person p
   WHERE rv.resource_id = p.resource_id
     AND rv.rel_attr_id = 'C1'
     AND rv.client      = 'A1';

  UPDATE person_responsible_assoc SET company_id = (SELECT distinct company_id 
                                                        FROM  person_company_assoc 
                                                       WHERE person_responsible_assoc.person_id  = person_company_assoc.person_id
                                                         AND  person_responsible_assoc.date_from = person_company_assoc.date_from
                                                         AND  person_responsible_assoc.date_to   = person_company_assoc.date_to
                                                         AND  person_responsible_assoc.status    = person_company_assoc.status
                                                      );
                                                      
  UPDATE person_responsible_assoc SET company_id = (SELECT  company_id 
                                                          FROM  person
                                                         WHERE person.person_id = person_responsible_assoc.person_id
                                                        )
   WHERE company_id IS NULL;
                                                       
  UPDATE person_responsible_assoc SET responsible_id = responsible_id || company_id;
   -- WHERE substr(responsible_id,length(responsible_id)-1,2) NOT IN (SELECT company_id FROM company);
  

  DELETE FROM person_parttime_pct_history;
  INSERT INTO person_parttime_pct_history
  ( person_parttime_pct_history_id,
    person_id,
    date_from,
    date_to,
    period_from,
    period_to,
    parttime_pct,
    last_update
    )
   SELECT sys_guid(), person.person_id, mv_aprresourcepost.date_from, mv_aprresourcepost.date_to, null,null, mv_aprresourcepost.parttime_pct/100,mv_aprresourcepost.last_update
     FROM g_agrles.mv_aprresourcepost, 
           person
    WHERE mv_aprresourcepost.resource_id = person.resource_id;

  /*
  UPDATE person_parttime_pct_history SET responsible_id = (SELECT DISTINCT responsible_id 
                                                               FROM person_responsible_assoc 
                                                               WHERE person_responsible_assoc.person_id = person_parttime_pct_history.person_id
                                                                 AND person_responsible_assoc.date_from <= person_parttime_pct_history.date_from
                                                                 AND person_responsible_assoc.date_to   >= person_parttime_pct_history.date_to
                                                            );
*/
  COMMIT;
  
  OPEN l_curResPersonParttimeHistory;
  FETCH l_curResPersonParttimeHistory INTO l_iRowID;
  WHILE l_curResPersonParttimeHistory%FOUND LOOP
  
     SELECT person_id INTO l_iPersonID  FROM person_parttime_pct_history WHERE person_parttime_pct_history_id = l_iRowID;
     SELECT date_from INTO l_dtDateFrom FROM person_parttime_pct_history WHERE person_parttime_pct_history_id = l_iRowID;
     SELECT date_to   INTO l_dtDateTo   FROM person_parttime_pct_history WHERE person_parttime_pct_history_id = l_iRowID;
     
     BEGIN
       SELECT responsible_id INTO l_strResponsibleId 
         FROM person_responsible_assoc 
        WHERE person_id = l_iPersonID
          AND date_from <= l_dtDateFrom
          AND date_to   >= l_dtDateTo;
     EXCEPTION WHEN no_data_found THEN SELECT responsible_id INTO l_strResponsibleId FROM person WHERE person_id = l_iPersonID;
                 WHEN too_many_rows THEN SELECT responsible_id INTO l_strResponsibleId FROM person WHERE person_id = l_iPersonID; --l_strResponsibleId := NULL; --DBMS_OUTPUT.PUT_LINE(l_iPersonID) ;
     END; 

     UPDATE person_parttime_pct_history SET responsible_id =  l_strResponsibleId  WHERE person_parttime_pct_history_id = l_iRowID;
  
  FETCH l_curResPersonParttimeHistory INTO l_iRowID;
  END LOOP;
  CLOSE l_curResPersonParttimeHistory;
  
  COMMIT;
  
  DELETE person_salary_addition WHERE agresso_code_id in ('I056','I106','I040');

 -- ADSL og telefon
 /* OPPRINNELIG ETL Endret 19082014
  INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    rate.value_id, 
    rate.value_1, 
    person.person_id, 
    200
  FROM
    g_agrles.mv_ahsresrate rate, 
    g_agrles.mv_aprrules rule, person
  WHERE rate.client = rule.client
    AND rate.value_id = rule.amount_ref
    AND rate.resource_id = person.resource_id
    AND rate.client = 'A1'
    AND to_char(rate.date_to,'ddmmyyyy') = '31122099'
    AND rate.value_id = 'I056'
    AND rate.value_1 <> 0
    AND RULE.status = 'N'
    AND person.resource_id is not null;
    
    
  INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    VAL.value_id, 
    val.value_1, 
    person.person_id, 
    200
   FROM g_agrles.mv_aprvalues VAl, person
   WHERE VAL.dim_value = person.resource_id
     AND val.attribute_id = 'C0' 
     AND val.client = 'A1' 
     AND value_id = 'I056'
     AND val.status = 'N'
     AND val.date_from < SYSDATE 
     AND val.date_to > SYSDATE; -- AND to_char(date_to,'ddmmyyyy') = '31122099' 
*/
  INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    VAL.value_id, 
    val.value_1, 
    person.person_id, 
    200
   FROM g_agrles.mv_ahsresrate VAl, person
   WHERE VAL.resource_id = person.resource_id
     AND val.attribute_id in ('C0','C5') 
     AND val.client = 'A1' 
     AND value_id = 'I056'
     AND val.date_from < SYSDATE 
     AND val.date_to > SYSDATE; -- AND to_char(date_to,'ddmmyyyy') = '31122099' 



-- Vakttillegg
/* OPPRINNELIG ETL Endret 19082014
  INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    rate.value_id, 
    rate.value_1, 
    person.person_id, 
    3276444
  FROM 
    g_agrles.mv_ahsresrate rate, 
    g_agrles.mv_aprrules rule, person
  WHERE rate.client = rule.client
    AND rate.value_id = rule.amount_ref
    AND rate.resource_id = person.resource_id
    AND rate.client = 'A1'
    AND to_char(rate.date_to,'ddmmyyyy') = '31122099'
    AND rate.value_id = 'I106'
    AND rate.value_1 <> 0
    AND rate.attribute_id = 'C0'
    AND trim(RULE.add_pd) IS NULL
    AND rule.status = 'N'
    AND person.resource_id IS NOT NULL;
    */
  INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    VAL.value_id, 
    val.value_1, 
    person.person_id, 
    3276444
   FROM g_agrles.mv_ahsresrate VAl, person
   WHERE VAL.resource_id = person.resource_id
     AND val.attribute_id in ('C0','C5')  
     AND val.client = 'A1' 
     AND value_id = 'I106'
     AND val.date_from < SYSDATE 
     AND val.date_to > SYSDATE; -- AND to_char(date_to,'ddmmyyyy') = '31122099'  
    
-- Komp for å ikke ha firmabil
/*
  INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    rate.value_id, 
    rate.value_1, 
    person.person_id, 
    400
  FROM 
    g_agrles.mv_ahsresrate rate, 
    g_agrles.mv_aprrules rule, person
  WHERE rate.client = rule.client
    AND rate.value_id = rule.amount_ref
    AND rate.resource_id = person.resource_id
    AND rate.client = 'A1'
    AND to_char(rate.date_to,'ddmmyyyy') = '31122099'
    AND rate.value_id = 'I040'
    AND rate.value_1 <> 0
    AND rate.attribute_id = 'C0'
    AND trim(RULE.add_pd) IS NULL
    AND rule.status = 'N'
    AND person.resource_id IS NOT NULL;
*/

INSERT INTO person_salary_addition 
  (person_salary_addition_id
  ,agresso_code_id
  ,value
  ,person_id
  ,salary_addition_category_id)
  SELECT 
    sys_guid(),
    VAL.value_id, 
    val.value_1, 
    person.person_id, 
    400
   FROM g_agrles.mv_ahsresrate VAl, person
   WHERE VAL.resource_id = person.resource_id
     AND val.attribute_id in ('C0','C5') 
     AND val.client = 'A1' 
     AND value_id = 'I040'
     AND val.date_from < SYSDATE 
     AND val.date_to > SYSDATE; -- AND to_char(date_to,'ddmmyyyy') = '31122099'  

-- Oppdater info om ressurstype
EXECUTE IMMEDIATE('TRUNCATE TABLE resource_type_history');

INSERT INTO resource_type_history
(
  resource_type_history_id,
  person_id,
  resource_type_id,
  date_from,
  date_to,
  status,
  last_update 
)
SELECT  
  sys_guid()
 ,person.person_id
 ,ahs.rel_value
 ,ahs.date_from
 ,ahs.date_to
 ,ahs.status
 ,ahs.last_update
  FROM g_agrles.mv_ahsrelvalue ahs, person 
 WHERE ahs.resource_id = person.resource_id
   AND ahs.rel_attr_id = 'C2' 
   AND ahs.client = 'A1';
  
UPDATE resource_type_history SET period_from = (SELECT MIN(acc_period) FROM period WHERE period.date_from = resource_type_history.date_from);
UPDATE resource_type_history SET period_to   = (SELECT MAX(acc_period) FROM period WHERE period.date_to = resource_type_history.date_to);

UPDATE resource_type_history SET company_id = 
  ( SELECT company_id 
      FROM person_company_assoc 
     WHERE resource_type_history.person_id = person_company_assoc.person_id 
       AND   resource_type_history.date_from = person_company_assoc.date_from
       AND   resource_type_history.date_to = person_company_assoc.date_to
);

UPDATE resource_type_history SET company_id = 
  ( SELECT company_id 
      FROM person_company_assoc 
     WHERE resource_type_history.person_id = person_company_assoc.person_id 
       AND   resource_type_history.date_to = person_company_assoc.date_to
)
WHERE company_id IS NULL;

UPDATE resource_type_history SET company_id = 
  ( SELECT company_id 
      FROM person_company_assoc 
     WHERE resource_type_history.person_id = person_company_assoc.person_id 
       AND   resource_type_history.date_to > person_company_assoc.date_to
       AND   resource_type_history.date_to = person_company_assoc.date_to
)
WHERE company_id IS NULL;


UPDATE resource_type_history SET company_id = 
  ( SELECT company_id 
      FROM person_company_assoc 
     WHERE resource_type_history.person_id = person_company_assoc.person_id 
       AND   resource_type_history.date_to > person_company_assoc.date_to
       AND   resource_type_history.date_to = person_company_assoc.date_to
)
WHERE company_id IS NULL;

UPDATE resource_type_history SET company_id = 
  ( SELECT company_id 
      FROM person
     WHERE resource_type_history.person_id = person.person_id 
)
WHERE company_id IS NULL;


-- Oppdater person-selskapshistorikk med ressurstype for å kunne telle antall ansatte med riktig historisk ressurstype

UPDATE person_company_assoc SET resource_type_id = ( SELECT resource_type_id 
                                                         FROM resource_type_history 
                                                        WHERE person_company_assoc.person_id = resource_type_history.person_id
                                                          AND  person_company_assoc.date_to  >= resource_type_history.date_to
                                                          AND  person_company_assoc.date_from <= resource_type_history.date_from
                                                          AND  person_company_assoc.date_from = (SELECT max(date_from) FROM resource_type_history hist2 WHERE hist2.person_id = resource_type_history.person_id)
                                                          AND  person_company_assoc.date_to = (SELECT max(date_to) FROM resource_type_history hist2 WHERE hist2.person_id = resource_type_history.person_id));
                                                          
UPDATE person_company_assoc SET resource_type_id = ( SELECT max(resource_type_id) 
                                                         FROM resource_type_history 
                                                        WHERE person_company_assoc.person_id = resource_type_history.person_id
                                                          AND  person_company_assoc.date_to  >= resource_type_history.date_to
                                                          AND  person_company_assoc.date_from <= resource_type_history.date_from
                                                          AND  person_company_assoc.date_from < (SELECT max(date_from) FROM resource_type_history hist2 WHERE hist2.person_id = resource_type_history.person_id)
                                                          AND  person_company_assoc.date_to >= (SELECT max(date_to) FROM resource_type_history hist2 WHERE hist2.person_id = resource_type_history.person_id))
WHERE resource_type_id IS NULL;


UPDATE person_company_assoc SET resource_type_id = ( SELECT resource_type_id
                                                         FROM person 
                                                        WHERE person_company_assoc.person_id = person.person_id)
WHERE resource_type_id IS NULL;

COMMIT;
    
    /*
    OBS OBS FØLGENDE UNDER MÅ FJERNES ETTER AT FEBRUARRAPPORTERINGEN FROM HMS ER GJORT
    
         UPDATE person set company_id = 'SK', responsible_id = '700SK' WHERE resource_id = '920345';
         UPDATE person set responsible_id = '701SK' WHERE resource_id = '910716';
         UPDATE person set responsible_id = '701SK' WHERE resource_id = '910702';
   COMMIT;
   */
   /* SLUTT ENDRING*/

END UpdateEmployee;

PROCEDURE UpdateCustomer IS
BEGIN
  MERGE INTO customer c
  USING (
    SELECT DISTINCT apar_id, client, apar_name, status
      FROM g_agrles.MV_ACUHEADER
      WHERE client IN (SELECT company_id FROM COMPANY) --('NO', 'EN')  -- Test klienter
      ORDER BY apar_id, client) mv
  ON (c.customer_id = mv.apar_id || mv.client)
  WHEN MATCHED THEN
    UPDATE SET c.customer_name=mv.apar_name, c.customer_status=mv.status
  WHEN NOT MATCHED THEN
    INSERT (c.customer_id, c.customer_ident,c.customer_name, c.customer_status, c.customer_top_20, c.company_id)
    VALUES (mv.apar_id || mv.client, mv.apar_id, mv.apar_name, mv.status, NULL,mv.client);
   
  COMMIT;
  
  DELETE customer WHERE company_id = 'EL';
   
   INSERT INTO customer (customer_id,customer_ident,customer_name,company_id)
     SELECT kun_nr || 'EL', kun_nr, NVL(kun_navn,'Ingen navn registrert'), 'EL' FROM g_vismales.load_kund;

  COMMIT;
   
   
END UpdateCustomer;

PROCEDURE UpdateSupplier (i_jobbID varchar2 default '') IS

BEGIN

  -- Setter Startid
  SELECT sysdate INTO g_dtStartTime from dual;
  
  g_bResult := false;
  g_strText := 'START: UpdateSupplier';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSupplier', 0, i_jobbID);
  
  MERGE INTO supplier s
  USING (
    SELECT DISTINCT apar_id, client, nvl(apar_name,'Ingen navn registrert') as apar_name, status
      FROM g_agrles.MV_ASUHEADER
      WHERE client IN (SELECT company_id FROM company) 
      ORDER BY apar_id, client) mv
  ON (s.supplier_id = mv.apar_id || mv.client)
  WHEN MATCHED THEN
    UPDATE SET s.apar_name=nvl(mv.apar_name,'Ingen navn registrert'), s.status=mv.status
  WHEN NOT MATCHED THEN
    INSERT 
    (s.supplier_id, s.apar_name, s.client, s.status, s.apar_id)
    VALUES 
    ( mv.apar_id || mv.client, nvl(mv.apar_name,'Ingen navn registrert'), mv.client, mv.status,mv.apar_id ); 

   --DELETE supplier WHERE client = 'EL';
   
  MERGE INTO supplier s
  USING (
    SELECT DISTINCT lev_nr || 'EL', 'EL', nvl(lev_navn,'Ingen navn registrert') as lev_navn, 'N',lev_nr
      FROM G_VISMALES.VISMA_LEVR_EXTERNAL 
      WHERE lev_nr IS NOT NULL
      ORDER BY lev_nr) mv
  ON (s.supplier_id = mv.lev_nr || 'EL')
  WHEN MATCHED THEN
    UPDATE SET s.apar_name=nvl(mv.lev_navn,'Ingen navn registrert')
  WHEN NOT MATCHED THEN
    INSERT 
    (s.supplier_id, s.apar_name, s.client, s.status, s.apar_id)
    VALUES 
    ( mv.lev_nr || 'EL', nvl(mv.lev_navn,'Ingen navn registrert'), 'EL', 'N', mv.lev_nr ); 
   
   /*
   INSERT INTO supplier (supplier_id,apar_id,apar_name,client)
     SELECT lev_nr || 'EL', lev_nr, NVL(lev_navn,'Ingen navn registrert'), 'EL' FROM g_vismales.load_levr;
*/
  COMMIT;
  
  -- Setter sluttid
  SELECT sysdate INTO g_dtEndTime FROM dual;
  
  --Script for å finne tidsforbruk
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );
  
  -- Sluttlogg 
  g_strText := 'FINISH: UpdateSupplier - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSupplier', 0, i_jobbID );
  
END UpdateSupplier;

PROCEDURE UpdateVOOB IS
BEGIN
  INSERT INTO voob(voob_id,voob_ident,voob_name,company_id,status)
  SELECT dim_value || client, dim_value, description, client,status
    FROM g_agrles.MV_AGLDIMVALUE 
   WHERE attribute_id = 'U0'   --VOOB 
     AND client IN (SELECT company_id FROM company where termination_code_id IS NULL)
     AND dim_value || client NOT IN (SELECT voob_id FROM voob)
   ORDER BY client, dim_value;
END UpdateVOOB;
   
PROCEDURE UpdateSectionDivision IS
BEGIN
     DELETE section;
     DELETE division;
     
     INSERT INTO section (section_id,section_name,division_id, section_responsible,company_id)
     SELECT dim_value || client, description, null, null,client
       FROM g_agrles.MV_AGLDIMVALUE 
      WHERE attribute_id = 'N7'   --SECTION
        AND status = 'N'
        AND dim_value || client NOT IN (SELECT section_id FROM section);
        
     INSERT INTO division (division_id,division_name,company_id)
     SELECT dim_value || client, description, client
       FROM g_agrles.MV_AGLDIMVALUE 
      WHERE attribute_id = 'N5'   --division
        AND status = 'N'
        AND dim_value || client NOT IN (SELECT division_id FROM division);
     
     UPDATE responsible SET section_id =
       (SELECT rel_value || client FROM  g_agrles.mv_aglrelvalue 
         WHERE attribute_id = 'C1' 
           AND rel_attr_id  = 'N7'
           AND client IN ( SELECT company_id FROM company ) --= 'SE' 
           AND responsible.responsible_id = att_value || client);
           
     UPDATE section SET division_id = 
       (SELECT rel_value || client FROM  g_agrles.mv_aglrelvalue 
         WHERE attribute_id = 'N7' 
           AND rel_attr_id  = 'N5'
           AND client IN ( SELECT company_id FROM company ) --= 'SE' 
           AND section.section_id = att_value || client);

     COMMIT;
     
END UpdateSectionDivision;
   
PROCEDURE UpdateProject IS
BEGIN
  INSERT INTO project (project_id,project_ident,project_name,large_project_id,company_id,status)
  SELECT dim_value || client, dim_value, description, NULL, client, status
    FROM g_agrles.MV_AGLDIMVALUE 
   WHERE attribute_id = 'B0'
     AND client IN (SELECT company_id FROM company)
     AND dim_value || client NOT IN (SELECT project_id FROM project)
   ORDER BY client,dim_value;
   
  COMMIT;
   
END UpdateProject;

PROCEDURE UpdateWorkOrder IS
BEGIN
  INSERT INTO work_order (work_order_id,work_order_ident, work_order_name,company_id, status)
  SELECT dim_value || client, dim_value, description, client, status
    FROM g_agrles.MV_AGLDIMVALUE 
   WHERE attribute_id = 'BF'   --ARBEIDSORDRE    
     AND client IN (SELECT company_id FROM company)
     AND dim_value || client NOT IN (SELECT work_order_id FROM work_order)
  ORDER BY client,dim_value;
  
  /* SKRIV OM TAR EVIGHETER
  UPDATE work_order SET work_order_name = (SELECT description FROM g_agrles.MV_AGLDIMVALUE 
   WHERE attribute_id = 'BF'   --ARBEIDSORDRE         
     AND dim_value || client  = work_order.work_order_id
     AND description is not null);
     
     */
  COMMIT;
  
END UpdateWorkOrder;

PROCEDURE UpdateResourceType IS
BEGIN
  INSERT INTO resource_type(resource_type_id,resource_type_name,status)
    SELECT dim_value,description,status 
      FROM g_agrles.mv_agldimvalue 
     WHERE client       = 'A1' 
       AND attribute_id = 'C2'
       AND dim_value NOT IN (SELECT resource_type_id FROM resource_type );
   
   UPDATE resource_type SET resource_type_name = (SELECT description
                                                      FROM g_agrles.mv_agldimvalue 
                                                     WHERE client       = 'A1' 
                                                       AND attribute_id = 'C2'
                                                       AND resource_type.resource_type_id = dim_value);
       
   UPDATE resource_type SET status             = (SELECT status
                                                      FROM g_agrles.mv_agldimvalue 
                                                     WHERE client       = 'A1' 
                                                       AND attribute_id = 'C2'
                                                       AND resource_type.resource_type_id = dim_value);

  COMMIT;
    
END UpdateResourceType;

PROCEDURE UpdateDistributionKey IS
BEGIN
  EXECUTE IMMEDIATE('TRUNCATE TABLE BUDGET_DISTRIBUTION_KEY_HEAD');

  INSERT INTO BUDGET_DISTRIBUTION_KEY_HEAD
  SELECT DISTINCT DECODE(TYPE,'R','10000','B','20000') || budget_key, description, NULL, DECODE(TYPE,'R',1,'B',2,-1)  
    FROM G_AGRLES.mv_aglbudgetkey 
   WHERE DECODE(TYPE,'R','10000','B','20000') || budget_key NOT IN (SELECT budget_dkh_id FROM BUDGET_DISTRIBUTION_KEY_HEAD)
     AND DECODE(TYPE,'R',1,'B',2,-1) <> -1
   ORDER BY DECODE(type,'R','10000','B','20000') || budget_key;

  COMMIT;

  EXECUTE IMMEDIATE('TRUNCATE TABLE BUDGET_DISTRIBUTION_KEY_ITEM');

  INSERT INTO BUDGET_DISTRIBUTION_KEY_ITEM
  SELECT DISTINCT DECODE(TYPE,'R','10000','B','20000') || budget_key || to_char(ROWNUM), DECODE(TYPE,'R','10000','B','20000')  || budget_key, bud_period, budget_pro, NULL  
    FROM G_AGRLES.mv_aglbudgetkey 
   WHERE DECODE(TYPE,'R','10000','B','20000') || budget_key IN (SELECT budget_dkh_id FROM BUDGET_DISTRIBUTION_KEY_HEAD)
   ORDER BY DECODE(TYPE,'R','10000','B','20000')  || budget_key, bud_period;

  COMMIT; 
END UpdateDistributionKey;

PROCEDURE MoveCashFlowEffectsToPeriod IS

 l_row ltp_cash_flow_effect%ROWTYPE;
 
 l_iCurrentId ltp_cash_flow_effect.LTP_CASH_FLOW_EFFECTS_ID%TYPE;
 l_iProcessedId ltp_cash_flow_effect.LTP_CASH_FLOW_EFFECTS_ID%TYPE;
 
 l_strLTP1Year  VARCHAR2(4);
 l_strLTP2Year  VARCHAR2(4);
 l_strLTP3Year  VARCHAR2(4);
 l_strLTP4Year  VARCHAR2(4);
 l_strLTP5Year  VARCHAR2(4);
 
 l_iTableCount  NUMBER(11,0);
 
CURSOR l_curLines IS SELECT * FROM ltp_cash_flow_effect;
BEGIN
  
  l_iProcessedId := 0;
  DELETE ltp_cash_flow_effect_tmp;
  DELETE LTP_CASH_FLOW_EFFECT WHERE account_amount IS NULL AND prognosis_amount = 0     AND  ltp1_amount IS NULL AND ltp2_amount IS NULL AND ltp3_amount IS NULL AND ltp4_amount IS NULL AND ltp5_amount IS NULL;
  DELETE LTP_CASH_FLOW_EFFECT WHERE account_amount IS NULL AND prognosis_amount IS NULL AND  ltp1_amount IS NULL AND ltp2_amount IS NULL AND ltp3_amount IS NULL AND ltp4_amount IS NULL AND ltp5_amount IS NULL;
  COMMIT;

      OPEN l_curLines;
      FETCH l_curLines INTO l_row;
      WHILE l_curLines%FOUND LOOP

     l_iCurrentId := l_row.LTP_CASH_FLOW_EFFECTS_ID;
     
     IF l_iCurrentId <> l_iProcessedId THEN
         SELECT TO_CHAR(ltp_entry_head_year,'YYYY')                INTO l_strLTP1Year FROM ltp_entry_head WHERE ltp_entry_head_id = l_row.ltp_id;
         SELECT TO_CHAR(ADD_MONTHS(ltp_entry_head_year,12),'YYYY') INTO l_strLTP2Year FROM ltp_entry_head WHERE ltp_entry_head_id = l_row.ltp_id;
         SELECT TO_CHAR(ADD_MONTHS(ltp_entry_head_year,24),'YYYY') INTO l_strLTP3Year FROM ltp_entry_head WHERE ltp_entry_head_id = l_row.ltp_id;
         SELECT TO_CHAR(ADD_MONTHS(ltp_entry_head_year,36),'YYYY') INTO l_strLTP4Year FROM ltp_entry_head WHERE ltp_entry_head_id = l_row.ltp_id;
         SELECT TO_CHAR(ADD_MONTHS(ltp_entry_head_year,48),'YYYY') INTO l_strLTP5Year FROM ltp_entry_head WHERE ltp_entry_head_id = l_row.ltp_id;
     
      IF nvl(l_row.LTP1_AMOUNT,0) <> 0 THEN 
      
      INSERT INTO ltp_cash_flow_effect_tmp (LTP_ID,CONTRA_COMPANY_ID,REPORT_LEVEL_3_ID,LTP1_AMOUNT,LTP_CASH_FLOW_EFFECTS_COMMENT,PERIOD) 
      VALUES (l_row.ltp_id,l_row.contra_company_id,l_row.report_level_3_id,l_row.ltp1_amount,l_row.LTP_CASH_FLOW_EFFECTS_COMMENT,
               to_number(l_strLTP1Year || '07'));
      
      END IF;
      IF nvl(l_row.LTP2_AMOUNT,0) <> 0 THEN 
      
      INSERT INTO ltp_cash_flow_effect_tmp (LTP_ID,CONTRA_COMPANY_ID,REPORT_LEVEL_3_ID,LTP2_AMOUNT,LTP_CASH_FLOW_EFFECTS_COMMENT,PERIOD) 
      VALUES (l_row.ltp_id,l_row.contra_company_id,l_row.report_level_3_id,l_row.ltp2_amount,l_row.LTP_CASH_FLOW_EFFECTS_COMMENT,
               to_number(l_strLTP2Year || '07'));
      
      END IF;
      IF nvl(l_row.LTP3_AMOUNT,0) <> 0 THEN 
      
      INSERT INTO ltp_cash_flow_effect_tmp (LTP_ID,CONTRA_COMPANY_ID,REPORT_LEVEL_3_ID,LTP3_AMOUNT,LTP_CASH_FLOW_EFFECTS_COMMENT,PERIOD) 
      VALUES (l_row.ltp_id,l_row.contra_company_id,l_row.report_level_3_id,l_row.ltp3_amount,l_row.LTP_CASH_FLOW_EFFECTS_COMMENT,
               to_number(l_strLTP3Year || '01'));
      
      END IF;
      IF nvl(l_row.LTP4_AMOUNT,0) <> 0 THEN 
      
      INSERT INTO ltp_cash_flow_effect_tmp (LTP_ID,CONTRA_COMPANY_ID,REPORT_LEVEL_3_ID,LTP4_AMOUNT,LTP_CASH_FLOW_EFFECTS_COMMENT,PERIOD) 
      VALUES (l_row.ltp_id,l_row.contra_company_id,l_row.report_level_3_id,l_row.ltp4_amount,l_row.LTP_CASH_FLOW_EFFECTS_COMMENT,
               to_number(l_strLTP4Year || '01'));
      
      END IF;
      IF nvl(l_row.LTP5_AMOUNT,0) <> 0 THEN 
      
      INSERT INTO ltp_cash_flow_effect_tmp (LTP_ID,CONTRA_COMPANY_ID,REPORT_LEVEL_3_ID,LTP5_AMOUNT,LTP_CASH_FLOW_EFFECTS_COMMENT,PERIOD) 
      VALUES (l_row.ltp_id,l_row.contra_company_id,l_row.report_level_3_id,l_row.ltp5_amount,l_row.LTP_CASH_FLOW_EFFECTS_COMMENT,
               to_number(l_strLTP5Year || '01'));
      
      END IF;
     
     l_iProcessedId := l_iCurrentId;
     
     END IF;

      FETCH l_curLines INTO l_row;
     END LOOP;
     CLOSE l_curLines;

   SELECT count(*) INTO l_iTableCount FROM user_tables WHERE lower(table_name) LIKE 'ltp_cash_flow_effect_year';
   IF l_iTableCount = 1 THEN
     EXECUTE IMMEDIATE ('DROP TABLE ltp_cash_flow_effect_year' );
   END IF;
   EXECUTE IMMEDIATE('CREATE TABLE ltp_cash_flow_effect_year AS SELECT * FROM ltp_cash_flow_effect');
  
   DELETE FROM ltp_cash_flow_effect;
  

INSERT INTO ltp_cash_flow_effect
(ltp_cash_flow_effects_id
,ltp_id
,contra_company_id
,report_level_3_id
,ltp1_amount
,ltp2_amount
,ltp3_amount
,ltp4_amount
,ltp5_amount
,ltp_cash_flow_effects_comment
,period)
SELECT 
  ROWNUM
 ,ltp_id
 ,contra_company_id
,report_level_3_id
,ltp1_amount
,ltp2_amount
,ltp3_amount
,ltp4_amount
,ltp5_amount
,ltp_cash_flow_effects_comment
,period
FROM ltp_cash_flow_effect_tmp;
COMMIT;

END MoveCashFlowEffectsToPeriod;

PROCEDURE UpdateHMSOrgStructure IS
BEGIN

EXECUTE IMMEDIATE('TRUNCATE TABLE hms_org_level_1');
INSERT INTO hms_org_level_1 (hms_org_level_1_id,hms_org_level_1_name) SELECT dim_value, description FROM g_agrles.mv_agldimvalue WHERE client = 'A1' AND attribute_id = 'XHR1';


/*
EXECUTE IMMEDIATE('TRUNCATE TABLE hms_org_level_2');
INSERT INTO hms_org_level_2 (hms_org_level_2_id,hms_org_level_2_name,hms_org_level_1_id,dk_treekey)
SELECT v.dim_value, v.description, r.rel_value, dk.treekey  
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR2'
  AND r.rel_attr_id = 'XHR1'
  AND lower(dk.displaytext (+)) = lower(v.description)
  AND substr(dk.treekey,0,4) <> '3008'      
  AND length(dk.treekey) = 4
order by dim_value;
*/
DELETE hms_org_level_2 
   WHERE hms_org_level_2_id NOT IN ( SELECT v.dim_value
                                         FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r
                                        WHERE v.client = r.client
                                          AND v.dim_value = r.att_value
                                          AND v.client = 'A1' 
                                          AND v.attribute_id = 'XHR2'
                                          AND r.rel_attr_id = 'XHR1');

MERGE INTO hms_org_level_2
USING ( SELECT v.dim_value, v.description, r.rel_value, dk.treekey    
           FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
          WHERE v.client = r.client
            AND v.dim_value = r.att_value
            AND v.client = 'A1' 
            AND v.attribute_id = 'XHR2'
            AND r.rel_attr_id = 'XHR1'
            AND lower(dk.displaytext (+)) = lower(v.description)
            --AND substr(dk.treekey,0,4) <> '3008'      
            AND length(dk.treekey) = 4 ) src
   ON (hms_org_level_2.hms_org_level_2_id = src.dim_value)
   WHEN MATCHED THEN
     UPDATE SET hms_org_level_2_name = src.description,  hms_org_level_1_id = src.rel_value, dk_treekey = src.treekey
   WHEN NOT MATCHED THEN
     INSERT ( hms_org_level_2_id, hms_org_level_2_name, hms_org_level_1_id, dk_treekey)
     VALUES ( src.dim_value,      src.description,      src.rel_value,      src.treekey);


/*  OIG/HR 011215 - Endret til å hente treekey direkte fra g_dkles.dk_vorgnode_external
SELECT v.dim_value, v.description, r.rel_value, dk.treekey  
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR2'
  AND r.rel_attr_id = 'XHR1'
  AND dk.displaytext (+) = v.description
order by dim_value;
*/

/*
EXECUTE IMMEDIATE('TRUNCATE TABLE hms_org_level_3');
INSERT INTO hms_org_level_3 (hms_org_level_3_id,hms_org_level_3_name,hms_org_level_2_id,dk_treekey)
SELECT v.dim_value, v.description, r.rel_value, dk.treekey    
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR3'
  AND r.rel_attr_id = 'XHR2'
  AND lower(dk.displaytext (+)) = lower(v.description)
  AND substr(dk.treekey,0,4) <> '3008'      
  AND length(dk.treekey) = 6
order by dim_value;
*/
/*
HR/OIG 270116: Endret innlesing av seksjoner/nivå 3 fra Agresso til å bare ta med endringene. Med dette beholder vi koblingene mot HMS Seksjon som vi tidligere måtte mappe 
               på nytt etter hver import/oppdatering
*/
  DELETE hms_org_level_3 
   WHERE hms_org_level_3_id NOT IN ( SELECT v.dim_value
                                         FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r
                                        WHERE v.client = r.client
                                          AND v.dim_value = r.att_value
                                          AND v.client = 'A1' 
                                          AND v.attribute_id = 'XHR3'
                                          AND r.rel_attr_id = 'XHR2')
     AND dk_treekey <> '300799';   -- HR/OIG 270116 Denne treekey er lagt til manuelt pga "Strategi" sitt manglende undernivå

MERGE INTO hms_org_level_3
USING ( SELECT v.dim_value, v.description, r.rel_value, dk.treekey    
           FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
          WHERE v.client = r.client
            AND v.dim_value = r.att_value
            AND v.client = 'A1' 
            AND v.attribute_id = 'XHR3'
            AND r.rel_attr_id = 'XHR2'
            AND lower(dk.displaytext (+)) = lower(v.description)
            --AND substr(dk.treekey,0,4) <> '3008'      
            AND length(dk.treekey) = 6 ) src
   ON (hms_org_level_3.hms_org_level_3_id = src.dim_value)
   WHEN MATCHED THEN
     UPDATE SET hms_org_level_3_name = src.description,  hms_org_level_2_id = src.rel_value, dk_treekey = src.treekey
   WHEN NOT MATCHED THEN
     INSERT ( hms_org_level_3_id, hms_org_level_3_name, hms_org_level_2_id, dk_treekey)
     VALUES ( src.dim_value,      src.description,      src.rel_value,      src.treekey);
     


/*SELECT v.dim_value, v.description, r.rel_value  
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r 
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR3'
  AND r.rel_attr_id = 'XHR2'
order by dim_value;
*/


/*
EXECUTE IMMEDIATE('TRUNCATE TABLE hms_org_level_4');
INSERT INTO hms_org_level_4 (hms_org_level_4_id,hms_org_level_4_name,hms_org_level_3_id,dk_treekey)
SELECT v.dim_value, v.description, r.rel_value, dk.treekey     
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk  
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR4'
  AND r.rel_attr_id = 'XHR3'
  AND lower(dk.displaytext (+)) = lower(v.description)
  AND substr(dk.treekey,0,4) <> '3008'  
  AND length(dk.treekey) = 8
ORDER BY dim_value;

*/
DELETE hms_org_level_4
 WHERE hms_org_level_4_id NOT IN ( SELECT v.dim_value
                                         FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r
                                        WHERE v.client = r.client
                                          AND v.dim_value = r.att_value
                                          AND v.client = 'A1' 
                                          AND v.attribute_id = 'XHR4'
                                          AND r.rel_attr_id = 'XHR3');

MERGE INTO hms_org_level_4
USING ( SELECT v.dim_value, v.description, r.rel_value, dk.treekey    
           FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
          WHERE v.client = r.client
            AND v.dim_value = r.att_value
            AND v.client = 'A1' 
            AND v.attribute_id = 'XHR4'
            AND r.rel_attr_id = 'XHR3'
            AND lower(dk.displaytext (+)) = lower(v.description)
            --AND substr(dk.treekey,0,4) <> '3008'      
            AND length(dk.treekey) = 8 ) src
   ON (hms_org_level_4.hms_org_level_4_id = src.dim_value)
   WHEN MATCHED THEN
     UPDATE SET hms_org_level_4_name = src.description
   WHEN NOT MATCHED THEN
     INSERT ( hms_org_level_4_id, hms_org_level_4_name, hms_org_level_3_id, dk_treekey)
     VALUES ( src.dim_value,      src.description,      src.rel_value,      src.treekey);


/*
EXECUTE IMMEDIATE('TRUNCATE TABLE hms_org_level_5');
INSERT INTO hms_org_level_5 (hms_org_level_5_id,hms_org_level_5_name,hms_org_level_4_id,dk_treekey)
SELECT v.dim_value, v.description, r.rel_value, dk.treekey   
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk  
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR5'
  AND r.rel_attr_id = 'XHR4'
  AND lower(dk.displaytext (+)) = lower(v.description)
  AND substr(dk.treekey,0,4) <> '3008'      
  AND length(dk.treekey) = 10
ORDER BY dim_value;
*/
DELETE hms_org_level_5
 WHERE hms_org_level_5_id NOT IN ( SELECT v.dim_value
                                         FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r
                                        WHERE v.client = r.client
                                          AND v.dim_value = r.att_value
                                          AND v.client = 'A1' 
                                          AND v.attribute_id = 'XHR5'
                                          AND r.rel_attr_id = 'XHR4');

MERGE INTO hms_org_level_5
USING ( SELECT v.dim_value, v.description, r.rel_value, dk.treekey    
           FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
          WHERE v.client = r.client
            AND v.dim_value = r.att_value
            AND v.client = 'A1' 
            AND v.attribute_id = 'XHR5'
            AND r.rel_attr_id = 'XHR4'
            AND lower(dk.displaytext (+)) = lower(v.description)
            --AND substr(dk.treekey,0,4) <> '3008'      
            AND length(dk.treekey) = 10 ) src
   ON (hms_org_level_5.hms_org_level_5_id = src.dim_value)
   WHEN MATCHED THEN
     UPDATE SET hms_org_level_5_name = src.description
   WHEN NOT MATCHED THEN
     INSERT ( hms_org_level_5_id, hms_org_level_5_name, hms_org_level_4_id, dk_treekey)
     VALUES ( src.dim_value,      src.description,      src.rel_value,      src.treekey);


/*
EXECUTE IMMEDIATE('TRUNCATE TABLE hms_org_level_6');
INSERT INTO hms_org_level_6 (hms_org_level_6_id,hms_org_level_6_name,hms_org_level_5_id,dk_treekey)
SELECT v.dim_value, v.description, r.rel_value, dk.treekey   
FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk  
WHERE v.client = r.client
  AND v.dim_value = r.att_value
  AND v.client = 'A1' 
  AND v.attribute_id = 'XHR6'
  AND r.rel_attr_id = 'XHR5'
  AND lower(dk.displaytext (+)) = lower(v.description)
  AND substr(dk.treekey,0,4) <> '3008'      
  AND length(dk.treekey) = 12
ORDER BY dim_value;
*/
DELETE hms_org_level_6
 WHERE hms_org_level_6_id NOT IN ( SELECT v.dim_value
                                         FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r
                                        WHERE v.client = r.client
                                          AND v.dim_value = r.att_value
                                          AND v.client = 'A1' 
                                          AND v.attribute_id = 'XHR6'
                                          AND r.rel_attr_id = 'XHR5');

MERGE INTO hms_org_level_6
USING ( SELECT v.dim_value, v.description, r.rel_value, dk.treekey    
           FROM g_agrles.mv_agldimvalue v, g_agrles.mv_aglrelvalue r, g_dkles.dk_vorgnode_external dk 
          WHERE v.client = r.client
            AND v.dim_value = r.att_value
            AND v.client = 'A1' 
            AND v.attribute_id = 'XHR6'
            AND r.rel_attr_id = 'XHR5'
            AND lower(dk.displaytext (+)) = lower(v.description)
            --AND substr(dk.treekey,0,4) <> '3008'      
            AND length(dk.treekey) = 12 ) src
   ON (hms_org_level_6.hms_org_level_6_id = src.dim_value)
   WHEN MATCHED THEN
     UPDATE SET hms_org_level_6_name = src.description
   WHEN NOT MATCHED THEN
     INSERT ( hms_org_level_6_id, hms_org_level_6_name, hms_org_level_5_id, dk_treekey)
     VALUES ( src.dim_value,      src.description,      src.rel_value,      src.treekey);


COMMIT;

UPDATE person SET hms_org_level_6_id = (SELECT rel_value 
                                          FROM g_agrles.mv_ahsrelvalue 
                                         WHERE client = 'A1' 
                                           AND resource_id = person.resource_id
                                           AND rel_attr_id = 'XHR6'
                                           AND status = 'N'
                                           AND date_to >= SYSDATE
                                           AND date_from <= SYSDATE
                                           AND rownum < 2);
/*
UPDATE hms_org_level_1 SET DK_TREEKEY = (SELECT treekey FROM g_dkles.dk_vorgnode_external      WHERE trim(lower(displaytext)) = trim(lower(hms_org_level_1.hms_org_level_1_name)) AND LENGTH(treekey) = 2);
UPDATE hms_org_level_2 SET DK_TREEKEY = (SELECT treekey FROM g_dkles.dk_vorgnode_external      WHERE trim(lower(displaytext)) = trim(lower(hms_org_level_2.hms_org_level_2_name)) AND LENGTH(treekey) = 4);
UPDATE hms_org_level_3 SET DK_TREEKEY = (SELECT MIN(treekey) FROM g_dkles.dk_vorgnode_external WHERE trim(lower(displaytext)) = trim(lower(hms_org_level_3.hms_org_level_3_name)) AND LENGTH(treekey) = 6);
UPDATE hms_org_level_4 SET DK_TREEKEY = (SELECT treekey FROM g_dkles.dk_vorgnode_external      WHERE trim(lower(displaytext)) = trim(lower(hms_org_level_4.hms_org_level_4_name)) AND LENGTH(treekey) = 8);
UPDATE hms_org_level_5 SET DK_TREEKEY = (SELECT MIN(treekey) FROM g_dkles.dk_vorgnode_external WHERE trim(lower(displaytext)) = trim(lower(hms_org_level_5.hms_org_level_5_name)) AND LENGTH(treekey) = 10);
*/

COMMIT;

END UpdateHMSOrgStructure;

PROCEDURE UpdateDiscrepancy (i_jobbID varchar2 default '') IS

  bkup_tbl_exists NUMBER(11,0);
  
  l_strDKCompanyID VARCHAR(500);
  l_lstDKCompanyID VARCHAR(500);
  l_iNoOfIDs pls_integer;
  
  /*
  OIG 29.01.16 Husk å oppdatere/kontrollere SelskapsId (Treekey) registert for hvert selskap i formen "Organisasjon - Selskaper (tilknyttede systemer)
  
  SELECT abs_company_id from COMPANY:
  */
  CURSOR l_curCompanies IS 
      SELECT abs_company_id FROM company WHERE abs_company_id IS NOT NULL ORDER BY length(abs_company_id) desc; --SELECT abs_company_id FROM company WHERE abs_company_id IS NOT NULL;
  l_arrIds  dbms_utility.uncl_array;
  l_comma_index  pls_integer;
  l_strParam     varchar2(200);
  l_index        pls_integer := 1;
 
  
BEGIN
  -- Setter Startid
  SELECT sysdate INTO g_dtStartTime from dual;
  
  -- Skriver logg
  g_bResult := false;
  g_strText := 'START: UpdateDiscrepancy';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 0, i_jobbID);
  
  /* Laster status for avvik (fkLifecycle = 5)
  pkLifecycle	DisplayName
  1	          Internt tilsyn
  2	          Funn
  3	          Tiltak
  4	          Risikoanalyser
  5	          Avvik/UÃ˜ 
  */
  
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_status');
  INSERT INTO discrepancy_status (discrepancy_status_id,discrepancy_status_name)
    SELECT pkLifecyclePhase, l.DisplayText FROM g_dkles.dk_lifecyclephase_external
      INNER JOIN  g_dkles.dk_lang_external l ON pkLang = fkLang_displayText_During
    WHERE fkLifecycle = 5;
    
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_class');
  INSERT INTO discrepancy_class (discrepancy_class_id,discrepancy_class_name,discrepancy_class_enabled)
    SELECT pkObjectClass, l.DisplayText, enabled FROM g_dkles.dk_objectclass_external
      INNER JOIN  g_dkles.dk_lang_external l ON pkLang = fkLang_displayText;
  
  INSERT INTO discrepancy_class (discrepancy_class_id,discrepancy_class_name,discrepancy_class_enabled) VALUES  (-1,'- Ikke valgt -',-1);
  
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_type');
  INSERT INTO discrepancy_type (discrepancy_type_id,discrepancy_class_id, discrepancy_type_name)
    SELECT pkObjectType, fkObjectClass, l.DisplayText FROM g_dkles.dk_objecttype_external 
      INNER JOIN  g_dkles.dk_lang_external l ON pkLang = fkLang_displayText;
  
  INSERT INTO discrepancy_type (discrepancy_type_id,discrepancy_class_id, discrepancy_type_name) VALUES  (-1,-1, '- Ikke valgt -');  
  /*
  Meldingskategori
  */
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_msg_category');
  INSERT INTO discrepancy_msg_category ( discrepancy_msg_category_id, discrepancy_msg_category_name)
  SELECT pkSelectionListLeaf LeafId,lang.DisplayText 
    FROM g_dkles.dk_SelectionListVar_external 
    INNER JOIN g_dkles.dk_SelectionList_external     ON dk_SelectionListVar_external.fkSelectionList = pkSelectionList
    INNER JOIN g_dkles.dk_SelectionListLeaf_external ON dk_SelectionListLeaf_external.fkSelectionList=pkSelectionList
    INNER JOIN g_dkles.dk_Lang_external lang         ON fkLang_Display=lang.pkLang
     WHERE pkSelectionListVariant = (SELECT fkSelectionListVariant FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 140);
     
  INSERT INTO discrepancy_msg_category (discrepancy_msg_category_id, discrepancy_msg_category_name) VALUES  (-1,'- Ikke valgt -');
  
  /* Forhold */
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_subcat');
  INSERT INTO discrepancy_subcat (discrepancy_subcat_id, discrepancy_subcat_name)
  SELECT pkSelectionListLeaf LeafId,lang.DisplayText 
    FROM g_dkles.dk_SelectionListVar_external 
    INNER JOIN g_dkles.dk_SelectionList_external     ON dk_SelectionListVar_external.fkSelectionList = pkSelectionList
    INNER JOIN g_dkles.dk_SelectionListLeaf_external ON dk_SelectionListLeaf_external.fkSelectionList=pkSelectionList
    INNER JOIN g_dkles.dk_Lang_external lang         ON fkLang_Display=lang.pkLang
     WHERE pkSelectionListVariant = (SELECT fkSelectionListVariant FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 141);
     
  INSERT INTO discrepancy_subcat (discrepancy_subcat_id, discrepancy_subcat_name) VALUES  (-1,'- Ikke valgt -');

  /* Skade/Skadetype */
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_injury');
  INSERT INTO discrepancy_injury (discrepancy_injury_id, discrepancy_injury_name)
  SELECT pkSelectionListLeaf LeafId,lang.DisplayText 
    FROM g_dkles.dk_SelectionListVar_external 
    INNER JOIN g_dkles.dk_SelectionList_external     ON dk_SelectionListVar_external.fkSelectionList = pkSelectionList
    INNER JOIN g_dkles.dk_SelectionListLeaf_external ON dk_SelectionListLeaf_external.fkSelectionList=pkSelectionList
    INNER JOIN g_dkles.dk_Lang_external lang         ON fkLang_Display=lang.pkLang
     WHERE pkSelectionListVariant = (SELECT fkSelectionListVariant FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 142);
     
  INSERT INTO discrepancy_injury (discrepancy_injury_id, discrepancy_injury_name) VALUES  (-1,'- Ikke valgt -');


  /* Hendelsen gjelder */
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_event_applies_to');
  INSERT INTO discrepancy_event_applies_to (disc_event_applies_to_id, disc_event_applies_to_name)
  SELECT pkSelectionListLeaf LeafId,lang.DisplayText 
    FROM g_dkles.dk_SelectionListVar_external 
    INNER JOIN g_dkles.dk_SelectionList_external     ON dk_SelectionListVar_external.fkSelectionList = pkSelectionList
    INNER JOIN g_dkles.dk_SelectionListLeaf_external ON dk_SelectionListLeaf_external.fkSelectionList=pkSelectionList
    INNER JOIN g_dkles.dk_Lang_external lang         ON fkLang_Display=lang.pkLang
     WHERE pkSelectionListVariant = (SELECT fkSelectionListVariant FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 165);
     
  INSERT INTO discrepancy_event_applies_to (disc_event_applies_to_id, disc_event_applies_to_name) VALUES  (-1,'- Ikke valgt -');

  /* Skjema */
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy_form');
  INSERT INTO discrepancy_form (discrepancy_form_id, discrepancy_form_name)
  	SELECT pkForm, 
	         NVL(TO_CHAR((SELECT DisplayText FROM g_dkles.dk_lang_external WHERE LangDef=0 AND pklang=fkLang_Name)),'') DisplayValue
                        FROM g_dkles.dk_form_external
                        WHERE fkObjectType in
                        (	
	                        SELECT pkObjectType
	                        FROM g_dkles.dk_ObjectType_external	
	                        WHERE fkObjectClass = (SELECT fkObjectClass FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 155));
   
  INSERT INTO discrepancy_form (discrepancy_form_id, discrepancy_form_name) VALUES  (-1,'- Ikke valgt -');
  
  -- Forbedringsforslag gjennomført 
  EXECUTE IMMEDIATE('TRUNCATE TABLE disc_improvement_executed');
  INSERT INTO disc_improvement_executed (disc_improvement_executed_id, disc_improvement_executed_name) VALUES (0, 'Nei');
  INSERT INTO disc_improvement_executed (disc_improvement_executed_id, disc_improvement_executed_name) VALUES (1, 'Ja');
  INSERT INTO disc_improvement_executed (disc_improvement_executed_id, disc_improvement_executed_name) VALUES (-1,'- Ikke valgt -');
  
  g_strText := 'UpdateDiscrepancy: Loading discrepancies';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 5, i_jobbID );
       
  EXECUTE IMMEDIATE('TRUNCATE TABLE discrepancy');
  insert into discrepancy (discrepancy_id,discrepancy_refno,discrepancy_name,company_id,dk_company_treekey,discrepancy_type_id,discrepancy_msg_category_id,
                           discrepancy_status_id,date_reported,date_due, date_occurred, discrepancy_object_type, discrepancy_subcat_id,discrepancy_injury_id,discrepancy_form_id,
                           disc_event_applies_to_id,discrepancy_reported_by,dk_reported_by_treekey,disc_improvement_executed_id,date_closing)
    SELECT 
       pkObject
      ,RefNo
      ,Title
      ,NVL(pkFieldDef_27,-1)  -- Plassering (company_id) Denne endres siden til å benytte standard selskapsregister
      ,NVL(pkFieldDef_27,-1)  -- Plassering
      ,NVL(pkFieldDef_155,-1) -- Type
      ,NVL(pkFieldDef_140,-1) -- Meldingskategori
      ,NVL(pkFieldDef_148,-1) -- Status
      ,pkFieldDef_29          -- Dato registert
      ,pkfielddef_156         -- Frist
      ,pkfielddef_14          -- Hendelse oppstått
      ,NVL(pkFieldDef_24,-1)  -- Objekttype
      ,NVL(pkFieldDef_141,-1) -- Forhold (Subkategory)
      ,NVL(pkFieldDef_142,-1) -- FSkade/Skagetype
      ,NVL(pkFieldDef_155,-1) -- Skjema
      ,NVL(pkFieldDef_165,-1) -- Hendelsen gjelder disc_event_applies_to_id
      ,NVL(pkFieldDef_196,-1) -- Meldt fra 
      ,NVL(pkFieldDef_196,-1) -- Meldt fra TREEKEY
      ,NVL(pkFieldDef_181,-1) -- Forbedringsforslag gjennomført 
      ,pkfielddef_251         -- Lukkefrist (Lagt til 23.11.2015 på forespørsel fra HMS)
   FROM G_DKLES.DK_AVVIK_External
   ORDER BY pkObject;


  g_strText := 'UpdateDiscrepancy: Connecting discrepancies to company_id';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 5, i_jobbID );

  COMMIT;
  
  --Flytter det som ligger på Strategi ned ett nivå
  update discrepancy set DK_COMPANY_TREEKEY = 300999 where dk_company_treekey = 3009;
  
  
  -- Connecting company_id      
  OPEN l_curCompanies;
  FETCH l_curCompanies INTO l_strDKCompanyID;
  WHILE l_curCompanies%FOUND LOOP
    l_index := 1;
    l_lstDKCompanyID := l_strDKCompanyID || ',';   
     LOOP
     l_comma_index := INSTR(l_lstDKCompanyID, ',', l_index);
       EXIT
     WHEN l_comma_index = 0;
       l_strParam   := SUBSTR(l_lstDKCompanyID, l_index, l_comma_index - l_index);
       l_index      := l_comma_index + 1;
       
       UPDATE DISCREPANCY t1  SET company_id = (SELECT company_id FROM company WHERE abs_company_id = l_strDKCompanyID )
        WHERE SUBSTR(t1.dk_company_treekey,1,LENGTH(l_strParam)) = l_strParam;
       
       UPDATE DISCREPANCY t1  SET company_id_reported_by = (SELECT company_id FROM company WHERE abs_company_id = l_strDKCompanyID )
        WHERE SUBSTR(t1.dk_reported_by_treekey,1,LENGTH(l_strParam)) = l_strParam;
       
     END LOOP;
  
  FETCH l_curCompanies INTO l_strDKCompanyID;
  END LOOP;
  CLOSE l_curCompanies;

  UPDATE DISCREPANCY t1  SET company_id_reported_by = company_id  WHERE dk_reported_by_treekey = -1;

  UPDATE DISCREPANCY t1  SET dk_reported_by_treekey = dk_company_treekey  WHERE dk_reported_by_treekey = -1;



/* BACKUP 02.12.2015
  -- Oppdaterer selskap for avvikene, tilpasset ny struktur i DK 30.06.2015.
  -- SE Strategi , Kommunikasjon, Industrielt eierskap
  UPDATE DISCREPANCY t1
  SET company_id = 'SE' 
  WHERE t1.company_id like '3002';
  
 
 -- Kommunikasjon
  UPDATE DISCREPANCY t1
  SET company_id = 'SE' 
  WHERE t1.company_id like '300201%';
  
  -- Strategi
  UPDATE DISCREPANCY t1
  SET company_id = 'SE' 
  WHERE t1.company_id like '300206%';
  
  -- Selskapene som ligger under 3002 (Varme, Elektro, Naturgass og Fjernvarme)
  UPDATE DISCREPANCY t1
  SET company_id = (SELECT company_id
                         FROM  company t2
                         WHERE substr(t1.company_id,1,6) = t2.abs_company_id)
  WHERE substr(t1.company_id,3,2)= '02'
  AND company_id <> 'SE' ;
   
   -- Resten av selskapene (ligger ikke under 3002)
   UPDATE DISCREPANCY t1
   SET company_id = (SELECT company_id
                         FROM  company t2
                         WHERE nvl(DECODE(substr(t1.company_id,3,2),'03','01','02','01',substr(t1.company_id,3,2)),'01') = t2.abs_company_id)
	 WHERE EXISTS (
	    SELECT 1
	      FROM company t2
	      WHERE nvl(DECODE(substr(t1.company_id,3,2),'03','01','02','01',substr(t1.company_id,3,2)),'01')= t2.ABS_COMPANY_ID )
        AND substr(t1.company_id,3,2) <> '02';
*/
  -- OIG 04082015 For å håndtere manglende informasjon på seksjonsnivå (nivå 3 treekey = 6 siffer)
  -- UPDATE DISCREPANCY 
  -- SET dk_company_treekey = '300599'
 ---  WHERE company_id = 'SN'
--AND dk_company_treekey = '3005';
   
        
/* BACKUP Sommer 2015
  UPDATE DISCREPANCY t1
   SET company_id = (SELECT company_id
                         FROM  company t2
                         WHERE nvl(DECODE(substr(t1.company_id,3,2),'03','01','02','01',substr(t1.company_id,3,2)),'01') = t2.abs_company_id)
	 WHERE EXISTS (
	    SELECT 1
	      FROM company t2
	      WHERE nvl(DECODE(substr(t1.company_id,3,2),'03','01','02','01',substr(t1.company_id,3,2)),'01')= t2.ABS_COMPANY_ID );
*/

/* BACKUP GAMMELT
  UPDATE DISCREPANCY t1
   SET company_id_reported_by = (SELECT company_id
                         FROM  company t2
                        WHERE nvl(DECODE(substr(t2.discrepancy_reported_by,3,2),'03','01','02','01',substr(t2.company_id,3,2)),'01') = t2.abs_company_id)
	 WHERE EXISTS (
	    SELECT 1
	      FROM company t2
	     WHERE nvl(DECODE(substr(t2.discrepancy_reported_by,3,2),'03','01','02','01',substr(t2.company_id,3,2)),'01')= t2.ABS_COMPANY_ID );
*/

  g_strText := 'UpdateDiscrepancy: Connecting discrepancies to reported_by companies';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 5, i_jobbID );

-- Resten av selskapene (ligger ikke under 3002)
-- Bruker plassering dersom meldt fra er tom.
  
  /*
  UPDATE discrepancy dis
    SET dis.company_id_reported_by = DECODE(
                                            nvl(substr(dis.discrepancy_reported_by,3,2),0),
                                            '0',
                                            dis.dk_company_treekey,
                                            dis.discrepancy_reported_by
                                            );
                                            
/*
 UPDATE discrepancy dis
    SET dis.company_id_reported_by = nvl(dis.discrepancy_reported_by,dis.dk_company_treekey);
 
 
  UPDATE DISCREPANCY dis
  SET company_id_reported_by = 'SE' 
  WHERE dis.company_id_reported_by like '3002';
 

  UPDATE DISCREPANCY dis
  SET company_id_reported_by = 'SE' 
  WHERE dis.company_id_reported_by like '300201%';
  

  UPDATE DISCREPANCY dis
  SET company_id_reported_by = 'SE' 
  WHERE dis.company_id_reported_by like '300206%'; 
  

  UPDATE DISCREPANCY dis
  SET company_id_reported_by = (SELECT company_id
                                FROM  company t2
                                WHERE substr(dis.company_id_reported_by,1,6) = t2.abs_company_id)
  WHERE substr(dis.company_id_reported_by,3,2)= '02'
  AND company_id_reported_by <> 'SE';
  
  -- Bruk "dk_company_treekey" hvis "discrepancy_reported_by" er null
  UPDATE discrepancy dis
     SET dis.company_id_reported_by = ( SELECT c.company_id
                                          FROM  company c
                                         WHERE  decode(
                                                        substr(dis.dk_company_treekey,3,2),
                                                        '03',
                                                        '01',
                                                        '02',
                                                        '01',
                                                        substr(dis.dk_company_treekey,3,2)
                                                        )
                                                   = c.abs_company_id)
    WHERE substr(dis.dk_company_treekey,3,2) <> '02'
    AND substr(dis.discrepancy_reported_by,3,2) is null;
    
    -- Ellers benyttes "discrepancy_reported_by"
     UPDATE discrepancy dis
     SET dis.company_id_reported_by = ( SELECT c.company_id
                                          FROM  company c
                                         WHERE  decode(
                                                        substr(dis.discrepancy_reported_by,3,2),
                                                        '03',
                                                        '01',
                                                        '02',
                                                        '01',
                                                        substr(dis.discrepancy_reported_by,3,2)
                                                        )   
                                                   = c.abs_company_id)
    WHERE substr(dis.discrepancy_reported_by,3,2) <> '02';
  
    */
    
 /*BACKUP
  UPDATE discrepancy dis
     SET dis.company_id_reported_by = ( select c.company_id
                                       from  company c
                                      where nvl(decode(substr(dis.discrepancy_reported_by,3,2),'03','01','02','01',substr(dis.discrepancy_reported_by,3,2)),
                                                                           
                                      decode(substr(dis.dk_company_treekey,3,2),'03','01','02','01',substr(dis.dk_company_treekey,3,2))) = c.abs_company_id);
 */
 
 UPDATE discrepancy set company_id_reported_by = 'SE' 
 WHERE company_id = 'SE' 
 AND company_id_reported_by is null;

  COMMIT;


-- Oppdaterer seksjonsinformasjon for Meldt fra
 -------------------------------- Nivå 1 ------------------------------------
  UPDATE discrepancy 
  SET hms_reported_by_org_level_1_id = ( SELECT MIN(hms_org_level_1_id)  
                                                FROM hms_org_level_1 
                                               WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,2));
                                                       
 -------------------------------- Nivå 2 ------------------------------------                                                            
  UPDATE discrepancy 
  SET hms_reported_by_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                               FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,4));
   -- Krysskobling av Elektro, Varme, Naturgass og Fjernvarme                                                               
  /*
  --Elektro
  UPDATE discrepancy 
  SET hms_reported_by_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                               FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,6)
                                        )
  WHERE discrepancy.dk_reported_by_treekey like '300202%';  
  */
  --Naturgass
  UPDATE discrepancy 
  SET hms_reported_by_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                          FROM hms_org_level_2 
                                          WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,6)
                                         )
  WHERE discrepancy.dk_reported_by_treekey like '300101%';                                                            
  -- Varme                                                          
  UPDATE discrepancy 
  SET hms_reported_by_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                              FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,6)
                                             )
  WHERE discrepancy.dk_reported_by_treekey like '300102%';                                                            
  --Fjernvarme                                                          
  UPDATE discrepancy 
  SET hms_reported_by_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                              FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,6)
                                            )
  WHERE discrepancy.dk_reported_by_treekey like '300103%';


 -------------------------------- Nivå 3 ------------------------------------
  --Hovedkobling
  UPDATE discrepancy 
  SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                               FROM hms_org_level_3 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,6)
                                              );
   -- Krysskobling av Elektro, Varme, Naturgass og Fjernvarme                                                                                                                
  /*
  UPDATE discrepancy 
  SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,8)
                                          )
  WHERE discrepancy.dk_reported_by_treekey like '300202%';  
  */
  
  UPDATE discrepancy 
  SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,8)
                                            )
  WHERE discrepancy.dk_reported_by_treekey like '300101%';  
                                                            
  UPDATE discrepancy 
  SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,8)
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '300102%';                                              
                                                            
  UPDATE discrepancy 
  SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,8)
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '300103%';
  
  
  
  
 -------------------------------- Nivå 4 ------------------------------------
 --Hovedkobling
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
  
                                               WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,8));
  -- Krysskobling av Elektro, Varme, Naturgass og Fjernvarme 
  /*
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,10)
                                          )
  WHERE discrepancy.dk_reported_by_treekey like '300202%';                                                              
  */
  
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,10)
                                            )
  WHERE discrepancy.dk_reported_by_treekey like '300101%';  
                                                            
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,10)
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '300102%';                                              
                                                            
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,10)
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '300103%';

/*
OIG 030815 Denne endringen/fixen utgår da de ønsker å rapportere på ny struktur fom juli 2015

  -- KRAFT: Krysskobling av Numedal - utgår
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = '30040202'
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '30040203%';
  
  -- KRAFT: Krysskobling av Nord til Øst
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = '30040206'
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '30040204%';
  
  -- KRAFT: Krysskobling av Tinnelva til Øst
  UPDATE discrepancy 
  SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = '30040206'
                                              )
  WHERE discrepancy.dk_reported_by_treekey like '30040207%';
  
 */ 
 -------------------------------- Nivå 5 ------------------------------------
   --Hovedkobling
  UPDATE discrepancy 
  SET hms_reported_by_org_level_5_id = ( SELECT MIN(hms_org_level_5_id)  
                                              FROM hms_org_level_5 
                                              WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,10)
                                          );
 

  g_strText := 'UpdateDiscrepancy: Setting discrepancy placement';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 5, i_jobbID );
  
  
  -- Oppdaterer seksjonsinformasjon for Selskap/Plassering
 -------------------------------- Nivå 1 ------------------------------------
  UPDATE discrepancy 
  SET hms_company_org_level_1_id = ( SELECT MIN(hms_org_level_1_id)  
                                          FROM hms_org_level_1 
                                          WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,2)
                                        );
                                          
 -------------------------------- Nivå 2  ------------------------------------
  --Hovedkobling
  UPDATE discrepancy 
  SET hms_company_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)  
                                          FROM hms_org_level_2 
                                          WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,4)
                                      );
  
  -- Krysskobling av Elektro, Varme, Naturgass og Fjernvarme
  /*
  UPDATE discrepancy 
  SET hms_company_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                               FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,6)
                                        )
  WHERE discrepancy.dk_company_treekey like '300202%';  
  */
  
  UPDATE discrepancy 
  SET hms_company_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                          FROM hms_org_level_2 
                                          WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,6)
                                         )
  WHERE discrepancy.dk_company_treekey like '300101%';                                                            
                                                            
  UPDATE discrepancy 
  SET hms_company_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                              FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,6)
                                             )
  WHERE discrepancy.dk_company_treekey like '300102%';                                                            
                                                            
  UPDATE discrepancy 
  SET hms_company_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)
                                              FROM hms_org_level_2 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,6)
                                            )
  WHERE discrepancy.dk_company_treekey like '300103%';
 
 -------------------------------- Nivå 3 ------------------------------------
  --Hovedkobling
  UPDATE discrepancy 
  SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                          FROM hms_org_level_3 
                                          WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,6));
   -- Krysskobling av Elektro, Varme, Naturgass og Fjernvarme
  /*
  UPDATE discrepancy 
  SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,8)
                                          )
  WHERE discrepancy.dk_company_treekey like '300202%';  
  */
  
  UPDATE discrepancy 
  SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,8)
                                            )
  WHERE discrepancy.dk_company_treekey like '300101%';  
                                                            
  UPDATE discrepancy 
  SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,8)
                                              )
  WHERE discrepancy.dk_company_treekey like '300102%';                                              
                                                            
  UPDATE discrepancy 
  SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  
                                              FROM hms_org_level_3
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,8)
                                              )
  WHERE discrepancy.dk_company_treekey like '300103%';
  
 -------------------------------- Nivå 4 ------------------------------------
  --Hovedkobling
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                          FROM hms_org_level_4 
                                          WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,8));
   -- Krysskobling av Elektro, Varme, Naturgass og Fjernvarme
  /*
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,10)
                                          )
  WHERE discrepancy.dk_company_treekey like '300202%';  
  */
  
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,10)
                                            )
  WHERE discrepancy.dk_company_treekey like '300101%';  
                                                            
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,10)
                                              )
  WHERE discrepancy.dk_company_treekey like '300102%';                                              
                                                            
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,10)
                                              )
  WHERE discrepancy.dk_company_treekey like '300103%';
  
  
  /*
  OIG 030815 Denne endringen/fixen utgår da de ønsker å rapportere på ny struktur fom juli 2015
   -- Krysskobling av Numedal - utgår
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = '30040202'
                                              )
  WHERE discrepancy.dk_company_treekey = '30040203';

  -- KRAFT: Krysskobling av Nord til Øst
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = '30040206'
                                              )
  WHERE discrepancy.dk_company_treekey like '30040204%';
  
  -- KRAFT: Krysskobling av Tinnelva til Øst
  UPDATE discrepancy 
  SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  
                                               FROM hms_org_level_4 
                                              WHERE dk_treekey = '30040206'
                                              )
  WHERE discrepancy.dk_company_treekey like '30040207%';
  
*/
 -------------------------------- Nivå 5 ------------------------------------
  UPDATE discrepancy 
  SET hms_company_org_level_5_id = ( SELECT MIN(hms_org_level_5_id)  
                                          FROM hms_org_level_5 
                                          WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,10));
 
/* BACKUP
  -- Oppdaterer seksjonsinformasjon for Meldt fra
  UPDATE discrepancy SET hms_reported_by_org_level_1_id = ( SELECT MIN(hms_org_level_1_id)  FROM hms_org_level_1 WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,2));-- AND LENGTH(dk_treekey) = 2 )
  -- WHERE LENGTH(dk_treekey) = 2;
  UPDATE discrepancy SET hms_reported_by_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)  FROM hms_org_level_2 WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,4));-- AND LENGTH(dk_treekey) = 4 )
  -- WHERE LENGTH(dk_treekey) = 4;
  UPDATE discrepancy SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  FROM hms_org_level_3 WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,6));-- AND LENGTH(dk_treekey) = 6 )
  -- WHERE LENGTH(dk_treekey) = 6;
  UPDATE discrepancy SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  FROM hms_org_level_4 WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,8));-- AND LENGTH(dk_treekey) = 8 )
  -- WHERE LENGTH(dk_treekey) = 8;
  UPDATE discrepancy SET hms_reported_by_org_level_5_id = ( SELECT MIN(hms_org_level_5_id)  FROM hms_org_level_5 WHERE dk_treekey = substr(discrepancy.dk_reported_by_treekey,0,10));-- AND LENGTH(dk_treekey) = 10 )
  -- WHERE LENGTH(dk_treekey) = 10;

  -- Oppdaterer seksjonsinformasjon for Selskap/Plassering
  UPDATE discrepancy SET hms_company_org_level_1_id = ( SELECT MIN(hms_org_level_1_id)  FROM hms_org_level_1 WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,2));-- AND LENGTH(dk_treekey) = 2 )
  -- WHERE LENGTH(dk_treekey) = 2;
  UPDATE discrepancy SET hms_company_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)  FROM hms_org_level_2 WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,4));-- AND LENGTH(dk_treekey) = 4 )
  -- WHERE LENGTH(dk_treekey) = 4;
  UPDATE discrepancy SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  FROM hms_org_level_3 WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,6));-- AND LENGTH(dk_treekey) = 6 )
  -- WHERE LENGTH(dk_treekey) = 6;
  UPDATE discrepancy SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  FROM hms_org_level_4 WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,8));-- AND LENGTH(dk_treekey) = 8 )
  -- WHERE LENGTH(dk_treekey) = 8;
  UPDATE discrepancy SET hms_company_org_level_5_id = ( SELECT MIN(hms_org_level_5_id)  FROM hms_org_level_5 WHERE dk_treekey = substr(discrepancy.dk_company_treekey,0,10));-- AND LENGTH(dk_treekey) = 10 )
  -- WHERE LENGTH(dk_treekey) = 10;
*/
  /* For seksjonsrapportering   
  DENNE BØR ENDRES TIL NOE MER ROBUST OG BRA
  */  
  -- Lag en kopi av avvikstabellen
  SELECT count(*) INTO bkup_tbl_exists FROM USER_TABLES WHERE lower(table_name) = 'discrepancy_bkup';
  IF bkup_tbl_exists > 0 THEN EXECUTE IMMEDIATE ('DROP TABLE discrepancy_bkup'); END IF;
   EXECUTE IMMEDIATE ('CREATE TABLE discrepancy_bkup AS SELECT * FROM discrepancy');
 
 
  -- Kode for å tilegne avvik/FBF som er plassert/rapportert på selskaps-/seksjonsnivå en seksjon/avdeling.
  -- MOR (ny kode juli 2015) --
  -- AVK/FBF rapportert på selskapsnivå legges på seksjonen "Toppnivå"
  UPDATE discrepancy SET hms_company_org_level_3_id = '309999'
   WHERE hms_company_org_level_3_id IS NULL 
     AND company_id = 'SE'
     AND dk_company_treekey = '3001';
  
  UPDATE discrepancy SET hms_reported_by_org_level_3_id = '309999'
   WHERE hms_reported_by_org_level_3_id IS NULL 
     AND company_id_reported_by = 'SE'
     AND dk_reported_by_treekey = '3001';
 
  UPDATE discrepancy SET hms_company_org_level_3_id = '309999'
   WHERE hms_company_org_level_3_id IS NULL 
     AND company_id = 'SE'
     AND dk_company_treekey like '3002%';
  
  UPDATE discrepancy SET hms_reported_by_org_level_3_id = '309999'
   WHERE hms_reported_by_org_level_3_id IS NULL 
     AND company_id_reported_by = 'SE'
     AND dk_reported_by_treekey like '3002%';  
  
   UPDATE discrepancy SET hms_company_org_level_3_id = '309999'
   WHERE hms_company_org_level_3_id IS NULL 
     AND company_id = 'SE'
     AND dk_company_treekey like '3003%';
  
  UPDATE discrepancy SET hms_reported_by_org_level_3_id = '309999'
   WHERE hms_reported_by_org_level_3_id IS NULL 
     AND company_id_reported_by = 'SE'
     AND dk_reported_by_treekey like '3003%';  
     
      UPDATE discrepancy SET hms_company_org_level_3_id = '309999'
   WHERE hms_company_org_level_3_id IS NULL 
     AND company_id = 'SE'
     AND dk_company_treekey like '3007%';
  
  UPDATE discrepancy SET hms_reported_by_org_level_3_id = '309999'
   WHERE hms_reported_by_org_level_3_id IS NULL 
     AND company_id_reported_by = 'SE'
     AND dk_reported_by_treekey like '3007%';  
     
  -- KRAFT --
  UPDATE discrepancy SET hms_company_org_level_3_id = ( SELECT MIN(hms_org_level_3_id) 
                                                                FROM hms_org_level_4 
                                                               WHERE hms_org_level_report_4_id = (SELECT hms_org_level_report_4_id 
                                                                                                     FROM hms_org_level_report_4 
                                                                                                    WHERE hms_org_level_report_name LIKE 'Hovedkontor/Felles' AND company_id = 'SK')
                                                            )
   WHERE hms_company_org_level_3_id IS NULL AND company_id = 'SK';
  
  UPDATE discrepancy SET hms_company_org_level_4_id = ( SELECT MIN(hms_org_level_4_id) 
                                                                FROM hms_org_level_4 
                                                               WHERE hms_org_level_report_4_id = (SELECT hms_org_level_report_4_id 
                                                                                                     FROM hms_org_level_report_4 
                                                                                                    WHERE hms_org_level_report_name LIKE 'Hovedkontor/Felles' AND company_id = 'SK')
                                                            )
   WHERE hms_company_org_level_4_id IS NULL AND company_id = 'SK'; 

  UPDATE discrepancy SET hms_reported_by_org_level_3_id = ( SELECT MIN(hms_org_level_3_id) 
                                                                FROM hms_org_level_4 
                                                               WHERE hms_org_level_report_4_id = (SELECT hms_org_level_report_4_id 
                                                                                                     FROM hms_org_level_report_4 
                                                                                                    WHERE hms_org_level_report_name LIKE 'Hovedkontor/Felles' AND company_id = 'SK')
                                                            )
   WHERE hms_reported_by_org_level_3_id IS NULL AND company_id_reported_by = 'SK';
  
  UPDATE discrepancy SET hms_reported_by_org_level_4_id = ( SELECT MIN(hms_org_level_4_id) 
                                                                FROM hms_org_level_4 
                                                               WHERE hms_org_level_report_4_id = (SELECT hms_org_level_report_4_id 
                                                                                                     FROM hms_org_level_report_4 
                                                                                                    WHERE hms_org_level_report_name LIKE 'Hovedkontor/Felles' AND company_id = 'SK')
                                                            )
   WHERE hms_reported_by_org_level_4_id IS NULL AND company_id_reported_by = 'SK';


  -- NETT --
  UPDATE discrepancy SET hms_company_org_level_3_id = ( SELECT hms_org_level_3_id
                                                                FROM hms_org_level_3
                                                               WHERE hms_org_level_report_id = ( SELECT hms_org_level_report_id 
                                                                                                    FROM hms_org_level_report_3 
                                                                                                   WHERE hms_org_level_report_name LIKE 'Administrasjon%' 
                                                                                                     AND company_id = 'SN')
                                                            )
  WHERE hms_company_org_level_3_id IS NULL AND company_id = 'SN'; 
  
  UPDATE discrepancy SET hms_reported_by_org_level_3_id = ( SELECT hms_org_level_3_id
                                                                FROM hms_org_level_3
                                                               WHERE hms_org_level_report_id = ( SELECT hms_org_level_report_id 
                                                                                                    FROM hms_org_level_report_3 
                                                                                                   WHERE hms_org_level_report_name LIKE 'Administrasjon%' 
                                                                                                     AND company_id = 'SN')
                                                            )
  WHERE hms_reported_by_org_level_3_id IS NULL AND company_id_reported_by = 'SN'; -- 10.07.2015 byttet ut company_id da dette la avvik fra SE på SN
  
/*
  UPDATE discrepancy SET hms_org_level_1_id = ( SELECT MIN(hms_org_level_1_id)  FROM hms_org_level_1 WHERE dk_treekey = substr(discrepancy.dk_treekey,0,2) AND LENGTH(dk_treekey) = 2 )
   WHERE LENGTH(dk_treekey) = 2;
  UPDATE discrepancy SET hms_org_level_2_id = ( SELECT MIN(hms_org_level_2_id)  FROM hms_org_level_2 WHERE dk_treekey = substr(discrepancy.dk_treekey,0,4) AND LENGTH(dk_treekey) = 4 )
   WHERE LENGTH(dk_treekey) = 4;
  UPDATE discrepancy SET hms_org_level_3_id = ( SELECT MIN(hms_org_level_3_id)  FROM hms_org_level_3 WHERE dk_treekey = substr(discrepancy.dk_treekey,0,6) AND LENGTH(dk_treekey) = 6 )
   WHERE LENGTH(dk_treekey) = 6;
  UPDATE discrepancy SET hms_org_level_4_id = ( SELECT MIN(hms_org_level_4_id)  FROM hms_org_level_4 WHERE dk_treekey = substr(discrepancy.dk_treekey,0,8) AND LENGTH(dk_treekey) = 8 )
   WHERE LENGTH(dk_treekey) = 8;
  UPDATE discrepancy SET hms_org_level_5_id = ( SELECT min(hms_org_level_5_id)  FROM hms_org_level_5 WHERE dk_treekey = substr(discrepancy.dk_treekey,0,10) AND LENGTH(dk_treekey) = 10 )
   WHERE LENGTH(dk_treekey) = 10;
*/

  g_strText := 'UpdateDiscrepancy: Loading ABS';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 5, i_jobbID );
  
    /*  ABS momentanalyse sikker/usikker */
    EXECUTE IMMEDIATE('TRUNCATE TABLE abs_element_analysis');
    INSERT INTO abs_element_analysis (abs_element_analysis_id, abs_element_analysis_name)
       SELECT pkSelectionListLeaf, DisplayText
          FROM g_dkles.dk_SelectionListVar_external 
          INNER JOIN g_dkles.dk_SelectionList_external     ON g_dkles.dk_SelectionListVar_external.fkSelectionList = pkSelectionList
          INNER JOIN g_dkles.dk_SelectionListLeaf_external ON g_dkles.dk_SelectionListLeaf_external.fkSelectionList    = pkSelectionList
          INNER JOIN g_dkles.dk_lang_external              ON g_dkles.dk_lang_external.pkLang = fkLang_Display
            WHERE pkSelectionListVariant = (SELECT  fkSelectionListVariant FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 68);   

    INSERT INTO abs_element_analysis (abs_element_analysis_id, abs_element_analysis_name) VALUES  (-1,'- Ikke valgt -');            
    
    /*  ABS momenter */
    EXECUTE IMMEDIATE('TRUNCATE TABLE abs_element');
    INSERT INTO abs_element (abs_element_id, abs_element_name)
       SELECT pkSelectionListLeaf, DisplayText
          FROM g_dkles.dk_SelectionListVar_external 
          INNER JOIN g_dkles.dk_SelectionList_external     ON g_dkles.dk_SelectionListVar_external.fkSelectionList = pkSelectionList
          INNER JOIN g_dkles.dk_SelectionListLeaf_external ON g_dkles.dk_SelectionListLeaf_external.fkSelectionList    = pkSelectionList
          INNER JOIN g_dkles.dk_lang_external              ON g_dkles.dk_lang_external.pkLang = fkLang_Display
            WHERE pkSelectionListVariant = (SELECT  fkSelectionListVariant FROM g_dkles.dk_FieldDef_external WHERE pkFieldDef = 66);    
    
    INSERT INTO abs_element (abs_element_id, abs_element_name) VALUES  (-1,'- Ikke valgt -');            
        
    EXECUTE IMMEDIATE('TRUNCATE TABLE abs');
    
    --Lager en kopi av den eksterne tabellen pga ytelse
    SELECT count(*) INTO bkup_tbl_exists FROM ALL_TABLES WHERE lower(table_name) = 'dk_abs_internal' AND lower(owner) = 'g_dkles';
    IF bkup_tbl_exists > 0 THEN EXECUTE IMMEDIATE ('DROP TABLE g_dkles.dk_abs_internal'); END IF;
    EXECUTE IMMEDIATE('CREATE TABLE g_dkles.dk_abs_internal as select * from g_dkles.dk_abs_external');
    
    --Lager en kopi av den eksterne tabellen pga ytelse
    SELECT count(*) INTO bkup_tbl_exists FROM ALL_TABLES WHERE lower(table_name) = 'dk_fieldvalue_internal' AND lower(owner) = 'g_dkles';
    IF bkup_tbl_exists > 0 THEN EXECUTE IMMEDIATE ('DROP TABLE g_dkles.dk_FieldValue_internal'); END IF;
    EXECUTE IMMEDIATE('CREATE TABLE g_dkles.dk_FieldValue_internal as select * from g_dkles.dk_FieldValue_external');


    INSERT INTO abs(absid,company_id,title,LOCATION,reported_date,abs_date,occured_date, changed_date,changed_by_person_id,
    responsible_person_id,abs_element_id,abs_element_analysis_id,abs_object_type_id,work_operation,refabsid)
         SELECT
         t1.pkObject
        ,NVL(t1.pkFieldDef_94,(SELECT sub.pkFieldDef_94 FROM g_dkles.dk_abs_internal sub WHERE sub.pkObject = t1.fkObject ))  -- Plassering OrgNode / Location
        ,t1.title
        ,NVL(t1.pkFieldDef_94,(SELECT sub.pkFieldDef_94 FROM g_dkles.dk_abs_internal sub WHERE sub.pkObject = t1.fkObject ))  -- Plassering OrgNode / Location
        ,t1.pkFieldDef_95          -- Dato opprettet
        ,NVL(t1.pkFieldDef_73, (SELECT sub.pkFieldDef_73 FROM g_dkles.dk_abs_internal sub WHERE sub.pkObject = t1.fkObject ))          -- Dato
        ,NVL(t1.pkFieldDef_73, (SELECT sub.pkFieldDef_73 FROM g_dkles.dk_abs_internal sub WHERE sub.pkObject = t1.fkObject ))          -- Dato
        ,NULL
        ,NULL
        ,NULL
        ,NVL(t1.pkFieldDef_66,(SELECT sub2.fkSelectionListLeaf FROM g_dkles.dk_FieldValue_internal sub2 WHERE sub2.fkFieldDef = 66 and sub2.fkObjectValue = t1.pkObject)) -- ABS Moment
        ,t1.pkFieldDef_68 -- ABS Sikker / Usikker
        ,t1.pkFieldDef_79 -- Objecttype
        ,t1.pkFieldDef_72 -- Arbeidsoperasjon
        ,t1.fkObject
      FROM g_dkles.dk_abs_internal t1;
    
    /*   
      ,[pkFieldDef_69] = ABS Beskrivelse
      ,[pkFieldDef_68] = ABS Sikker / Usikker
      ,[pkFieldDef_66] = ABS Moment
      ,[pkFieldDef_87] = Responsible
      ,[pkFieldDef_72] = Arbeidsoperasjon
      ,[pkFieldDef_73] = Dato
      ,[pkFieldDef_95] = Date Created
      ,[pkFieldDef_81] = Fylke
      ,[pkFieldDef_74] = Observator
      ,[pkFieldDef_94] = OrgNode / Location
      ,[pkFieldDef_80] = Form
      ,[pkFieldDef_70] = Status
      ,[pkFieldDef_71] = Sted
      ,[pkFieldDef_79] = Type
      ,[pkFieldDef_88] = VernFaktorer_Anmerkning
      ,[pkFieldDef_93] = VernFaktorer_TiltaksAnsv
      ,[pkFieldDef_90] = VernFaktorer_Vurdering
      ,[pkFieldDef_89] = VernFaktorer
      ,[pkFieldDef_92] = VernFaktorer_Kommentar
    
   */
   
  OPEN l_curCompanies;
  FETCH l_curCompanies INTO l_strDKCompanyID;
  WHILE l_curCompanies%FOUND LOOP
    l_index := 1;
    l_lstDKCompanyID := l_strDKCompanyID || ',';   
     LOOP
     l_comma_index := INSTR(l_lstDKCompanyID, ',', l_index);
       EXIT
     WHEN l_comma_index = 0;
       l_strParam   := SUBSTR(l_lstDKCompanyID, l_index, l_comma_index - l_index);
       l_index      := l_comma_index + 1;
       
       UPDATE ABS t1  SET company_id = (SELECT company_id FROM company WHERE abs_company_id = l_strDKCompanyID )
        WHERE SUBSTR(t1.location,1,LENGTH(l_strParam)) = l_strParam;
       
     END LOOP;
  
  FETCH l_curCompanies INTO l_strDKCompanyID;
  END LOOP;
  CLOSE l_curCompanies;
 
 /* Tar ikke med 3002
    -- Selskapene som ligger under 3001 (Varme, Naturgass og Fjernvarme)
  UPDATE abs t1
  SET company_id = (SELECT company_id
                         FROM  company t2
                         WHERE substr(t1.company_id,1,6) = t2.abs_company_id)
  WHERE substr(t1.company_id,1,4)= '3001'
  AND company_id <> 'SE' ;
  
   -- Resten av selskapene (ligger ikke under 3001)
    UPDATE abs t1
     SET company_id = (SELECT company_id
                         FROM  company t2
                        WHERE nvl(substr(t1.company_id,1,4),'01') = t2.ABS_COMPANY_ID)
	   WHERE EXISTS (
	     SELECT 1
	       FROM company t2
	       WHERE nvl(substr(t1.company_id,1,4),'01') = t2.ABS_COMPANY_ID )
          AND substr(t1.company_id,3,2) <> '01';
   
   */
  /* 
    -- SE Strategi , Kommunikasjon, Industrielt eierskap
  UPDATE abs t1
  SET company_id = 'SE' 
  WHERE t1.company_id like '3002';
 
 -- Kommunikasjon
  UPDATE abs t1
  SET company_id = 'SE' 
  WHERE t1.company_id like '300201%';
  
  -- Strategi
  UPDATE abs t1
  SET company_id = 'SE' 
  WHERE t1.company_id like '300206%';
  
  -- Selskapene som ligger under 3002 (Varme, Elektro, Naturgass og Fjernvarme)
  UPDATE abs t1
  SET company_id = (SELECT company_id
                         FROM  company t2
                         WHERE substr(t1.company_id,1,6) = t2.abs_company_id)
  WHERE substr(t1.company_id,3,2)= '02'
  AND company_id <> 'SE' ;
  
   -- Resten av selskapene (ligger ikke under 3002)
    UPDATE abs t1
     SET company_id = (SELECT company_id
                         FROM  company t2
                        WHERE nvl(substr(t1.company_id,3,2),'01') = t2.ABS_COMPANY_ID)
	   WHERE EXISTS (
	     SELECT 1
	       FROM company t2
	       WHERE nvl(substr(t1.company_id,3,2),'01') = t2.ABS_COMPANY_ID )
          AND substr(t1.company_id,3,2) <> '02';
  */
  
   /* BACKUP
    UPDATE abs t1
     SET company_id = (SELECT company_id
                         FROM  company t2
                        WHERE nvl(substr(t1.company_id,3,2),'01') = t2.ABS_COMPANY_ID)
	   WHERE EXISTS (
	     SELECT 1
	       FROM company t2
	       WHERE nvl(substr(t1.company_id,3,2),'01') = t2.ABS_COMPANY_ID );
         */
         

  /* OPPRINNELIG DATAFANGST UTVILKET AV MAGNUS SKAAR 
  EXECUTE IMMEDIATE ('TRUNCATE TABLE abs_report_point');
  INSERT INTO abs_report_point
    SELECT 
      ROWNUM, analysemoment
    FROM ( SELECT DISTINCT analysemoment from G_DKLES.v_abs ORDER BY 1);

  EXECUTE IMMEDIATE( 'TRUNCATE TABLE abs');
  INSERT INTO abs(
    ABSID,
    COMPANY_ID,
    TITLE,
    LOCATION,
    REPORTED_DATE,
    CHANGED_DATE,
    OCCURED_DATE,
    CHANGED_BY_PERSON_ID,
    RESPONSIBLE_PERSON_ID,
    ABS_REPORT_POINT_ID,
    SAFETY_LEVEL,
    WORK_OPERATION
    )
  SELECT 
    rownum,
    company_id,
    TITLE,
    PLASSERING,
    DATE_REPORTED,
    DATE_LASTCHANGED,
    DATE_OCCURED,
    endret_av,
    ansvarlig_person,
    moment,
    sikker,
    WORK_OPERATION
  FROM (
    SELECT 
      v_abs.TITLE,
      v_abs.PLASSERING,
      v_abs.DATE_REPORTED,
      v_abs.DATE_LASTCHANGED,
      v_abs.DATE_OCCURED,
--      NVL(v_abs.selskapid,'01') as company_id,
      selskap.company_id,
      ANSV.PERSON_ID ansvarlig_person,
      chg.PERSON_ID endret_av,
      decode(DISPLAYTEXT, 'Sikker', 1, 'Usikker', 2, 3) sikker,
      pkt.abs_report_pointid moment,
      v_abs.WORK_OPERATION
    FROM g_dkles.v_abs
    LEFT OUTER JOIN company selskap on (selskap.abs_company_id = nvl(v_abs.selskapid,'01'))
    LEFT OUTER JOIN person ansv ON upper(ansv.user_name) = upper(v_abs.USER_RESPONSIBLE)
    LEFT OUTER JOIN  person chg on upper(chg.user_name) = upper(v_abs.USER_LASTCHANGED)
    LEFT OUTER JOIN abs_report_point pkt ON pkt.abs_report_point_name = v_abs.ANALYSEMOMENT
    );
  */
  COMMIT;
  
  -- Setter sluttid
  SELECT sysdate INTO g_dtEndTime FROM dual;
  
  --Script for å finne tidsforbruk
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );
  
  -- Sluttlogg 
  g_strText := 'END: UpdateDiscrepancy - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateDiscrepancy', 0, i_jobbID );
  
END;

PROCEDURE DivideSickLeave (i_strToMonth VARCHAR, i_jobbID varchar2 default '') IS
  l_emp kapasitet_timer.employee_id%TYPE := -1;
  l_dato              DATE;
  l_dato_forste       DATE;
  l_dato_siste        DATE;
  l_dager             NUMBER := 0;
  l_dager_mellom      NUMBER := 0;
  l_dager_mellom_lang NUMBER := 0;
  l_iLangFravaer      NUMBER := 0;
  l_strEmpId          VARCHAR(25);
  
  CURSOR cur_emp IS SELECT DISTINCT employee_id FROM kapasitet_timer; -- WHERE employee_id = 931041; --FOR DEBUG
  
  CURSOR cur_timer (i_strEmpId VARCHAR, i_strToMonth VARCHAR ) IS
    SELECT kap.employee_id, kap.dato, kap.timer_kapasitet, tim.timer_fravar, tim.kode_nr
      FROM kapasitet_timer kap
        INNER JOIN hours_worked tim ON (kap.employee_id = tim.employee_id AND kap.dato = tim.dato)
      WHERE kap.employee_id          = i_strEmpId
        AND kap.timer_kapasitet      > 0
        AND TO_CHAR(kap.dato,'YYYY') >= TO_CHAR(SYSDATE,'YYYY')-1
        AND kap.dato                 <= last_day( to_date( '01' || i_strToMonth,'DDMMYYYY'))
        ORDER BY kap.dato;
      
BEGIN
  SELECT sysdate INTO g_dtStartTime from dual;

  g_bResult := false;
  g_strText := 'START: DivideSickLeave';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'DivideSickLeave', 0 );


  /* RETTE FEIL I DATAGRUNNLAGET FRA WINTID
     GRUNNLAGET INNEHOLDER DATA FRA 728 Numedal FOR 2013 SOM ER FEIL. DISSE SKAL FJERNES OG MANUELL INPUT BENYTTES
  */
  DELETE kapasitet_timer WHERE to_char(dato,'YYYY') = '2013' AND employee_id IN (SELECT resource_id FROM person WHERE responsible_id = '728SK');
  DELETE hours_worked    WHERE to_char(dato,'YYYY') = '2013' AND employee_id IN (SELECT resource_id FROM person WHERE responsible_id = '728SK');
  
  COMMIT;

  -- Sett all langtid til 0 da vi går ut i fra at alt fravær er korttid
  UPDATE hours_worked h
     SET h.fravar_langtid = 0
   WHERE h.timer_fravar > 0
     AND TO_CHAR(dato,'YYYY') >= TO_CHAR(SYSDATE,'YYYY')-1;
  
  COMMIT;

  OPEN cur_emp;
  FETCH cur_emp INTO l_strEmpId;
  WHILE cur_emp%FOUND LOOP

    FOR r IN cur_timer (l_strEmpId, i_strToMonth) LOOP
  
    IF r.employee_id <> l_emp THEN
      l_emp         := r.employee_id;
      l_dager       := 0;
      l_dato        := r.dato;
      l_dato_siste  := r.dato;
      l_dato_forste := NULL;
    END IF;
    
    IF NVL(r.timer_fravar,0) = 0 AND l_dager = 0 THEN
      CONTINUE; -- Hopp ut og sjekk neste dag
    ELSIF NVL(r.timer_fravar,0) = 0 THEN 
      l_dager_mellom := r.dato - l_dato_siste; -- Tell dager siden siste fraværsdag
      CONTINUE;  -- Hopp ut og sjekk neste dag
    END IF;
    l_dager_mellom := r.dato - l_dato_siste; -- må telle dager i mellom også ved fravær
    
    IF l_dager_mellom > 16 THEN  -- Nullstill og begynn å telle på nytt dersom det er mer enn 16 dager mellom fraværene
      l_dager        := 0;
      l_dager_mellom := 0;
      l_dato_forste  := NULL;
    END IF;
    -- vi har fravær, akkumuler
    IF NVL(r.timer_fravar,0) > 0 THEN 
      l_dato_siste := r.dato;
      
      IF l_dato_forste IS NULL THEN l_dato_forste  := r.dato; END IF;
      
      IF l_dager = 0            THEN l_dato := r.dato; END IF;
      
      l_dager := l_dager + 1;
      l_dager_mellom_lang := r.dato - l_dato_forste;
      IF l_dager_mellom_lang > 16 THEN l_iLangFravaer := 1; ELSE l_iLangFravaer := 0; END IF;
    END IF;
    
    /* KODE DATERT/ENDRET 05112014 da egenmelding ble håndtert som korttid
       Se mail fra Nils W. Jespersen og Ellen E. Dreng datert 4.11.2014,emne: spørsmål fravær
       
       
    IF (NVL(r.timer_fravar,0) > 0 AND r.kode_nr <> 1021) THEN -- Håndterer egenmelding (1021) som kort fravær
      l_dato_siste := r.dato;
      IF l_dato_forste IS NULL THEN l_dato_forste  := r.dato; END IF;
      IF l_dager = 0 THEN l_dato := r.dato; END IF;
      l_dager := l_dager+1;
      
      l_dager_mellom_lang := r.dato - l_dato_forste;
      IF l_dager_mellom_lang > 16 THEN l_iLangFravaer := 1; ELSE l_iLangFravaer := 0; END IF;
    END IF;
    */

    IF l_dager > 16 THEN
    -- langtidsfravær
      UPDATE hours_worked h
         SET  h.fravar_langtid = h.timer_fravar
       WHERE  h.employee_id = l_strEmpId --r.employee_id
         AND h.dato BETWEEN l_dato AND r.dato;
         
      COMMIT;
    END IF;
   
    IF l_iLangFravaer = 1 THEN
    -- langtidsfravær
      UPDATE hours_worked h
         SET  h.fravar_langtid = h.timer_fravar
       WHERE  h.employee_id = l_strEmpId --r.employee_id
         AND h.dato BETWEEN l_dato_forste AND r.dato;
         
      COMMIT;
    END IF;
    

  END LOOP; 
  
  FETCH cur_emp INTO l_strEmpId;
  END LOOP;
  CLOSE cur_emp;
  

  UPDATE hours_worked h
     SET h.fravar_korttid = h.timer_fravar
   WHERE  h.fravar_langtid = 0
     AND h.timer_fravar > 0;

  UPDATE hours_worked h
     SET h.fravar_korttid = 0
   WHERE h.fravar_langtid > 0
     AND h.timer_fravar > 0;
  
  COMMIT;
  
  SELECT sysdate INTO g_dtEndTime FROM dual;
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );

  g_strText := 'FINISH: DivideSickLeave - TIDSFORBRUK: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'DivideSickLeave', 0 );
  
END;


PROCEDURE UpdateSupplierLedger (i_jobbID varchar2 default '') IS
    l_jobbID      VARCHAR2(50);
    
BEGIN
 
  -- Opprett jobbID hvis ingen finnes
  IF NVL(i_jobbID,0) = 0 THEN 
    SELECT sys_guid() INTO l_jobbID from dual;
  ELSE
    l_jobbID := i_jobbID;
  END IF;
  
  -- Oppdaterer tabellen med leverandører
  UpdateSupplier(l_jobbID);

  -- Setter Startid
  SELECT sysdate INTO g_dtStartTime from dual;
  
  -- Starter logg
  g_bResult := false;
  g_strText := 'START: UpdateSupplierLedger (Agresso)';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSupplierLedger', 0, l_jobbID);
    
  -- Sletter alle leverandører fra Agresso
  DELETE supplier_ledger WHERE client <> 'EL';

  INSERT INTO supplier_ledger
  (supplier_ledger_id,
	 amount,
	 apar_type,
	 collect_ref,
	 collect_status,
	 compl_delay,
	 curr_doc,
	 curr_licence,
	 cur_amount,
	 dc_flag,
	 discount,
	 disc_date,
	 disc_percent,
	 due_date,
	 exch_rate,
	 int_date,
	 int_status,
	 kid,
	 last_update,
	 legal_status,
	 payment_date,
	 payperiod,
	 pay_flag,
	 pay_method,
	 pay_transfer,
	 period,
	 remind_date,
	 remitt_curr,
	 remit_amount,
	 rem_level,
	 rest_amount,
	 rest_curr,
	 rest_value_2,
	 rest_value_3,
	 rev_date,
	 rev_diff,
	 rev_diff_v2,
	 rev_diff_v3,
	 sequence_no,
	 status,
	 trans_date,
	 value_2,
	 value_3,
	 voucher_date,
	 account ,
	 apar_id,
	 arrive_id ,
	 att_1_id ,
	 att_2_id  ,
	 att_3_id ,
	 att_4_id,
	 att_5_id,
	 att_6_id,
	 att_7_id,
	 client ,
	 collect_agency,
	 commitment,
	 complaint,
	 currency ,
	 description ,
	 dim_1  ,
	 dim_2  ,
	 dim_3  ,
	 dim_4  ,
	 dim_5  ,
	 dim_6  ,
	 dim_7  ,
	 ext_inv_ref,
	 factor_short,
	 intrule_id,
	 order_id ,
	 pay_currency ,
	 pay_plan_id ,
	 remitt_id  ,
	 responsible,
	 tax_code  ,
	 trans_id ,
	 user_id ,
	 voucher_no,
	 voucher_ref,
	 voucher_type,
	 arrival_date,
	 contract_id)
   SELECT 
     rownum,
	 amount,
	 apar_type,
	 collect_ref,
	 collect_status,
	 compl_delay,
	 curr_doc,
	 curr_licence,
	 cur_amount,
	 dc_flag,
	 discount,
	 disc_date,
	 disc_percent,
	 due_date,
	 exch_rate,
	 int_date,
	 int_status,
	 kid,
	 last_update,
	 legal_status,
	 payment_date,
	 payperiod,
	 pay_flag,
	 pay_method,
	 pay_transfer,
	 period,
	 remind_date,
	 remitt_curr,
	 remit_amount,
	 rem_level,
	 rest_amount,
	 rest_curr,
	 rest_value_2,
	 rest_value_3,
	 rev_date,
	 rev_diff,
	 rev_diff_v2,
	 rev_diff_v3,
	 sequence_no,
	 status,
	 trans_date,
	 value_2,
	 value_3,
	 voucher_date,
	 account ,
	 apar_id || client,
	 arrive_id ,
	 att_1_id ,
	 att_2_id  ,
	 att_3_id ,
	 att_4_id,
	 att_5_id,
	 att_6_id,
	 att_7_id,
	 client ,
	 collect_agency,
	 commitment,
	 complaint,
	 currency ,
	 description ,
	 dim_1  ,
	 dim_2  ,
	 dim_3  ,
	 dim_4  ,
	 dim_5  ,
	 dim_6  ,
	 dim_7  ,
	 ext_inv_ref,
	 factor_short,
	 intrule_id,
	 order_id ,
	 pay_currency ,
	 pay_plan_id ,
	 remitt_id  ,
	 responsible,
	 tax_code  ,
	 trans_id ,
	 user_id ,
	 voucher_no,
	 voucher_ref,
	 voucher_type,
	 arrival_date,
	 contract_id
  FROM g_agrles.mv_asutrans
  UNION ALL
  SELECT 
   rownum,
	 amount,
	 apar_type,
	 collect_ref,
	 collect_status,
	 compl_delay,
	 curr_doc,
	 curr_licence,
	 cur_amount,
	 dc_flag,
	 discount,
	 disc_date,
	 disc_percent,
	 due_date,
	 exch_rate,
	 int_date,
	 int_status,
	 kid,
	 last_update,
	 legal_status,
	 payment_date,
	 payperiod,
	 pay_flag,
	 pay_method,
	 pay_transfer,
	 period,
	 remind_date,
	 remitt_curr,
	 remit_amount,
	 rem_level,
	 rest_amount,
	 rest_curr,
	 rest_value_2,
	 rest_value_3,
	 rev_date,
	 rev_diff,
	 rev_diff_v2,
	 rev_diff_v3,
	 sequence_no,
	 status,
	 trans_date,
	 value_2,
	 value_3,
	 voucher_date,
	 account ,
	 apar_id || client,
	 arrive_id ,
	 att_1_id ,
	 att_2_id  ,
	 att_3_id ,
	 att_4_id,
	 att_5_id,
	 att_6_id,
	 att_7_id,
	 client ,
	 collect_agency,
	 commitment,
	 complaint,
	 currency ,
	 description ,
	 dim_1  ,
	 dim_2  ,
	 dim_3  ,
	 dim_4  ,
	 dim_5  ,
	 dim_6  ,
	 dim_7  ,
	 ext_inv_ref,
	 factor_short,
	 intrule_id,
	 order_id ,
	 pay_currency ,
	 pay_plan_id ,
	 remitt_id  ,
	 responsible,
	 tax_code  ,
	 trans_id ,
	 user_id ,
	 voucher_no,
	 voucher_ref,
	 voucher_type,
	 arrival_date,
	 contract_id
  FROM g_agrles.mv_asuhistr; 

COMMIT; 

  -- Setter sluttiden
  SELECT sysdate INTO g_dtEndTime FROM dual;
  
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );
  
  -- Sluttlogg 
  g_strText := 'FINISH: UpdateSupplierLedger (Agresso) - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSupplierLedger', 0, l_jobbID );

  -- Lager aggregat
  CreateSupplierLedgerAggregate(l_jobbID);

END UpdateSupplierLedger;



PROCEDURE UpdateSupplierLedgerVisma (i_jobbID varchar2 default '') IS
  
BEGIN
    
  -- Oppdaterer tabellen med leverandører
  UpdateSupplier(i_jobbID);

  -- Setter Startid
  SELECT sysdate INTO g_dtStartTime from dual;
  
  -- Starter logg
  g_bResult := false;
  g_strText := 'START: UpdateSupplierLedgerVisma';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSupplierLedgerVisma', 0, i_jobbID);
  
   -- Fjerner elektrodata 
   DELETE supplier_ledger WHERE client = 'EL';

  -- Setter inn ny elektrodata
   INSERT INTO supplier_ledger
    (supplier_ledger_id
    ,amount
    ,rest_amount
    ,period
    ,apar_id
    ,client
    ,voucher_type
    ,apar_type)
   SELECT 
     rownum * -1
     ,nvl(lpo_belop,0)
     ,nvl(lpo_restbelop,0)
     , to_number(to_char(lpo_post_aar) || to_char(lpad(lpo_post_per,2,'0')))
     ,to_char(lpo_leverandor) || 'EL'
     ,'EL'
     ,lpo_bilag_art
     ,'0'
    FROM G_VISMALES.VISMA_LPOS_EXTERNAL;
    
COMMIT; 
  
  -- Setter sluttiden
  SELECT sysdate INTO g_dtEndTime FROM dual;
  
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );
    
  g_strText := 'FINISH: UpdateSupplierLedgerVisma - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSupplierLedgerVisma', 0, i_jobbID );
  
-- Lager aggregat
CreateSupplierLedgerAggregate (i_jobbID);

END UpdateSupplierLedgerVisma;



PROCEDURE CreateSupplierLedgerAggregate (i_jobbID varchar2 default '') IS

  l_iTableExits NUMBER;
  
BEGIN
  
  -- Setter Startid
  SELECT sysdate INTO g_dtStartTime from dual;
  
  g_bResult := false;
  g_strText := 'START: CreateSupplierLedgerAggregate';
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'CreateSupplierLedgerAggregate', 0, i_jobbID);

  SELECT count(*) INTO l_iTableExits FROM user_tables WHERE lower(table_name) = 'supplier_ledger_agg';
  IF l_iTableExits > 0 THEN 
    EXECUTE IMMEDIATE( 'DROP TABLE supplier_ledger_agg');
  END IF;
  
  EXECUTE IMMEDIATE ('CREATE TABLE supplier_ledger_agg AS  
                      SELECT
                         apar_id || TO_CHAR(period.date_from,''YYYY'') || client AS supplier_ledger_agg_id,
                         apar_id           as supplier_id,
                         TO_DATE( ''0101'' || TO_CHAR(period.date_from,''YYYY''),''DDMMYYYY'') as supplier_ledger_year_dt, 
                         TO_NUMBER(TO_CHAR(period.date_from,''YYYY'')) as supplier_ledger_year, 
                         client            AS company_id,
                         voucher_type      AS voucher_type,
                         SUM(amount)       AS amount
                      FROM supplier_ledger, period
                      WHERE supplier_ledger.period = period.acc_period
                        AND client IN (select company_id FROM company)
                      GROUP BY 
                         APAR_ID || TO_CHAR(period.date_from,''YYYY'') || client,
                         TO_DATE( ''0101'' || TO_CHAR(period.date_from,''YYYY''),''DDMMYYYY''), 
                         TO_NUMBER(TO_CHAR(period.date_from,''YYYY'')),
                         client,
                         apar_id,
                         voucher_type');

-- Setter sluttiden
  SELECT sysdate INTO g_dtEndTime FROM dual;
  
  --Script for å finne tidsforbruk...
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );
    
  g_strText := 'FINISH: CreateSupplierLedgerAggregate - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'CreateSupplierLedgerAggregate', 0, i_jobbID );
  

END CreateSupplierLedgerAggregate;


PROCEDURE UpdateCustomerLedger IS
BEGIN
  UpdateCustomer;
  
  EXECUTE IMMEDIATE ('TRUNCATE TABLE customer_ledger');

  INSERT INTO customer_ledger
  (customer_ledger_id,
	 amount,
	 apar_type,
	 collect_ref,
	 collect_status,
	 compl_delay,
	 curr_doc,
	 curr_licence,
	 cur_amount,
	 dc_flag,
	 discount,
	 disc_date,
	 disc_percent,
	 due_date,
	 exch_rate,
	 int_date,
	 int_status,
	 kid,
	 last_update,
	 legal_status,
	 payment_date,
	 payperiod,
	 pay_flag,
	 pay_method,
	 pay_transfer,
	 period,
	 remind_date,
	 remitt_curr,
	 remit_amount,
	 rem_level,
	 rest_amount,
	 rest_curr,
	 rest_value_2,
	 rest_value_3,
	 rev_date,
	 rev_diff,
	 rev_diff_v2,
	 rev_diff_v3,
	 sequence_no,
	 status,
	 trans_date,
	 value_2,
	 value_3,
	 voucher_date,
	 account ,
	 apar_id,
	 arrive_id ,
	 att_1_id ,
	 att_2_id  ,
	 att_3_id ,
	 att_4_id,
	 att_5_id,
	 att_6_id,
	 att_7_id,
	 client ,
	 collect_agency,
	 commitment,
	 complaint,
	 currency ,
	 description ,
	 dim_1  ,
	 dim_2  ,
	 dim_3  ,
	 dim_4  ,
	 dim_5  ,
	 dim_6  ,
	 dim_7  ,
	 ext_inv_ref,
	 factor_short,
	 intrule_id,
	 order_id ,
	 pay_currency ,
	 pay_plan_id ,
	 remitt_id  ,
	 responsible,
	 tax_code  ,
	 trans_id ,
	 user_id ,
	 voucher_no,
	 voucher_ref,
	 voucher_type,
	 arrival_date,
	 contract_id)
   SELECT 
     rownum,
	 amount,
	 apar_type,
	 collect_ref,
	 collect_status,
	 compl_delay,
	 curr_doc,
	 curr_licence,
	 cur_amount,
	 dc_flag,
	 discount,
	 disc_date,
	 disc_percent,
	 due_date,
	 exch_rate,
	 int_date,
	 int_status,
	 kid,
	 last_update,
	 legal_status,
	 payment_date,
	 payperiod,
	 pay_flag,
	 pay_method,
	 pay_transfer,
	 period,
	 remind_date,
	 remitt_curr,
	 remit_amount,
	 rem_level,
	 rest_amount,
	 rest_curr,
	 rest_value_2,
	 rest_value_3,
	 rev_date,
	 rev_diff,
	 rev_diff_v2,
	 rev_diff_v3,
	 sequence_no,
	 status,
	 trans_date,
	 value_2,
	 value_3,
	 voucher_date,
	 account ,
	 apar_id || client,
	 arrive_id ,
	 att_1_id ,
	 att_2_id  ,
	 att_3_id ,
	 att_4_id,
	 att_5_id,
	 att_6_id,
	 att_7_id,
	 client ,
	 collect_agency,
	 commitment,
	 complaint,
	 currency ,
	 description ,
	 dim_1  ,
	 dim_2  ,
	 dim_3  ,
	 dim_4  ,
	 dim_5  ,
	 dim_6  ,
	 dim_7  ,
	 ext_inv_ref,
	 factor_short,
	 intrule_id,
	 order_id ,
	 pay_currency ,
	 pay_plan_id ,
	 remitt_id  ,
	 responsible,
	 tax_code  ,
	 trans_id ,
	 user_id ,
	 voucher_no,
	 voucher_ref,
	 voucher_type,
	 arrival_date,
	 contract_id
  FROM g_agrles.mv_acutrans
  UNION ALL
  SELECT 
   rownum,
	 amount,
	 apar_type,
	 collect_ref,
	 collect_status,
	 compl_delay,
	 curr_doc,
	 curr_licence,
	 cur_amount,
	 dc_flag,
	 discount,
	 disc_date,
	 disc_percent,
	 due_date,
	 exch_rate,
	 int_date,
	 int_status,
	 kid,
	 last_update,
	 legal_status,
	 payment_date,
	 payperiod,
	 pay_flag,
	 pay_method,
	 pay_transfer,
	 period,
	 remind_date,
	 remitt_curr,
	 remit_amount,
	 rem_level,
	 rest_amount,
	 rest_curr,
	 rest_value_2,
	 rest_value_3,
	 rev_date,
	 rev_diff,
	 rev_diff_v2,
	 rev_diff_v3,
	 sequence_no,
	 status,
	 trans_date,
	 value_2,
	 value_3,
	 voucher_date,
	 account ,
	 apar_id || client,
	 arrive_id ,
	 att_1_id ,
	 att_2_id  ,
	 att_3_id ,
	 att_4_id,
	 att_5_id,
	 att_6_id,
	 att_7_id,
	 client ,
	 collect_agency,
	 commitment,
	 complaint,
	 currency ,
	 description ,
	 dim_1  ,
	 dim_2  ,
	 dim_3  ,
	 dim_4  ,
	 dim_5  ,
	 dim_6  ,
	 dim_7  ,
	 ext_inv_ref,
	 factor_short,
	 intrule_id,
	 order_id ,
	 pay_currency ,
	 pay_plan_id ,
	 remitt_id  ,
	 responsible,
	 tax_code  ,
	 trans_id ,
	 user_id ,
	 voucher_no,
	 voucher_ref,
	 voucher_type,
	 arrival_date,
	 contract_id
  FROM g_agrles.mv_acuhistr; 

  COMMIT; 

-- ELEKTRO RESKONTRO
 
   INSERT INTO customer_ledger
    (customer_ledger_id
    ,amount
    ,rest_amount
    ,period
    ,apar_id
    ,client
    ,voucher_type
    ,account
    ,due_date
    ,voucher_no
    ,voucher_date)
   SELECT 
     rownum * -1
    , NVL(CASE substr(kpo_belop,1,1) 
         WHEN '.' THEN TO_NUMBER('0'||replace(kpo_belop,'.',','))
         WHEN '-' THEN 
           CASE substr(kpo_belop,2,1) 
             WHEN '.' THEN TO_NUMBER('-0,'||substr(replace(kpo_belop,'.',','),3,length(kpo_belop))) ELSE to_number(replace(kpo_belop,'.',','))  END
         ELSE TO_NUMBER(replace(kpo_belop,'.',','))  END,0)
         
    , NVL(CASE substr(kpo_restbelop,1,1) 
         WHEN '.' THEN TO_NUMBER('0'||replace(kpo_restbelop,'.',','))
         WHEN '-' THEN 
           CASE substr(kpo_restbelop,2,1) 
             WHEN '.' THEN TO_NUMBER('-0,'||substr(replace(kpo_restbelop,'.',','),3,length(kpo_restbelop))) ELSE to_number(replace(kpo_restbelop,'.',','))  END
         ELSE TO_NUMBER(replace(kpo_restbelop,'.',','))  END,0)
     , to_number(to_char(kpo_post_aar) || to_char(lpad(kpo_post_per,2,'0')))
     ,to_char(kpo_kunde) || 'EL'
     ,'EL'
     ,kpo_bilag_art || 'EL'
     ,kpo_motkonto
     ,case length(kpo_forfall_dato)
        when 1 then null
        when 6 then to_date(substr(kpo_forfall_dato,1,2) || substr(kpo_forfall_dato,3,2) || '20' || substr(kpo_forfall_dato,5,2),'DDMMYYYY')
        when 5 then to_date('0' || substr(kpo_forfall_dato,1,1) || substr(kpo_forfall_dato,2,2) || '20' || substr(kpo_forfall_dato,4,2) ,'DDMMYYYY')
        else null
      end
    ,kpo_bilag
    ,to_date(kpo_bilag_aar || lpad(kpo_bilag_mnd,2,'0') || lpad(kpo_bilag_dag,2,'0'),'YYYYMMDD')
    FROM g_vismales.load_kpos
    WHERE kpo_post_aar IS NOT NULL;
   

COMMIT; 

END UpdateCustomerLedger;

PROCEDURE UpdateSickLeave (i_jobbID varchar2 default '') AS  
  l_iMaxRowNum NUMBER;
BEGIN
    -- Setter Startid
    SELECT sysdate INTO g_dtStartTime from dual;
    
    -- Skriver logg
    g_bResult := false;
    g_strText := 'START: UpdateSickLeave';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSickLeave', 0, i_jobbID);
    
    -- Konverteringen gjøres nå i view'et
    --UPDATE g_wtles.wt_resultat_external  SET timer = REPLACE(timer,'.',',');
    --UPDATE g_wtles.wt_kapasitet_external SET timer = REPLACE(timer,'.',',');
    --EXECUTE IMMEDIATE('UPDATE g_wtles.wt_resultat_external  SET timer = REPLACE(timer,''.'','','')');
    --EXECUTE IMMEDIATE('UPDATE g_wtles.wt_kapasitet_external SET timer = REPLACE(timer,''.'','','')');
    --COMMIT;
    
    --EXECUTE IMMEDIATE('TRUNCATE TABLE hours_worked');
    
    g_strText := 'UpdateSickLeave: Loading absence';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSickLeave', 5, i_jobbID );
    
    DELETE hours_worked WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);
    
    SELECT MAX(hours_workedID) INTO l_iMaxRowNum FROM hours_worked;
    
    INSERT INTO hours_worked
    (
      hours_workedID,
      employee_id,
      calendar_id,
      dato,
      timer_arbeidet,
      timer_fravar,
      kode_nr,
      kode_navn,
      fravar_langtid,
      fravar_korttid
    )
    SELECT 
      l_iMaxRowNum + rownum,
      src.ans_nr,
      calendar.calendar_id,
      src.dato,
      src.arbeidet,
      src.fravar,
      src.kode_nr,
      src.kode_navn,
      0,
      0
    FROM g_wtles.v_fravar src,
          calendar
    WHERE calendar.calendar_date = src.dato
      AND src.dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);
    
    
    g_strText := 'UpdateSickLeave: Loading capacity';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSickLeave', 5, i_jobbID );
    
    
    --EXECUTE IMMEDIATE('TRUNCATE TABLE kapasitet_timer');
    DELETE kapasitet_timer WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);
    
    SELECT MAX(kapasitet_timerID) INTO l_iMaxRowNum FROM kapasitet_timer;
    
    INSERT INTO kapasitet_timer
    (
      kapasitet_timerID,
      employee_id,
      kalenderid,
      dato,
      timer_kapasitet
    )
    SELECT 
      l_iMaxRowNum + rownum,
      src.ans_nr,
      calendar.calendar_id,
      src.dato,
      src.timer
    FROM g_wtles.V_TIMEVERK src,
         calendar
    WHERE calendar.calendar_date = src.dato
      AND src.dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);
    
    COMMIT;
/*    
create index idx_kapasitet_timer_emp_id on KAPASITET_TIMER (employee_id)
create index idx_kapasitet_timer_dato on KAPASITET_TIMER (dato)

create index idx_PERSON_COMP_ASSOC_per_id on PERSON_COMPANY_ASSOC (person_id)
create index idx_PERSON_COMP_ASSOC_dt_from on PERSON_COMPANY_ASSOC (date_from)
create index idx_PERSON_COMP_ASSOC_dt_to on PERSON_COMPANY_ASSOC (date_to)
create index idx_PERSON_COMP_ASSOC_status on PERSON_COMPANY_ASSOC (status)


create index idx_PERSON_res_ASSOC_per_id on PERSON_responsible_ASSOC (person_id)
create index idx_PERSON_res_ASSOC_dt_from on PERSON_responsible_ASSOC (date_from)
create index idx_PERSON_res_ASSOC_dt_to on PERSON_responsible_ASSOC (date_to)
create index idx_PERSON_res_ASSOC_status on PERSON_responsible_ASSOC (status)


create index idx_HOURS_WORKED_dato on HOURS_WORKED (dato)
create index idx_HOURS_WORKED_emp_id on HOURS_WORKED (employee_id)
*/
    g_strText := 'UpdateSickLeave: Updating company and responsible id';
    g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSickLeave', 5, i_jobbID );
    
    UPDATE hours_worked SET company_id = (SELECT MAX(person_company_assoc.company_id) 
                                              FROM person_company_assoc, 
                                                    person 
                                             WHERE person.resource_id             = hours_worked.employee_id
                                               AND person_company_assoc.person_id = person.person_id
                                               AND hours_worked.dato              >= person_company_assoc.date_from
                                               AND hours_worked.dato              <= person_company_assoc.date_to
                                               AND person_company_assoc.status    = 'N'
                                            )
    WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                            
                                             
    UPDATE hours_worked set company_id = (SELECT company_id 
                                              FROM person 
                                             WHERE person.resource_id = hours_worked.employee_id
                                           )
     WHERE company_id IS NULL
       AND dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);

     UPDATE hours_worked SET responsible_id = (SELECT MAX(person_responsible_assoc.responsible_id) 
                                                   FROM person_responsible_assoc, 
                                                         person 
                                                  WHERE person.resource_id                 = hours_worked.employee_id
                                                    AND person_responsible_assoc.person_id = person.person_id
                                                    AND hours_worked.dato                  >= person_responsible_assoc.date_from
                                                    AND hours_worked.dato                  <= person_responsible_assoc.date_to
                                                    AND person_responsible_assoc.status    = 'N'
                                                 )
     WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                                                                           

     -- DENNE RETTER OPP MISMATCH MELLOM WINTID OG AGRESS0 DERSOM EN PERSON SLUTTER MIDT I MND
     UPDATE hours_worked SET responsible_id = (SELECT MAX(person_responsible_assoc.responsible_id) 
                                                   FROM person_responsible_assoc, 
                                                         person 
                                                  WHERE person.resource_id                 = hours_worked.employee_id
                                                    AND person_responsible_assoc.person_id = person.person_id
                                                    AND hours_worked.dato                  >= person_responsible_assoc.date_from
                                                    AND hours_worked.dato                  <= last_day(person_responsible_assoc.date_to)
                                                    AND person_responsible_assoc.status    = 'N'
                                                 )
     WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual)
       AND (responsible_id IS NULL OR (responsible_id NOT IN (SELECT responsible_id FROM responsible)));


     UPDATE hours_worked SET responsible_id = ( SELECT responsible_id 
                                                   FROM person 
                                                  WHERE person.resource_id = hours_worked.employee_id
                                                )
     WHERE responsible_id IS NULL
       AND dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                          


    UPDATE hours_worked SET resource_type_id = (SELECT MAX(his.resource_type_id) 
                                                    FROM resource_type_history his, 
                                                    person 
                                             WHERE person.resource_id = hours_worked.employee_id
                                               AND his.person_id      = person.person_id
                                               AND hours_worked.dato  >= his.date_from
                                               AND hours_worked.dato  <= his.date_to
                                               AND his.status         = 'N'
                                            )
    WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                            

    UPDATE hours_worked SET resource_type_id = ( SELECT resource_type_id 
                                                   FROM person 
                                                  WHERE person.resource_id = hours_worked.employee_id
                                                )
     WHERE resource_type_id IS NULL
       AND dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                          

     UPDATE kapasitet_timer set company_id = ( SELECT MAX(person_company_assoc.company_id) 
                                                   FROM person_company_assoc, 
                                                         person 
                                                  WHERE person.resource_id             = kapasitet_timer.employee_id
                                                    AND person_company_assoc.person_id = person.person_id
                                                    AND kapasitet_timer.dato           >= person_company_assoc.date_from
                                                    AND kapasitet_timer.dato           <= person_company_assoc.date_to
                                                    AND person_company_assoc.status    = 'N'
                                               )
     WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                                                                           

     UPDATE kapasitet_timer SET company_id = ( SELECT company_id 
                                                   FROM person 
                                                  WHERE person.resource_id = kapasitet_timer.employee_id
                                               )
     WHERE company_id IS NULL
       AND  dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                            


     UPDATE kapasitet_timer SET responsible_id = ( SELECT MAX(person_responsible_assoc.responsible_id) 
                                                       FROM person_responsible_assoc, 
                                                             person 
                                                      WHERE person.resource_id                 = kapasitet_timer.employee_id
                                                        AND person_responsible_assoc.person_id = person.person_id
                                                        AND kapasitet_timer.dato               >= person_responsible_assoc.date_from
                                                        AND kapasitet_timer.dato               <= person_responsible_assoc.date_to
                                                        AND person_responsible_assoc.status    = 'N'
                                                   )
     WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                            

     -- DENNE RETTER OPP MISMATCH MELLOM WINTID OG AGRESS0 DERSOM EN PERSON SLUTTER MIDT I MND
     UPDATE kapasitet_timer SET responsible_id = ( SELECT MAX(person_responsible_assoc.responsible_id) 
                                                       FROM person_responsible_assoc, 
                                                             person 
                                                      WHERE person.resource_id                 = kapasitet_timer.employee_id
                                                        AND person_responsible_assoc.person_id = person.person_id
                                                        AND kapasitet_timer.dato               >= person_responsible_assoc.date_from
                                                        AND kapasitet_timer.dato               <= last_day(person_responsible_assoc.date_to)
                                                        AND person_responsible_assoc.status    = 'N'
                                                   )
     WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual)                           
       AND (responsible_id IS NULL OR (responsible_id NOT IN (SELECT responsible_id FROM responsible)));

     UPDATE kapasitet_timer SET responsible_id = ( SELECT responsible_id 
                                                       FROM person 
                                                      WHERE person.resource_id = kapasitet_timer.employee_id
                                                   )
     WHERE responsible_id IS NULL
       AND dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                            

  
    UPDATE kapasitet_timer SET resource_type_id = (SELECT MAX(his.resource_type_id) 
                                                    FROM resource_type_history his, 
                                                    person 
                                             WHERE person.resource_id    = kapasitet_timer.employee_id
                                               AND his.person_id         = person.person_id
                                               AND kapasitet_timer.dato  >= his.date_from
                                               AND kapasitet_timer.dato  <= his.date_to
                                               AND his.status            = 'N'
                                            )
    WHERE dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                            

    UPDATE kapasitet_timer SET resource_type_id = ( SELECT resource_type_id 
                                                        FROM person 
                                                      WHERE person.resource_id = kapasitet_timer.employee_id
                                                    )
     WHERE resource_type_id IS NULL
       AND dato >= (SELECT add_months(to_date( '0101' || to_char(sysdate,'YYYY'),'DDMMYYYY'),-12) FROM dual);                                          

  
  COMMIT;
  
   -- Setter sluttid
  SELECT sysdate INTO g_dtEndTime FROM dual;
  
  --Script for å finne tidsforbruk
  SELECT to_char(to_number(SUBSTR(A,9,2)) - 01 || ':' || SUBSTR(A,12,2) || ':' || SUBSTR(A,15,2) || ':' || SUBSTR(A,18,2)) INTO g_strTimeUsage
    FROM ( SELECT to_char(to_date('20000101','YYYYMMDD') + (g_dtEndTime-g_dtStartTime),'YYYY MM DD HH24:MI:SS') A FROM dual );
  
  -- Sluttlogg 
  g_strText := 'END: UpdateSickLeave - TIME USAGE: ' || g_strTimeUsage ;
  g_bResult := MAINTENANCE_API.WriteLog(g_strText, user, SQL%ROWCOUNT,'UpdateSickLeave', 0, i_jobbID );
    
END UpdateSickLeave;

/*
***************************************************************************
*																		                                      *
*                         SUPPORT FUNCTIONS       						            *
*						  												                                    *
***************************************************************************
*/
function WriteLog (
				i_LogTekst   g_kolibri.g_log.log_text%type, 
				i_bruker  	 g_kolibri.g_log.g_user%type ,
				i_antPoster  int,
				i_ProcNavn 	 g_kolibri.g_log.proc_name%type  default '',
				i_offset     int default 0,
        i_jobbID     varchar2 default '')  return boolean is

/*
   ** funksjons navn WriteLog
   ** 
   ** returerer		  True/False (boolean)
   ** parametere		p_logtekst   : Tekst beskrivelse for log record
   **						    p_bruker     : Pålogget bruker (user)
   **						    p_antPoster	 : Antall poster påvirket hvis dette er tilgjengelig
   **						    p_ProcNavn   : Navn på den prosedyre eller funksjon som produserte 
   **								          	   log recorden. 
   **						    p_offset     : Offset til teksten, letter lesbarhet															
   ** Beskrivelse:  Brukes for å logge alle hendelser i datavarehuset, Funksjonen skriver inn logtekst
   **						    i tabellen DW_Log iht. oppgitt parametere,  
   ** 				 
   **/

	  l_logTekst     g_kolibri.g_log.log_text%type;
    l_jobbGUID     g_kolibri.g_log.job_guid%type;
	
   BEGIN
  		-- justerer offset for tekst
	    l_logTekst := lpad(i_LogTekst, i_offset + length(i_LogTekst), ' ');
      
      -- konverter streng(på GUID-format) til RAW for å kunne legge inn i guid-felt
       IF INSTR(i_jobbID,'-') <> 0 THEN l_jobbGUID := g_guidtoraw(i_jobbID); ELSE l_jobbGUID := i_jobbID; END IF;
	 	  
	     INSERT INTO  g_kolibri.g_log (log_guid, log_text, g_user, no_of_rows, proc_name, job_guid)
	             VALUES                (sys_guid(), l_logTekst, i_bruker, i_antPoster, i_ProcNavn, l_jobbGUID);
      
       COMMIT;

	   RETURN TRUE;

   END WriteLog;



END MAINTENANCE_API;