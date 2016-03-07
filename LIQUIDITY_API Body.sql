create or replace PACKAGE BODY "LIQUIDITY_API" AS
  g_strCompanyId            COMPANY.COMPANY_ID%TYPE;
  g_iPeriodId               PERIOD.ACC_PERIOD%TYPE;
  
  -- Regelegenskaper
  g_bUsePaymentPeriodAssoc     RULE_ENTRY.USE_RULE_PERIOD_PAYMENT_DATE%TYPE := 0;

/************************************************************************
*
* NAME
*   LIQUIDITY_API.Generate 
* FUNCTION
*   Main procedure in package LIQUIDITY_API. 
* NOTES
*   Input format is STRING : <LiquidityId> i.e '7A90628C85707D49808B59EA3E1AD9AA'
*
* MODIFIED
*     oig     20.04.2010 - created
*
**************************************************************************/
PROCEDURE Generate ( i_strParam  IN VARCHAR ) 
IS
 l_exNoPrognosisFound      EXCEPTION;
 l_exNoJournalFound        EXCEPTION;
 l_exOther                 EXCEPTION;
 l_iJournalCount           NUMBER(11,0);
 l_iType                   NUMBER(11,0);
 l_rLiquidityId            LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE;
 l_rLiquidityEntryMonth    LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE; 
 l_rCurrentMonthRow        LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE; 
  
 l_rRuleId                 RULE_ENTRY.RULE_ENTRY_ID%TYPE;
 l_rHardCodedRuleId        RULE_ENTRY.RULE_ENTRY_ID%TYPE;
-- l_iPeriodId               PERIOD.ACC_PERIOD%TYPE;
 l_iRollingPeriod          PERIOD.ACC_PERIOD%TYPE;
 l_iRollingDiff            NUMBER(11,0);  
 l_iPaymentSource          NUMBER(11,0);
 
 l_iPeriodMonth1           PERIOD.ACC_PERIOD%TYPE;
 l_iPeriodMonth2           PERIOD.ACC_PERIOD%TYPE;
 l_iPeriodMonth3           PERIOD.ACC_PERIOD%TYPE;
 
 l_iPrognosisId            PROGNOSIS.PROGNOSIS_ID%TYPE;
 l_iLiquidityReportLineId  REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
 l_iNotToBeSpecifiedOnDay  REPORT_LEVEL_3.LIQUDITY_DO_NOT_SPECIFY_ON_DAY%TYPE;
 l_iIncludeVoucherTemplate NUMBER(11,0);
 l_iOrgLevel               NUMBER(11,0);
 
 l_iFetchFromPreModule  NUMBER(11,0);
 l_iFetchFromBudget     NUMBER(11,0);
 l_iFetchFromLTP        NUMBER(11,0);
 l_iFetchFromGL         NUMBER(11,0);
 l_iFetchFromPrognosis  NUMBER(11,0);   
 l_iFetchFromNoteLine   NUMBER(11,0);
 l_iFetchFromInvestment NUMBER(11,0);
 
 /* Erstattes av l_iFetchFromXXXXX
 
 l_iUseGLAsSrcForAccounts         NUMBER(11,0);
 l_iUseBudgetAsSrcForAccounts     NUMBER(11,0);
 l_iUseProgAsSrcForAccounts       NUMBER(11,0);
 l_iUseLTPAsSrcForAccounts        NUMBER(11,0);
 l_iUseNoteLineAsSrcForAccounts   NUMBER(11,0);
 l_iUseInvestAsSrcForAccounts     NUMBER(11,0);
 */
 
 l_bUsePaymentSourceMatrix    RULE_ENTRY.USE_RULE_PERIOD_PAYMENT_MATRIX%TYPE;
 l_bShiftToPreviousWorkingDay RULE_ENTRY.SHIFT_TO_PREVIOUS_WORKING_DAY%TYPE;
 l_bShiftToNextWorkingDay     RULE_ENTRY.SHIFT_TO_NEXT_WORKING_DAY%TYPE;
 l_dtCurrentRolling           CALENDAR.CALENDAR_DATE%TYPE;
 l_iIsHoliday                 NUMBER(11,0);
 l_iPaymentFrequencyId        RULE_ENTRY.PAYMENT_FREQUENCY_ID%TYPE;
 l_iPaymentMonthNo            RULE_ENTRY.PAYMENT_MONTH_NO%TYPE;
 l_iPaymentDayNo              RULE_ENTRY.PAYMENT_DAY_NO%TYPE;
 l_iManualEditedRowCount      NUMBER(11,0); -- For sjekke om det finnes manuelt registrerte poster
 l_iMatrixSource              NUMBER(11,0); --Brukes som kildeindikator for beregning 
 l_iPaymentPeriodCount        NUMBER(11,0);
 
 l_strR3Name                 REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 
 l_rliquidity_entry_mth_item_id LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE;  -- For å genere id ved flytting fra tmp til prod
 
 -- Finn alle konteringsregler for likvidtet
 CURSOR l_curLiquidityRule IS 
   SELECT rule_entry_id 
     FROM rule_entry 
    WHERE rule_type_id = 3                       -- LIKVIDITET
      AND hard_coded_db_proc IS NULL    -- IKKE TA REGLER SOM ER SPESIELLE, EKS MANUELLE, HARDKODEDE ETC
      AND use_internal_calculation = 0           -- BRUK INTERN KALKULASJON = FALSE 
     -- AND rule_entry_id ='C00D0DC0F8B5E449B5D412CB65772BBE'
   ORDER BY rule_entry_order; 
   
 -- Finn hardkodede konteringsregler for likvidtet
 CURSOR l_curHardCodedLiquidityRule ( i_iFormulaId RULE_ENTRY.hard_coded_db_proc%TYPE ) IS
   SELECT rule_entry_id 
     FROM rule_entry 
    WHERE rule_type_id = 3                        -- LIKVIDITET
      AND hard_coded_db_proc = i_iFormulaId
   ORDER BY rule_entry_order; 

 -- FINN ALLE R3 LINJER FOR LIKVIDITET FOR EN GITT KONTERINGSREGEL
 /* OIG 31.08.15 Endret til å ta høyde for en regel pr r3 pr selskap
 CURSOR l_curLiquidityR3ForRuleEntry ( i_rRuleId RULE_ENTRY.RULE_ENTRY_ID%TYPE ) IS
   SELECT report_level_3_id 
     FROM report_level_3 
    WHERE rule_id_liquidity = i_rRuleId
      AND report_type_id    = 6;  -- LIKVIDITET 
 */
 CURSOR l_curLiquidityR3ForRuleEntry ( i_rRuleId RULE_ENTRY.RULE_ENTRY_ID%TYPE, i_strCompanyId COMPANY.COMPANY_ID%TYPE ) IS
   SELECT rel.report_level_3_id 
     FROM r3_rule_company_relation rel, report_level_3 r3
    WHERE rel.report_level_3_id  = r3.report_level_3_id 
      AND rel.rule_id            = i_rRuleId
      AND rel.company_id        = i_strCompanyId
      AND rel.is_enabled        = 1
      AND r3. report_type_id    = 6;  -- LIKVIDITET 
      
 CURSOR l_curPaymentPeriodOperator (i_rRuleId RULE_ENTRY.RULE_ENTRY_ID%TYPE , i_iRollingPeriod PERIOD.ACC_PERIOD%TYPE) IS
 --BEGIN
    SELECT * --logical_operator 
      FROM rule_period_payment_src_calc 
     WHERE rule_period_payment_id IN ( SELECT RULE_PERIOD_PAYMENT_ID 
                                         FROM RULE_PERIOD_PAYMENT 
                                        WHERE rule_entry_id  = i_rRuleId --'C00D0DC0F8B5E449B5D412CB65772BBE' 
                                          AND period_payment = SUBSTR(i_iRollingPeriod,5,2));
  --EXCEPTION WHEN TOO_MANY_ROWS THEN DBMS_OUTPUT.PUT_LINE('Regel: ' || i_rRuleId || ' - Periode: ' || i_iRollingPeriod);
  --END;

   l_recRulePeriodPaymentSrcCalc l_curPaymentPeriodOperator%ROWTYPE;
 
 -- FINN ALLE RULLERENDE PERIODER - 12 STK     
 CURSOR l_curRollingPeriod ( i_rLiquidityId LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE ) IS
   SELECT acc_period 
     FROM period 
    WHERE date_from >= ( SELECT date_from  
                           FROM period   
                          WHERE acc_period = ( SELECT acc_period 
                                                 FROM period 
                                                WHERE date_from = ( SELECT ADD_MONTHS(date_from,1) 
                                                                      FROM period 
                                                                     WHERE acc_period = ( SELECT period 
                                                                                            FROM liquidity_entry_head
                                                                                           WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                         )
                                                                  )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                 
                                             )
                       )
      AND date_from <= ( SELECT date_from
                            FROM period   
                           WHERE acc_period = ( SELECT acc_period 
                                                  FROM period 
                                                 WHERE date_from = ( SELECT ADD_MONTHS(date_from,12) 
                                                                       FROM period 
                                                                       WHERE acc_period = ( SELECT period 
                                                                                              FROM liquidity_entry_head
                                                                                             WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                          )
                                                                   )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                                                               
                                              )
                       )
      AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
 
 -- FINN ALLE RADER SOM SKAL SPESIFISERES PÅ… DAG, DVS DE TRE FØRSTE MND
 CURSOR l_curMonthToBeSpecifiedToDay ( i_rLiquidityId LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE ) IS
 SELECT liquidity_entry_mth_item_id
   FROM liquidity_entry_mth_item 
  WHERE liquidity_entry_head_id = i_rLiquidityId
    AND period IN (l_iPeriodMonth1,l_iPeriodMonth2,l_iPeriodMonth3)
    ORDER BY period;
    
BEGIN
  g_ReturnCode := -1;
  
  -- KONVERTER GUID TO RAW FOR Å FÅ RIKTIG ID
  --SJEKK FORMAT PÅ INNPARAMETER OG KONVERTER GUID TO RAW FOR Å FÅ RIKTIG ID DERSOM NØDVENDIG
  IF INSTR(i_strParam,'-') <> 0 THEN l_rLiquidityId := g_guidtoraw(i_strParam); ELSE l_rLiquidityId := i_strParam; END IF;
  
  -- SJEKK OM VI FINNER LIKVIDITETSPROGNOSEN
  SELECT count(*) INTO l_iJournalCount FROM liquidity_entry_head WHERE liquidity_entry_head_id =  l_rLiquidityId;
  IF l_iJournalCount <> 1 THEN 
    RAISE l_exNoJournalFound;
  END IF;
   
  -- HENT SELSKAP OG PERIODE FRA LIKVIDITETSPROGNOSEN
  SELECT company_id INTO g_strCompanyId FROM liquidity_entry_head WHERE liquidity_entry_head_id =  l_rLiquidityId;
  SELECT period     INTO g_iPeriodId   FROM liquidity_entry_head WHERE liquidity_entry_head_id =  l_rLiquidityId;
  -- FINN DE FØRSTE TRE PERIODENE (FOR UTREGNING PÅ DAG)
  SELECT acc_period 
    INTO l_iPeriodMonth1 
    FROM period 
   WHERE date_from = ( SELECT date_from FROM period  WHERE acc_period = 
                       ( SELECT acc_period FROM period  WHERE date_from = 
                         ( SELECT ADD_MONTHS(date_from,1) FROM period WHERE acc_period = 
                           ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = l_rLiquidityId))
                           AND SUBSTR(acc_period,5,2) NOT IN ('00','13')))
     AND SUBSTR(acc_period,5,2) NOT IN ('00','13');                           

  SELECT acc_period 
    INTO l_iPeriodMonth2 
    FROM period 
   WHERE date_from = ( SELECT date_from FROM period  WHERE acc_period = 
                       ( SELECT acc_period FROM period  WHERE date_from = 
                         ( SELECT ADD_MONTHS(date_from,2) FROM period WHERE acc_period = 
                           ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = l_rLiquidityId))
                           AND SUBSTR(acc_period,5,2) NOT IN ('00','13')))
     AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
     
  SELECT acc_period 
    INTO l_iPeriodMonth3
    FROM period 
   WHERE date_from = ( SELECT date_from FROM period  WHERE acc_period = 
                       ( SELECT acc_period FROM period  WHERE date_from = 
                         ( SELECT ADD_MONTHS(date_from,3) FROM period WHERE acc_period = 
                           ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = l_rLiquidityId))
                           AND SUBSTR(acc_period,5,2) NOT IN ('00','13')))
     AND SUBSTR(acc_period,5,2) NOT IN ('00','13');

  -- FINN PROGNOSE FOR GJELDENDE LIKVIDITETSPROGNOSE
  -- Denne kan fjernes da situasjonen håndteres i Genus.
 /*
  BEGIN
    SELECT prognosis_id 
      INTO l_iPrognosisId 
      FROM prognosis 
     WHERE company_id = g_strCompanyId
       AND period     = g_iPeriodId;
  EXCEPTION
  WHEN NO_DATA_FOUND THEN RAISE l_exNoPrognosisFound;
  END ;
  */
  -- Finn siste godkjente prognose  
  SELECT prognosis_id INTO l_iPrognosisId  
    FROM ( SELECT prognosis_id 
              FROM prognosis 
             WHERE company_id = g_strCompanyId
               AND prognosis_status_tp = 3
            ORDER BY period DESC
          )
  WHERE rownum < 2;   
       

  -- FJERN TIDLIGERE BEREGNEDE RADER
  DELETE FROM liquidity_entry_mth_item_tmp;
  DELETE FROM liquidity_entry_mth_salary_tmp;
  
  DELETE 
    FROM liquidity_entry_mth_item 
   WHERE liquidity_entry_head_id = l_rLiquidityId
     AND edited_by_user = 0   -- IKKE FJERN MANUELT ENDREDE RADER
     AND nvl(source_id,1) <> 2 -- IKKE FJERN INFO HENTET FRA BANK
     AND report_level_3_id NOT IN ( SELECT rel.report_level_3_id 
                                       FROM r3_rule_company_relation rel, report_level_3 r3 
                                      WHERE rel.report_level_3_id  = r3.report_level_3_id 
                                        AND rel.company_id = g_strCompanyId
                                        AND rel.is_enabled = 1
                                        AND r3.report_type_id = 6   -- LIKVIDITET
                                        AND rel.rule_id IN ( SELECT rule_entry_id FROM rule_entry WHERE hard_coded_db_proc = 1 )); -- IKKE TA MED R3 rader som er markert med databaseprosedye "1 - Manuell registrering"
                                      
  DELETE 
    FROM liquidity_entry_day_item 
   WHERE liquidity_entry_head_id = l_rLiquidityId
     AND edited_by_user = 0  -- IKKE FJERN MANUELT ENDREDE RADER
     AND nvl(source_id,1) <> 2 -- IKKE FJERN INFO HENTET FRA BANK
     AND report_level_3_id NOT IN ( SELECT rel.report_level_3_id 
                                       FROM r3_rule_company_relation rel, report_level_3 r3 
                                      WHERE rel.report_level_3_id  = r3.report_level_3_id 
                                        AND rel.company_id = g_strCompanyId
                                        AND rel.is_enabled = 1                                        
                                        AND r3.report_type_id = 6   -- LIKVIDITET
                                        AND rel.rule_id IN ( SELECT rule_entry_id FROM rule_entry WHERE hard_coded_db_proc = 1 )); -- IKKE TA MED R3 rader som er markert med databaseprosedye "1 - Manuell registrering"
                                       
  COMMIT;                                       
  
  
  OPEN l_curLiquidityRule;
  FETCH l_curLiquidityRule INTO l_rRuleId;
  WHILE l_curLiquidityRule%FOUND LOOP
  
     -- Sjekk om regelen skal hente data fra forsystem - støtte
     SELECT count(*) INTO l_iFetchFromPreModule    FROM rule_r3_for_pre_module_assoc WHERE rule_id = l_rRuleId;  
     -- Sjekk om regelen skal hente data fra Budsjett
     SELECT count(*) INTO l_iFetchFromBudget       FROM rule_budget_assoc            WHERE rule_id = l_rRuleId;  
     -- Sjekk om regelen skal hente data fra LTP
     SELECT count(*) INTO l_iFetchFromLTP          FROM rule_ltp_assoc               WHERE rule_id = l_rRuleId;  
     -- Sjekk om regelen skal hente data fra hovedboken
     SELECT count(*) INTO l_iFetchFromGL           FROM rule_gl_assoc                WHERE rule_id = l_rRuleId;  -- l_iLiqudityFromAccounts --> l_iFetchFromGL
     -- Sjekk om regelen skal hente data fra prognose
     SELECT count(*) INTO l_iFetchFromPrognosis    FROM rule_prognosis_assoc         WHERE rule_id = l_rRuleId;
     -- Sjekk om regelen skal hente data fra notelinje
     SELECT count(*) INTO l_iFetchFromNoteLine FROM rule_note_line_assoc             WHERE rule_id = l_rRuleId;
     -- Sjekk om regelen skal hente data fra investering
     SELECT count(*) INTO l_iFetchFromInvestment   FROM rule_investment_progno_assoc WHERE rule_id = l_rRuleId;

    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
       -- For debug
       SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = l_iLiquidityReportLineId;
      -- Sjekk om det er betalinger som skal utføres i gjeldende periode for regel og R3
      -- Bruke tilknytning for betalingsperioder eller direkte på regelen?
      SELECT use_rule_period_payment_date  INTO g_bUsePaymentPeriodAssoc     FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Bruke kildematrise?
      SELECT use_rule_period_payment_matrix INTO l_bUsePaymentSourceMatrix   FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Sjekk om betaling skal flyttes til nærmeste forrige arbeisdag
      SELECT shift_to_previous_working_day INTO l_bShiftToPreviousWorkingDay FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Eller om betaling skal flyttes til nærmeste neste arbeisdag
      SELECT shift_to_next_working_day     INTO l_bShiftToNextWorkingDay     FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Hent betalingsfrekvens for regel
      SELECT NVL(payment_frequency_id,1)   INTO l_iPaymentFrequencyId        FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Hent betalingsmåned - benyttes dersom frekvens er årlig
      SELECT payment_month_no              INTO l_iPaymentMonthNo            FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Hent betalingsdag 
      SELECT payment_day_no                INTO l_iPaymentDayNo              FROM rule_entry WHERE rule_entry_id = l_rRuleId;
      
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP

          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;
        
        --Gå ut hvis det er manuelle rader
        IF l_iManualEditedRowCount > 0 THEN 
           RETURN;
        END IF;
        
           l_iPaymentSource              := 1;
         /* DISABLED 25022016 grunnet endringer på bakgrunn av møte med Annte og Brit 28.01.2016 
         Koden nedenfor er tidligere benyttet for angivelse av kilde for Brutto fakturerte nettinntekter - Dobbeltklikk på betalingsperioderaden
         -- Finn diff mellom den rullerende perioden og gjeldende likviditetsprognose
         SELECT l_iRollingPeriod - g_iPeriodId INTO l_iRollingDiff FROM DUAL;
         -- Setter default kilde
         l_iPaymentSource              := 1;
         l_recRulePeriodPaymentSrcCalc := null;
         
         FOR rec IN l_curPaymentPeriodOperator (l_rRuleId,l_iRollingPeriod)
         LOOP
           CASE rec.logical_operator
             WHEN 1 THEN
               BEGIN
                  SELECT * INTO l_recRulePeriodPaymentSrcCalc
                   FROM rule_period_payment_src_calc 
                  WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                     FROM rule_period_payment 
                                                    WHERE rule_entry_id = l_rRuleId 
                                                      AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                    AND l_iRollingDiff = rule_source_limit
                    AND logical_operator = 1;
                 EXCEPTION WHEN NO_DATA_FOUND THEN null;
               END;
             WHEN 2 THEN
               BEGIN
                  SELECT * INTO l_recRulePeriodPaymentSrcCalc
                   FROM rule_period_payment_src_calc 
                  WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                     FROM rule_period_payment 
                                                    WHERE rule_entry_id = l_rRuleId 
                                                      AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                    AND l_iRollingDiff <> rule_source_limit
                    AND logical_operator = 2;
                 EXCEPTION WHEN NO_DATA_FOUND THEN null;
               END;
             WHEN 3 THEN
             BEGIN
                 SELECT * INTO l_recRulePeriodPaymentSrcCalc
                 FROM rule_period_payment_src_calc 
                WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                   FROM rule_period_payment 
                                                  WHERE rule_entry_id = l_rRuleId 
                                                    AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                  AND l_iRollingDiff > rule_source_limit
                  AND l_iRollingDiff < NVL(rule_source_limit_2,50)  --- Denne må implementeres grudigere
                  AND logical_operator = 3;
                    EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;
             WHEN 4 THEN
             BEGIN
                 SELECT * INTO l_recRulePeriodPaymentSrcCalc
                 FROM rule_period_payment_src_calc 
                WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                   FROM rule_period_payment 
                                                  WHERE rule_entry_id = l_rRuleId 
                                                    AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                  AND l_iRollingDiff >= rule_source_limit
                  AND l_iRollingDiff < NVL(rule_source_limit_2,50)
                  AND logical_operator = 4;
                    EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;
             WHEN 5 THEN
             BEGIN
                 SELECT * INTO l_recRulePeriodPaymentSrcCalc
                 FROM rule_period_payment_src_calc 
                WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                   FROM rule_period_payment 
                                                  WHERE rule_entry_id = l_rRuleId 
                                                    AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                  AND l_iRollingDiff < rule_source_limit
                  AND logical_operator = 5;
                  EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;  
             WHEN 6 THEN
                BEGIN
                   SELECT * INTO l_recRulePeriodPaymentSrcCalc
                    FROM rule_period_payment_src_calc 
                   WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                      FROM rule_period_payment 
                                                     WHERE rule_entry_id = l_rRuleId 
                                                       AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                    AND l_iRollingDiff <= rule_source_limit
                    AND logical_operator = 6;
                  EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;
             ELSE NULL;
           END CASE;
         
         END LOOP;         
         
         IF l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id IS NOT NULL THEN l_iPaymentSource := l_recRulePeriodPaymentSrcCalc.rule_source_id; END IF;
 */
 
        IF g_bUsePaymentPeriodAssoc = 0 THEN
          --Ikke bruk betalingsperiodetilknytning
          CASE l_iPaymentFrequencyId 
            WHEN 1 THEN -- Månedlig (default)
              -- IF ((l_iFetchFromGL > 0) AND (l_iRowCount = 0)) THEN 
             --     GenerateRowFromAccounts( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); END IF;
               IF ((l_iFetchFromPrognosis > 0) AND (l_iManualEditedRowCount = 0)) THEN 
                  GenerateRowFromPrognosis( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromNoteLine  > 0) AND (l_iManualEditedRowCount = 0)) THEN 
                  GenerateRowFromNoteLine ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromInvestment  > 0) AND (l_iManualEditedRowCount = 0)) THEN 
                  GenerateRowFromInvestment ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;

            WHEN 2 THEN -- Kvartalsvis
              null;
            WHEN 3 THEN -- Årlig
               IF ((l_iFetchFromPrognosis > 0) AND (l_iManualEditedRowCount = 0) AND (l_iPaymentMonthNo = to_number(substr(l_iRollingPeriod,5,2)))) THEN 
                  GenerateRowFromPrognosis( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromNoteLine  > 0) AND (l_iManualEditedRowCount = 0) AND (l_iPaymentMonthNo = to_number(substr(l_iRollingPeriod,5,2)))) THEN 
                  GenerateRowFromNoteLine ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromInvestment  > 0) AND (l_iManualEditedRowCount = 0) AND (l_iPaymentMonthNo = to_number(substr(l_iRollingPeriod,5,2)))) THEN 
                  GenerateRowFromInvestment ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;

            ELSE null; -- Do nothing
          END CASE;
        ELSE -- BRUKE BETALINGSPERIODER OG IKKE HARDKODET

          BEGIN    -- Er det utbetalinger på denne rullerende periode? Hopp ut dersom det ikke er det 
            SELECT COUNT(DISTINCT period_payment) INTO l_iPaymentPeriodCount
              FROM rule_period_payment 
             WHERE rule_entry_id = l_rRuleId
               AND period_payment =  substr(l_iRollingPeriod,5,2);        
          EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
          END;

          CASE l_iPaymentFrequencyId 
            WHEN 1 THEN -- Månedlig (default)
               IF l_bUsePaymentSourceMatrix = 1 THEN -- Bruk kildematrise
               
                   -- Fetch info from source matrix (1 - Regnskap, 2 - Prognose, 3 - Delt)
                   SELECT NVL(source_id,1) INTO l_iMatrixSource
                     FROM rule_calc_matrix_liquidity 
                    WHERE rule_entry_id = l_rRuleId
                      AND liq_entry_head_period = SUBSTR(g_iPeriodId,5,2) 
                      AND liq_entry_head_rolling_period = SUBSTR(l_iRollingPeriod,5,2);
               
                 IF ((l_iMatrixSource = 1) AND (l_iFetchFromGL > 0)) THEN 
                      GenerateRowFromAccounts( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;

                 IF ((l_iMatrixSource = 2) AND (l_iFetchFromPrognosis > 0)) THEN 
                      GenerateRowFromPrognosis( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); 
                 END IF;

                 IF ((l_iMatrixSource = 3) AND (l_iFetchFromGL > 0) AND (l_iFetchFromPrognosis = 1)) THEN 
                      GenerateRowFromGL5050( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                      GenerateRowFromPrognosis5050( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); 
                 END IF;
               END IF; -- l_bUsePaymentSourceMatrix = 1

              IF l_bUsePaymentSourceMatrix = 0 THEN -- Ikke bruk kildematrise

                 IF ((l_iFetchFromGL > 0) AND (l_iPaymentSource = 1)) THEN 
                    GenerateRowFromAccounts( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;
                 IF ((l_iFetchFromBudget > 0) AND (l_iPaymentSource = 2)) THEN 
                    GenerateRowFromBudget( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;
                 IF l_iFetchFromPreModule > 0 THEN 
                    GenerateRowFromPreModule( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;
              END IF;
            WHEN 2 THEN null; 
          END CASE;
         END IF; --l_bUsePaymentPeriodAssoc = 0 BRUKE BETALINGSPERIODER?

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;
    
  
  FETCH l_curLiquidityRule INTO l_rRuleId;
  END LOOP;
  CLOSE l_curLiquidityRule;
  
  -- KALL PROSEDYRER FOR HARDKODEDE RADER
  -- Sjekke om prosedyre for lønn er benyttet
  -- Tøm temporær tabell
  DELETE liquidity_entry_item_tax_tmp;
  DELETE liquidity_entry_mth_salary_tmp;
  
  OPEN l_curHardCodedLiquidityRule ( 993 );   --993 = LØNN
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
      
         -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

         IF l_iManualEditedRowCount = 0 THEN 
           GenerateForLonn         (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
         END IF;
      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;
  
  -- Sjekke om prosedyre for MVA er benyttet
  OPEN l_curHardCodedLiquidityRule ( 994 );   --994 = MVA
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForMVA (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  OPEN l_curHardCodedLiquidityRule ( 992 );   --993 = ELAVGIFT
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
      
         -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

         IF l_iManualEditedRowCount = 0 THEN 
           GenerateForELAvgift         (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
         END IF;
      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  -- Sjekke om prosedyre for Nettinntekter Husholdning/Privat er benyttet
  OPEN l_curHardCodedLiquidityRule ( 9912 );   --9912 = Nettinntekter Husholdning/Privat
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForNettleiePrivat (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  -- Sjekke om prosedyre for ENOVA er benyttet
  OPEN l_curHardCodedLiquidityRule ( 995 );   --995 = ENOVA
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForEnovaAvgift (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  -- Sjekke om prosedyre for Grunnrente-, naturressurs og overskuddsskatt er benyttet
  OPEN l_curHardCodedLiquidityRule ( 996 );   --996 = Grunnrente-, naturressurs og overskuddsskatt
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForGrunnNaturOverSkatt (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;


  -- END: KALL PROSEDYRER FOR HARDKODEDE RADER
  -- FLYTT TEMP-RADER TIL PROD FOR MÅNED
    
  INSERT INTO liquidity_entry_mth_item
         --(liquidity_entry_mth_item_id
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount
         ,liquidity_entry_mth_comment)
    SELECT
       --l_rliquidity_entry_mth_item_id --'E1' --sys_guid()  --Fjernet: Håndtert av default verdi på kolonnen
      liquidity_entry_head_id
      ,report_level_3_id
      ,period
      ,SUM(amount)
      ,null
    FROM liquidity_entry_mth_item_tmp
    GROUP BY
      --l_rliquidity_entry_mth_item_id  --'E1'  --sys_guid()
      liquidity_entry_head_id
      ,report_level_3_id
      ,period;
  
    UPDATE liquidity_entry_mth_item 
       SET liquidity_entry_mth_item_id = sys_guid() 
     WHERE liquidity_entry_mth_item_id IS NULL
       AND liquidity_entry_head_id = l_rLiquidityId;
  
  COMMIT;
  
  -- SPESIFISER MND NED TIL DAG FOR DE TRE FØRSTE MND
  OPEN l_curMonthToBeSpecifiedToDay ( l_rLiquidityId );
  FETCH l_curMonthToBeSpecifiedToDay INTO l_rCurrentMonthRow;
  WHILE l_curMonthToBeSpecifiedToDay%FOUND LOOP
  
    -- Sjekk om raden er endret manuelt
    SELECT count(*) INTO l_iManualEditedRowCount
      FROM liquidity_entry_day_item 
     WHERE liquidity_entry_mth_item_id = l_rCurrentMonthRow
       AND edited_by_user = 1;
       
    BEGIN
      SELECT liqudity_do_not_specify_on_day INTO l_iNotToBeSpecifiedOnDay
        FROM report_level_3 WHERE report_level_3_id = ( SELECT report_level_3_id 
                                                          FROM liquidity_entry_mth_item 
                                                         WHERE liquidity_entry_mth_item_id = l_rCurrentMonthRow );
      EXCEPTION WHEN NO_DATA_FOUND THEN l_iNotToBeSpecifiedOnDay := 0;
    END; 
       
    IF ((l_iManualEditedRowCount = 0) AND (l_iNotToBeSpecifiedOnDay <> 1)) THEN
      GenerateRowForDay ( l_rCurrentMonthRow );
    END IF;
  
  FETCH l_curMonthToBeSpecifiedToDay INTO l_rCurrentMonthRow;
  END LOOP;
  CLOSE l_curMonthToBeSpecifiedToDay;


  -- KALL PROSEDYRE FOR IB BANK, DENNE MÅ KJØRES HELT TIL SLUTT DA DENNE BRUKER TIDLIGERE BEREGNEDE TALL
  -- BARE EN LINJE MED DENNE REGELEN
  SELECT rule_entry_id     INTO l_rHardCodedRuleId       FROM rule_entry     WHERE hard_coded_db_proc = 1000;
  BEGIN
    SELECT report_level_3_id INTO l_iLiquidityReportLineId FROM r3_rule_company_relation  WHERE rule_id = l_rHardCodedRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iLiquidityReportLineId := NULL;
  END;
  
   IF l_rLiquidityId           IS NOT NULL
  AND l_rHardCodedRuleId       IS NOT NULL
  AND l_iPrognosisId           IS NOT NULL
  AND l_iLiquidityReportLineId IS NOT NULL THEN
  
     GenerateForIBBank (l_rLiquidityId, l_rHardCodedRuleId, l_iPrognosisId, l_iLiquidityReportLineId, null, null);
  
  END IF;

  EXCEPTION 
    --WHEN l_exNoPrognosisFound THEN raise_application_error (-20601,'Finner ingen godkjent prognose for selskapet for periode ' || g_iPeriodId || '.' || chr(13) || chr(10)|| chr(13) || chr(10));
    WHEN l_exNoJournalFound   THEN raise_application_error (-20602,'Finner ingen likviditetsjournal. Kontakt systemansvarlig. ' || chr(13) || chr(10)|| chr(13) || chr(10));
    WHEN l_exOther            THEN raise_application_error (-20603,'Ukjent feil. Kontakt systemansvarlig. ' || chr(13) || chr(10)|| chr(13) || chr(10));
END Generate;

PROCEDURE GenerateRowFromPreModule ( i_rLiquidityId         IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                    i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                    i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                    i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                    i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                    i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                    i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
 l_iCurrentPeriod      PERIOD.ACC_PERIOD%TYPE;
 l_dtStartRollingDate  PERIOD.DATE_FROM%TYPE;
 l_dtEndRollingDate    PERIOD.DATE_TO%TYPE;
 l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
 l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
 l_strR3Name           REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 l_iYearOffset NUMBER(11,0);
 
 l_iUseSameNumberForAllMonths NUMBER(11,0);

BEGIN
  /* Initialiser parametre */
  SELECT period     INTO l_iCurrentPeriod      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  --SELECT company_id INTO l_strCompanyId        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT date_from  INTO l_dtStartRollingDate  FROM period    WHERE acc_period  = (SELECT acc_period FROM period WHERE date_from = (SELECT ADD_MONTHS(date_from,1) FROM period where acc_period = l_iCurrentPeriod AND substr(acc_period,5,2) NOT IN ('00','13')) AND substr(acc_period,5,2) NOT IN ('00','13'));
  SELECT date_from  INTO l_dtEndRollingDate    FROM period    WHERE date_from    = ADD_MONTHS(l_dtStartRollingDate,12) AND substr(acc_period,5,2) NOT IN ('00','13');
  SELECT acc_period INTO l_iFirstRollingPeriod FROM period    WHERE date_from    = l_dtStartRollingDate                AND substr(acc_period,5,2) NOT IN ('00','13');
  -- For debug
  SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = i_iLiquidityReportLineId;
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
     WHERE rule_entry_id  = i_rRuleId
       AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Skal beløpet fremskrives?  
  BEGIN
    SELECT NVL(liqudity_use_same_for_all_mths,0) INTO l_iUseSameNumberForAllMonths FROM rule_entry WHERE rule_entry_id = i_rRuleId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iUseSameNumberForAllMonths := 0;
  END;
  
  IF l_iUseSameNumberForAllMonths = 0 THEN
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(pre_msf.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM pre_module_supporting_figures pre_msf, 
            rule_period_payment rp, 
            rule_r3_for_pre_module_assoc gla
      WHERE pre_msf.report_level_3_id       = gla.report_level_3_id
        AND rp.rule_entry_id                = gla.rule_id
        AND substr(pre_msf.period,5,2)      = rp.period_basis
        AND rp.rule_entry_id                = i_rRuleId 
        AND rp.period_payment               = l_strPaymentPeriod
        AND pre_msf.liquidity_entry_head_id = i_rLiquidityId
        AND substr(pre_msf.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(pre_msf.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset;

  END IF;
  
  /*
  IF l_iUseSameNumberForAllMonths = 1 THEN
    IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
    ELSE
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(amount)
       FROM liquidity_entry_mth_item_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id = i_iLiquidityReportLineId
         AND period = (SELECT acc_period 
                         FROM period 
                        WHERE date_from = (SELECT ADD_MONTHS(date_from,-1) FROM period WHERE acc_period = i_iRollingPeriod AND substr(acc_period,5,2) NOT IN ('00','13'))
                          AND substr(acc_period,5,2) NOT IN ('00','13') 
                      )
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
    
    END IF;
  END IF;
 */
  COMMIT;
END GenerateRowFromPreModule;



PROCEDURE GenerateRowFromAccounts ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                     i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                    i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                    i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                    i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                    i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                    i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
 l_iCurrentPeriod      PERIOD.ACC_PERIOD%TYPE;
 l_dtStartRollingDate  PERIOD.DATE_FROM%TYPE;
 l_dtEndRollingDate    PERIOD.DATE_TO%TYPE;
 l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
 l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
 l_strR3Name           REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 l_iYearOffset NUMBER(11,0);
 
 l_iUseSameNumberForAllMonths NUMBER(11,0);

BEGIN
  /* Initialiser parametre */
  SELECT period     INTO l_iCurrentPeriod      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  --SELECT company_id INTO l_strCompanyId        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT date_from  INTO l_dtStartRollingDate  FROM period    WHERE acc_period  = (SELECT acc_period FROM period WHERE date_from = (SELECT ADD_MONTHS(date_from,1) FROM period where acc_period = l_iCurrentPeriod AND substr(acc_period,5,2) NOT IN ('00','13')) AND substr(acc_period,5,2) NOT IN ('00','13'));
  SELECT date_from  INTO l_dtEndRollingDate    FROM period    WHERE date_from    = ADD_MONTHS(l_dtStartRollingDate,12) AND substr(acc_period,5,2) NOT IN ('00','13');
  SELECT acc_period INTO l_iFirstRollingPeriod FROM period    WHERE date_from    = l_dtStartRollingDate                AND substr(acc_period,5,2) NOT IN ('00','13');
  -- For debug
  SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = i_iLiquidityReportLineId;
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
     WHERE rule_entry_id  = i_rRuleId
       AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Skal beløpet fremskrives?  
  BEGIN
    SELECT NVL(liqudity_use_same_for_all_mths,0) INTO l_iUseSameNumberForAllMonths FROM rule_entry WHERE rule_entry_id = i_rRuleId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iUseSameNumberForAllMonths := 0;
  END;
  
  IF l_iUseSameNumberForAllMonths = 0 THEN
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
  END IF;
 
   -- Her fremskrives beløpet
  IF l_iUseSameNumberForAllMonths = 1 THEN
    IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
    ELSE
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(amount)
       FROM liquidity_entry_mth_item_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id = i_iLiquidityReportLineId
         AND period = (SELECT acc_period 
                         FROM period 
                        WHERE date_from = (SELECT ADD_MONTHS(date_from,-1) FROM period WHERE acc_period = i_iRollingPeriod AND substr(acc_period,5,2) NOT IN ('00','13'))
                          AND substr(acc_period,5,2) NOT IN ('00','13') 
                      )
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
    
    END IF;
  END IF;
 
  COMMIT;
END GenerateRowFromAccounts;

PROCEDURE GenerateRowFromGL5050 ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                              i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                              i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                              i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                              i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                              i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                              i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
 l_iCurrentPeriod      PERIOD.ACC_PERIOD%TYPE;
 l_dtStartRollingDate  PERIOD.DATE_FROM%TYPE;
 l_dtEndRollingDate    PERIOD.DATE_TO%TYPE;
 l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
 l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
 l_strR3Name           REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 l_iYearOffset NUMBER(11,0);
 
 l_iUseSameNumberForAllMonths NUMBER(11,0);
 
 type tblPeriods is table of number(11,0);
 
 l_tblPeriod tblPeriods;

BEGIN
  /* Initialiser parametre */
  SELECT period     INTO l_iCurrentPeriod      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  --SELECT company_id INTO l_strCompanyId        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT date_from  INTO l_dtStartRollingDate  FROM period    WHERE acc_period  = (SELECT acc_period FROM period WHERE date_from = (SELECT ADD_MONTHS(date_from,1) FROM period where acc_period = l_iCurrentPeriod AND substr(acc_period,5,2) NOT IN ('00','13')) AND substr(acc_period,5,2) NOT IN ('00','13'));
  SELECT date_from  INTO l_dtEndRollingDate    FROM period    WHERE date_from    = ADD_MONTHS(l_dtStartRollingDate,12) AND substr(acc_period,5,2) NOT IN ('00','13');
  SELECT acc_period INTO l_iFirstRollingPeriod FROM period    WHERE date_from    = l_dtStartRollingDate                AND substr(acc_period,5,2) NOT IN ('00','13');
  -- For debug
  SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = i_iLiquidityReportLineId;
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
     WHERE rule_entry_id  = i_rRuleId
       AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Skal beløpet fremskrives?  
  BEGIN
    SELECT NVL(liqudity_use_same_for_all_mths,0) INTO l_iUseSameNumberForAllMonths FROM rule_entry WHERE rule_entry_id = i_rRuleId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iUseSameNumberForAllMonths := 0;
  END;
  
  -- Finn  alle grunnlagsperioder 
  /*
  SELECT period_basis BULK COLLECT INTO l_tblPeriod
    FROM rule_period_payment 
   WHERE period_payment = substr(i_iRollingPeriod,5,2)
     AND rule_entry_id  = i_rRuleId;
                                                
   l_tblPeriod.Count/2
  */
  IF l_iUseSameNumberForAllMonths = 0 THEN
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT T.period_basis
                                          FROM (SELECT period_basis FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId order by period_basis) T
                                         WHERE rownum <= (SELECT count(*)/2 FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId))
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
  END IF;
 
   -- Her fremskrives beløpet
  IF l_iUseSameNumberForAllMonths = 1 THEN
    IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT T.period_basis
                                          FROM (SELECT period_basis FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId order by period_basis) T
                                         WHERE rownum <= (SELECT count(*)/2 FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId))
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
    ELSE
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(amount)
       FROM liquidity_entry_mth_item_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id = i_iLiquidityReportLineId
         AND period = (SELECT acc_period 
                         FROM period 
                        WHERE date_from = (SELECT ADD_MONTHS(date_from,-1) FROM period WHERE acc_period = i_iRollingPeriod AND substr(acc_period,5,2) NOT IN ('00','13'))
                          AND substr(acc_period,5,2) NOT IN ('00','13') 
                      )
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
    
    END IF;
  END IF;
 
  COMMIT;
END GenerateRowFromGL5050;

PROCEDURE GenerateRowFromBudget    ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                       i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
  l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_iYearOffset         NUMBER(11,0);
BEGIN
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id  = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;

  IF i_rRulePerPaySrcCalcId IS NULL THEN
      
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(be.budget_amount*NVL(rb.adjustment_factor,0)*NVL(rb.sign_effect,1)) 
       FROM budget_entry be, rule_period_payment rp, rule_budget_assoc rb
      WHERE TO_CHAR(be.budget_date,'MM') = rp.period_basis
        AND rp.rule_entry_id  = i_rRuleId 
        AND rp.period_payment = l_strPaymentPeriod
        AND be.account_id                    = rb.account_id
        AND rb.rule_id                       = i_rRuleId 
        AND be.company_id                  =  g_strCompanyId  --(SELECT company_id         FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId)
        --AND be.account_id                  IN (SELECT account_id         FROM rule_gl_assoc WHERE rule_id = i_rRuleId)
--        AND be.account_id                  IN (SELECT account_id         FROM rule_budget_assoc WHERE rule_id = i_rRuleId)
        AND TO_CHAR(be.budget_date,'YYYY') =  substr(i_iRollingPeriod,0,4)
        AND TO_CHAR(be.budget_date,'MM')   IN (SELECT period_basis 
                                              FROM rule_period_payment 
                                             WHERE rule_entry_id  = i_rRuleId 
                                               AND period_payment = l_strPaymentPeriod);
  ELSE
     -- Bruke kildekontroll for betalingsperioder
     -- Finne årsforskyvning
     SELECT year_offset INTO l_iYearOffset FROM rule_period_payment_src_calc WHERE rule_per_pay_src_calc_id = i_rRulePerPaySrcCalcId;
      
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(be.budget_amount*rb.adjustment_factor*rb.sign_effect) 
       FROM budget_entry be, rule_period_payment rp, RULE_PERIOD_PAYMENT_SRC_CALC rpcalc, rule_budget_assoc rb
      WHERE TO_CHAR(be.budget_date,'MM') = rp.period_basis
        AND rp.rule_entry_id                 = i_rRuleId 
        AND be.account_id                    = rb.account_id
        AND rb.rule_id                       = i_rRuleId 
        AND rp.rule_period_payment_id        = rpcalc.rule_period_payment_id
        AND rpcalc.rule_per_pay_src_calc_id  = i_rRulePerPaySrcCalcId
        AND rp.period_payment                = l_strPaymentPeriod
        AND be.company_id                    =  g_strCompanyId  --(SELECT company_id         FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId)
        --AND be.account_id                  IN (SELECT account_id         FROM rule_gl_assoc WHERE rule_id = i_rRuleId)
        --AND be.account_id                  IN (SELECT account_id         FROM rule_budget_assoc WHERE rule_id = i_rRuleId)
        AND TO_CHAR(be.budget_date,'YYYY') =  substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND TO_CHAR(be.budget_date,'MM')   IN (SELECT period_basis 
                                              FROM rule_period_payment 
                                             WHERE rule_entry_id  = i_rRuleId 
                                               AND period_payment = l_strPaymentPeriod);
  
  END IF;

END GenerateRowFromBudget;

PROCEDURE GenerateRowFromPrognosis ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                      i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                      i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                      i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                      i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                      i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iNoOfMthShift               RULE_ENTRY.NO_OF_MONTH_SHIFT%TYPE;
  l_iNoOfMonthGrouped           RULE_ENTRY.NO_OF_MONTH_GROUPED%TYPE;
  l_iCalcAccYTLiqPeriodThenProg RULE_ENTRY.CALC_ACCOUNT_THEN_PROGNOSIS%TYPE;
  l_iPeriod                     PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iZeroIfNegative             RULE_ENTRY.ZERO_IF_NEGATIVE%TYPE;
  l_iZeroIfPositive             RULE_ENTRY.ZERO_IF_POSITIVE%TYPE;

BEGIN
  -- Beregner Regnskap til og med likviditetsperiode og legger til prognose ut året. (Overstyrer "Antall mnd forskjøvet/gruppert)
  SELECT nvl(calc_account_then_prognosis,0) INTO l_iCalcAccYTLiqPeriodThenProg 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Antall måneder gruppert
  SELECT nvl(no_of_month_grouped,1) INTO l_iNoOfMonthGrouped 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Antall måneder forskjøvet
  SELECT nvl(no_of_month_shift,0) INTO l_iNoOfMthShift 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Hent forskjøvet måned
  SELECT acc_period INTO l_iPeriod 
    FROM period 
   WHERE date_from = ( SELECT add_months(date_from,l_iNoOfMthShift) FROM period WHERE acc_period = i_iRollingPeriod )
     AND substr(acc_period,5,2) NOT IN ('00','13');
  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');
 -- Sett resultat lik 0 dersom negativt beløp
 SELECT nvl(zero_if_negative,0) INTO l_iZeroIfNegative 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
 -- Sett resultat lik 0 dersom positivt beløp
 SELECT nvl(zero_if_positive,0) INTO l_iZeroIfPositive
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;

  IF l_iCalcAccYTLiqPeriodThenProg = 1 THEN
    -- Regnskap
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND substr(gl.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
       AND gl.period             <= ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) --Til og med likviditetsperiode
       AND gl.activity_id        = '2'
     GROUP BY 
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
        
    -- Prognose
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod --pe.period
      ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
    WHERE pe.report_level_3_id  = r.report_level_3_id
      AND pe.prognosis_id       = i_iPrognosisId
      AND substr(pe.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
      AND pe.period             >= l_iFirstRollingPeriod  -- Hittil i år
      AND r.rule_id             = re.rule_entry_id
      AND re.rule_entry_id      = i_rRuleId
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod; --pe.period;

  END IF;

  IF ((l_iNoOfMonthGrouped = 1) AND (l_iCalcAccYTLiqPeriodThenProg = 0)) THEN
      IF ( ( i_iRollingPeriod = l_iFirstRollingPeriod ) AND
           ( l_iNoOfMthShift <> 0 ) )  THEN
        -- Regnskap  
        BEGIN
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod 
            ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
            FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
           WHERE r3a.report_level_3_id = r.report_level_3_id
             AND r.rule_id             = re.rule_entry_id
             AND re.rule_entry_id      = i_rRuleId
             AND gl.account_id         = r3a.account_id
             AND r3a.report_level_3_id = r.report_level_3_id
             AND gl.company_id  = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
             AND gl.period      = g_iPeriodId --( SELECT period     FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) --l_iPreviousRollingPeriod
             AND gl.activity_id = '2'
           GROUP BY 
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod ;
    
        END;
        ELSE
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod --pe.period
            ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
           FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
          WHERE pe.report_level_3_id = r.report_level_3_id
            AND pe.prognosis_id      = i_iPrognosisId
            AND pe.period            = l_iPeriod -- FORSKJØVET IHHT REGEL  i_iRollingPeriod
            AND r.rule_id            = re.rule_entry_id
            AND re.rule_entry_id     = i_rRuleId
          GROUP BY 
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod; --pe.period;
        
      END IF;
  END IF;
  
  IF ((l_iNoOfMonthGrouped = 2) AND (l_iCalcAccYTLiqPeriodThenProg = 0)) THEN --GRUPPERER JAN/FEB, MAR/APR, MAI/JUN osv
   null;
   
  END IF;
  
  IF ((l_iNoOfMonthGrouped = 12) AND (l_iCalcAccYTLiqPeriodThenProg = 0)) THEN -- Summerer hele året
    -- Regnskap
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND substr(gl.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
       AND gl.period             <= l_iPeriod  -- Hittil i år
       AND gl.activity_id        = '2'
     GROUP BY 
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
        
    -- Prognose
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod --pe.period
      ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
    WHERE pe.report_level_3_id  = r.report_level_3_id
      AND pe.prognosis_id       = i_iPrognosisId
      AND substr(pe.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
      AND pe.period             >= l_iFirstRollingPeriod  -- Hittil i år
      AND r.rule_id             = re.rule_entry_id
      AND re.rule_entry_id      = i_rRuleId
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod; --pe.period;

   
  END IF;
  
  COMMIT;
END GenerateRowFromPrognosis;

PROCEDURE GenerateRowFromPrognosis5050 ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                          i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                          i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                          i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iNoOfMthShift               RULE_ENTRY.NO_OF_MONTH_SHIFT%TYPE;
  l_iNoOfMonthGrouped           RULE_ENTRY.NO_OF_MONTH_GROUPED%TYPE;
  l_iCalcAccYTLiqPeriodThenProg RULE_ENTRY.CALC_ACCOUNT_THEN_PROGNOSIS%TYPE;
  l_iPeriod                     PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iZeroIfNegative             RULE_ENTRY.ZERO_IF_NEGATIVE%TYPE;
  l_iZeroIfPositive             RULE_ENTRY.ZERO_IF_POSITIVE%TYPE;
  l_iYearOffset                 RULE_PERIOD_PAYMENT.YEAR_OFFSET%TYPE;

BEGIN
  -- Denne metoden forutsetter bruk av betalingsperioder
  -- Prognose
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
    WHERE pe.report_level_3_id  = r.report_level_3_id
      AND pe.prognosis_id       = i_iPrognosisId
      AND r.rule_id             = re.rule_entry_id
      AND re.rule_entry_id      = i_rRuleId
      AND substr(pe.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
      AND substr(pe.period,5,2) IN ( SELECT T.period_basis
                                         FROM (SELECT period_basis FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId order by period_basis DESC) T
                                        WHERE rownum <= (SELECT count(*)/2 FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId))
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
  
  COMMIT;
END GenerateRowFromPrognosis5050;

PROCEDURE GenerateRowFromNoteLine ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                    i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                    i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                    i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                    i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                    i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount NUMBER(11,0);
BEGIN
  INSERT INTO liquidity_entry_mth_item_tmp
     (liquidity_entry_head_id
     ,report_level_3_id
     ,period
     ,amount)
   SELECT
     i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,pe.period
    ,SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
   FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
  WHERE pne.note_line_id         = r.note_line_id
    AND pne.prognosis_entry_id = pe.prognosis_entry_id
    AND pe.prognosis_id          = i_iPrognosisId
    AND pe.period                = i_iRollingPeriod
    AND r.rule_id                = re.rule_entry_id
    AND re.rule_entry_id         = i_rRuleId
  GROUP BY 
      i_rLiquidityId
     ,i_iLiquidityReportLineId
     ,pe.period;
      
  COMMIT;
END GenerateRowFromNoteLine;

PROCEDURE GenerateRowFromInvestment  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iNoOfMthShift       RULE_ENTRY.NO_OF_MONTH_SHIFT%TYPE;
  l_iNoOfMonthGrouped   RULE_ENTRY.NO_OF_MONTH_GROUPED%TYPE;
  l_iPeriod             PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
BEGIN
  -- Antall måneder gruppert
  SELECT nvl(no_of_month_grouped,1) INTO l_iNoOfMonthGrouped 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  
  -- Antall måneder forskjøvet
  SELECT nvl(no_of_month_shift,0) INTO l_iNoOfMthShift 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Hent forskjøvet måned
  SELECT acc_period INTO l_iPeriod 
    FROM period 
   WHERE date_from = ( SELECT add_months(date_from,l_iNoOfMthShift) FROM period WHERE acc_period = i_iRollingPeriod )
     AND substr(acc_period,5,2) NOT IN ('00','13');
  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');

  IF l_iNoOfMonthGrouped = 1 THEN
      IF ( ( i_iRollingPeriod = l_iFirstRollingPeriod ) AND
           ( l_iNoOfMthShift <> 0 ) )  THEN
        -- Regnskap  
        BEGIN
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod 
            ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
            FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
           WHERE r3a.report_level_3_id = r.report_level_3_id
             AND r.rule_id             = re.rule_entry_id
             AND re.rule_entry_id      = i_rRuleId
             AND gl.account_id         = r3a.account_id
             AND r3a.report_level_3_id = r.report_level_3_id
             AND gl.company_id  = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
             AND gl.period      = l_iPeriod 
             AND gl.activity_id IN ('7','8')
           GROUP BY 
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod ;
    
        END;
        ELSE
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod --pe.period
            ,SUM(pie.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
           FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
          WHERE pie.activity_id      = r.activity_id
            AND pie.prognosis_id     = i_iPrognosisId
            AND pie.period           = l_iPeriod -- FORSKJØVET IHHT REGEL  i_iRollingPeriod
            AND r.rule_id            = re.rule_entry_id
            AND re.rule_entry_id     = i_rRuleId
          GROUP BY 
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod; --pe.period;
        
      END IF;
  END IF;
  
  IF l_iNoOfMonthGrouped = 2 THEN --GRUPPERER JAN/FEB, MAR/APR, MAI/JUN osv
   null;
   
  END IF;
  
  IF l_iNoOfMonthGrouped = 12 THEN -- Summerer hele året
    -- Regnskap
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND gl.company_id         = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND substr(gl.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
       AND gl.period             <= l_iPeriod  -- Hittil i år
       AND gl.activity_id        IN ('7','8')
     GROUP BY 
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
        
    -- Prognose
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod --pe.period
      ,SUM(pie.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
    WHERE pie.activity_id        = r.activity_id
      AND pie.prognosis_id       = i_iPrognosisId
      AND substr(pie.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
      AND pie.period             >= l_iFirstRollingPeriod  -- Hittil i år
      AND r.rule_id              = re.rule_entry_id
      AND re.rule_entry_id       = i_rRuleId
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod; --pe.period;

   
  END IF;
  
  COMMIT;
END GenerateRowFromInvestment;

PROCEDURE GenerateRowForDay ( i_rLiquidityEntryMonth IN LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE
                              
                           /* i_rLiquidityEntryMonth    IN LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE, 
                              i_rLiquidityId            IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                              i_rRuleId                 IN RULE_ENTRY.RULE_ENTRY_ID%TYPE,  
                              i_iLiquidityReportLineId  IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE, 
                              i_iRollingPeriod          IN PERIOD.ACC_PERIOD%TYPE */
                            )
IS
  l_dtDay                    DATE;
  l_dtWorkDay                DATE;
  l_dtLastWorkingDay         DATE;
  l_dtNextToLastWorkingDay   DATE;
  l_iNoOfDaysToBeDistributed NUMBER(11,0);
  l_iNoOfDaysInMth           NUMBER(11,0);  
  l_iCountManualEdited       NUMBER(11,0);  
  l_iEvenDistribution        RULE_ENTRY.EVEN_DISTRIBUTION%TYPE;
  l_iDayNo                   RULE_ENTRY.PAYMENT_DAY_NO%TYPE;
  l_iShiftToPreviousDay      RULE_ENTRY.SHIFT_TO_PREVIOUS_WORKING_DAY%TYPE;
  l_iShiftToNextDay          RULE_ENTRY.SHIFT_TO_NEXT_WORKING_DAY%TYPE;
  l_iPaymentProfile          RULE_ENTRY.PATTERN_OF_PAYMENTS_DAY%TYPE;  
  
  l_rLiquidityHeadId  LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_HEAD_ID%TYPE;
  l_iR3               LIQUIDITY_ENTRY_MTH_ITEM.REPORT_LEVEL_3_ID%TYPE;
  l_iPeriod           LIQUIDITY_ENTRY_MTH_ITEM.PERIOD%TYPE;
  l_iCurrentPeriod    LIQUIDITY_ENTRY_MTH_ITEM.PERIOD%TYPE;
  l_fAmount           LIQUIDITY_ENTRY_MTH_ITEM.AMOUNT%TYPE;
  
  CURSOR l_curDateInMonth ( i_iPeriod PERIOD.ACC_PERIOD%TYPE ) IS
    SELECT to_date(to_char(i_iPeriod) || lpad(to_char(rownum),2,0),'YYYYMMDD')
      FROM all_objects
     WHERE rownum <= (last_day(to_date(to_char(i_iPeriod) || '01','YYYYMMDD'))+1 - to_date(to_char(i_iPeriod) || '01','YYYYMMDD'));
     
  CURSOR l_curWorkDay IS SELECT day FROM liquidity_day_calendar_tmp;
BEGIN
  -- Sjekk om det finnes 

  -- Slett tidligere opprader
  DELETE FROM liquidity_entry_day_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth AND nvl(source_id,1) = 1 AND edited_by_user = 0;
  
   
  -- Hent basisinfo
  SELECT period                  INTO l_iPeriod          FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  SELECT report_level_3_id       INTO l_iR3              FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  SELECT liquidity_entry_head_id INTO l_rLiquidityHeadId FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  SELECT amount                  INTO l_fAmount          FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  -- Hent regelinfo for gjeldende rad
  BEGIN
    SELECT NVL(even_distribution,0) INTO l_iEvenDistribution FROM rule_entry 
     WHERE rule_entry_id = ( SELECT rule_id
                               FROM r3_rule_company_relation 
                              WHERE company_id = g_strCompanyId
                                AND is_enabled = 1
                                AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found THEN l_iEvenDistribution := 0;
  END;
  
  BEGIN
    SELECT NVL(payment_day_no,1) INTO l_iDayNo FROM rule_entry 
     WHERE rule_entry_id = ( SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found THEN  l_iDayNo := 1;
  END; 
  
  BEGIN                                                       
    SELECT shift_to_next_working_day INTO l_iShiftToNextDay FROM rule_entry 
     WHERE rule_entry_id = (  SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found THEN  l_iShiftToNextDay := 1;
  END;
  BEGIN
    SELECT shift_to_previous_working_day INTO l_iShiftToPreviousDay FROM rule_entry 
     WHERE rule_entry_id = (  SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth));
    EXCEPTION WHEN no_data_found  THEN l_iShiftToPreviousDay := 0;
  END;
  BEGIN
    SELECT pattern_of_payments_day INTO l_iPaymentProfile FROM rule_entry 
     WHERE rule_entry_id = (  SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found  THEN l_iPaymentProfile := null;
  END;
  
  IF NVL(l_iCurrentPeriod,0) <> l_iPeriod THEN 
      -- Finn antall virkedager i gjeldende månden
      -- Lager denne bare en gang pr periode
      -- Rydd opp først
      
      DELETE FROM liquidity_day_calendar_tmp;
      COMMIT;
      
      OPEN l_curDateInMonth ( l_iPeriod );
      FETCH l_curDateInMonth INTO l_dtDay;
      WHILE  l_curDateInMonth%FOUND LOOP
      
        IF IsHoliday(l_dtDay) = 0 THEN
          INSERT INTO liquidity_day_calendar_tmp VALUES (l_dtDay);
        END IF;
      
      FETCH l_curDateInMonth INTO l_dtDay;
      END LOOP;
      CLOSE l_curDateInMonth;
      COMMIT;
      
      l_iCurrentPeriod := l_iPeriod;
  END IF;
  
  -- Betalingsprofil overstyrer annen fordeling
  IF l_iPaymentProfile IS NOT NULL THEN
    IF l_iPaymentProfile = 2 THEN
    
          -- Finn antall dager i måneden
          SELECT TO_NUMBER(TO_CHAR(LAST_DAY(DATO), 'DD')) INTO l_iNoOfDaysInMth FROM (SELECT MIN(day) AS DATO FROM liquidity_day_calendar_tmp );
          -- Finn antall dager det skal fordeles på  
          SELECT count(*) INTO l_iNoOfDaysToBeDistributed FROM liquidity_day_calendar_tmp;
          
          OPEN l_curWorkDay;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          WHILE l_curWorkDay%FOUND LOOP
          
              SELECT count(*) INTO l_iCountManualEdited 
                FROM liquidity_entry_day_item
               WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                 AND report_level_3_id = l_iR3
                 AND period = l_iPeriod
                 AND liquidity_entry_day_item_date = l_dtWorkDay
                 AND edited_by_user = 1;
                 
            IF l_iCountManualEdited = 0 THEN
              SELECT  1 + TRUNC (l_dtWorkDay)  - TRUNC (l_dtWorkDay, 'IW') INTO l_iDayNo FROM DUAL;  
              IF l_iDayNo =  3 THEN 
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,(l_fAmount/l_iNoOfDaysInMth)*3,0);
              ELSE 
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount/l_iNoOfDaysInMth,0);
              
              END IF;
            END IF;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          END LOOP;
          CLOSE l_curWorkDay;
    END IF;
    IF l_iPaymentProfile = 3 THEN
          -- Finn antall dager i måneden
          SELECT TO_NUMBER(TO_CHAR(LAST_DAY(DATO), 'DD')) INTO l_iNoOfDaysInMth FROM (SELECT MIN(day) AS DATO FROM liquidity_day_calendar_tmp );
          -- Finn antall dager det skal fordeles på  
          SELECT count(*) INTO l_iNoOfDaysToBeDistributed FROM liquidity_day_calendar_tmp;
          -- Finn siste virkedag
          SELECT MAX(day) INTO l_dtLastWorkingDay FROM liquidity_day_calendar_tmp;
          -- Finn nestsiste virkedag
          SELECT MAX(day) INTO l_dtNextToLastWorkingDay FROM liquidity_day_calendar_tmp WHERE day <> l_dtLastWorkingDay;
          
          OPEN l_curWorkDay;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          WHILE l_curWorkDay%FOUND LOOP
          
              SELECT count(*) INTO l_iCountManualEdited 
                FROM liquidity_entry_day_item
               WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                 AND report_level_3_id = l_iR3
                 AND period = l_iPeriod
                 AND liquidity_entry_day_item_date = l_dtWorkDay
                 AND edited_by_user = 1;
                 
           IF l_iCountManualEdited = 0 THEN
              IF l_dtWorkDay NOT IN (l_dtLastWorkingDay,l_dtNextToLastWorkingDay) THEN 
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,(l_fAmount*0.23)/(l_iNoOfDaysToBeDistributed-2),0);
              ELSE
                IF l_dtWorkDay = l_dtNextToLastWorkingDay THEN
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount*0.07,0);
                ELSE
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount*0.7,0);
                END IF;
              END IF;
           END IF;   

          FETCH l_curWorkDay INTO l_dtWorkDay;
          END LOOP;
          CLOSE l_curWorkDay;
    END IF;
  ELSE
      -- SKAL DENNE RADEN FORDELES FLATT 
      IF l_iEvenDistribution = 1 THEN
          -- Finn antall dager det skal fordeles på  
          SELECT count(*) INTO l_iNoOfDaysToBeDistributed FROM liquidity_day_calendar_tmp;
          
          OPEN l_curWorkDay;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          WHILE l_curWorkDay%FOUND LOOP
            SELECT count(*) INTO l_iCountManualEdited 
                  FROM liquidity_entry_day_item
                 WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                   AND report_level_3_id = l_iR3
                   AND period = l_iPeriod
                   AND liquidity_entry_day_item_date = l_dtWorkDay
                   AND edited_by_user = 1;
                   
              IF l_iCountManualEdited = 0 THEN
                INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                      period,liquidity_entry_day_item_date,amount,edited_by_user)
                VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount/l_iNoOfDaysToBeDistributed,0);
              END IF;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          END LOOP;
          CLOSE l_curWorkDay;
      END IF;
      
      IF l_iEvenDistribution = 0
      AND l_iDayNo IS NOT NULL THEN
         
        IF l_iDayNo = 99 THEN -- SISTE DAG I MND
          SELECT last_day(to_date(to_char(l_iPeriod) || to_char('01'),'YYYYMMDD')) INTO l_dtDay FROM dual;
        ELSE
          SELECT to_date(to_char(l_iPeriod) || to_char(l_iDayNo),'YYYYMMDD') INTO l_dtDay FROM dual;
        END IF;
        
        IF IsHoliday(l_dtDay) = 1 THEN -- Helligdag eller helg
           IF l_iShiftToNextDay = 1 THEN
              l_dtDay := l_dtDay + 1; -- øk med en dag
              WHILE IsHoliday(l_dtDay) = 1 LOOP l_dtDay := l_dtDay + 1; END LOOP;
           END IF;
           IF l_iShiftToPreviousDay = 1 THEN
              l_dtDay := l_dtDay - 1; -- trekk fra en dag
              WHILE IsHoliday(l_dtDay) = 1 LOOP l_dtDay := l_dtDay - 1; END LOOP;
           END IF;
        END IF;

                SELECT count(*) INTO l_iCountManualEdited 
                  FROM liquidity_entry_day_item
                 WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                   AND report_level_3_id = l_iR3
                   AND period = l_iPeriod
                   AND liquidity_entry_day_item_date = l_dtDay
                   AND edited_by_user = 1;
                   
              IF l_iCountManualEdited = 0 THEN

                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtDay,l_fAmount,0);
              END IF;
      END IF;

  END IF;    
    
  COMMIT;
END GenerateRowForDay;

FUNCTION  IsHoliday  ( i_iDate  IN DATE) RETURN NUMBER
IS
 l_iIsHoliday NUMBER;
 l_iTemp      NUMBER(11,0);
 l_strDayName VARCHAR2(15);
 l_iDayNo     NUMBER(11,0);
BEGIN
  l_iTemp := 0;
  SELECT count(*) INTO l_iTemp 
    FROM calendar 
   WHERE 
    --to_char(calendar_date,'DDMMYYYY') = to_char(i_iDate,'DDMMYYYY')
     calendar_date = i_iDate
     AND calendar_type_id is not null;
   
 -- SELECT TO_NUMBER(TO_CHAR(i_iDate,'D')) INTO l_iDayNo FROM DUAL;
  SELECT  1 + TRUNC (i_iDate)  - TRUNC (i_iDate, 'IW') INTO l_iDayNo FROM DUAL;
  IF l_iDayNo IN (6,7) THEN l_iTemp := l_iTemp + 1; END IF;

  IF l_iTemp >= 1 THEN l_iIsHoliday := 1; ELSE l_iIsHoliday := 0; END IF;

  RETURN  l_iIsHoliday;

END IsHoliday;
                               
FUNCTION  CalculateTaxFromAccounts   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS                                        
BEGIN
  RETURN 0;
END CalculateTaxFromAccounts;

FUNCTION  CalculateTaxFromPrognosis  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
BEGIN
  RETURN 0;
END CalculateTaxFromPrognosis;

FUNCTION  CalculateVATFromLiquidity  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS        
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(NVL(t.amount,0)*nvl(p.adjustment_factor,1)*nvl(p.sign_effect,1)) INTO l_fAmount
    FROM liquidity_entry_mth_item_tmp t, rule_prognosis_assoc p
   WHERE t.report_level_3_id = p.report_level_3_id
     AND p.rule_id  = i_rRuleId 
     AND p.report_level_3_id IN (SELECT report_level_3_id FROM report_level_3 WHERE report_type_id = 6)
     AND substr(t.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
--     AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || '00') FROM dual )
  --   AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || period_basis)) 
    --                       FROM rule_period_payment 
      --                    WHERE rule_entry_id  = i_rRuleId 
        --                    AND period_payment = i_strPaymentPeriod )
     AND liquidity_entry_head_id = i_rLiquidityId;
  
  RETURN l_fAmount;
END CalculateVATFromLiquidity;

FUNCTION  CalculateVATFromAccounts   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS        
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(NVL(gl.amount,0)*nvl(p.adjustment_factor,1)*nvl(p.sign_effect,1)) INTO l_fAmount
    FROM general_ledger gl, rule_gl_assoc p
   WHERE gl.account_id = p.account_id
     AND p.rule_id     = i_rRuleId
     AND gl.period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || '00') FROM dual )
     AND gl.period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || period_basis)) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = i_strPaymentPeriod )
     AND gl.company_id = g_strCompanyId; --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  
  RETURN l_fAmount;
END CalculateVATFromAccounts;

FUNCTION  CalculateVATFromAccountsSplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                          i_iYearOffset      IN NUMBER,
                                          i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS        
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  SELECT SUM(NVL(gl.amount,0)*nvl(p.adjustment_factor,1)*nvl(p.sign_effect,1)) INTO l_fAmount
    FROM general_ledger gl, rule_gl_assoc p
   WHERE gl.account_id = p.account_id
     AND p.rule_id     = i_rRuleId
     AND gl.period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || '00') FROM dual )
     AND gl.period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || period_basis)) 
                           FROM rule_period_payment 
                          WHERE rule_entry_id  = i_rRuleId 
                            AND period_payment = i_strPaymentPeriod )
     AND company_id = g_strCompanyId; --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  RETURN l_fAmount;
END CalculateVATFromAccountsSplit;

FUNCTION  CalculateVATFromPrognosis  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
        FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
       WHERE pe.report_level_3_id = r.report_level_3_id
         AND pe.prognosis_id      = i_iPrognosisId
         AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
         -- OIG Endret 12012011 SJEKK
         --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND r.rule_id            = re.rule_entry_id
         AND re.rule_entry_id     = i_rRuleId;
  RETURN l_fAmount;
END CalculateVATFromPrognosis;

FUNCTION  CalculateVATFromPrognosisSplit  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                            i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                            i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                            i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                            i_iYearOffset      IN NUMBER,
                                            i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
        FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
       WHERE pe.report_level_3_id = r.report_level_3_id
         AND pe.prognosis_id      = i_iPrognosisId
         AND substr(pe.period,5,2) IN ( SELECT MAX(period_basis)
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
         -- OIG 12012011 SJEKK
         --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND r.rule_id            = re.rule_entry_id
         AND re.rule_entry_id     = i_rRuleId;
  RETURN l_fAmount;
END CalculateVATFromPrognosisSplit;

FUNCTION  CalculateVATFromNoteLine   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
    FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
   WHERE pne.note_line_id         = r.note_line_id
     AND pne.prognosis_entry_id   = pe.prognosis_entry_id
     AND r.rule_id                = re.rule_entry_id
     AND re.rule_entry_id         = i_rRuleId
     AND pe.prognosis_id          = i_iPrognosisId
     AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                      FROM rule_period_payment 
                                     WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                       AND rule_entry_id = i_rRuleId)
     -- OIG 12012012 SJEKK
     --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
     AND r.rule_note_line_included_in = 3; -- Gjelder for utregning av r3 prognose/resultat
  
  RETURN l_fAmount;
END CalculateVATFromNoteLine;

FUNCTION  CalculateVATFromNoteLineSplit   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                            i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                            i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                            i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                            i_iYearOffset      IN NUMBER,
                                            i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
    FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
   WHERE pne.note_line_id         = r.note_line_id
     AND pne.prognosis_entry_id   = pe.prognosis_entry_id
     AND r.rule_id                = re.rule_entry_id
     AND re.rule_entry_id         = i_rRuleId
     AND pe.prognosis_id          = i_iPrognosisId
     AND substr(pe.period,5,2) IN ( SELECT MAX(period_basis) 
                                      FROM rule_period_payment 
                                     WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                       AND rule_entry_id = i_rRuleId)
     -- OIG 12012012 SJEKK 
     --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
     AND r.rule_note_line_included_in = 3; -- Gjelder for utregning av r3 prognose/resultat
  
  RETURN l_fAmount;
END CalculateVATFromNoteLineSplit;

FUNCTION  CalculateVATFromInvestment ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
    SELECT NVL(SUM(pie.amount * NVL(re.adjustment_factor,1) * NVL(r.adjustment_factor,1) * NVL(r.sign_effect,1)),0) INTO l_fAmount
         FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
        WHERE pie.activity_id          = r.activity_id
          AND pie.prognosis_id         = i_iPrognosisId
          AND substr(pie.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId) 
          AND substr(pie.period,0,4)   = ( SELECT substr(period,0,4)+i_iYearOffset FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId;
  
  RETURN l_fAmount;
END CalculateVATFromInvestment;

FUNCTION  CalculateVATFromInvestSplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                        i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                        i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                        i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                        i_iYearOffset      IN NUMBER,
                                        i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
    SELECT NVL(SUM(pie.amount * NVL(re.adjustment_factor,1) * NVL(r.adjustment_factor,1) * NVL(r.sign_effect,1)),0) INTO l_fAmount
         FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
        WHERE pie.activity_id          = r.activity_id
          AND pie.prognosis_id         = i_iPrognosisId
          AND substr(pie.period,5,2) IN ( SELECT MAX(period_basis) 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId) 
          AND substr(pie.period,0,4)   = ( SELECT substr(period,0,4)+i_iYearOffset FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND r.rule_id          = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId;
  
  RETURN l_fAmount;
END CalculateVATFromInvestSplit;

FUNCTION  CalculateVATFromActSalary ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                      i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                      i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                      i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                      i_iYearOffset      IN NUMBER,
                                      i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT NVL(SUM(pne.amount* NVL(re.adjustment_factor,1)* NVL(r.adjustment_factor,1)),0) INTO l_fAmount
         FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
        WHERE pne.note_line_id         = r.note_line_id
          AND pne.prognosis_entry_id   = pe.prognosis_entry_id
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId
          AND pe.prognosis_id          = i_iPrognosisId
          AND r.rule_note_line_included_in  = 5  -- Gjelder for investering
          AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId)
          AND substr(pe.period,0,4)    = ( SELECT substr(period,0,4)+i_iYearOffset FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  
  RETURN l_fAmount;
END CalculateVATFromActSalary;

FUNCTION  CalculateVATFromActSalarySplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                           i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                           i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                           i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                           i_iYearOffset      IN NUMBER,
                                           i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
    SELECT NVL(SUM(pne.amount* NVL(re.adjustment_factor,1)* NVL(r.adjustment_factor,1)),0) INTO l_fAmount
         FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
        WHERE pne.note_line_id         = r.note_line_id
          AND pne.prognosis_entry_id   = pe.prognosis_entry_id
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId
          AND pe.prognosis_id          = i_iPrognosisId
          AND r.rule_note_line_included_in  = 5  -- Gjelder for investering
          AND substr(pe.period,5,2) IN ( SELECT MAX(period_basis) 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId)
          AND substr(pe.period,0,4)    = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  RETURN l_fAmount;
END CalculateVATFromActSalarySplit;

/* HARDKODEDE RAPPORTLINJER - MÅ ENDRES I FORVALTNING  */

PROCEDURE GenerateForNettleieNaering ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iFirstRollingPeriod    PERIOD.ACC_PERIOD%TYPE;
  l_iPreviousRollingPeriod PERIOD.ACC_PERIOD%TYPE;
--  l_strCompanyId           COMPANY.COMPANY_ID%TYPE;
  l_fAmountCommercial      NUMBER(18,2);
  
  l_iCountPaymentPeriod    NUMBER(11,0);

BEGIN
  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');
  -- Forrige periode (Kommer inn med i_iRollingPeriod=201104, skal returnere 201103)  
  SELECT acc_period INTO l_iPreviousRollingPeriod
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,-1) 
                        FROM period 
                      WHERE acc_period = i_iRollingPeriod
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');

  -- NÃ†RING
  -- Hent prognosetall for forrige prognosemåned
  -- Dersom det er første rullerende måned skal beløpet hentes fra regnskap
  IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
    -- Regnskap  
    BEGIN
      SELECT SUM(gl.amount*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountCommercial
        FROM general_ledger gl, report_l3_account_assoc r3a, rule_prognosis_assoc r
       WHERE r3a.report_level_3_id = r.report_level_3_id
         AND r.rule_id             = i_rRuleId
         AND gl.account_id         = r3a.account_id
         AND r3a.report_level_3_id = i_iLiquidityReportLineId
         AND gl.company_id  = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND gl.period      = g_iPeriodId    --( SELECT period     FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) --l_iPreviousRollingPeriod
         AND gl.activity_id = '2';

    EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountCommercial := 0;
    END;
  ELSE
    -- Prognose
    BEGIN
      SELECT SUM(pe.amount*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountCommercial
       FROM prognosis_entry pe, rule_prognosis_assoc r
      WHERE pe.report_level_3_id = r.report_level_3_id
        AND pe.prognosis_id      = i_iPrognosisId
        AND pe.period            = l_iPreviousRollingPeriod
        AND r.rule_id            = i_rRuleId;
  
    EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountCommercial := 0;
    END;
  
  
  END IF;
  
  INSERT INTO liquidity_entry_mth_item_tmp
    (liquidity_entry_head_id
    ,report_level_3_id
    ,period
    ,amount)
  VALUES 
    (i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,i_iRollingPeriod
    ,NVL(l_fAmountCommercial,0));
    
    COMMIT;

END GenerateForNettleieNaering;

PROCEDURE GenerateForNettleiePrivat  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fAmount          NUMBER(18,2);

  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
BEGIN
  l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    /*
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_basis =  substr(i_iRollingPeriod,5,2); */
     -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  IF l_strPaymentPeriod = 'NA' THEN
    RETURN;  -- Returnerer siden det ikke er utbetaling denne rullerende periode
  END IF;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utganspunktet er 1 (og rullerende er 3) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 1
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
        -- Prognose for periode 2
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      END IF;
    WHEN l_iPeriodNo = 2 THEN 
      -- Første rullerende periode er her 03
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utgangspunktet er 2 (og rullerende er 3) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         =  g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
           
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;

        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        
      END IF;
    WHEN l_iPeriodNo = 3 THEN
      -- Første rullerende periode er her 04
      IF substr(i_iRollingPeriod,5,2)  = 5 THEN -- Når utganspunktet er 3 (og rullerende er 5) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 3
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        -- Prognose for periode 2
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                             FROM rule_period_payment 
                                            WHERE rule_entry_id  = i_rRuleId 
                                              AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 4 THEN 
      -- Første rullerende periode er her 05
      IF substr(i_iRollingPeriod,5,2)  = 5 THEN -- Når utgangspunktet er 4 (og rullerende er 5) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
           
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                             FROM rule_period_payment 
                                            WHERE rule_entry_id  = i_rRuleId 
                                              AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 5 THEN
      -- Første rullerende periode er her 06
      IF substr(i_iRollingPeriod,5,2)  = 7 THEN -- Når utganspunktet er 5 (og rullerende er 7) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 1
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
        -- Prognose for periode 8
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                             FROM rule_period_payment 
                                            WHERE rule_entry_id  = i_rRuleId 
                                              AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      END IF;
    WHEN l_iPeriodNo = 6 THEN 
      -- Første rullerende periode er her 07
      IF substr(i_iRollingPeriod,5,2)  = 7 THEN -- Når utgangspunktet er 6 (og rullerende er 7) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 7 THEN
      -- Første rullerende periode er her 08
      IF substr(i_iRollingPeriod,5,2)  = 9 THEN -- Når utganspunktet er 7 (og rullerende er 9) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 7
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
        -- Prognose for periode 8
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 8 THEN 
      -- Første rullerende periode er her 09
      IF substr(i_iRollingPeriod,5,2)  = 9 THEN -- Når utgangspunktet er 8 (og rullerende er 9) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 9 THEN
      -- Første rullerende periode er her 10
      IF substr(i_iRollingPeriod,5,2)  = 11 THEN -- Når utganspunktet er 9 (og rullerende er 11) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 9
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        -- Prognose for periode 10
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      END IF;
    WHEN l_iPeriodNo = 10 THEN 
      -- Første rullerende periode er her 11
      IF substr(i_iRollingPeriod,5,2)  = 11 THEN -- Når utgangspunktet er 10 (og rullerende er 11) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
           
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 11 THEN
      -- Første rullerende periode er her 12
      IF substr(i_iRollingPeriod,5,2)  = 1 THEN -- Når utganspunktet er 11 (og rullerende er 1) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 11
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        -- Prognose for periode 12
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;
        
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;
        
      END IF;
    WHEN l_iPeriodNo = 12 THEN 
          -- Første rullerende periode er her 01
      IF substr(i_iRollingPeriod,5,2)  = 1 THEN -- Når utgangspunktet er 12 (og rullerende er 1) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;  
      END IF;
    ELSE NULL;
    END CASE;

    COMMIT; 
END GenerateForNettleiePrivat;

PROCEDURE GenerateForLonn            ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  
  l_fAllFactors           NUMBER(11,4);
  l_fAmountFromProgonsis  PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountBase           PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPersonellCost  PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPayRollTax     PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPension        PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountVacationSalary PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountTax            PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPRTofPensionVS PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  
  l_iLiquidityTax            REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_iLiquidityVacationSalary REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_iLiquidityPayrollTax     REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_iPeriodNo                NUMBER(11,0);
  l_iLastRollingPeriod       NUMBER(11,0);
  l_iLiquidityPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iLiquidityReportLineId   REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  
  l_iYearOffset              NUMBER(11,0);
  
  l_strPaymentPeriod         RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_rRuleId                  RULE_ENTRY.RULE_ENTRY_ID%TYPE;
  
  TYPE PaymentPeriods IS TABLE OF RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  --TYPE PaymentPeriods IS VARRAY(14) OF RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_arrPaymentPeriods    PaymentPeriods; 
  
  CONST_PERSONELL_COST       CONSTANT NUMBER(11,4) := 2; -- Beregner 2% personellkostnad
  CONST_TAX_RATE             CONSTANT NUMBER(11,4) := 37.5; -- Beregner 37,5% skatt
  CONST_WORK_TAX_RATE        CONSTANT NUMBER(11,4) := 14.1; -- Trekker ut 14,1% arbeidsgiveravgift
  CONST_PENSION_RATE         CONSTANT NUMBER(11,4) := 11;  -- Trekker ut 11% pensjon
  CONST_VACATION_SALARY_RATE CONSTANT NUMBER(11,4) := 12;   -- Trekker ut 12% feriepenger

BEGIN
  l_strPaymentPeriod := 'NA';
  SELECT period INTO l_iLiquidityPeriod FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  SELECT acc_period INTO l_iLastRollingPeriod 
    FROM period 
   WHERE date_from = ( SELECT date_from
                        FROM period   
                       WHERE acc_period = ( SELECT acc_period 
                                              FROM period 
                                             WHERE date_from = ( SELECT ADD_MONTHS(date_from,12) 
                                                                   FROM period 
                                                                  WHERE acc_period = ( SELECT period 
                                                                                         FROM liquidity_entry_head
                                                                                        WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                      )
                                                                )
                                                AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                                                               
                                            )
                     )
      AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
  /*   28.04.2015 Utgår pga nytt forsystem i prognosemodul hvor lønn blir lagt direkte på ekstern/intern lønn og ikke på notelinje
  BEGIN
    
    SELECT SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountFromProgonsis --l_fAmountWOPersonellCost
      FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
     WHERE pne.note_line_id       = r.note_line_id
       AND pne.prognosis_entry_id = pe.prognosis_entry_id
       AND pe.prognosis_id        = i_iPrognosisId
       AND pe.period              = i_iRollingPeriod
       AND r.rule_id              = re.rule_entry_id
       AND re.rule_entry_id       = i_rRuleId;
    EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountFromProgonsis := 0;
  END;
  */
  -- Dersom vi ikke finner taller fra notelinjen må vi sjekke på R3 nivå fra samme regel
  -- 28.04.2015 Utgår pga nytt forsystem i prognosemodul hvor lønn blir lagt direkte på ekstern/intern lønn
  
  --IF NVL(l_fAmountFromProgonsis,0) = 0 THEN
    BEGIN
      SELECT SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountFromProgonsis
       FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
      WHERE pe.report_level_3_id  = r.report_level_3_id
        AND pe.prognosis_id       = i_iPrognosisId
        AND pe.period              = i_iRollingPeriod
        AND r.rule_id             = re.rule_entry_id
        AND re.rule_entry_id      = i_rRuleId;  
      EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountFromProgonsis := 0;
    END;  
 -- END IF;
  
  l_fAllFactors := ((CONST_PERSONELL_COST + CONST_WORK_TAX_RATE + CONST_PENSION_RATE + CONST_VACATION_SALARY_RATE ) / 100) + 1;
    
  l_fAmountBase           := l_fAmountFromProgonsis / l_fAllFactors;
  l_fAmountPersonellCost  := l_fAmountBase * (CONST_PERSONELL_COST / 100);
  l_fAmountPayRollTax     := l_fAmountBase * (CONST_WORK_TAX_RATE / 100);         -- Trekker ut arbeidsgiveravgift
  l_fAmountPension        := l_fAmountBase * (CONST_PENSION_RATE / 100);          -- Trekker ut pensjon
  l_fAmountVacationSalary := l_fAmountBase * (CONST_VACATION_SALARY_RATE / 100);  -- Trekker ut feriepenger
  l_fAmountTax            := l_fAmountBase * (CONST_TAX_RATE / 100);              -- Beregner skatt
  l_fAmountPRTofPensionVS := (l_fAmountVacationSalary + l_fAmountPension) * (CONST_WORK_TAX_RATE/100);


  -- 28.04.2015 Beløpet som legges på Utbetalt lønn er for høyt, må korrigeres med 45% grunnet skatt og andre trekk...jfr Bente og Brit
  l_fAmountBase := l_fAmountBase * 0.55;

   INSERT INTO liquidity_entry_mth_salary_tmp
          (liquidity_entry_head_id,report_level_3_id,period,base_amount,personell_cost_amount,work_tax_amount,pension_amount,vacation_salary_amount,tax_amount,PRTofPensionVS_amount)
   VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fAmountBase,l_fAmountPersonellCost,l_fAmountPayRollTax,l_fAmountPension,l_fAmountVacationSalary,l_fAmountTax,l_fAmountPRTofPensionVS);
  
  COMMIT;

  -- Beregner arbeidsgiveravgift
  SELECT rule_entry_id     INTO l_rRuleId                FROM rule_entry WHERE hard_coded_db_proc = 997; --arbeidsgiveravgift
  SELECT report_level_3_id INTO l_iLiquidityReportLineId FROM r3_rule_company_relation WHERE rule_id = l_rRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
  GenerateForArbGiverAvgift (i_rLiquidityId,l_rRuleId,i_iPrognosisId,l_iLiquidityReportLineId,i_iRollingPeriod,i_dtCurrentRolling);
    
  --Beregner skatt
  SELECT rule_entry_id     INTO l_rRuleId                FROM rule_entry WHERE hard_coded_db_proc = 998; --Skatt
  SELECT report_level_3_id INTO l_iLiquidityReportLineId FROM r3_rule_company_relation WHERE rule_id = l_rRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
  GenerateForSkattetrekk (i_rLiquidityId,l_rRuleId,i_iPrognosisId,l_iLiquidityReportLineId,i_iRollingPeriod,i_dtCurrentRolling);
  
  -- Beregner feriepenger for siste periode
  IF i_iRollingPeriod = l_iLastRollingPeriod THEN
    SELECT rule_entry_id     INTO l_rRuleId FROM rule_entry WHERE hard_coded_db_proc = 9932; --Feriepengeregel
    SELECT report_level_3_id INTO l_iLiquidityVacationSalary FROM r3_rule_company_relation WHERE rule_id = l_rRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
    GenerateForFeriePenger(i_rLiquidityId,l_rRuleId,i_iPrognosisId,l_iLiquidityVacationSalary,i_iRollingPeriod,i_dtCurrentRolling);
  END IF;
  
  -- Flytter lønnskostnader til tmp tabell -- FLYTTE DENNE UT AV CURSOR?
  l_arrPaymentPeriods := PaymentPeriods('01','02','03','04','05','07','08','09','10','11','12');
  SELECT substr(i_iRollingPeriod,5,2) INTO l_strPaymentPeriod FROM dual;
  
  IF l_strPaymentPeriod MEMBER OF l_arrPaymentPeriods THEN
    INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
      SELECT liquidity_entry_head_id,report_level_3_id,period,base_amount 
        FROM liquidity_entry_mth_salary_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id       = i_iLiquidityReportLineId
         AND period                  = i_iRollingPeriod;
  END IF;
  
  COMMIT;
END GenerateForLonn;

PROCEDURE GenerateForFeriePenger     ( i_rLiquidityId         IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iLiquidityPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iVacationSalaryPeriod    PERIOD.ACC_PERIOD%TYPE;
  l_iVacationSalaryPeriodNo  NUMBER(2);
  
  l_fVacationSalaryAmount    PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
BEGIN

  BEGIN
    SELECT payment_month_no
      INTO l_iVacationSalaryPeriodNo
      FROM rule_entry 
     WHERE hard_coded_db_proc = 9932;  -- Feriepenger
  EXCEPTION WHEN NO_DATA_FOUND THEN l_iVacationSalaryPeriodNo := 6;   --DEFAULT ER JUNI
  END;
  SELECT period INTO l_iLiquidityPeriod FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  IF TO_NUMBER(SUBSTR(l_iLiquidityPeriod,5,2)) < l_iVacationSalaryPeriodNo THEN
    l_iVacationSalaryPeriod := TO_NUMBER(SUBSTR(l_iLiquidityPeriod,0,4) || LPAD (l_iVacationSalaryPeriodNo,2,'0'));
  ELSE  
    l_iVacationSalaryPeriod := TO_NUMBER(SUBSTR(l_iLiquidityPeriod,0,4)+1 || LPAD (l_iVacationSalaryPeriodNo,2,'0'));
  END IF;
  
  IF i_iLiquidityReportLineId <> -1 THEN    
     IF to_number(substr(l_iLiquidityPeriod,5,2)) <= 5 THEN ---Hent feriepenger fra balansekonto 2940,2941,2942
        
        INSERT INTO liquidity_entry_mth_item_tmp
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount)
        SELECT 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod
          ,NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0)
        FROM general_ledger
        WHERE account_id         IN ( SELECT account_id            FROM rule_gl_assoc WHERE rule_id =  i_rRuleId )
          AND company_id         =  g_strCompanyId --( SELECT company_id            FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId ) 
          AND substr(period,0,4) =  ( SELECT substr(period,0,4)-1  FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId )
        GROUP BY 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod;
          
      ELSE
        -- Hent det som er registrert i regnskap inneværende år
         INSERT INTO liquidity_entry_mth_item_tmp
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount)
        SELECT 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod
          ,NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0)
        FROM general_ledger
        WHERE account_id         IN ( SELECT account_id FROM rule_gl_assoc WHERE rule_id = i_rRuleId )
          AND company_id         = g_strCompanyId --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
          AND substr(period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND period             <= ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
        GROUP BY 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod;
          
        --Hent resterende fra de tidligere beregnede radene
        SELECT SUM(vacation_salary_amount) INTO l_fVacationSalaryAmount FROM liquidity_entry_mth_salary_tmp
        WHERE liquidity_entry_head_id = i_rLiquidityId
          AND period                  > l_iLiquidityPeriod
          AND substr(period,0,4)      = ( SELECT substr(leh.period,0,4) FROM liquidity_entry_head leh WHERE leh.liquidity_entry_head_id = i_rLiquidityId );

        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES (i_rLiquidityId,i_iLiquidityReportLineId,l_iVacationSalaryPeriod,l_fVacationSalaryAmount);

      END IF;
  END IF;    
  COMMIT;
  -- SLUTT FERIEPENGER
END GenerateForFeriePenger;

FUNCTION GetSalaryWorkTaxAmountMAX( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                   ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                   ,l_iYearOffset      IN NUMBER
                                   ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                   ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(work_tax_amount+PrtofPensionVS_Amount) INTO l_fResult --Legger også til AGA av pensjon og feriepenger
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  = (SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                      FROM rule_period_payment 
                                     WHERE rule_entry_id  = i_rRuleId 
                                       AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryWorkTaxAmountMAX;

FUNCTION GetSalaryWorkTaxAmountIN ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                   ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                   ,l_iYearOffset      IN NUMBER
                                   ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                   ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(work_tax_amount+PrtofPensionVS_Amount) INTO l_fResult --Legger også til AGA av pensjon og feriepenger
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryWorkTaxAmountIN;

PROCEDURE GenerateForArbGiverAvgift  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
 IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fPayRollTaxBasis NUMBER(18,2);
  l_fSalaryTaxAmount  NUMBER(18,2);
  
  l_strPaymentPeriod        RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_iVacationSalaryPeriodNo RULE_ENTRY.PAYMENT_MONTH_NO%TYPE;
  l_iLiquidityPeriod        LIQUIDITY_ENTRY_HEAD.PERIOD%TYPE;

BEGIN
  l_strPaymentPeriod := 'NA';
  SELECT period                        INTO l_iLiquidityPeriod FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utganspunktet er 1 (og rullerende er 3) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 1
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
          FROM general_ledger
         WHERE account_id  =  ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
           AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
           AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 2
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
  
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
  
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
      END IF;
    WHEN l_iPeriodNo = 2 THEN
      -- Første rullerende periode er her 03
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utgangspunktet er 2 (og rullerende er 3) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 3 THEN
      -- Første rullerende periode er her 04
      IF substr(i_iRollingPeriod,5,2) = 5 THEN -- Når utgangspunktet er 3 (og rullerende er 5) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 3
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
          FROM general_ledger
         WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
           AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
           AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
        -- Prognose for periode 4
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 4 THEN
      -- Første rullerende periode er her 05
      IF substr(i_iRollingPeriod,5,2) = 5 THEN -- Når utganspunktet er 4 (og rullerende er 5) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
      END IF;
    WHEN l_iPeriodNo = 5 THEN
      -- Første rullerende periode er her 06
      IF substr(i_iRollingPeriod,5,2) = 7 THEN -- Når utgangspunktet er 5 (og rullerende er 7) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 5
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
           FROM general_ledger
          WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
            AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
            AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
            AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 6
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);                

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 6 THEN
      -- Første rullerende periode er her 07
      IF substr(i_iRollingPeriod,5,2) = 7 THEN -- Når utgangspunktet er 6 (og rullerende er 7) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
             AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
             AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                   FROM rule_period_payment 
                                  WHERE rule_entry_id  = i_rRuleId 
                                    AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    WHEN l_iPeriodNo = 7 THEN
      -- Første rullerende periode er her 08
      IF substr(i_iRollingPeriod,5,2) = 9 THEN -- Når utgangspunktet er 7 (og rullerende er 9) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 7
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
             AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
             AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 8
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);                

      ELSE
        -- Hent fra prognose
        BEGIN
         l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
       
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 8 THEN
      -- Første rullerende periode er her 09
      IF substr(i_iRollingPeriod,5,2) = 9 THEN -- Når utganspunktet er 8 (og rullerende er 9) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    WHEN l_iPeriodNo = 9 THEN
      -- Første rullerende periode er her 10
      IF substr(i_iRollingPeriod,5,2) = 11 THEN -- Når utgangspunktet er 9 (og rullerende er 11) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 9
           SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
             FROM general_ledger
            WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
              AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                     FROM rule_period_payment 
                                    WHERE rule_entry_id  = i_rRuleId 
                                      AND period_payment = l_strPaymentPeriod )
              AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 10
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
         
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);              

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
  
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 10 THEN
      -- Første rullerende periode er her 11
      IF substr(i_iRollingPeriod,5,2) = 11 THEN -- Når utgangspunktet er 10 (og rullerende er 11) skal det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    WHEN l_iPeriodNo = 11 THEN
      -- Første rullerende periode er her 12
      IF substr(i_iRollingPeriod,5,2) = 1 THEN -- Når utgangspunktet er 11 (og rullerende er 1) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 11
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
           FROM general_ledger
          WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
            AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
            AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                   FROM rule_period_payment 
                                  WHERE rule_entry_id  = i_rRuleId 
                                    AND period_payment = l_strPaymentPeriod )
            AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 12
        BEGIN
           l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);               

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 12 THEN
      -- Første rullerende periode er her 01
      IF substr(i_iRollingPeriod,5,2) = 1 THEN -- Når utgangspunktet er 12 (og rullerende er 1) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
             AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
             AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                   FROM rule_period_payment 
                                  WHERE rule_entry_id  = i_rRuleId 
                                    AND period_payment = l_strPaymentPeriod )
             AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	        EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    ELSE NULL;
    END CASE;

END GenerateForArbGiverAvgift;

FUNCTION GetSalaryTaxAmountMAX( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                               ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                               ,l_iYearOffset      IN NUMBER
                               ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                               ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(tax_amount) INTO l_fResult 
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  = (SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                      FROM rule_period_payment 
                                     WHERE rule_entry_id  = i_rRuleId 
                                       AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryTaxAmountMAX;

FUNCTION GetSalaryTaxAmountIN ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                   ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                   ,l_iYearOffset      IN NUMBER
                                   ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                   ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(tax_amount) INTO l_fResult 
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryTaxAmountIN;

PROCEDURE GenerateForSkattetrekk     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS                                       
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fPayRollTaxBasis NUMBER(18,2);
  
  l_fTaxBasis        PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fTaxAmount       PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  
BEGIN
  l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
     -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;

    CASE 
      WHEN l_iPeriodNo = 1 THEN
        IF substr(i_iRollingPeriod,5,2) = 3 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
           
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
             VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;       
          
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 2 THEN
        IF substr(i_iRollingPeriod,5,2) = 3 THEN
          -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	        EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
      
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 3 THEN
        IF substr(i_iRollingPeriod,5,2) = 5 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
             VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
          END;
  
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 4 THEN
        IF substr(i_iRollingPeriod,5,2) = 5 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 5 THEN
        IF substr(i_iRollingPeriod,5,2) = 7 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
            
            INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
            EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
          END;
          
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 6 THEN
        IF substr(i_iRollingPeriod,5,2) = 7 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	         EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 7 THEN
        IF substr(i_iRollingPeriod,5,2) = 9 THEN
                   -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
            INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 8 THEN
        IF substr(i_iRollingPeriod,5,2) = 9 THEN
                  -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 9 THEN
        IF substr(i_iRollingPeriod,5,2) = 11 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
            l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
             INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 10 THEN
        IF substr(i_iRollingPeriod,5,2) = 11 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	         EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 11 THEN
        IF substr(i_iRollingPeriod,5,2) = 1 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
              EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
            INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 12 THEN
        IF substr(i_iRollingPeriod,5,2) = 1 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
    ELSE NULL;
    END CASE;

END GenerateForSkattetrekk;

PROCEDURE GenerateForMVA             ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fPayRollTaxBasis NUMBER(18,2);
  
  l_fAmountWOPersonellCost  NUMBER(18,2);
  l_fAmountWOPayRollTax     NUMBER(18,2);
  l_fAmountWOPension        NUMBER(18,2);
  l_fAmountWOVacationSalary NUMBER(18,2);
  l_fAmountTax              NUMBER(18,2);
  l_fAmountNetSalary        NUMBER(18,2);
  l_fAmountPayrollTax       NUMBER(18,2);
  
  l_fInvestment      NUMBER(18,2);
  l_fActivatedSalary NUMBER(18,2);
  
  l_iLiquidityVAT   REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
BEGIN
  l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  BEGIN
    
    SELECT report_level_3_id 
      INTO l_iLiquidityVAT
      FROM r3_rule_company_relation 
     WHERE rule_id = ( SELECT rule_entry_id FROM rule_entry WHERE hard_coded_db_proc = 994 )  -- MVA
       AND company_id = g_strCompanyId
       AND is_enabled = 1;
     
  EXCEPTION WHEN NO_DATA_FOUND THEN l_iLiquidityVAT := -1;
  END;
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      IF substr(i_iRollingPeriod,5,2) = 2 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 4 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      END IF;
    
      IF g_strCompanyId = 'SN' THEN
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      END IF;         
               
    WHEN l_iPeriodNo = 2 THEN
      IF substr(i_iRollingPeriod,5,2) = 4 THEN -- Hente fra regnskap når startperiode er 2 og rullerende er 4
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod),'Fra hovebok');
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''),'Fra prognose');
       -- Hente fra notelinje
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
         VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''),'Fra notelinje');
       -- Investering - notelinje (Aktivert lønn)
       l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
       l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
       IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
         INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount, liquidity_entry_mth_comment)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0),'Fra investering + aktivert lønn');
       END IF; 

IF g_strCompanyId = 'SN' THEN    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod), 'Fra likviditet - BFN');
               END IF;
      END IF;
    WHEN l_iPeriodNo = 3 THEN 
      IF substr(i_iRollingPeriod,5,2) = 4 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 6 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      

    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 4 THEN 
      IF substr(i_iRollingPeriod,5,2) = 6 THEN -- Hente fra regnskap når startperiode er 4 og rullerende er 6
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- NOTELINJE
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- Investering - notelinje (Aktivert lønn)
       l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
       l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
       IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
         INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
       END IF; 
      
    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 5 THEN 
      IF substr(i_iRollingPeriod,5,2) = 6 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 8 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      

    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 6 THEN 
      IF substr(i_iRollingPeriod,5,2) = 8 THEN -- Hente fra regnskap når startperiode er 6 og rullerende er 8
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- NOTELINJE
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF;
      
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
      END IF;
    WHEN l_iPeriodNo = 7 THEN 
      IF substr(i_iRollingPeriod,5,2) = 8 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 10 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      

    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 8 THEN 
      IF substr(i_iRollingPeriod,5,2) = 10 THEN -- Hente fra regnskap når startperiode er 8 og rullerende er 10
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- NOTELINJE
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- Investering - notelinje (Aktivert lønn)
       l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
       l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
            VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF;
    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 9 THEN 
      IF substr(i_iRollingPeriod,5,2) = 10 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 12 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Må sette l_iYearOffset for å hente investeringer for riktig periode og ÅR
        IF substr(i_iRollingPeriod,5,2) = 2 THEN
          l_iYearOffset := 0;
        ELSE l_iYearOffset := 1;
        END IF;
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
   
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 10 THEN 
      IF substr(i_iRollingPeriod,5,2) = 12 THEN -- Hente fra regnskap når startperiode er 10 og rullerende er 12
      
              INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- NOTELINJE
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
         -- Investering - notelinje (Aktivert lønn)
         l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
         l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
         INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF;
            
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 11 THEN 
      IF substr(i_iRollingPeriod,5,2) = 12 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 2 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
     
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 12 THEN 
      IF substr(i_iRollingPeriod,5,2) = 2 THEN -- Hente fra regnskap når startperiode er 12 og rullerende er 2
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- NOTELINJE
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,1,'');  -- OIG 20022015 Sjekk l_iOffsetYEAR
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));       
        END IF;
     
     
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
        END IF;
    
    ELSE NULL;
  END CASE;
END GenerateForMVA;

PROCEDURE GenerateForELAvgift        ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_iLiquidityYear   NUMBER(11,0);
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
BEGIN
    l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,0,4)) INTO l_iLiquidityYear FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  IF substr(i_iRollingPeriod,5,2)  = 2 THEN -- Når utganspunktet er 1 (og rullerende er 2) må det hentes fra regnskap i fjor
  -- Kan Year Offset håndteres i regelen?
    l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor når likviditetsperiode er 1
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
      ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
     FROM general_ledger
    WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
        -- Tall må hentes akkumulert fra periode 00
      AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
      AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
      AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
      GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

  ELSE 
    l_iYearOffset := -1; -- Hente regnskaptall fra i fjor 

    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
      ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
    FROM general_ledger
   WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
     -- Tall må hentes akkumulert fra periode 00
     AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
     AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
    AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
    GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

  END IF;
END GenerateForELAvgift;

PROCEDURE GenerateForEnovaAvgift     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_iLiquidityYear   NUMBER(11,0);
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  
BEGIN
    l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;

  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,0,4)) INTO l_iLiquidityYear FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2)  = 2 THEN -- Når utganspunktet er 1 (og rullerende er 2) må det hentes fra regnskap i fjor
        l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
         AND period <= (SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
         AND gl.company_id         =  g_strCompanyId
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
         

/*
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
         FROM general_ledger
        WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  g_strCompanyId --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

*/

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                            -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  = g_strCompanyId -- ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 2 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) = 4 THEN -- Når utganspunktet er 2 (og rullerende er 4) må det hentes fra regnskap
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  =  g_strCompanyId -- ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  =  g_strCompanyId --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  =  g_strCompanyId -- ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 3 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) = 4 THEN -- Når utganspunktet er 3 (og rullerende er 4) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 4 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (6,4) THEN -- Når utganspunktet er 4 (og rullerende er 6 eller 4) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 5 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (6,4) THEN -- Når utganspunktet er 5 (og rullerende er 6 eller 4) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 6 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (8,4,6) THEN -- Når utganspunktet er 6 (og rullerende er 8,4 eller 6) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 7 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (8,4,6) THEN -- Når utganspunktet er 7 (og rullerende er 8,4 eller 6) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 8 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (10,4,6,8) THEN -- Når utganspunktet er 8 (og rullerende er 10,4,6 eller 8) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
                  ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
           -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 9 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (10,4,6,8) THEN -- Når utganspunktet er 9 (og rullerende er 10,4,6 eller 8) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 10 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (12,4,6,8,10) THEN -- Når utganspunktet er 10 (og rullerende er 12,4,6,8 eller 10) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 11 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (12,4,6,8,10) THEN -- Når utganspunktet er 11 (og rullerende er 12,4,6,8 eller 10) må det hentes fra regnskap i fjor
        l_iYearOffset := -1; -- Hente regnskaptall fra i fjor i forhold til rullerende periode
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
      /*
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -2; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
         FROM general_ledger
        WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        
        */
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)  -- Legger 1 på l_iPeriodNo for neste periode
          --AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 12 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (4,6,8,10,12) THEN -- Når utganspunktet er 12 (og rullerende er 2,4,6,8,10 eller 12) må det hentes fra regnskap i år
        l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

        ELSE 
        l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        
      END IF;
    ELSE NULL;
  END CASE;  
      
  /*
  INSERT INTO liquidity_entry_mth_item_tmp
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount)
  SELECT
    i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
    ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
   FROM general_ledger
   WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
                                 --rule_period_payment 
                                --WHERE rule_entry_id  = i_rRuleId 
                                --AND period_payment = l_strPaymentPeriod
                        
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
   GROUP BY 
     i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
  */
END GenerateForEnovaAvgift;

PROCEDURE GenerateForGrunnNaturOverskatt ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                           i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                           i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                           i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                           i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                           i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_fTaxBasis           NUMBER(18,2);
  l_fTaxBasisYear1      NUMBER(18,2);
  l_fTaxBasisYear2      NUMBER(18,2);
  l_fTempAmount         NUMBER(18,2); 
  l_iYearOffset         NUMBER(11,0);
  l_iRowCount           NUMBER(11,0);
  l_iPaymentPeriodCount NUMBER(11,0);
  l_iPeriodNo           NUMBER(11,0);
  l_iPeriodId           NUMBER(11,0);
  l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_iZeroIfNegative     RULE_ENTRY.ZERO_IF_NEGATIVE%TYPE;
  l_iZeroIfPositive     RULE_ENTRY.ZERO_IF_POSITIVE%TYPE;

BEGIN
  l_strPaymentPeriod := 'NA';
  -- Sjekk om det er utbetalinger for gjeldende periode
  SELECT count(*) INTO l_iPaymentPeriodCount 
    FROM rule_period_payment 
   WHERE rule_entry_id = i_rRuleId 
     AND period_payment = substr(i_iRollingPeriod,5,2);
  
  IF l_iPaymentPeriodCount = 0 THEN
    RETURN;
  END IF;
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    SELECT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2)
        AND period_basis   =  substr(i_iRollingPeriod,5,2);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; 
  END;
 -- Sett resultat lik 0 dersom negativt beløp
 SELECT nvl(zero_if_negative,0) INTO l_iZeroIfNegative 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
 -- Sett resultat lik 0 dersom positivt beløp
 SELECT nvl(zero_if_positive,0) INTO l_iZeroIfPositive
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  
  -- Sjekk om raden allerede er laget    
    SELECT count(*) INTO l_iRowCount
      FROM liquidity_entry_mth_item_tmp 
     WHERE liquidity_entry_head_id = i_rLiquidityId
       AND report_level_3_id       = i_iLiquidityReportLineId
       AND substr(period,5,2)      = l_strPaymentPeriod;
    
  IF l_iRowCount <> 0 THEN
    RETURN; -- Returner, Har allerede laget raden for denne betalingsperioden
  END IF;

  -- FJERNET: SPESIELL BEHANDLING AV MAI 05
 -- IF substr(i_iRollingPeriod,5,2) <> 5 THEN
  
  /* OIG 04032013 Endret til å hente fra prognose i stedet for regnskap 
     
     Fra mail fra Benete Østby / 03032014:
     
     Som vi snakket om tidligere henter modellen regnskapstall for 2012 i prognose for 2014 p.t. Jeg skulle sjekke med Nett og Kraft hvordan det blir mest riktig å gjøre det 
     og konklusjonen er nå at vi endrer til at modellen isteden henter tall fra resultatprognosen for "betalbar skatt" for fjoråret og 50% legges på februar og 50% på april. 
     Når man står i 2014 hentes prognosetall for bet.skatt 2013, og for 2015 henter man årsprognosen for 2014.


  
    SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
      FROM general_ledger
     WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = l_strPaymentPeriod )
       AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
    */
    SELECT period INTO l_iPeriodId FROM liquidity_entry_head WHERE liquidity_entry_head_id =  i_rLiquidityId;
    -- Dersom rullerende periode er i samme år som likviditetsprognosen henter vi fra fjorårets regnskap
    IF  substr(i_iRollingPeriod,0,4) = substr(l_iPeriodId,0,4) THEN

    SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fTaxBasis
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = l_strPaymentPeriod )
       AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND gl.activity_id        = '2';       

/*        
        FROM general_ledger
       WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
         AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = l_strPaymentPeriod )
         AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
*/    

    END IF;
    -- Dersom rullerende periode IKKE er i samme år som likviditetsprognosen henter vi fra prognosen    
    IF  substr(i_iRollingPeriod,0,4) <> substr(l_iPeriodId,0,4) THEN
    SELECT NVL(SUM(amount_year*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fTaxBasis
      FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
     WHERE pe.report_level_3_id  = r.report_level_3_id
       AND pe.prognosis_id       = i_iPrognosisId
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId;
   END IF;
      
    IF ((l_iZeroIfNegative = 1) AND (l_fTaxBasis < 0)) THEN l_fTaxBasis :=0; END IF;
    IF ((l_iZeroIfPositive = 1) AND (l_fTaxBasis > 0)) THEN l_fTaxBasis :=0; END IF;
    
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);  
  
  --END IF;
  
  /* Fjernes i følge mld fra Bente 04032014 
  -- SPESIELL BEHANDLING AV MAI 05
  -- SKAL BARE REGNES UT DERSOM LIKVIDITETSPROGNOSEN ER GENERERT I MÅNED 01,02,03 eller 04
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  IF l_iPeriodNo IN (1,2,3,4) THEN
  
    IF substr(i_iRollingPeriod,5,2) = 5 THEN
  
    -- HENTER ET ÅR TIDLIGERE (to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset-1) ENN HVA SOM ER OPPGITT PÅ BETALINGSPERIODER 
    SELECT NVL(SUM(amount),0) INTO l_fTaxBasisYear2
      FROM general_ledger
     WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset-1 || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = '04' )
       AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
    
    SELECT NVL(SUM(amount),0) INTO l_fTaxBasisYear1
      FROM general_ledger
     WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = '04' )
       AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  
   -- l_fTempAmount := ABS(l_fTaxBasisYear1)-ABS(l_fTaxBasisYear2);
    
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,-(l_fTaxBasisYear2-l_fTaxBasisYear1));

--    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
--      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,(l_fTaxBasisYear2-l_fTaxBasisYear1)*-1);
  
    END IF;
  END IF;

*/
END GenerateForGrunnNaturOverskatt;

PROCEDURE GenerateForIBBank ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                              i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                              i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                              i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                              i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                              i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_fAmount             NUMBER(18,2);
  l_fAmountLiquidity    NUMBER(18,2);
  l_iPeriodId           PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
  l_iRollingPeriod      PERIOD.ACC_PERIOD%TYPE;
  
  -- RULLERENDE MND FRA MND 2 -12 
  CURSOR l_curRollingPeriod ( i_rLiquidityId LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE ) IS
   SELECT acc_period 
     FROM period 
    WHERE date_from >= ( SELECT date_from  
                           FROM period   
                          WHERE acc_period = ( SELECT acc_period 
                                                 FROM period 
                                                WHERE date_from = ( SELECT ADD_MONTHS(date_from,2)  -- HOPPER OVER FØRSTE MND SIDEN DENNE REGNES BARE FRA REGNSKAP 
                                                                      FROM period 
                                                                     WHERE acc_period = ( SELECT period 
                                                                                            FROM liquidity_entry_head
                                                                                           WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                         )
                                                                  )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                 
                                             )
                       )
      AND date_from <= ( SELECT date_from
                            FROM period   
                           WHERE acc_period = ( SELECT acc_period 
                                                  FROM period 
                                                 WHERE date_from = ( SELECT ADD_MONTHS(date_from,12) 
                                                                       FROM period 
                                                                       WHERE acc_period = ( SELECT period 
                                                                                              FROM liquidity_entry_head
                                                                                             WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                          )
                                                                   )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                                                               
                                              )
                       )
      AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
 
BEGIN
  SELECT period INTO l_iPeriodId FROM liquidity_entry_head WHERE liquidity_entry_head_id =  i_rLiquidityId;

  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');

  -- Beregn IB fra regnskap frem til første rullerende måned
  SELECT SUM(amount) INTO l_fAmount
    FROM general_ledger gl
   WHERE gl.company_id =  ( SELECT company_id FROM liquidity_entry_head        WHERE liquidity_entry_head_id = i_rLiquidityId)
     AND gl.account_id IN ( SELECT account_id FROM rule_gl_assoc WHERE rule_id =  i_rRuleId )
     AND gl.period >=     ( SELECT acc_period FROM period WHERE date_from = to_date('0101' || SUBSTR(l_iPeriodId,0,4),'DDMMYYYY') AND substr(acc_period,5,2) = '00')  -- STARTEN AV ÅRET
     AND gl.period <=     ( SELECT acc_period FROM period WHERE date_from = to_date('01' || SUBSTR(l_iPeriodId,5,2) || SUBSTR(l_iPeriodId,0,4),'DDMMYYYY')); -- TIl FØRSTE RULLERENDE MND
  
  
  INSERT INTO liquidity_entry_mth_item (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,l_iFirstRollingPeriod,l_fAmount);
      
  COMMIT; 

  -- REGNE UT SALDO FOR RULLERENDE MND 2-12
  OPEN l_curRollingPeriod ( i_rLiquidityId );
  FETCH l_curRollingPeriod INTO l_iRollingPeriod;
  WHILE l_curRollingPeriod%FOUND LOOP
  
    SELECT sum(amount) INTO l_fAmountLiquidity
      FROM liquidity_entry_mth_item 
     WHERE liquidity_entry_head_id = i_rLiquidityId
       AND report_level_3_id IN ( SELECT report_level_3_id FROM report_level_3 WHERE report_type_id = 6 )
       AND period = ( SELECT acc_period FROM period WHERE date_from = ( SELECT ADD_MONTHS(date_from,-1) 
                                                                          FROM period 
                                                                         WHERE acc_period = l_iRollingPeriod )
                                                      AND substr(acc_period,5,2) NOT IN ('00','13'));
       
  
    INSERT INTO liquidity_entry_mth_item (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,l_iRollingPeriod,l_fAmountLiquidity);  
    
    COMMIT;
  
  FETCH l_curRollingPeriod INTO l_iRollingPeriod;
  END LOOP;
  
  CLOSE l_curRollingPeriod;
    
  COMMIT;
END GenerateForIBBank;

/* SLUTT HARDKODING */

/*  GENERATEFORMVA ----KODE FRA FØR FLYTTET TIL FUNKSJONER
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT 
           i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod
          ,NVL(SUM(amount),0)
        FROM general_ledger
        WHERE account_id = ( SELECT closing_balance_account_id FROM rule_entry           WHERE hard_coded_db_proc = 994 )
          AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
          AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
          AND company_id = ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY 
           i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod;
      
         /*
         -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
          i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod --pe.period
          ,NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0)
        FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
       WHERE pe.report_level_3_id = r.report_level_3_id
         AND pe.prognosis_id      = i_iPrognosisId
         AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
         AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND r.rule_id            = re.rule_entry_id
         AND re.rule_entry_id     = i_rRuleId
       GROUP BY 
          i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod;
         */ 
       -- NOTELINJE
       /*
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,i_iRollingPeriod
        ,SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
       FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
      WHERE pne.note_line_id         = r.note_line_id
        AND pne.prognosis_entry_id   = pe.prognosis_entry_id
        AND r.rule_id                = re.rule_entry_id
        AND re.rule_entry_id         = i_rRuleId
        AND pe.prognosis_id          = i_iPrognosisId
        AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
        AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
        AND r.rule_note_line_included_in = 3 -- Gjelder for utregning av r3 prognose/resultat
      GROUP BY 
        i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,i_iRollingPeriod;create or replace PACKAGE BODY "LIQUIDITY_API" AS
  g_strCompanyId            COMPANY.COMPANY_ID%TYPE;
  g_iPeriodId               PERIOD.ACC_PERIOD%TYPE;
  
  -- Regelegenskaper
  g_bUsePaymentPeriodAssoc     RULE_ENTRY.USE_RULE_PERIOD_PAYMENT_DATE%TYPE := 0;

/************************************************************************
*
* NAME
*   LIQUIDITY_API.Generate 
* FUNCTION
*   Main procedure in package LIQUIDITY_API. 
* NOTES
*   Input format is STRING : <LiquidityId> i.e '7A90628C85707D49808B59EA3E1AD9AA'
*
* MODIFIED
*     oig     20.04.2010 - created
*
**************************************************************************/
PROCEDURE Generate ( i_strParam  IN VARCHAR ) 
IS
 l_exNoPrognosisFound      EXCEPTION;
 l_exNoJournalFound        EXCEPTION;
 l_exOther                 EXCEPTION;
 l_iJournalCount           NUMBER(11,0);
 l_iType                   NUMBER(11,0);
 l_rLiquidityId            LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE;
 l_rLiquidityEntryMonth    LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE; 
 l_rCurrentMonthRow        LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE; 
  
 l_rRuleId                 RULE_ENTRY.RULE_ENTRY_ID%TYPE;
 l_rHardCodedRuleId        RULE_ENTRY.RULE_ENTRY_ID%TYPE;
-- l_iPeriodId               PERIOD.ACC_PERIOD%TYPE;
 l_iRollingPeriod          PERIOD.ACC_PERIOD%TYPE;
 l_iRollingDiff            NUMBER(11,0);  
 l_iPaymentSource          NUMBER(11,0);
 
 l_iPeriodMonth1           PERIOD.ACC_PERIOD%TYPE;
 l_iPeriodMonth2           PERIOD.ACC_PERIOD%TYPE;
 l_iPeriodMonth3           PERIOD.ACC_PERIOD%TYPE;
 
 l_iPrognosisId            PROGNOSIS.PROGNOSIS_ID%TYPE;
 l_iLiquidityReportLineId  REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
 l_iNotToBeSpecifiedOnDay  REPORT_LEVEL_3.LIQUDITY_DO_NOT_SPECIFY_ON_DAY%TYPE;
 l_iIncludeVoucherTemplate NUMBER(11,0);
 l_iOrgLevel               NUMBER(11,0);
 
 l_iFetchFromPreModule  NUMBER(11,0);
 l_iFetchFromBudget     NUMBER(11,0);
 l_iFetchFromLTP        NUMBER(11,0);
 l_iFetchFromGL         NUMBER(11,0);
 l_iFetchFromPrognosis  NUMBER(11,0);   
 l_iFetchFromNoteLine   NUMBER(11,0);
 l_iFetchFromInvestment NUMBER(11,0);
 
 /* Erstattes av l_iFetchFromXXXXX
 
 l_iUseGLAsSrcForAccounts         NUMBER(11,0);
 l_iUseBudgetAsSrcForAccounts     NUMBER(11,0);
 l_iUseProgAsSrcForAccounts       NUMBER(11,0);
 l_iUseLTPAsSrcForAccounts        NUMBER(11,0);
 l_iUseNoteLineAsSrcForAccounts   NUMBER(11,0);
 l_iUseInvestAsSrcForAccounts     NUMBER(11,0);
 */
 
 l_bUsePaymentSourceMatrix    RULE_ENTRY.USE_RULE_PERIOD_PAYMENT_MATRIX%TYPE;
 l_bShiftToPreviousWorkingDay RULE_ENTRY.SHIFT_TO_PREVIOUS_WORKING_DAY%TYPE;
 l_bShiftToNextWorkingDay     RULE_ENTRY.SHIFT_TO_NEXT_WORKING_DAY%TYPE;
 l_dtCurrentRolling           CALENDAR.CALENDAR_DATE%TYPE;
 l_iIsHoliday                 NUMBER(11,0);
 l_iPaymentFrequencyId        RULE_ENTRY.PAYMENT_FREQUENCY_ID%TYPE;
 l_iPaymentMonthNo            RULE_ENTRY.PAYMENT_MONTH_NO%TYPE;
 l_iPaymentDayNo              RULE_ENTRY.PAYMENT_DAY_NO%TYPE;
 l_iManualEditedRowCount      NUMBER(11,0); -- For sjekke om det finnes manuelt registrerte poster
 l_iMatrixSource              NUMBER(11,0); --Brukes som kildeindikator for beregning 
 l_iPaymentPeriodCount        NUMBER(11,0);
 
 l_strR3Name                 REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 
 l_rliquidity_entry_mth_item_id LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE;  -- For å genere id ved flytting fra tmp til prod
 
 -- Finn alle konteringsregler for likvidtet
 CURSOR l_curLiquidityRule IS 
   SELECT rule_entry_id 
     FROM rule_entry 
    WHERE rule_type_id = 3                       -- LIKVIDITET
      AND hard_coded_db_proc IS NULL    -- IKKE TA REGLER SOM ER SPESIELLE, EKS MANUELLE, HARDKODEDE ETC
      AND use_internal_calculation = 0           -- BRUK INTERN KALKULASJON = FALSE 
     -- AND rule_entry_id ='C00D0DC0F8B5E449B5D412CB65772BBE'
   ORDER BY rule_entry_order; 
   
 -- Finn hardkodede konteringsregler for likvidtet
 CURSOR l_curHardCodedLiquidityRule ( i_iFormulaId RULE_ENTRY.hard_coded_db_proc%TYPE ) IS
   SELECT rule_entry_id 
     FROM rule_entry 
    WHERE rule_type_id = 3                        -- LIKVIDITET
      AND hard_coded_db_proc = i_iFormulaId
   ORDER BY rule_entry_order; 

 -- FINN ALLE R3 LINJER FOR LIKVIDITET FOR EN GITT KONTERINGSREGEL
 /* OIG 31.08.15 Endret til å ta høyde for en regel pr r3 pr selskap
 CURSOR l_curLiquidityR3ForRuleEntry ( i_rRuleId RULE_ENTRY.RULE_ENTRY_ID%TYPE ) IS
   SELECT report_level_3_id 
     FROM report_level_3 
    WHERE rule_id_liquidity = i_rRuleId
      AND report_type_id    = 6;  -- LIKVIDITET 
 */
 CURSOR l_curLiquidityR3ForRuleEntry ( i_rRuleId RULE_ENTRY.RULE_ENTRY_ID%TYPE, i_strCompanyId COMPANY.COMPANY_ID%TYPE ) IS
   SELECT rel.report_level_3_id 
     FROM r3_rule_company_relation rel, report_level_3 r3
    WHERE rel.report_level_3_id  = r3.report_level_3_id 
      AND rel.rule_id            = i_rRuleId
      AND rel.company_id        = i_strCompanyId
      AND rel.is_enabled        = 1
      AND r3. report_type_id    = 6;  -- LIKVIDITET 
      
 CURSOR l_curPaymentPeriodOperator (i_rRuleId RULE_ENTRY.RULE_ENTRY_ID%TYPE , i_iRollingPeriod PERIOD.ACC_PERIOD%TYPE) IS
 --BEGIN
    SELECT * --logical_operator 
      FROM rule_period_payment_src_calc 
     WHERE rule_period_payment_id IN ( SELECT RULE_PERIOD_PAYMENT_ID 
                                         FROM RULE_PERIOD_PAYMENT 
                                        WHERE rule_entry_id  = i_rRuleId --'C00D0DC0F8B5E449B5D412CB65772BBE' 
                                          AND period_payment = SUBSTR(i_iRollingPeriod,5,2));
  --EXCEPTION WHEN TOO_MANY_ROWS THEN DBMS_OUTPUT.PUT_LINE('Regel: ' || i_rRuleId || ' - Periode: ' || i_iRollingPeriod);
  --END;

   l_recRulePeriodPaymentSrcCalc l_curPaymentPeriodOperator%ROWTYPE;
 
 -- FINN ALLE RULLERENDE PERIODER - 12 STK     
 CURSOR l_curRollingPeriod ( i_rLiquidityId LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE ) IS
   SELECT acc_period 
     FROM period 
    WHERE date_from >= ( SELECT date_from  
                           FROM period   
                          WHERE acc_period = ( SELECT acc_period 
                                                 FROM period 
                                                WHERE date_from = ( SELECT ADD_MONTHS(date_from,1) 
                                                                      FROM period 
                                                                     WHERE acc_period = ( SELECT period 
                                                                                            FROM liquidity_entry_head
                                                                                           WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                         )
                                                                  )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                 
                                             )
                       )
      AND date_from <= ( SELECT date_from
                            FROM period   
                           WHERE acc_period = ( SELECT acc_period 
                                                  FROM period 
                                                 WHERE date_from = ( SELECT ADD_MONTHS(date_from,12) 
                                                                       FROM period 
                                                                       WHERE acc_period = ( SELECT period 
                                                                                              FROM liquidity_entry_head
                                                                                             WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                          )
                                                                   )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                                                               
                                              )
                       )
      AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
 
 -- FINN ALLE RADER SOM SKAL SPESIFISERES PÅ… DAG, DVS DE TRE FØRSTE MND
 CURSOR l_curMonthToBeSpecifiedToDay ( i_rLiquidityId LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE ) IS
 SELECT liquidity_entry_mth_item_id
   FROM liquidity_entry_mth_item 
  WHERE liquidity_entry_head_id = i_rLiquidityId
    AND period IN (l_iPeriodMonth1,l_iPeriodMonth2,l_iPeriodMonth3)
    ORDER BY period;
    
BEGIN
  g_ReturnCode := -1;
  
  -- KONVERTER GUID TO RAW FOR Å FÅ RIKTIG ID
  --SJEKK FORMAT PÅ INNPARAMETER OG KONVERTER GUID TO RAW FOR Å FÅ RIKTIG ID DERSOM NØDVENDIG
  IF INSTR(i_strParam,'-') <> 0 THEN l_rLiquidityId := g_guidtoraw(i_strParam); ELSE l_rLiquidityId := i_strParam; END IF;
  
  -- SJEKK OM VI FINNER LIKVIDITETSPROGNOSEN
  SELECT count(*) INTO l_iJournalCount FROM liquidity_entry_head WHERE liquidity_entry_head_id =  l_rLiquidityId;
  IF l_iJournalCount <> 1 THEN 
    RAISE l_exNoJournalFound;
  END IF;
   
  -- HENT SELSKAP OG PERIODE FRA LIKVIDITETSPROGNOSEN
  SELECT company_id INTO g_strCompanyId FROM liquidity_entry_head WHERE liquidity_entry_head_id =  l_rLiquidityId;
  SELECT period     INTO g_iPeriodId   FROM liquidity_entry_head WHERE liquidity_entry_head_id =  l_rLiquidityId;
  -- FINN DE FØRSTE TRE PERIODENE (FOR UTREGNING PÅ DAG)
  SELECT acc_period 
    INTO l_iPeriodMonth1 
    FROM period 
   WHERE date_from = ( SELECT date_from FROM period  WHERE acc_period = 
                       ( SELECT acc_period FROM period  WHERE date_from = 
                         ( SELECT ADD_MONTHS(date_from,1) FROM period WHERE acc_period = 
                           ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = l_rLiquidityId))
                           AND SUBSTR(acc_period,5,2) NOT IN ('00','13')))
     AND SUBSTR(acc_period,5,2) NOT IN ('00','13');                           

  SELECT acc_period 
    INTO l_iPeriodMonth2 
    FROM period 
   WHERE date_from = ( SELECT date_from FROM period  WHERE acc_period = 
                       ( SELECT acc_period FROM period  WHERE date_from = 
                         ( SELECT ADD_MONTHS(date_from,2) FROM period WHERE acc_period = 
                           ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = l_rLiquidityId))
                           AND SUBSTR(acc_period,5,2) NOT IN ('00','13')))
     AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
     
  SELECT acc_period 
    INTO l_iPeriodMonth3
    FROM period 
   WHERE date_from = ( SELECT date_from FROM period  WHERE acc_period = 
                       ( SELECT acc_period FROM period  WHERE date_from = 
                         ( SELECT ADD_MONTHS(date_from,3) FROM period WHERE acc_period = 
                           ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = l_rLiquidityId))
                           AND SUBSTR(acc_period,5,2) NOT IN ('00','13')))
     AND SUBSTR(acc_period,5,2) NOT IN ('00','13');

  -- FINN PROGNOSE FOR GJELDENDE LIKVIDITETSPROGNOSE
  -- Denne kan fjernes da situasjonen håndteres i Genus.
 /*
  BEGIN
    SELECT prognosis_id 
      INTO l_iPrognosisId 
      FROM prognosis 
     WHERE company_id = g_strCompanyId
       AND period     = g_iPeriodId;
  EXCEPTION
  WHEN NO_DATA_FOUND THEN RAISE l_exNoPrognosisFound;
  END ;
  */
  -- Finn siste godkjente prognose  
  SELECT prognosis_id INTO l_iPrognosisId  
    FROM ( SELECT prognosis_id 
              FROM prognosis 
             WHERE company_id = g_strCompanyId
               AND prognosis_status_tp = 3
            ORDER BY period DESC
          )
  WHERE rownum < 2;   
       

  -- FJERN TIDLIGERE BEREGNEDE RADER
  DELETE FROM liquidity_entry_mth_item_tmp;
  DELETE FROM liquidity_entry_mth_salary_tmp;
  
  DELETE 
    FROM liquidity_entry_mth_item 
   WHERE liquidity_entry_head_id = l_rLiquidityId
     AND edited_by_user = 0   -- IKKE FJERN MANUELT ENDREDE RADER
     AND nvl(source_id,1) <> 2 -- IKKE FJERN INFO HENTET FRA BANK
     AND report_level_3_id NOT IN ( SELECT rel.report_level_3_id 
                                       FROM r3_rule_company_relation rel, report_level_3 r3 
                                      WHERE rel.report_level_3_id  = r3.report_level_3_id 
                                        AND rel.company_id = g_strCompanyId
                                        AND rel.is_enabled = 1
                                        AND r3.report_type_id = 6   -- LIKVIDITET
                                        AND rel.rule_id IN ( SELECT rule_entry_id FROM rule_entry WHERE hard_coded_db_proc = 1 )); -- IKKE TA MED R3 rader som er markert med databaseprosedye "1 - Manuell registrering"
                                      
  DELETE 
    FROM liquidity_entry_day_item 
   WHERE liquidity_entry_head_id = l_rLiquidityId
     AND edited_by_user = 0  -- IKKE FJERN MANUELT ENDREDE RADER
     AND nvl(source_id,1) <> 2 -- IKKE FJERN INFO HENTET FRA BANK
     AND report_level_3_id NOT IN ( SELECT rel.report_level_3_id 
                                       FROM r3_rule_company_relation rel, report_level_3 r3 
                                      WHERE rel.report_level_3_id  = r3.report_level_3_id 
                                        AND rel.company_id = g_strCompanyId
                                        AND rel.is_enabled = 1                                        
                                        AND r3.report_type_id = 6   -- LIKVIDITET
                                        AND rel.rule_id IN ( SELECT rule_entry_id FROM rule_entry WHERE hard_coded_db_proc = 1 )); -- IKKE TA MED R3 rader som er markert med databaseprosedye "1 - Manuell registrering"
                                       
  COMMIT;                                       
  
  
  OPEN l_curLiquidityRule;
  FETCH l_curLiquidityRule INTO l_rRuleId;
  WHILE l_curLiquidityRule%FOUND LOOP
  
     -- Sjekk om regelen skal hente data fra forsystem - støtte
     SELECT count(*) INTO l_iFetchFromPreModule    FROM rule_r3_for_pre_module_assoc WHERE rule_id = l_rRuleId;  
     -- Sjekk om regelen skal hente data fra Budsjett
     SELECT count(*) INTO l_iFetchFromBudget       FROM rule_budget_assoc            WHERE rule_id = l_rRuleId;  
     -- Sjekk om regelen skal hente data fra LTP
     SELECT count(*) INTO l_iFetchFromLTP          FROM rule_ltp_assoc               WHERE rule_id = l_rRuleId;  
     -- Sjekk om regelen skal hente data fra hovedboken
     SELECT count(*) INTO l_iFetchFromGL           FROM rule_gl_assoc                WHERE rule_id = l_rRuleId;  -- l_iLiqudityFromAccounts --> l_iFetchFromGL
     -- Sjekk om regelen skal hente data fra prognose
     SELECT count(*) INTO l_iFetchFromPrognosis    FROM rule_prognosis_assoc         WHERE rule_id = l_rRuleId;
     -- Sjekk om regelen skal hente data fra notelinje
     SELECT count(*) INTO l_iFetchFromNoteLine FROM rule_note_line_assoc             WHERE rule_id = l_rRuleId;
     -- Sjekk om regelen skal hente data fra investering
     SELECT count(*) INTO l_iFetchFromInvestment   FROM rule_investment_progno_assoc WHERE rule_id = l_rRuleId;

    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
       -- For debug
       SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = l_iLiquidityReportLineId;
      -- Sjekk om det er betalinger som skal utføres i gjeldende periode for regel og R3
      -- Bruke tilknytning for betalingsperioder eller direkte på regelen?
      SELECT use_rule_period_payment_date  INTO g_bUsePaymentPeriodAssoc     FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Bruke kildematrise?
      SELECT use_rule_period_payment_matrix INTO l_bUsePaymentSourceMatrix   FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Sjekk om betaling skal flyttes til nærmeste forrige arbeisdag
      SELECT shift_to_previous_working_day INTO l_bShiftToPreviousWorkingDay FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Eller om betaling skal flyttes til nærmeste neste arbeisdag
      SELECT shift_to_next_working_day     INTO l_bShiftToNextWorkingDay     FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Hent betalingsfrekvens for regel
      SELECT NVL(payment_frequency_id,1)   INTO l_iPaymentFrequencyId        FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Hent betalingsmåned - benyttes dersom frekvens er årlig
      SELECT payment_month_no              INTO l_iPaymentMonthNo            FROM rule_entry where rule_entry_id = l_rRuleId;
      -- Hent betalingsdag 
      SELECT payment_day_no                INTO l_iPaymentDayNo              FROM rule_entry WHERE rule_entry_id = l_rRuleId;
      
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP

          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;
        
        --Gå ut hvis det er manuelle rader
        IF l_iManualEditedRowCount > 0 THEN 
           RETURN;
        END IF;
        
           l_iPaymentSource              := 1;
         /* DISABLED 25022016 grunnet endringer på bakgrunn av møte med Annte og Brit 28.01.2016 
         Koden nedenfor er tidligere benyttet for angivelse av kilde for Brutto fakturerte nettinntekter - Dobbeltklikk på betalingsperioderaden
         -- Finn diff mellom den rullerende perioden og gjeldende likviditetsprognose
         SELECT l_iRollingPeriod - g_iPeriodId INTO l_iRollingDiff FROM DUAL;
         -- Setter default kilde
         l_iPaymentSource              := 1;
         l_recRulePeriodPaymentSrcCalc := null;
         
         FOR rec IN l_curPaymentPeriodOperator (l_rRuleId,l_iRollingPeriod)
         LOOP
           CASE rec.logical_operator
             WHEN 1 THEN
               BEGIN
                  SELECT * INTO l_recRulePeriodPaymentSrcCalc
                   FROM rule_period_payment_src_calc 
                  WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                     FROM rule_period_payment 
                                                    WHERE rule_entry_id = l_rRuleId 
                                                      AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                    AND l_iRollingDiff = rule_source_limit
                    AND logical_operator = 1;
                 EXCEPTION WHEN NO_DATA_FOUND THEN null;
               END;
             WHEN 2 THEN
               BEGIN
                  SELECT * INTO l_recRulePeriodPaymentSrcCalc
                   FROM rule_period_payment_src_calc 
                  WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                     FROM rule_period_payment 
                                                    WHERE rule_entry_id = l_rRuleId 
                                                      AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                    AND l_iRollingDiff <> rule_source_limit
                    AND logical_operator = 2;
                 EXCEPTION WHEN NO_DATA_FOUND THEN null;
               END;
             WHEN 3 THEN
             BEGIN
                 SELECT * INTO l_recRulePeriodPaymentSrcCalc
                 FROM rule_period_payment_src_calc 
                WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                   FROM rule_period_payment 
                                                  WHERE rule_entry_id = l_rRuleId 
                                                    AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                  AND l_iRollingDiff > rule_source_limit
                  AND l_iRollingDiff < NVL(rule_source_limit_2,50)  --- Denne må implementeres grudigere
                  AND logical_operator = 3;
                    EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;
             WHEN 4 THEN
             BEGIN
                 SELECT * INTO l_recRulePeriodPaymentSrcCalc
                 FROM rule_period_payment_src_calc 
                WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                   FROM rule_period_payment 
                                                  WHERE rule_entry_id = l_rRuleId 
                                                    AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                  AND l_iRollingDiff >= rule_source_limit
                  AND l_iRollingDiff < NVL(rule_source_limit_2,50)
                  AND logical_operator = 4;
                    EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;
             WHEN 5 THEN
             BEGIN
                 SELECT * INTO l_recRulePeriodPaymentSrcCalc
                 FROM rule_period_payment_src_calc 
                WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                   FROM rule_period_payment 
                                                  WHERE rule_entry_id = l_rRuleId 
                                                    AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                  AND l_iRollingDiff < rule_source_limit
                  AND logical_operator = 5;
                  EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;  
             WHEN 6 THEN
                BEGIN
                   SELECT * INTO l_recRulePeriodPaymentSrcCalc
                    FROM rule_period_payment_src_calc 
                   WHERE rule_period_payment_id = ( SELECT rule_period_payment_id 
                                                      FROM rule_period_payment 
                                                     WHERE rule_entry_id = l_rRuleId 
                                                       AND period_payment = SUBSTR(l_iRollingPeriod,5,2))
                    AND l_iRollingDiff <= rule_source_limit
                    AND logical_operator = 6;
                  EXCEPTION WHEN NO_DATA_FOUND THEN null;
                  END;
             ELSE NULL;
           END CASE;
         
         END LOOP;         
         
         IF l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id IS NOT NULL THEN l_iPaymentSource := l_recRulePeriodPaymentSrcCalc.rule_source_id; END IF;
 */
 
        IF g_bUsePaymentPeriodAssoc = 0 THEN
          --Ikke bruk betalingsperiodetilknytning
          CASE l_iPaymentFrequencyId 
            WHEN 1 THEN -- Månedlig (default)
              -- IF ((l_iFetchFromGL > 0) AND (l_iRowCount = 0)) THEN 
             --     GenerateRowFromAccounts( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); END IF;
               IF ((l_iFetchFromPrognosis > 0) AND (l_iManualEditedRowCount = 0)) THEN 
                  GenerateRowFromPrognosis( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromNoteLine  > 0) AND (l_iManualEditedRowCount = 0)) THEN 
                  GenerateRowFromNoteLine ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromInvestment  > 0) AND (l_iManualEditedRowCount = 0)) THEN 
                  GenerateRowFromInvestment ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;

            WHEN 2 THEN -- Kvartalsvis
              null;
            WHEN 3 THEN -- Årlig
               IF ((l_iFetchFromPrognosis > 0) AND (l_iManualEditedRowCount = 0) AND (l_iPaymentMonthNo = to_number(substr(l_iRollingPeriod,5,2)))) THEN 
                  GenerateRowFromPrognosis( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromNoteLine  > 0) AND (l_iManualEditedRowCount = 0) AND (l_iPaymentMonthNo = to_number(substr(l_iRollingPeriod,5,2)))) THEN 
                  GenerateRowFromNoteLine ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;
               IF ((l_iFetchFromInvestment  > 0) AND (l_iManualEditedRowCount = 0) AND (l_iPaymentMonthNo = to_number(substr(l_iRollingPeriod,5,2)))) THEN 
                  GenerateRowFromInvestment ( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); END IF;

            ELSE null; -- Do nothing
          END CASE;
        ELSE -- BRUKE BETALINGSPERIODER OG IKKE HARDKODET

          BEGIN    -- Er det utbetalinger på denne rullerende periode? Hopp ut dersom det ikke er det 
            SELECT COUNT(DISTINCT period_payment) INTO l_iPaymentPeriodCount
              FROM rule_period_payment 
             WHERE rule_entry_id = l_rRuleId
               AND period_payment =  substr(l_iRollingPeriod,5,2);        
          EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
          END;

          CASE l_iPaymentFrequencyId 
            WHEN 1 THEN -- Månedlig (default)
               IF l_bUsePaymentSourceMatrix = 1 THEN -- Bruk kildematrise
               
                   -- Fetch info from source matrix (1 - Regnskap, 2 - Prognose, 3 - Delt)
                   SELECT NVL(source_id,1) INTO l_iMatrixSource
                     FROM rule_calc_matrix_liquidity 
                    WHERE rule_entry_id = l_rRuleId
                      AND liq_entry_head_period = SUBSTR(g_iPeriodId,5,2) 
                      AND liq_entry_head_rolling_period = SUBSTR(l_iRollingPeriod,5,2);
               
                 IF ((l_iMatrixSource = 1) AND (l_iFetchFromGL > 0)) THEN 
                      GenerateRowFromAccounts( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;

                 IF ((l_iMatrixSource = 2) AND (l_iFetchFromPrognosis > 0)) THEN 
                      GenerateRowFromPrognosis( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); 
                 END IF;

                 IF ((l_iMatrixSource = 3) AND (l_iFetchFromGL > 0) AND (l_iFetchFromPrognosis = 1)) THEN 
                      GenerateRowFromGL5050( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                      GenerateRowFromPrognosis5050( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling); 
                 END IF;
               END IF; -- l_bUsePaymentSourceMatrix = 1

              IF l_bUsePaymentSourceMatrix = 0 THEN -- Ikke bruk kildematrise

                 IF ((l_iFetchFromGL > 0) AND (l_iPaymentSource = 1)) THEN 
                    GenerateRowFromAccounts( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;
                 IF ((l_iFetchFromBudget > 0) AND (l_iPaymentSource = 2)) THEN 
                    GenerateRowFromBudget( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;
                 IF l_iFetchFromPreModule > 0 THEN 
                    GenerateRowFromPreModule( l_rLiquidityId,l_rRuleId, l_iPrognosisId, l_iLiquidityReportLineId, l_iRollingPeriod, l_dtCurrentRolling,l_recRulePeriodPaymentSrcCalc.rule_per_pay_src_calc_id); 
                 END IF;
              END IF;
            WHEN 2 THEN null; 
          END CASE;
         END IF; --l_bUsePaymentPeriodAssoc = 0 BRUKE BETALINGSPERIODER?

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;
    
  
  FETCH l_curLiquidityRule INTO l_rRuleId;
  END LOOP;
  CLOSE l_curLiquidityRule;
  
  -- KALL PROSEDYRER FOR HARDKODEDE RADER
  -- Sjekke om prosedyre for lønn er benyttet
  -- Tøm temporær tabell
  DELETE liquidity_entry_item_tax_tmp;
  DELETE liquidity_entry_mth_salary_tmp;
  
  OPEN l_curHardCodedLiquidityRule ( 993 );   --993 = LØNN
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
      
         -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

         IF l_iManualEditedRowCount = 0 THEN 
           GenerateForLonn         (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
         END IF;
      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;
  
  -- Sjekke om prosedyre for MVA er benyttet
  OPEN l_curHardCodedLiquidityRule ( 994 );   --994 = MVA
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForMVA (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  OPEN l_curHardCodedLiquidityRule ( 992 );   --993 = ELAVGIFT
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
      
         -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

         IF l_iManualEditedRowCount = 0 THEN 
           GenerateForELAvgift         (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
         END IF;
      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  -- Sjekke om prosedyre for Nettinntekter Husholdning/Privat er benyttet
  OPEN l_curHardCodedLiquidityRule ( 9912 );   --9912 = Nettinntekter Husholdning/Privat
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForNettleiePrivat (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  -- Sjekke om prosedyre for ENOVA er benyttet
  OPEN l_curHardCodedLiquidityRule ( 995 );   --995 = ENOVA
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForEnovaAvgift (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;

  -- Sjekke om prosedyre for Grunnrente-, naturressurs og overskuddsskatt er benyttet
  OPEN l_curHardCodedLiquidityRule ( 996 );   --996 = Grunnrente-, naturressurs og overskuddsskatt
  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  WHILE l_curHardCodedLiquidityRule%FOUND LOOP
  
    -- Finn likviditetsrader for gjeldende formel
    OPEN l_curLiquidityR3ForRuleEntry ( l_rHardCodedRuleId, g_strCompanyId );
    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    WHILE l_curLiquidityR3ForRuleEntry%FOUND LOOP
    
      -- Beregn beløp for hver periode, R3 rad og regel - en iterasjon pr celle
      OPEN l_curRollingPeriod ( l_rLiquidityId );
      FETCH l_curRollingPeriod INTO l_iRollingPeriod;
      WHILE l_curRollingPeriod%FOUND LOOP
       
          -- Sjekk om denne posten finnes fra før som en manuelt registrert post
          SELECT count(*) 
            INTO l_iManualEditedRowCount 
            FROM liquidity_entry_mth_item
           WHERE liquidity_entry_head_id = l_rLiquidityId
             AND report_level_3_id       = l_iLiquidityReportLineId
             AND period                  = l_iRollingPeriod
             AND edited_by_user          = 1;

        IF l_iManualEditedRowCount = 0 THEN
          GenerateForGrunnNaturOverSkatt (l_rLiquidityId,l_rHardCodedRuleId,l_iPrognosisId,l_iLiquidityReportLineId,l_iRollingPeriod,null);
        END IF;

      FETCH l_curRollingPeriod INTO l_iRollingPeriod; 
      END LOOP;
      CLOSE l_curRollingPeriod;

    FETCH l_curLiquidityR3ForRuleEntry INTO l_iLiquidityReportLineId;
    END LOOP;
    CLOSE l_curLiquidityR3ForRuleEntry;

  FETCH l_curHardCodedLiquidityRule INTO l_rHardCodedRuleId;
  END LOOP;
  CLOSE l_curHardCodedLiquidityRule;


  -- END: KALL PROSEDYRER FOR HARDKODEDE RADER
  -- FLYTT TEMP-RADER TIL PROD FOR MÅNED
    
  INSERT INTO liquidity_entry_mth_item
         --(liquidity_entry_mth_item_id
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount
         ,liquidity_entry_mth_comment)
    SELECT
       --l_rliquidity_entry_mth_item_id --'E1' --sys_guid()  --Fjernet: Håndtert av default verdi på kolonnen
      liquidity_entry_head_id
      ,report_level_3_id
      ,period
      ,SUM(amount)
      ,null
    FROM liquidity_entry_mth_item_tmp
    GROUP BY
      --l_rliquidity_entry_mth_item_id  --'E1'  --sys_guid()
      liquidity_entry_head_id
      ,report_level_3_id
      ,period;
  
    UPDATE liquidity_entry_mth_item 
       SET liquidity_entry_mth_item_id = sys_guid() 
     WHERE liquidity_entry_mth_item_id IS NULL
       AND liquidity_entry_head_id = l_rLiquidityId;
  
  COMMIT;
  
  -- SPESIFISER MND NED TIL DAG FOR DE TRE FØRSTE MND
  OPEN l_curMonthToBeSpecifiedToDay ( l_rLiquidityId );
  FETCH l_curMonthToBeSpecifiedToDay INTO l_rCurrentMonthRow;
  WHILE l_curMonthToBeSpecifiedToDay%FOUND LOOP
  
    -- Sjekk om raden er endret manuelt
    SELECT count(*) INTO l_iManualEditedRowCount
      FROM liquidity_entry_day_item 
     WHERE liquidity_entry_mth_item_id = l_rCurrentMonthRow
       AND edited_by_user = 1;
       
    BEGIN
      SELECT liqudity_do_not_specify_on_day INTO l_iNotToBeSpecifiedOnDay
        FROM report_level_3 WHERE report_level_3_id = ( SELECT report_level_3_id 
                                                          FROM liquidity_entry_mth_item 
                                                         WHERE liquidity_entry_mth_item_id = l_rCurrentMonthRow );
      EXCEPTION WHEN NO_DATA_FOUND THEN l_iNotToBeSpecifiedOnDay := 0;
    END; 
       
    IF ((l_iManualEditedRowCount = 0) AND (l_iNotToBeSpecifiedOnDay <> 1)) THEN
      GenerateRowForDay ( l_rCurrentMonthRow );
    END IF;
  
  FETCH l_curMonthToBeSpecifiedToDay INTO l_rCurrentMonthRow;
  END LOOP;
  CLOSE l_curMonthToBeSpecifiedToDay;


  -- KALL PROSEDYRE FOR IB BANK, DENNE MÅ KJØRES HELT TIL SLUTT DA DENNE BRUKER TIDLIGERE BEREGNEDE TALL
  -- BARE EN LINJE MED DENNE REGELEN
  SELECT rule_entry_id     INTO l_rHardCodedRuleId       FROM rule_entry     WHERE hard_coded_db_proc = 1000;
  BEGIN
    SELECT report_level_3_id INTO l_iLiquidityReportLineId FROM r3_rule_company_relation  WHERE rule_id = l_rHardCodedRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iLiquidityReportLineId := NULL;
  END;
  
   IF l_rLiquidityId           IS NOT NULL
  AND l_rHardCodedRuleId       IS NOT NULL
  AND l_iPrognosisId           IS NOT NULL
  AND l_iLiquidityReportLineId IS NOT NULL THEN
  
     GenerateForIBBank (l_rLiquidityId, l_rHardCodedRuleId, l_iPrognosisId, l_iLiquidityReportLineId, null, null);
  
  END IF;

  EXCEPTION 
    --WHEN l_exNoPrognosisFound THEN raise_application_error (-20601,'Finner ingen godkjent prognose for selskapet for periode ' || g_iPeriodId || '.' || chr(13) || chr(10)|| chr(13) || chr(10));
    WHEN l_exNoJournalFound   THEN raise_application_error (-20602,'Finner ingen likviditetsjournal. Kontakt systemansvarlig. ' || chr(13) || chr(10)|| chr(13) || chr(10));
    WHEN l_exOther            THEN raise_application_error (-20603,'Ukjent feil. Kontakt systemansvarlig. ' || chr(13) || chr(10)|| chr(13) || chr(10));
END Generate;

PROCEDURE GenerateRowFromPreModule ( i_rLiquidityId         IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                    i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                    i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                    i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                    i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                    i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                    i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
 l_iCurrentPeriod      PERIOD.ACC_PERIOD%TYPE;
 l_dtStartRollingDate  PERIOD.DATE_FROM%TYPE;
 l_dtEndRollingDate    PERIOD.DATE_TO%TYPE;
 l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
 l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
 l_strR3Name           REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 l_iYearOffset NUMBER(11,0);
 
 l_iUseSameNumberForAllMonths NUMBER(11,0);

BEGIN
  /* Initialiser parametre */
  SELECT period     INTO l_iCurrentPeriod      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  --SELECT company_id INTO l_strCompanyId        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT date_from  INTO l_dtStartRollingDate  FROM period    WHERE acc_period  = (SELECT acc_period FROM period WHERE date_from = (SELECT ADD_MONTHS(date_from,1) FROM period where acc_period = l_iCurrentPeriod AND substr(acc_period,5,2) NOT IN ('00','13')) AND substr(acc_period,5,2) NOT IN ('00','13'));
  SELECT date_from  INTO l_dtEndRollingDate    FROM period    WHERE date_from    = ADD_MONTHS(l_dtStartRollingDate,12) AND substr(acc_period,5,2) NOT IN ('00','13');
  SELECT acc_period INTO l_iFirstRollingPeriod FROM period    WHERE date_from    = l_dtStartRollingDate                AND substr(acc_period,5,2) NOT IN ('00','13');
  -- For debug
  SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = i_iLiquidityReportLineId;
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
     WHERE rule_entry_id  = i_rRuleId
       AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Skal beløpet fremskrives?  
  BEGIN
    SELECT NVL(liqudity_use_same_for_all_mths,0) INTO l_iUseSameNumberForAllMonths FROM rule_entry WHERE rule_entry_id = i_rRuleId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iUseSameNumberForAllMonths := 0;
  END;
  
  IF l_iUseSameNumberForAllMonths = 0 THEN
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(pre_msf.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM pre_module_supporting_figures pre_msf, 
            rule_period_payment rp, 
            rule_r3_for_pre_module_assoc gla
      WHERE pre_msf.report_level_3_id       = gla.report_level_3_id
        AND rp.rule_entry_id                = gla.rule_id
        AND substr(pre_msf.period,5,2)      = rp.period_basis
        AND rp.rule_entry_id                = i_rRuleId 
        AND rp.period_payment               = l_strPaymentPeriod
        AND pre_msf.liquidity_entry_head_id = i_rLiquidityId
        AND substr(pre_msf.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(pre_msf.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset;

  END IF;
  
  /*
  IF l_iUseSameNumberForAllMonths = 1 THEN
    IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
    ELSE
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(amount)
       FROM liquidity_entry_mth_item_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id = i_iLiquidityReportLineId
         AND period = (SELECT acc_period 
                         FROM period 
                        WHERE date_from = (SELECT ADD_MONTHS(date_from,-1) FROM period WHERE acc_period = i_iRollingPeriod AND substr(acc_period,5,2) NOT IN ('00','13'))
                          AND substr(acc_period,5,2) NOT IN ('00','13') 
                      )
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
    
    END IF;
  END IF;
 */
  COMMIT;
END GenerateRowFromPreModule;



PROCEDURE GenerateRowFromAccounts ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                     i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                    i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                    i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                    i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                    i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                    i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
 l_iCurrentPeriod      PERIOD.ACC_PERIOD%TYPE;
 l_dtStartRollingDate  PERIOD.DATE_FROM%TYPE;
 l_dtEndRollingDate    PERIOD.DATE_TO%TYPE;
 l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
 l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
 l_strR3Name           REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 l_iYearOffset NUMBER(11,0);
 
 l_iUseSameNumberForAllMonths NUMBER(11,0);

BEGIN
  /* Initialiser parametre */
  SELECT period     INTO l_iCurrentPeriod      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  --SELECT company_id INTO l_strCompanyId        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT date_from  INTO l_dtStartRollingDate  FROM period    WHERE acc_period  = (SELECT acc_period FROM period WHERE date_from = (SELECT ADD_MONTHS(date_from,1) FROM period where acc_period = l_iCurrentPeriod AND substr(acc_period,5,2) NOT IN ('00','13')) AND substr(acc_period,5,2) NOT IN ('00','13'));
  SELECT date_from  INTO l_dtEndRollingDate    FROM period    WHERE date_from    = ADD_MONTHS(l_dtStartRollingDate,12) AND substr(acc_period,5,2) NOT IN ('00','13');
  SELECT acc_period INTO l_iFirstRollingPeriod FROM period    WHERE date_from    = l_dtStartRollingDate                AND substr(acc_period,5,2) NOT IN ('00','13');
  -- For debug
  SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = i_iLiquidityReportLineId;
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
     WHERE rule_entry_id  = i_rRuleId
       AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Skal beløpet fremskrives?  
  BEGIN
    SELECT NVL(liqudity_use_same_for_all_mths,0) INTO l_iUseSameNumberForAllMonths FROM rule_entry WHERE rule_entry_id = i_rRuleId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iUseSameNumberForAllMonths := 0;
  END;
  
  IF l_iUseSameNumberForAllMonths = 0 THEN
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
  END IF;
 
   -- Her fremskrives beløpet
  IF l_iUseSameNumberForAllMonths = 1 THEN
    IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT period_basis 
                                               FROM rule_period_payment 
                                              WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                                AND rule_entry_id  = i_rRuleId) 
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
    ELSE
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(amount)
       FROM liquidity_entry_mth_item_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id = i_iLiquidityReportLineId
         AND period = (SELECT acc_period 
                         FROM period 
                        WHERE date_from = (SELECT ADD_MONTHS(date_from,-1) FROM period WHERE acc_period = i_iRollingPeriod AND substr(acc_period,5,2) NOT IN ('00','13'))
                          AND substr(acc_period,5,2) NOT IN ('00','13') 
                      )
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
    
    END IF;
  END IF;
 
  COMMIT;
END GenerateRowFromAccounts;

PROCEDURE GenerateRowFromGL5050 ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                              i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                              i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                              i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                              i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                              i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                              i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
 l_iCurrentPeriod      PERIOD.ACC_PERIOD%TYPE;
 l_dtStartRollingDate  PERIOD.DATE_FROM%TYPE;
 l_dtEndRollingDate    PERIOD.DATE_TO%TYPE;
 l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
 l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
 l_strR3Name           REPORT_LEVEL_3.REPORT_LEVEL_3_NAME%TYPE;
 l_iYearOffset NUMBER(11,0);
 
 l_iUseSameNumberForAllMonths NUMBER(11,0);
 
 type tblPeriods is table of number(11,0);
 
 l_tblPeriod tblPeriods;

BEGIN
  /* Initialiser parametre */
  SELECT period     INTO l_iCurrentPeriod      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  --SELECT company_id INTO l_strCompanyId        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT date_from  INTO l_dtStartRollingDate  FROM period    WHERE acc_period  = (SELECT acc_period FROM period WHERE date_from = (SELECT ADD_MONTHS(date_from,1) FROM period where acc_period = l_iCurrentPeriod AND substr(acc_period,5,2) NOT IN ('00','13')) AND substr(acc_period,5,2) NOT IN ('00','13'));
  SELECT date_from  INTO l_dtEndRollingDate    FROM period    WHERE date_from    = ADD_MONTHS(l_dtStartRollingDate,12) AND substr(acc_period,5,2) NOT IN ('00','13');
  SELECT acc_period INTO l_iFirstRollingPeriod FROM period    WHERE date_from    = l_dtStartRollingDate                AND substr(acc_period,5,2) NOT IN ('00','13');
  -- For debug
  SELECT report_level_3_name INTO l_strR3Name FROM report_level_3 WHERE report_level_3_id = i_iLiquidityReportLineId;
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
     WHERE rule_entry_id  = i_rRuleId
       AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Skal beløpet fremskrives?  
  BEGIN
    SELECT NVL(liqudity_use_same_for_all_mths,0) INTO l_iUseSameNumberForAllMonths FROM rule_entry WHERE rule_entry_id = i_rRuleId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iUseSameNumberForAllMonths := 0;
  END;
  
  -- Finn  alle grunnlagsperioder 
  /*
  SELECT period_basis BULK COLLECT INTO l_tblPeriod
    FROM rule_period_payment 
   WHERE period_payment = substr(i_iRollingPeriod,5,2)
     AND rule_entry_id  = i_rRuleId;
                                                
   l_tblPeriod.Count/2
  */
  IF l_iUseSameNumberForAllMonths = 0 THEN
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT T.period_basis
                                          FROM (SELECT period_basis FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId order by period_basis) T
                                         WHERE rownum <= (SELECT count(*)/2 FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId))
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
  END IF;
 
   -- Her fremskrives beløpet
  IF l_iUseSameNumberForAllMonths = 1 THEN
    IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
       FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
      WHERE gl.account_id         = gla.account_id
        AND rp.rule_entry_id      = gla.rule_id
        AND substr(gl.period,5,2) = rp.period_basis
        AND rp.rule_entry_id      = i_rRuleId 
        AND rp.period_payment     = l_strPaymentPeriod
        AND gl.company_id         =  g_strCompanyId
        AND substr(gl.period,5,2) IN ( SELECT T.period_basis
                                          FROM (SELECT period_basis FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId order by period_basis) T
                                         WHERE rownum <= (SELECT count(*)/2 FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId))
        AND substr(gl.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND gl.activity_id = '2';
    ELSE
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(amount)
       FROM liquidity_entry_mth_item_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id = i_iLiquidityReportLineId
         AND period = (SELECT acc_period 
                         FROM period 
                        WHERE date_from = (SELECT ADD_MONTHS(date_from,-1) FROM period WHERE acc_period = i_iRollingPeriod AND substr(acc_period,5,2) NOT IN ('00','13'))
                          AND substr(acc_period,5,2) NOT IN ('00','13') 
                      )
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
    
    END IF;
  END IF;
 
  COMMIT;
END GenerateRowFromGL5050;

PROCEDURE GenerateRowFromBudget    ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                       i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE)
IS
  l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_iYearOffset         NUMBER(11,0);
BEGIN
  -- Sjekk om det er utbetaling på denne perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id  = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;

  IF i_rRulePerPaySrcCalcId IS NULL THEN
      
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(be.budget_amount*NVL(rb.adjustment_factor,0)*NVL(rb.sign_effect,1)) 
       FROM budget_entry be, rule_period_payment rp, rule_budget_assoc rb
      WHERE TO_CHAR(be.budget_date,'MM') = rp.period_basis
        AND rp.rule_entry_id  = i_rRuleId 
        AND rp.period_payment = l_strPaymentPeriod
        AND be.account_id                    = rb.account_id
        AND rb.rule_id                       = i_rRuleId 
        AND be.company_id                  =  g_strCompanyId  --(SELECT company_id         FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId)
        --AND be.account_id                  IN (SELECT account_id         FROM rule_gl_assoc WHERE rule_id = i_rRuleId)
--        AND be.account_id                  IN (SELECT account_id         FROM rule_budget_assoc WHERE rule_id = i_rRuleId)
        AND TO_CHAR(be.budget_date,'YYYY') =  substr(i_iRollingPeriod,0,4)
        AND TO_CHAR(be.budget_date,'MM')   IN (SELECT period_basis 
                                              FROM rule_period_payment 
                                             WHERE rule_entry_id  = i_rRuleId 
                                               AND period_payment = l_strPaymentPeriod);
  ELSE
     -- Bruke kildekontroll for betalingsperioder
     -- Finne årsforskyvning
     SELECT year_offset INTO l_iYearOffset FROM rule_period_payment_src_calc WHERE rule_per_pay_src_calc_id = i_rRulePerPaySrcCalcId;
      
  
      INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
        ,SUM(be.budget_amount*rb.adjustment_factor*rb.sign_effect) 
       FROM budget_entry be, rule_period_payment rp, RULE_PERIOD_PAYMENT_SRC_CALC rpcalc, rule_budget_assoc rb
      WHERE TO_CHAR(be.budget_date,'MM') = rp.period_basis
        AND rp.rule_entry_id                 = i_rRuleId 
        AND be.account_id                    = rb.account_id
        AND rb.rule_id                       = i_rRuleId 
        AND rp.rule_period_payment_id        = rpcalc.rule_period_payment_id
        AND rpcalc.rule_per_pay_src_calc_id  = i_rRulePerPaySrcCalcId
        AND rp.period_payment                = l_strPaymentPeriod
        AND be.company_id                    =  g_strCompanyId  --(SELECT company_id         FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId)
        --AND be.account_id                  IN (SELECT account_id         FROM rule_gl_assoc WHERE rule_id = i_rRuleId)
        --AND be.account_id                  IN (SELECT account_id         FROM rule_budget_assoc WHERE rule_id = i_rRuleId)
        AND TO_CHAR(be.budget_date,'YYYY') =  substr(i_iRollingPeriod,0,4)+l_iYearOffset
        AND TO_CHAR(be.budget_date,'MM')   IN (SELECT period_basis 
                                              FROM rule_period_payment 
                                             WHERE rule_entry_id  = i_rRuleId 
                                               AND period_payment = l_strPaymentPeriod);
  
  END IF;

END GenerateRowFromBudget;

PROCEDURE GenerateRowFromPrognosis ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                      i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                      i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                      i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                      i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                      i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iNoOfMthShift               RULE_ENTRY.NO_OF_MONTH_SHIFT%TYPE;
  l_iNoOfMonthGrouped           RULE_ENTRY.NO_OF_MONTH_GROUPED%TYPE;
  l_iCalcAccYTLiqPeriodThenProg RULE_ENTRY.CALC_ACCOUNT_THEN_PROGNOSIS%TYPE;
  l_iPeriod                     PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iZeroIfNegative             RULE_ENTRY.ZERO_IF_NEGATIVE%TYPE;
  l_iZeroIfPositive             RULE_ENTRY.ZERO_IF_POSITIVE%TYPE;

BEGIN
  -- Beregner Regnskap til og med likviditetsperiode og legger til prognose ut året. (Overstyrer "Antall mnd forskjøvet/gruppert)
  SELECT nvl(calc_account_then_prognosis,0) INTO l_iCalcAccYTLiqPeriodThenProg 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Antall måneder gruppert
  SELECT nvl(no_of_month_grouped,1) INTO l_iNoOfMonthGrouped 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Antall måneder forskjøvet
  SELECT nvl(no_of_month_shift,0) INTO l_iNoOfMthShift 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Hent forskjøvet måned
  SELECT acc_period INTO l_iPeriod 
    FROM period 
   WHERE date_from = ( SELECT add_months(date_from,l_iNoOfMthShift) FROM period WHERE acc_period = i_iRollingPeriod )
     AND substr(acc_period,5,2) NOT IN ('00','13');
  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');
 -- Sett resultat lik 0 dersom negativt beløp
 SELECT nvl(zero_if_negative,0) INTO l_iZeroIfNegative 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
 -- Sett resultat lik 0 dersom positivt beløp
 SELECT nvl(zero_if_positive,0) INTO l_iZeroIfPositive
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;

  IF l_iCalcAccYTLiqPeriodThenProg = 1 THEN
    -- Regnskap
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND substr(gl.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
       AND gl.period             <= ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) --Til og med likviditetsperiode
       AND gl.activity_id        = '2'
     GROUP BY 
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
        
    -- Prognose
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod --pe.period
      ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
    WHERE pe.report_level_3_id  = r.report_level_3_id
      AND pe.prognosis_id       = i_iPrognosisId
      AND substr(pe.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
      AND pe.period             >= l_iFirstRollingPeriod  -- Hittil i år
      AND r.rule_id             = re.rule_entry_id
      AND re.rule_entry_id      = i_rRuleId
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod; --pe.period;

  END IF;

  IF ((l_iNoOfMonthGrouped = 1) AND (l_iCalcAccYTLiqPeriodThenProg = 0)) THEN
      IF ( ( i_iRollingPeriod = l_iFirstRollingPeriod ) AND
           ( l_iNoOfMthShift <> 0 ) )  THEN
        -- Regnskap  
        BEGIN
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod 
            ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
            FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
           WHERE r3a.report_level_3_id = r.report_level_3_id
             AND r.rule_id             = re.rule_entry_id
             AND re.rule_entry_id      = i_rRuleId
             AND gl.account_id         = r3a.account_id
             AND r3a.report_level_3_id = r.report_level_3_id
             AND gl.company_id  = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
             AND gl.period      = g_iPeriodId --( SELECT period     FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) --l_iPreviousRollingPeriod
             AND gl.activity_id = '2'
           GROUP BY 
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod ;
    
        END;
        ELSE
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod --pe.period
            ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
           FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
          WHERE pe.report_level_3_id = r.report_level_3_id
            AND pe.prognosis_id      = i_iPrognosisId
            AND pe.period            = l_iPeriod -- FORSKJØVET IHHT REGEL  i_iRollingPeriod
            AND r.rule_id            = re.rule_entry_id
            AND re.rule_entry_id     = i_rRuleId
          GROUP BY 
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod; --pe.period;
        
      END IF;
  END IF;
  
  IF ((l_iNoOfMonthGrouped = 2) AND (l_iCalcAccYTLiqPeriodThenProg = 0)) THEN --GRUPPERER JAN/FEB, MAR/APR, MAI/JUN osv
   null;
   
  END IF;
  
  IF ((l_iNoOfMonthGrouped = 12) AND (l_iCalcAccYTLiqPeriodThenProg = 0)) THEN -- Summerer hele året
    -- Regnskap
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND substr(gl.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
       AND gl.period             <= l_iPeriod  -- Hittil i år
       AND gl.activity_id        = '2'
     GROUP BY 
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
        
    -- Prognose
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod --pe.period
      ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
    WHERE pe.report_level_3_id  = r.report_level_3_id
      AND pe.prognosis_id       = i_iPrognosisId
      AND substr(pe.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
      AND pe.period             >= l_iFirstRollingPeriod  -- Hittil i år
      AND r.rule_id             = re.rule_entry_id
      AND re.rule_entry_id      = i_rRuleId
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod; --pe.period;

   
  END IF;
  
  COMMIT;
END GenerateRowFromPrognosis;

PROCEDURE GenerateRowFromPrognosis5050 ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                          i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                          i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                          i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iNoOfMthShift               RULE_ENTRY.NO_OF_MONTH_SHIFT%TYPE;
  l_iNoOfMonthGrouped           RULE_ENTRY.NO_OF_MONTH_GROUPED%TYPE;
  l_iCalcAccYTLiqPeriodThenProg RULE_ENTRY.CALC_ACCOUNT_THEN_PROGNOSIS%TYPE;
  l_iPeriod                     PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iZeroIfNegative             RULE_ENTRY.ZERO_IF_NEGATIVE%TYPE;
  l_iZeroIfPositive             RULE_ENTRY.ZERO_IF_POSITIVE%TYPE;
  l_iYearOffset                 RULE_PERIOD_PAYMENT.YEAR_OFFSET%TYPE;

BEGIN
  -- Denne metoden forutsetter bruk av betalingsperioder
  -- Prognose
  BEGIN
    SELECT min(year_offset) INTO l_iYearOffset FROM rule_period_payment WHERE rule_entry_id = i_rRuleId AND period_payment =  substr(i_iRollingPeriod,5,2); 
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
    WHERE pe.report_level_3_id  = r.report_level_3_id
      AND pe.prognosis_id       = i_iPrognosisId
      AND r.rule_id             = re.rule_entry_id
      AND re.rule_entry_id      = i_rRuleId
      AND substr(pe.period,0,4)   = substr(i_iRollingPeriod,0,4)+l_iYearOffset
      AND substr(pe.period,5,2) IN ( SELECT T.period_basis
                                         FROM (SELECT period_basis FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId order by period_basis DESC) T
                                        WHERE rownum <= (SELECT count(*)/2 FROM rule_period_payment WHERE period_payment = substr(i_iRollingPeriod,5,2) AND rule_entry_id  = i_rRuleId))
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
  
  COMMIT;
END GenerateRowFromPrognosis5050;

PROCEDURE GenerateRowFromNoteLine ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                    i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                    i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                    i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                    i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                    i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount NUMBER(11,0);
BEGIN
  INSERT INTO liquidity_entry_mth_item_tmp
     (liquidity_entry_head_id
     ,report_level_3_id
     ,period
     ,amount)
   SELECT
     i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,pe.period
    ,SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
   FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
  WHERE pne.note_line_id         = r.note_line_id
    AND pne.prognosis_entry_id = pe.prognosis_entry_id
    AND pe.prognosis_id          = i_iPrognosisId
    AND pe.period                = i_iRollingPeriod
    AND r.rule_id                = re.rule_entry_id
    AND re.rule_entry_id         = i_rRuleId
  GROUP BY 
      i_rLiquidityId
     ,i_iLiquidityReportLineId
     ,pe.period;
      
  COMMIT;
END GenerateRowFromNoteLine;

PROCEDURE GenerateRowFromInvestment  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iNoOfMthShift       RULE_ENTRY.NO_OF_MONTH_SHIFT%TYPE;
  l_iNoOfMonthGrouped   RULE_ENTRY.NO_OF_MONTH_GROUPED%TYPE;
  l_iPeriod             PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
BEGIN
  -- Antall måneder gruppert
  SELECT nvl(no_of_month_grouped,1) INTO l_iNoOfMonthGrouped 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  
  -- Antall måneder forskjøvet
  SELECT nvl(no_of_month_shift,0) INTO l_iNoOfMthShift 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  -- Hent forskjøvet måned
  SELECT acc_period INTO l_iPeriod 
    FROM period 
   WHERE date_from = ( SELECT add_months(date_from,l_iNoOfMthShift) FROM period WHERE acc_period = i_iRollingPeriod )
     AND substr(acc_period,5,2) NOT IN ('00','13');
  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');

  IF l_iNoOfMonthGrouped = 1 THEN
      IF ( ( i_iRollingPeriod = l_iFirstRollingPeriod ) AND
           ( l_iNoOfMthShift <> 0 ) )  THEN
        -- Regnskap  
        BEGIN
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod 
            ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
            FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
           WHERE r3a.report_level_3_id = r.report_level_3_id
             AND r.rule_id             = re.rule_entry_id
             AND re.rule_entry_id      = i_rRuleId
             AND gl.account_id         = r3a.account_id
             AND r3a.report_level_3_id = r.report_level_3_id
             AND gl.company_id  = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
             AND gl.period      = l_iPeriod 
             AND gl.activity_id IN ('7','8')
           GROUP BY 
             i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod ;
    
        END;
        ELSE
          INSERT INTO liquidity_entry_mth_item_tmp
             (liquidity_entry_head_id
             ,report_level_3_id
             ,period
             ,amount)
          SELECT
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod --pe.period
            ,SUM(pie.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
           FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
          WHERE pie.activity_id      = r.activity_id
            AND pie.prognosis_id     = i_iPrognosisId
            AND pie.period           = l_iPeriod -- FORSKJØVET IHHT REGEL  i_iRollingPeriod
            AND r.rule_id            = re.rule_entry_id
            AND re.rule_entry_id     = i_rRuleId
          GROUP BY 
            i_rLiquidityId
            ,i_iLiquidityReportLineId
            ,i_iRollingPeriod; --pe.period;
        
      END IF;
  END IF;
  
  IF l_iNoOfMonthGrouped = 2 THEN --GRUPPERER JAN/FEB, MAR/APR, MAI/JUN osv
   null;
   
  END IF;
  
  IF l_iNoOfMonthGrouped = 12 THEN -- Summerer hele året
    -- Regnskap
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod 
      ,SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) 
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND gl.company_id         = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND substr(gl.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
       AND gl.period             <= l_iPeriod  -- Hittil i år
       AND gl.activity_id        IN ('7','8')
     GROUP BY 
       i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod;
        
    -- Prognose
    INSERT INTO liquidity_entry_mth_item_tmp
       (liquidity_entry_head_id
       ,report_level_3_id
       ,period
       ,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod --pe.period
      ,SUM(pie.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
     FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
    WHERE pie.activity_id        = r.activity_id
      AND pie.prognosis_id       = i_iPrognosisId
      AND substr(pie.period,0,4) = substr(l_iPeriod,0,4)   --- Inneværende år
      AND pie.period             >= l_iFirstRollingPeriod  -- Hittil i år
      AND r.rule_id              = re.rule_entry_id
      AND re.rule_entry_id       = i_rRuleId
    GROUP BY 
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,i_iRollingPeriod; --pe.period;

   
  END IF;
  
  COMMIT;
END GenerateRowFromInvestment;

PROCEDURE GenerateRowForDay ( i_rLiquidityEntryMonth IN LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE
                              
                           /* i_rLiquidityEntryMonth    IN LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE, 
                              i_rLiquidityId            IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                              i_rRuleId                 IN RULE_ENTRY.RULE_ENTRY_ID%TYPE,  
                              i_iLiquidityReportLineId  IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE, 
                              i_iRollingPeriod          IN PERIOD.ACC_PERIOD%TYPE */
                            )
IS
  l_dtDay                    DATE;
  l_dtWorkDay                DATE;
  l_dtLastWorkingDay         DATE;
  l_dtNextToLastWorkingDay   DATE;
  l_iNoOfDaysToBeDistributed NUMBER(11,0);
  l_iNoOfDaysInMth           NUMBER(11,0);  
  l_iCountManualEdited       NUMBER(11,0);  
  l_iEvenDistribution        RULE_ENTRY.EVEN_DISTRIBUTION%TYPE;
  l_iDayNo                   RULE_ENTRY.PAYMENT_DAY_NO%TYPE;
  l_iShiftToPreviousDay      RULE_ENTRY.SHIFT_TO_PREVIOUS_WORKING_DAY%TYPE;
  l_iShiftToNextDay          RULE_ENTRY.SHIFT_TO_NEXT_WORKING_DAY%TYPE;
  l_iPaymentProfile          RULE_ENTRY.PATTERN_OF_PAYMENTS_DAY%TYPE;  
  
  l_rLiquidityHeadId  LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_HEAD_ID%TYPE;
  l_iR3               LIQUIDITY_ENTRY_MTH_ITEM.REPORT_LEVEL_3_ID%TYPE;
  l_iPeriod           LIQUIDITY_ENTRY_MTH_ITEM.PERIOD%TYPE;
  l_iCurrentPeriod    LIQUIDITY_ENTRY_MTH_ITEM.PERIOD%TYPE;
  l_fAmount           LIQUIDITY_ENTRY_MTH_ITEM.AMOUNT%TYPE;
  
  CURSOR l_curDateInMonth ( i_iPeriod PERIOD.ACC_PERIOD%TYPE ) IS
    SELECT to_date(to_char(i_iPeriod) || lpad(to_char(rownum),2,0),'YYYYMMDD')
      FROM all_objects
     WHERE rownum <= (last_day(to_date(to_char(i_iPeriod) || '01','YYYYMMDD'))+1 - to_date(to_char(i_iPeriod) || '01','YYYYMMDD'));
     
  CURSOR l_curWorkDay IS SELECT day FROM liquidity_day_calendar_tmp;
BEGIN
  -- Sjekk om det finnes 

  -- Slett tidligere opprader
  DELETE FROM liquidity_entry_day_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth AND nvl(source_id,1) = 1 AND edited_by_user = 0;
  
   
  -- Hent basisinfo
  SELECT period                  INTO l_iPeriod          FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  SELECT report_level_3_id       INTO l_iR3              FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  SELECT liquidity_entry_head_id INTO l_rLiquidityHeadId FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  SELECT amount                  INTO l_fAmount          FROM liquidity_entry_mth_item WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth;
  -- Hent regelinfo for gjeldende rad
  BEGIN
    SELECT NVL(even_distribution,0) INTO l_iEvenDistribution FROM rule_entry 
     WHERE rule_entry_id = ( SELECT rule_id
                               FROM r3_rule_company_relation 
                              WHERE company_id = g_strCompanyId
                                AND is_enabled = 1
                                AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found THEN l_iEvenDistribution := 0;
  END;
  
  BEGIN
    SELECT NVL(payment_day_no,1) INTO l_iDayNo FROM rule_entry 
     WHERE rule_entry_id = ( SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found THEN  l_iDayNo := 1;
  END; 
  
  BEGIN                                                       
    SELECT shift_to_next_working_day INTO l_iShiftToNextDay FROM rule_entry 
     WHERE rule_entry_id = (  SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found THEN  l_iShiftToNextDay := 1;
  END;
  BEGIN
    SELECT shift_to_previous_working_day INTO l_iShiftToPreviousDay FROM rule_entry 
     WHERE rule_entry_id = (  SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth));
    EXCEPTION WHEN no_data_found  THEN l_iShiftToPreviousDay := 0;
  END;
  BEGIN
    SELECT pattern_of_payments_day INTO l_iPaymentProfile FROM rule_entry 
     WHERE rule_entry_id = (  SELECT  rule_id
                                FROM r3_rule_company_relation 
                               WHERE company_id = g_strCompanyId
                                 AND is_enabled = 1
                                 AND report_level_3_id = ( SELECT report_level_3_id 
                                                            FROM liquidity_entry_mth_item
                                                           WHERE liquidity_entry_mth_item_id = i_rLiquidityEntryMonth ));
    EXCEPTION WHEN no_data_found  THEN l_iPaymentProfile := null;
  END;
  
  IF NVL(l_iCurrentPeriod,0) <> l_iPeriod THEN 
      -- Finn antall virkedager i gjeldende månden
      -- Lager denne bare en gang pr periode
      -- Rydd opp først
      
      DELETE FROM liquidity_day_calendar_tmp;
      COMMIT;
      
      OPEN l_curDateInMonth ( l_iPeriod );
      FETCH l_curDateInMonth INTO l_dtDay;
      WHILE  l_curDateInMonth%FOUND LOOP
      
        IF IsHoliday(l_dtDay) = 0 THEN
          INSERT INTO liquidity_day_calendar_tmp VALUES (l_dtDay);
        END IF;
      
      FETCH l_curDateInMonth INTO l_dtDay;
      END LOOP;
      CLOSE l_curDateInMonth;
      COMMIT;
      
      l_iCurrentPeriod := l_iPeriod;
  END IF;
  
  -- Betalingsprofil overstyrer annen fordeling
  IF l_iPaymentProfile IS NOT NULL THEN
    IF l_iPaymentProfile = 2 THEN
    
          -- Finn antall dager i måneden
          SELECT TO_NUMBER(TO_CHAR(LAST_DAY(DATO), 'DD')) INTO l_iNoOfDaysInMth FROM (SELECT MIN(day) AS DATO FROM liquidity_day_calendar_tmp );
          -- Finn antall dager det skal fordeles på  
          SELECT count(*) INTO l_iNoOfDaysToBeDistributed FROM liquidity_day_calendar_tmp;
          
          OPEN l_curWorkDay;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          WHILE l_curWorkDay%FOUND LOOP
          
              SELECT count(*) INTO l_iCountManualEdited 
                FROM liquidity_entry_day_item
               WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                 AND report_level_3_id = l_iR3
                 AND period = l_iPeriod
                 AND liquidity_entry_day_item_date = l_dtWorkDay
                 AND edited_by_user = 1;
                 
            IF l_iCountManualEdited = 0 THEN
              SELECT  1 + TRUNC (l_dtWorkDay)  - TRUNC (l_dtWorkDay, 'IW') INTO l_iDayNo FROM DUAL;  
              IF l_iDayNo =  3 THEN 
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,(l_fAmount/l_iNoOfDaysInMth)*3,0);
              ELSE 
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount/l_iNoOfDaysInMth,0);
              
              END IF;
            END IF;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          END LOOP;
          CLOSE l_curWorkDay;
    END IF;
    IF l_iPaymentProfile = 3 THEN
          -- Finn antall dager i måneden
          SELECT TO_NUMBER(TO_CHAR(LAST_DAY(DATO), 'DD')) INTO l_iNoOfDaysInMth FROM (SELECT MIN(day) AS DATO FROM liquidity_day_calendar_tmp );
          -- Finn antall dager det skal fordeles på  
          SELECT count(*) INTO l_iNoOfDaysToBeDistributed FROM liquidity_day_calendar_tmp;
          -- Finn siste virkedag
          SELECT MAX(day) INTO l_dtLastWorkingDay FROM liquidity_day_calendar_tmp;
          -- Finn nestsiste virkedag
          SELECT MAX(day) INTO l_dtNextToLastWorkingDay FROM liquidity_day_calendar_tmp WHERE day <> l_dtLastWorkingDay;
          
          OPEN l_curWorkDay;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          WHILE l_curWorkDay%FOUND LOOP
          
              SELECT count(*) INTO l_iCountManualEdited 
                FROM liquidity_entry_day_item
               WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                 AND report_level_3_id = l_iR3
                 AND period = l_iPeriod
                 AND liquidity_entry_day_item_date = l_dtWorkDay
                 AND edited_by_user = 1;
                 
           IF l_iCountManualEdited = 0 THEN
              IF l_dtWorkDay NOT IN (l_dtLastWorkingDay,l_dtNextToLastWorkingDay) THEN 
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,(l_fAmount*0.23)/(l_iNoOfDaysToBeDistributed-2),0);
              ELSE
                IF l_dtWorkDay = l_dtNextToLastWorkingDay THEN
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount*0.07,0);
                ELSE
                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount*0.7,0);
                END IF;
              END IF;
           END IF;   

          FETCH l_curWorkDay INTO l_dtWorkDay;
          END LOOP;
          CLOSE l_curWorkDay;
    END IF;
  ELSE
      -- SKAL DENNE RADEN FORDELES FLATT 
      IF l_iEvenDistribution = 1 THEN
          -- Finn antall dager det skal fordeles på  
          SELECT count(*) INTO l_iNoOfDaysToBeDistributed FROM liquidity_day_calendar_tmp;
          
          OPEN l_curWorkDay;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          WHILE l_curWorkDay%FOUND LOOP
            SELECT count(*) INTO l_iCountManualEdited 
                  FROM liquidity_entry_day_item
                 WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                   AND report_level_3_id = l_iR3
                   AND period = l_iPeriod
                   AND liquidity_entry_day_item_date = l_dtWorkDay
                   AND edited_by_user = 1;
                   
              IF l_iCountManualEdited = 0 THEN
                INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                      period,liquidity_entry_day_item_date,amount,edited_by_user)
                VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtWorkDay,l_fAmount/l_iNoOfDaysToBeDistributed,0);
              END IF;
          FETCH l_curWorkDay INTO l_dtWorkDay;
          END LOOP;
          CLOSE l_curWorkDay;
      END IF;
      
      IF l_iEvenDistribution = 0
      AND l_iDayNo IS NOT NULL THEN
         
        IF l_iDayNo = 99 THEN -- SISTE DAG I MND
          SELECT last_day(to_date(to_char(l_iPeriod) || to_char('01'),'YYYYMMDD')) INTO l_dtDay FROM dual;
        ELSE
          SELECT to_date(to_char(l_iPeriod) || to_char(l_iDayNo),'YYYYMMDD') INTO l_dtDay FROM dual;
        END IF;
        
        IF IsHoliday(l_dtDay) = 1 THEN -- Helligdag eller helg
           IF l_iShiftToNextDay = 1 THEN
              l_dtDay := l_dtDay + 1; -- øk med en dag
              WHILE IsHoliday(l_dtDay) = 1 LOOP l_dtDay := l_dtDay + 1; END LOOP;
           END IF;
           IF l_iShiftToPreviousDay = 1 THEN
              l_dtDay := l_dtDay - 1; -- trekk fra en dag
              WHILE IsHoliday(l_dtDay) = 1 LOOP l_dtDay := l_dtDay - 1; END LOOP;
           END IF;
        END IF;

                SELECT count(*) INTO l_iCountManualEdited 
                  FROM liquidity_entry_day_item
                 WHERE liquidity_entry_head_id = l_rLiquidityHeadId
                   AND report_level_3_id = l_iR3
                   AND period = l_iPeriod
                   AND liquidity_entry_day_item_date = l_dtDay
                   AND edited_by_user = 1;
                   
              IF l_iCountManualEdited = 0 THEN

                  INSERT INTO liquidity_entry_day_item (liquidity_entry_day_item_id,liquidity_entry_head_id,liquidity_entry_mth_item_id,report_level_3_id,
                                                        period,liquidity_entry_day_item_date,amount,edited_by_user)
                  VALUES (sys_guid(), l_rLiquidityHeadId,i_rLiquidityEntryMonth,l_iR3,l_iPeriod,l_dtDay,l_fAmount,0);
              END IF;
      END IF;

  END IF;    
    
  COMMIT;
END GenerateRowForDay;

FUNCTION  IsHoliday  ( i_iDate  IN DATE) RETURN NUMBER
IS
 l_iIsHoliday NUMBER;
 l_iTemp      NUMBER(11,0);
 l_strDayName VARCHAR2(15);
 l_iDayNo     NUMBER(11,0);
BEGIN
  l_iTemp := 0;
  SELECT count(*) INTO l_iTemp 
    FROM calendar 
   WHERE 
    --to_char(calendar_date,'DDMMYYYY') = to_char(i_iDate,'DDMMYYYY')
     calendar_date = i_iDate
     AND calendar_type_id is not null;
   
 -- SELECT TO_NUMBER(TO_CHAR(i_iDate,'D')) INTO l_iDayNo FROM DUAL;
  SELECT  1 + TRUNC (i_iDate)  - TRUNC (i_iDate, 'IW') INTO l_iDayNo FROM DUAL;
  IF l_iDayNo IN (6,7) THEN l_iTemp := l_iTemp + 1; END IF;

  IF l_iTemp >= 1 THEN l_iIsHoliday := 1; ELSE l_iIsHoliday := 0; END IF;

  RETURN  l_iIsHoliday;

END IsHoliday;
                               
FUNCTION  CalculateTaxFromAccounts   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS                                        
BEGIN
  RETURN 0;
END CalculateTaxFromAccounts;

FUNCTION  CalculateTaxFromPrognosis  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
BEGIN
  RETURN 0;
END CalculateTaxFromPrognosis;

FUNCTION  CalculateVATFromLiquidity  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS        
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(NVL(t.amount,0)*nvl(p.adjustment_factor,1)*nvl(p.sign_effect,1)) INTO l_fAmount
    FROM liquidity_entry_mth_item_tmp t, rule_prognosis_assoc p
   WHERE t.report_level_3_id = p.report_level_3_id
     AND p.rule_id  = i_rRuleId 
     AND p.report_level_3_id IN (SELECT report_level_3_id FROM report_level_3 WHERE report_type_id = 6)
     AND substr(t.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
--     AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || '00') FROM dual )
  --   AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || period_basis)) 
    --                       FROM rule_period_payment 
      --                    WHERE rule_entry_id  = i_rRuleId 
        --                    AND period_payment = i_strPaymentPeriod )
     AND liquidity_entry_head_id = i_rLiquidityId;
  
  RETURN l_fAmount;
END CalculateVATFromLiquidity;

FUNCTION  CalculateVATFromAccounts   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS        
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(NVL(gl.amount,0)*nvl(p.adjustment_factor,1)*nvl(p.sign_effect,1)) INTO l_fAmount
    FROM general_ledger gl, rule_gl_assoc p
   WHERE gl.account_id = p.account_id
     AND p.rule_id     = i_rRuleId
     AND gl.period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || '00') FROM dual )
     AND gl.period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || period_basis)) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = i_strPaymentPeriod )
     AND gl.company_id = g_strCompanyId; --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  
  RETURN l_fAmount;
END CalculateVATFromAccounts;

FUNCTION  CalculateVATFromAccountsSplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                          i_iYearOffset      IN NUMBER,
                                          i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER
IS        
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  SELECT SUM(NVL(gl.amount,0)*nvl(p.adjustment_factor,1)*nvl(p.sign_effect,1)) INTO l_fAmount
    FROM general_ledger gl, rule_gl_assoc p
   WHERE gl.account_id = p.account_id
     AND p.rule_id     = i_rRuleId
     AND gl.period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || '00') FROM dual )
     AND gl.period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+i_iYearOffset || period_basis)) 
                           FROM rule_period_payment 
                          WHERE rule_entry_id  = i_rRuleId 
                            AND period_payment = i_strPaymentPeriod )
     AND company_id = g_strCompanyId; --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  RETURN l_fAmount;
END CalculateVATFromAccountsSplit;

FUNCTION  CalculateVATFromPrognosis  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
        FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
       WHERE pe.report_level_3_id = r.report_level_3_id
         AND pe.prognosis_id      = i_iPrognosisId
         AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
         -- OIG Endret 12012011 SJEKK
         --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND r.rule_id            = re.rule_entry_id
         AND re.rule_entry_id     = i_rRuleId;
  RETURN l_fAmount;
END CalculateVATFromPrognosis;

FUNCTION  CalculateVATFromPrognosisSplit  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                            i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                            i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                            i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                            i_iYearOffset      IN NUMBER,
                                            i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
        FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
       WHERE pe.report_level_3_id = r.report_level_3_id
         AND pe.prognosis_id      = i_iPrognosisId
         AND substr(pe.period,5,2) IN ( SELECT MAX(period_basis)
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
         -- OIG 12012011 SJEKK
         --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND r.rule_id            = re.rule_entry_id
         AND re.rule_entry_id     = i_rRuleId;
  RETURN l_fAmount;
END CalculateVATFromPrognosisSplit;

FUNCTION  CalculateVATFromNoteLine   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
    FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
   WHERE pne.note_line_id         = r.note_line_id
     AND pne.prognosis_entry_id   = pe.prognosis_entry_id
     AND r.rule_id                = re.rule_entry_id
     AND re.rule_entry_id         = i_rRuleId
     AND pe.prognosis_id          = i_iPrognosisId
     AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                      FROM rule_period_payment 
                                     WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                       AND rule_entry_id = i_rRuleId)
     -- OIG 12012012 SJEKK
     --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
     AND r.rule_note_line_included_in = 3; -- Gjelder for utregning av r3 prognose/resultat
  
  RETURN l_fAmount;
END CalculateVATFromNoteLine;

FUNCTION  CalculateVATFromNoteLineSplit   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                            i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                            i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                            i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                            i_iYearOffset      IN NUMBER,
                                            i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
    FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
   WHERE pne.note_line_id         = r.note_line_id
     AND pne.prognosis_entry_id   = pe.prognosis_entry_id
     AND r.rule_id                = re.rule_entry_id
     AND re.rule_entry_id         = i_rRuleId
     AND pe.prognosis_id          = i_iPrognosisId
     AND substr(pe.period,5,2) IN ( SELECT MAX(period_basis) 
                                      FROM rule_period_payment 
                                     WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                       AND rule_entry_id = i_rRuleId)
     -- OIG 12012012 SJEKK 
     --AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
     AND r.rule_note_line_included_in = 3; -- Gjelder for utregning av r3 prognose/resultat
  
  RETURN l_fAmount;
END CalculateVATFromNoteLineSplit;

FUNCTION  CalculateVATFromInvestment ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                       i_iYearOffset      IN NUMBER,
                                       i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
    SELECT NVL(SUM(pie.amount * NVL(re.adjustment_factor,1) * NVL(r.adjustment_factor,1) * NVL(r.sign_effect,1)),0) INTO l_fAmount
         FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
        WHERE pie.activity_id          = r.activity_id
          AND pie.prognosis_id         = i_iPrognosisId
          AND substr(pie.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId) 
          AND substr(pie.period,0,4)   = ( SELECT substr(period,0,4)+i_iYearOffset FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId;
  
  RETURN l_fAmount;
END CalculateVATFromInvestment;

FUNCTION  CalculateVATFromInvestSplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                        i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                        i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                        i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                        i_iYearOffset      IN NUMBER,
                                        i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
    SELECT NVL(SUM(pie.amount * NVL(re.adjustment_factor,1) * NVL(r.adjustment_factor,1) * NVL(r.sign_effect,1)),0) INTO l_fAmount
         FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
        WHERE pie.activity_id          = r.activity_id
          AND pie.prognosis_id         = i_iPrognosisId
          AND substr(pie.period,5,2) IN ( SELECT MAX(period_basis) 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId) 
          AND substr(pie.period,0,4)   = ( SELECT substr(period,0,4)+i_iYearOffset FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND r.rule_id          = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId;
  
  RETURN l_fAmount;
END CalculateVATFromInvestSplit;

FUNCTION  CalculateVATFromActSalary ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                      i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                      i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                      i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                      i_iYearOffset      IN NUMBER,
                                      i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
  
  SELECT NVL(SUM(pne.amount* NVL(re.adjustment_factor,1)* NVL(r.adjustment_factor,1)),0) INTO l_fAmount
         FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
        WHERE pne.note_line_id         = r.note_line_id
          AND pne.prognosis_entry_id   = pe.prognosis_entry_id
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId
          AND pe.prognosis_id          = i_iPrognosisId
          AND r.rule_note_line_included_in  = 5  -- Gjelder for investering
          AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId)
          AND substr(pe.period,0,4)    = ( SELECT substr(period,0,4)+i_iYearOffset FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  
  RETURN l_fAmount;
END CalculateVATFromActSalary;

FUNCTION  CalculateVATFromActSalarySplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                           i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                           i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                           i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                           i_iYearOffset      IN NUMBER,
                                           i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER
IS
  l_fAmount NUMBER(18,2);
BEGIN
  l_fAmount := 0;
    SELECT NVL(SUM(pne.amount* NVL(re.adjustment_factor,1)* NVL(r.adjustment_factor,1)),0) INTO l_fAmount
         FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
        WHERE pne.note_line_id         = r.note_line_id
          AND pne.prognosis_entry_id   = pe.prognosis_entry_id
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId
          AND pe.prognosis_id          = i_iPrognosisId
          AND r.rule_note_line_included_in  = 5  -- Gjelder for investering
          AND substr(pe.period,5,2) IN ( SELECT MAX(period_basis) 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId)
          AND substr(pe.period,0,4)    = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  RETURN l_fAmount;
END CalculateVATFromActSalarySplit;

/* HARDKODEDE RAPPORTLINJER - MÅ ENDRES I FORVALTNING  */

PROCEDURE GenerateForNettleieNaering ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iFirstRollingPeriod    PERIOD.ACC_PERIOD%TYPE;
  l_iPreviousRollingPeriod PERIOD.ACC_PERIOD%TYPE;
--  l_strCompanyId           COMPANY.COMPANY_ID%TYPE;
  l_fAmountCommercial      NUMBER(18,2);
  
  l_iCountPaymentPeriod    NUMBER(11,0);

BEGIN
  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');
  -- Forrige periode (Kommer inn med i_iRollingPeriod=201104, skal returnere 201103)  
  SELECT acc_period INTO l_iPreviousRollingPeriod
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,-1) 
                        FROM period 
                      WHERE acc_period = i_iRollingPeriod
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');

  -- NÃ†RING
  -- Hent prognosetall for forrige prognosemåned
  -- Dersom det er første rullerende måned skal beløpet hentes fra regnskap
  IF i_iRollingPeriod = l_iFirstRollingPeriod THEN
    -- Regnskap  
    BEGIN
      SELECT SUM(gl.amount*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountCommercial
        FROM general_ledger gl, report_l3_account_assoc r3a, rule_prognosis_assoc r
       WHERE r3a.report_level_3_id = r.report_level_3_id
         AND r.rule_id             = i_rRuleId
         AND gl.account_id         = r3a.account_id
         AND r3a.report_level_3_id = i_iLiquidityReportLineId
         AND gl.company_id  = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND gl.period      = g_iPeriodId    --( SELECT period     FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) --l_iPreviousRollingPeriod
         AND gl.activity_id = '2';

    EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountCommercial := 0;
    END;
  ELSE
    -- Prognose
    BEGIN
      SELECT SUM(pe.amount*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountCommercial
       FROM prognosis_entry pe, rule_prognosis_assoc r
      WHERE pe.report_level_3_id = r.report_level_3_id
        AND pe.prognosis_id      = i_iPrognosisId
        AND pe.period            = l_iPreviousRollingPeriod
        AND r.rule_id            = i_rRuleId;
  
    EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountCommercial := 0;
    END;
  
  
  END IF;
  
  INSERT INTO liquidity_entry_mth_item_tmp
    (liquidity_entry_head_id
    ,report_level_3_id
    ,period
    ,amount)
  VALUES 
    (i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,i_iRollingPeriod
    ,NVL(l_fAmountCommercial,0));
    
    COMMIT;

END GenerateForNettleieNaering;

PROCEDURE GenerateForNettleiePrivat  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fAmount          NUMBER(18,2);

  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
BEGIN
  l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    /*
    SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_basis =  substr(i_iRollingPeriod,5,2); */
     -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  IF l_strPaymentPeriod = 'NA' THEN
    RETURN;  -- Returnerer siden det ikke er utbetaling denne rullerende periode
  END IF;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utganspunktet er 1 (og rullerende er 3) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 1
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
        -- Prognose for periode 2
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      END IF;
    WHEN l_iPeriodNo = 2 THEN 
      -- Første rullerende periode er her 03
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utgangspunktet er 2 (og rullerende er 3) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         =  g_strCompanyId -- ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
           
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;

        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        
      END IF;
    WHEN l_iPeriodNo = 3 THEN
      -- Første rullerende periode er her 04
      IF substr(i_iRollingPeriod,5,2)  = 5 THEN -- Når utganspunktet er 3 (og rullerende er 5) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 3
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        -- Prognose for periode 2
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                             FROM rule_period_payment 
                                            WHERE rule_entry_id  = i_rRuleId 
                                              AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 4 THEN 
      -- Første rullerende periode er her 05
      IF substr(i_iRollingPeriod,5,2)  = 5 THEN -- Når utgangspunktet er 4 (og rullerende er 5) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
           
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                             FROM rule_period_payment 
                                            WHERE rule_entry_id  = i_rRuleId 
                                              AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 5 THEN
      -- Første rullerende periode er her 06
      IF substr(i_iRollingPeriod,5,2)  = 7 THEN -- Når utganspunktet er 5 (og rullerende er 7) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 1
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
        -- Prognose for periode 8
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                             FROM rule_period_payment 
                                            WHERE rule_entry_id  = i_rRuleId 
                                              AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      END IF;
    WHEN l_iPeriodNo = 6 THEN 
      -- Første rullerende periode er her 07
      IF substr(i_iRollingPeriod,5,2)  = 7 THEN -- Når utgangspunktet er 6 (og rullerende er 7) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 7 THEN
      -- Første rullerende periode er her 08
      IF substr(i_iRollingPeriod,5,2)  = 9 THEN -- Når utganspunktet er 7 (og rullerende er 9) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 7
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
        -- Prognose for periode 8
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 8 THEN 
      -- Første rullerende periode er her 09
      IF substr(i_iRollingPeriod,5,2)  = 9 THEN -- Når utgangspunktet er 8 (og rullerende er 9) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 9 THEN
      -- Første rullerende periode er her 10
      IF substr(i_iRollingPeriod,5,2)  = 11 THEN -- Når utganspunktet er 9 (og rullerende er 11) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 9
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        -- Prognose for periode 10
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;         
      END IF;
    WHEN l_iPeriodNo = 10 THEN 
      -- Første rullerende periode er her 11
      IF substr(i_iRollingPeriod,5,2)  = 11 THEN -- Når utgangspunktet er 10 (og rullerende er 11) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
           
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;           
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
      END IF;
    WHEN l_iPeriodNo = 11 THEN
      -- Første rullerende periode er her 12
      IF substr(i_iRollingPeriod,5,2)  = 1 THEN -- Når utganspunktet er 11 (og rullerende er 1) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 11
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             = ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
     
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;        
        -- Prognose for periode 12
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period              = ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;
        
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
  
        IF NVL(l_fAmount,0) <> 0 THEN
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;
        
      END IF;
    WHEN l_iPeriodNo = 12 THEN 
          -- Første rullerende periode er her 01
      IF substr(i_iRollingPeriod,5,2)  = 1 THEN -- Når utgangspunktet er 12 (og rullerende er 1) må det hentes fra regnskap
      -- Hent fra regnskap
        SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmount
          FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
         WHERE gl.account_id         = r3a.account_id
           AND r3a.report_level_3_id = r.report_level_3_id
           AND r.rule_id             = re.rule_entry_id
           AND re.rule_entry_id      = i_rRuleId
           AND gl.period             IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                           FROM rule_period_payment 
                                          WHERE rule_entry_id  = i_rRuleId 
                                            AND period_payment = l_strPaymentPeriod )
           AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
           AND gl.activity_id = '2';
      ELSE
        -- Hent fra prognose
        BEGIN
          SELECT NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fAmount
            FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
           WHERE pe.report_level_3_id = r.report_level_3_id
             AND pe.prognosis_id      = i_iPrognosisId
             AND pe.period            IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)
                                               FROM rule_period_payment 
                                              WHERE rule_entry_id  = i_rRuleId 
                                                AND period_payment = l_strPaymentPeriod )
             AND r.rule_id              = re.rule_entry_id
             AND re.rule_entry_id       = i_rRuleId;
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmount := 0;
        END;
        
        IF NVL(l_fAmount,0) <> 0 THEN
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,NVL(l_fAmount,0));
        END IF;  
      END IF;
    ELSE NULL;
    END CASE;

    COMMIT; 
END GenerateForNettleiePrivat;

PROCEDURE GenerateForLonn            ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  
  l_fAllFactors           NUMBER(11,4);
  l_fAmountFromProgonsis  PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountBase           PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPersonellCost  PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPayRollTax     PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPension        PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountVacationSalary PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountTax            PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fAmountPRTofPensionVS PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  
  l_iLiquidityTax            REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_iLiquidityVacationSalary REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_iLiquidityPayrollTax     REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_iPeriodNo                NUMBER(11,0);
  l_iLastRollingPeriod       NUMBER(11,0);
  l_iLiquidityPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iLiquidityReportLineId   REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  
  l_iYearOffset              NUMBER(11,0);
  
  l_strPaymentPeriod         RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_rRuleId                  RULE_ENTRY.RULE_ENTRY_ID%TYPE;
  
  TYPE PaymentPeriods IS TABLE OF RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  --TYPE PaymentPeriods IS VARRAY(14) OF RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_arrPaymentPeriods    PaymentPeriods; 
  
  CONST_PERSONELL_COST       CONSTANT NUMBER(11,4) := 2; -- Beregner 2% personellkostnad
  CONST_TAX_RATE             CONSTANT NUMBER(11,4) := 37.5; -- Beregner 37,5% skatt
  CONST_WORK_TAX_RATE        CONSTANT NUMBER(11,4) := 14.1; -- Trekker ut 14,1% arbeidsgiveravgift
  CONST_PENSION_RATE         CONSTANT NUMBER(11,4) := 11;  -- Trekker ut 11% pensjon
  CONST_VACATION_SALARY_RATE CONSTANT NUMBER(11,4) := 12;   -- Trekker ut 12% feriepenger

BEGIN
  l_strPaymentPeriod := 'NA';
  SELECT period INTO l_iLiquidityPeriod FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  SELECT acc_period INTO l_iLastRollingPeriod 
    FROM period 
   WHERE date_from = ( SELECT date_from
                        FROM period   
                       WHERE acc_period = ( SELECT acc_period 
                                              FROM period 
                                             WHERE date_from = ( SELECT ADD_MONTHS(date_from,12) 
                                                                   FROM period 
                                                                  WHERE acc_period = ( SELECT period 
                                                                                         FROM liquidity_entry_head
                                                                                        WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                      )
                                                                )
                                                AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                                                               
                                            )
                     )
      AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
  /*   28.04.2015 Utgår pga nytt forsystem i prognosemodul hvor lønn blir lagt direkte på ekstern/intern lønn og ikke på notelinje
  BEGIN
    
    SELECT SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountFromProgonsis --l_fAmountWOPersonellCost
      FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
     WHERE pne.note_line_id       = r.note_line_id
       AND pne.prognosis_entry_id = pe.prognosis_entry_id
       AND pe.prognosis_id        = i_iPrognosisId
       AND pe.period              = i_iRollingPeriod
       AND r.rule_id              = re.rule_entry_id
       AND re.rule_entry_id       = i_rRuleId;
    EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountFromProgonsis := 0;
  END;
  */
  -- Dersom vi ikke finner taller fra notelinjen må vi sjekke på R3 nivå fra samme regel
  -- 28.04.2015 Utgår pga nytt forsystem i prognosemodul hvor lønn blir lagt direkte på ekstern/intern lønn
  
  --IF NVL(l_fAmountFromProgonsis,0) = 0 THEN
    BEGIN
      SELECT SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fAmountFromProgonsis
       FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
      WHERE pe.report_level_3_id  = r.report_level_3_id
        AND pe.prognosis_id       = i_iPrognosisId
        AND pe.period              = i_iRollingPeriod
        AND r.rule_id             = re.rule_entry_id
        AND re.rule_entry_id      = i_rRuleId;  
      EXCEPTION WHEN NO_DATA_FOUND THEN l_fAmountFromProgonsis := 0;
    END;  
 -- END IF;
  
  l_fAllFactors := ((CONST_PERSONELL_COST + CONST_WORK_TAX_RATE + CONST_PENSION_RATE + CONST_VACATION_SALARY_RATE ) / 100) + 1;
    
  l_fAmountBase           := l_fAmountFromProgonsis / l_fAllFactors;
  l_fAmountPersonellCost  := l_fAmountBase * (CONST_PERSONELL_COST / 100);
  l_fAmountPayRollTax     := l_fAmountBase * (CONST_WORK_TAX_RATE / 100);         -- Trekker ut arbeidsgiveravgift
  l_fAmountPension        := l_fAmountBase * (CONST_PENSION_RATE / 100);          -- Trekker ut pensjon
  l_fAmountVacationSalary := l_fAmountBase * (CONST_VACATION_SALARY_RATE / 100);  -- Trekker ut feriepenger
  l_fAmountTax            := l_fAmountBase * (CONST_TAX_RATE / 100);              -- Beregner skatt
  l_fAmountPRTofPensionVS := (l_fAmountVacationSalary + l_fAmountPension) * (CONST_WORK_TAX_RATE/100);


  -- 28.04.2015 Beløpet som legges på Utbetalt lønn er for høyt, må korrigeres med 45% grunnet skatt og andre trekk...jfr Bente og Brit
  l_fAmountBase := l_fAmountBase * 0.55;

   INSERT INTO liquidity_entry_mth_salary_tmp
          (liquidity_entry_head_id,report_level_3_id,period,base_amount,personell_cost_amount,work_tax_amount,pension_amount,vacation_salary_amount,tax_amount,PRTofPensionVS_amount)
   VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fAmountBase,l_fAmountPersonellCost,l_fAmountPayRollTax,l_fAmountPension,l_fAmountVacationSalary,l_fAmountTax,l_fAmountPRTofPensionVS);
  
  COMMIT;

  -- Beregner arbeidsgiveravgift
  SELECT rule_entry_id     INTO l_rRuleId                FROM rule_entry WHERE hard_coded_db_proc = 997; --arbeidsgiveravgift
  SELECT report_level_3_id INTO l_iLiquidityReportLineId FROM r3_rule_company_relation WHERE rule_id = l_rRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
  GenerateForArbGiverAvgift (i_rLiquidityId,l_rRuleId,i_iPrognosisId,l_iLiquidityReportLineId,i_iRollingPeriod,i_dtCurrentRolling);
    
  --Beregner skatt
  SELECT rule_entry_id     INTO l_rRuleId                FROM rule_entry WHERE hard_coded_db_proc = 998; --Skatt
  SELECT report_level_3_id INTO l_iLiquidityReportLineId FROM r3_rule_company_relation WHERE rule_id = l_rRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
  GenerateForSkattetrekk (i_rLiquidityId,l_rRuleId,i_iPrognosisId,l_iLiquidityReportLineId,i_iRollingPeriod,i_dtCurrentRolling);
  
  -- Beregner feriepenger for siste periode
  IF i_iRollingPeriod = l_iLastRollingPeriod THEN
    SELECT rule_entry_id     INTO l_rRuleId FROM rule_entry WHERE hard_coded_db_proc = 9932; --Feriepengeregel
    SELECT report_level_3_id INTO l_iLiquidityVacationSalary FROM r3_rule_company_relation WHERE rule_id = l_rRuleId AND company_id = g_strCompanyId AND is_enabled = 1;
    GenerateForFeriePenger(i_rLiquidityId,l_rRuleId,i_iPrognosisId,l_iLiquidityVacationSalary,i_iRollingPeriod,i_dtCurrentRolling);
  END IF;
  
  -- Flytter lønnskostnader til tmp tabell -- FLYTTE DENNE UT AV CURSOR?
  l_arrPaymentPeriods := PaymentPeriods('01','02','03','04','05','07','08','09','10','11','12');
  SELECT substr(i_iRollingPeriod,5,2) INTO l_strPaymentPeriod FROM dual;
  
  IF l_strPaymentPeriod MEMBER OF l_arrPaymentPeriods THEN
    INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
      SELECT liquidity_entry_head_id,report_level_3_id,period,base_amount 
        FROM liquidity_entry_mth_salary_tmp
       WHERE liquidity_entry_head_id = i_rLiquidityId
         AND report_level_3_id       = i_iLiquidityReportLineId
         AND period                  = i_iRollingPeriod;
  END IF;
  
  COMMIT;
END GenerateForLonn;

PROCEDURE GenerateForFeriePenger     ( i_rLiquidityId         IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iLiquidityPeriod         PERIOD.ACC_PERIOD%TYPE;
  l_iVacationSalaryPeriod    PERIOD.ACC_PERIOD%TYPE;
  l_iVacationSalaryPeriodNo  NUMBER(2);
  
  l_fVacationSalaryAmount    PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
BEGIN

  BEGIN
    SELECT payment_month_no
      INTO l_iVacationSalaryPeriodNo
      FROM rule_entry 
     WHERE hard_coded_db_proc = 9932;  -- Feriepenger
  EXCEPTION WHEN NO_DATA_FOUND THEN l_iVacationSalaryPeriodNo := 6;   --DEFAULT ER JUNI
  END;
  SELECT period INTO l_iLiquidityPeriod FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  IF TO_NUMBER(SUBSTR(l_iLiquidityPeriod,5,2)) < l_iVacationSalaryPeriodNo THEN
    l_iVacationSalaryPeriod := TO_NUMBER(SUBSTR(l_iLiquidityPeriod,0,4) || LPAD (l_iVacationSalaryPeriodNo,2,'0'));
  ELSE  
    l_iVacationSalaryPeriod := TO_NUMBER(SUBSTR(l_iLiquidityPeriod,0,4)+1 || LPAD (l_iVacationSalaryPeriodNo,2,'0'));
  END IF;
  
  IF i_iLiquidityReportLineId <> -1 THEN    
     IF to_number(substr(l_iLiquidityPeriod,5,2)) <= 5 THEN ---Hent feriepenger fra balansekonto 2940,2941,2942
        
        INSERT INTO liquidity_entry_mth_item_tmp
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount)
        SELECT 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod
          ,NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0)
        FROM general_ledger
        WHERE account_id         IN ( SELECT account_id            FROM rule_gl_assoc WHERE rule_id =  i_rRuleId )
          AND company_id         =  g_strCompanyId --( SELECT company_id            FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId ) 
          AND substr(period,0,4) =  ( SELECT substr(period,0,4)-1  FROM liquidity_entry_head   WHERE liquidity_entry_head_id = i_rLiquidityId )
        GROUP BY 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod;
          
      ELSE
        -- Hent det som er registrert i regnskap inneværende år
         INSERT INTO liquidity_entry_mth_item_tmp
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount)
        SELECT 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod
          ,NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0)
        FROM general_ledger
        WHERE account_id         IN ( SELECT account_id FROM rule_gl_assoc WHERE rule_id = i_rRuleId )
          AND company_id         = g_strCompanyId --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
          AND substr(period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND period             <= ( SELECT period FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
        GROUP BY 
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,l_iVacationSalaryPeriod;
          
        --Hent resterende fra de tidligere beregnede radene
        SELECT SUM(vacation_salary_amount) INTO l_fVacationSalaryAmount FROM liquidity_entry_mth_salary_tmp
        WHERE liquidity_entry_head_id = i_rLiquidityId
          AND period                  > l_iLiquidityPeriod
          AND substr(period,0,4)      = ( SELECT substr(leh.period,0,4) FROM liquidity_entry_head leh WHERE leh.liquidity_entry_head_id = i_rLiquidityId );

        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES (i_rLiquidityId,i_iLiquidityReportLineId,l_iVacationSalaryPeriod,l_fVacationSalaryAmount);

      END IF;
  END IF;    
  COMMIT;
  -- SLUTT FERIEPENGER
END GenerateForFeriePenger;

FUNCTION GetSalaryWorkTaxAmountMAX( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                   ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                   ,l_iYearOffset      IN NUMBER
                                   ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                   ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(work_tax_amount+PrtofPensionVS_Amount) INTO l_fResult --Legger også til AGA av pensjon og feriepenger
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  = (SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                      FROM rule_period_payment 
                                     WHERE rule_entry_id  = i_rRuleId 
                                       AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryWorkTaxAmountMAX;

FUNCTION GetSalaryWorkTaxAmountIN ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                   ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                   ,l_iYearOffset      IN NUMBER
                                   ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                   ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(work_tax_amount+PrtofPensionVS_Amount) INTO l_fResult --Legger også til AGA av pensjon og feriepenger
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryWorkTaxAmountIN;

PROCEDURE GenerateForArbGiverAvgift  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
 IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fPayRollTaxBasis NUMBER(18,2);
  l_fSalaryTaxAmount  NUMBER(18,2);
  
  l_strPaymentPeriod        RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_iVacationSalaryPeriodNo RULE_ENTRY.PAYMENT_MONTH_NO%TYPE;
  l_iLiquidityPeriod        LIQUIDITY_ENTRY_HEAD.PERIOD%TYPE;

BEGIN
  l_strPaymentPeriod := 'NA';
  SELECT period                        INTO l_iLiquidityPeriod FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo        FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utganspunktet er 1 (og rullerende er 3) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 1
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
          FROM general_ledger
         WHERE account_id  =  ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
           AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
           AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 2
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
  
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
  
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
      END IF;
    WHEN l_iPeriodNo = 2 THEN
      -- Første rullerende periode er her 03
      IF substr(i_iRollingPeriod,5,2)  = 3 THEN -- Når utgangspunktet er 2 (og rullerende er 3) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 3 THEN
      -- Første rullerende periode er her 04
      IF substr(i_iRollingPeriod,5,2) = 5 THEN -- Når utgangspunktet er 3 (og rullerende er 5) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 3
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
          FROM general_ledger
         WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
           AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
           AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
        -- Prognose for periode 4
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 4 THEN
      -- Første rullerende periode er her 05
      IF substr(i_iRollingPeriod,5,2) = 5 THEN -- Når utganspunktet er 4 (og rullerende er 5) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
      END IF;
    WHEN l_iPeriodNo = 5 THEN
      -- Første rullerende periode er her 06
      IF substr(i_iRollingPeriod,5,2) = 7 THEN -- Når utgangspunktet er 5 (og rullerende er 7) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 5
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
           FROM general_ledger
          WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
            AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
            AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
            AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 6
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);                

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 6 THEN
      -- Første rullerende periode er her 07
      IF substr(i_iRollingPeriod,5,2) = 7 THEN -- Når utgangspunktet er 6 (og rullerende er 7) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
             AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
             AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                   FROM rule_period_payment 
                                  WHERE rule_entry_id  = i_rRuleId 
                                    AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    WHEN l_iPeriodNo = 7 THEN
      -- Første rullerende periode er her 08
      IF substr(i_iRollingPeriod,5,2) = 9 THEN -- Når utgangspunktet er 7 (og rullerende er 9) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 7
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
             AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
             AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
             AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 8
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);                

      ELSE
        -- Hent fra prognose
        BEGIN
         l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
       
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 8 THEN
      -- Første rullerende periode er her 09
      IF substr(i_iRollingPeriod,5,2) = 9 THEN -- Når utganspunktet er 8 (og rullerende er 9) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    WHEN l_iPeriodNo = 9 THEN
      -- Første rullerende periode er her 10
      IF substr(i_iRollingPeriod,5,2) = 11 THEN -- Når utgangspunktet er 9 (og rullerende er 11) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 9
           SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
             FROM general_ledger
            WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
              AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                     FROM rule_period_payment 
                                    WHERE rule_entry_id  = i_rRuleId 
                                      AND period_payment = l_strPaymentPeriod )
              AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 10
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
         
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);              

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
  
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 10 THEN
      -- Første rullerende periode er her 11
      IF substr(i_iRollingPeriod,5,2) = 11 THEN -- Når utgangspunktet er 10 (og rullerende er 11) skal det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
             AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    WHEN l_iPeriodNo = 11 THEN
      -- Første rullerende periode er her 12
      IF substr(i_iRollingPeriod,5,2) = 1 THEN -- Når utgangspunktet er 11 (og rullerende er 1) må det hentes fra både regnskap og prognose
        -- Hent fra regnskap og prognose
        -- Regnskap for periode 11
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
           FROM general_ledger
          WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
            AND period      >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
            AND period      <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                   FROM rule_period_payment 
                                  WHERE rule_entry_id  = i_rRuleId 
                                    AND period_payment = l_strPaymentPeriod )
            AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);
 
        -- Prognose for periode 12
        BEGIN
           l_fSalaryTaxAmount := GetSalaryWorkTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);               

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        

      END IF;
    WHEN l_iPeriodNo = 12 THEN
      -- Første rullerende periode er her 01
      IF substr(i_iRollingPeriod,5,2) = 1 THEN -- Når utgangspunktet er 12 (og rullerende er 1) må det hentes fra regnskap
      -- Hent fra regnskap
          SELECT NVL(SUM(amount),0) INTO l_fPayRollTaxBasis 
            -- Tar ikke hensyn til faktorer for regnskapstall
            FROM general_ledger
           WHERE account_id  = ( SELECT closing_balance_account_id    FROM rule_entry WHERE rule_entry_id = i_rRuleId )
             AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
             AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                   FROM rule_period_payment 
                                  WHERE rule_entry_id  = i_rRuleId 
                                    AND period_payment = l_strPaymentPeriod )
             AND company_id  = g_strCompanyId; -- ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fPayRollTaxBasis);

      ELSE
        -- Hent fra prognose
        BEGIN
          l_fSalaryTaxAmount := GetSalaryWorkTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	        EXCEPTION WHEN NO_DATA_FOUND THEN l_fSalaryTaxAmount := 0;
        END;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fSalaryTaxAmount);        
  
      END IF;
    ELSE NULL;
    END CASE;

END GenerateForArbGiverAvgift;

FUNCTION GetSalaryTaxAmountMAX( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                               ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                               ,l_iYearOffset      IN NUMBER
                               ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                               ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(tax_amount) INTO l_fResult 
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  = (SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                      FROM rule_period_payment 
                                     WHERE rule_entry_id  = i_rRuleId 
                                       AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryTaxAmountMAX;

FUNCTION GetSalaryTaxAmountIN ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                   ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                   ,l_iYearOffset      IN NUMBER
                                   ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                   ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER 
IS 
 l_fResult NUMBER;
BEGIN
  SELECT SUM(tax_amount) INTO l_fResult 
    FROM liquidity_entry_mth_salary_tmp 
   WHERE liquidity_entry_head_id = i_rLiquidityId
     AND period                  IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod );
  RETURN l_fResult;
END GetSalaryTaxAmountIN;

PROCEDURE GenerateForSkattetrekk     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS                                       
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fPayRollTaxBasis NUMBER(18,2);
  
  l_fTaxBasis        PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_fTaxAmount       PROGNOSIS_NOTE_ENTRY.AMOUNT%TYPE;
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  
BEGIN
  l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
     -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;

    CASE 
      WHEN l_iPeriodNo = 1 THEN
        IF substr(i_iRollingPeriod,5,2) = 3 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
           
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
             VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;       
          
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 2 THEN
        IF substr(i_iRollingPeriod,5,2) = 3 THEN
          -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	        EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
      
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 3 THEN
        IF substr(i_iRollingPeriod,5,2) = 5 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
             VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
          END;
  
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 4 THEN
        IF substr(i_iRollingPeriod,5,2) = 5 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 5 THEN
        IF substr(i_iRollingPeriod,5,2) = 7 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
            
            INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
            EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
          END;
          
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 6 THEN
        IF substr(i_iRollingPeriod,5,2) = 7 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	         EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 7 THEN
        IF substr(i_iRollingPeriod,5,2) = 9 THEN
                   -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
            INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 8 THEN
        IF substr(i_iRollingPeriod,5,2) = 9 THEN
                  -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 9 THEN
        IF substr(i_iRollingPeriod,5,2) = 11 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
            l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
             EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
             INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 10 THEN
        IF substr(i_iRollingPeriod,5,2) = 11 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	         EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 11 THEN
        IF substr(i_iRollingPeriod,5,2) = 1 THEN
           -- HENT FØRST FRA REGNSKAP
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MIN(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
              
           INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);
           -- SÅ FRA PROGNOSE
           BEGIN
             l_fTaxAmount := GetSalaryTaxAmountMAX(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
              EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
           END;
            INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
              VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);
          
        ELSE
          -- HENT BARE FRA PROGNOSE
          BEGIN
            l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
      WHEN l_iPeriodNo = 12 THEN
        IF substr(i_iRollingPeriod,5,2) = 1 THEN
           -- Hent fra regnskap
           SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
             FROM general_ledger
            WHERE account_id =  ( SELECT closing_balance_account_id FROM rule_entry WHERE rule_entry_id = i_rRuleId )
              AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
              AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                        FROM rule_period_payment 
                                       WHERE rule_entry_id  = i_rRuleId 
                                         AND period_payment = l_strPaymentPeriod )
              AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
     
          INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
            VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);

        ELSE
        -- Hent fra prognose
        BEGIN
          l_fTaxAmount := GetSalaryTaxAmountIN(i_rLiquidityId,i_iRollingPeriod,l_iYearOffset,i_rRuleId,l_strPaymentPeriod);
	          EXCEPTION WHEN NO_DATA_FOUND THEN l_fTaxAmount := 0;
        END;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxAmount);

        END IF;
    ELSE NULL;
    END CASE;

END GenerateForSkattetrekk;

PROCEDURE GenerateForMVA             ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_fPayRollTaxBasis NUMBER(18,2);
  
  l_fAmountWOPersonellCost  NUMBER(18,2);
  l_fAmountWOPayRollTax     NUMBER(18,2);
  l_fAmountWOPension        NUMBER(18,2);
  l_fAmountWOVacationSalary NUMBER(18,2);
  l_fAmountTax              NUMBER(18,2);
  l_fAmountNetSalary        NUMBER(18,2);
  l_fAmountPayrollTax       NUMBER(18,2);
  
  l_fInvestment      NUMBER(18,2);
  l_fActivatedSalary NUMBER(18,2);
  
  l_iLiquidityVAT   REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE;
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
BEGIN
  l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Henter tall fra regnskap
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  BEGIN
    
    SELECT report_level_3_id 
      INTO l_iLiquidityVAT
      FROM r3_rule_company_relation 
     WHERE rule_id = ( SELECT rule_entry_id FROM rule_entry WHERE hard_coded_db_proc = 994 )  -- MVA
       AND company_id = g_strCompanyId
       AND is_enabled = 1;
     
  EXCEPTION WHEN NO_DATA_FOUND THEN l_iLiquidityVAT := -1;
  END;
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      IF substr(i_iRollingPeriod,5,2) = 2 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 4 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      END IF;
    
      IF g_strCompanyId = 'SN' THEN
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      END IF;         
               
    WHEN l_iPeriodNo = 2 THEN
      IF substr(i_iRollingPeriod,5,2) = 4 THEN -- Hente fra regnskap når startperiode er 2 og rullerende er 4
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod),'Fra hovebok');
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''),'Fra prognose');
       -- Hente fra notelinje
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
         VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''),'Fra notelinje');
       -- Investering - notelinje (Aktivert lønn)
       l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
       l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
       IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
         INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount, liquidity_entry_mth_comment)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0),'Fra investering + aktivert lønn');
       END IF; 

IF g_strCompanyId = 'SN' THEN    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount, liquidity_entry_mth_comment)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod), 'Fra likviditet - BFN');
               END IF;
      END IF;
    WHEN l_iPeriodNo = 3 THEN 
      IF substr(i_iRollingPeriod,5,2) = 4 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 6 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      

    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 4 THEN 
      IF substr(i_iRollingPeriod,5,2) = 6 THEN -- Hente fra regnskap når startperiode er 4 og rullerende er 6
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- NOTELINJE
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- Investering - notelinje (Aktivert lønn)
       l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
       l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
       IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
         INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
       END IF; 
      
    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 5 THEN 
      IF substr(i_iRollingPeriod,5,2) = 6 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 8 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      

    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 6 THEN 
      IF substr(i_iRollingPeriod,5,2) = 8 THEN -- Hente fra regnskap når startperiode er 6 og rullerende er 8
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- NOTELINJE
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF;
      
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
      END IF;
    WHEN l_iPeriodNo = 7 THEN 
      IF substr(i_iRollingPeriod,5,2) = 8 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 10 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      

    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 8 THEN 
      IF substr(i_iRollingPeriod,5,2) = 10 THEN -- Hente fra regnskap når startperiode er 8 og rullerende er 10
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- NOTELINJE
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
       -- Investering - notelinje (Aktivert lønn)
       l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
       l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
            VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF;
    
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 9 THEN 
      IF substr(i_iRollingPeriod,5,2) = 10 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 12 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Må sette l_iYearOffset for å hente investeringer for riktig periode og ÅR
        IF substr(i_iRollingPeriod,5,2) = 2 THEN
          l_iYearOffset := 0;
        ELSE l_iYearOffset := 1;
        END IF;
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
   
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 10 THEN 
      IF substr(i_iRollingPeriod,5,2) = 12 THEN -- Hente fra regnskap når startperiode er 10 og rullerende er 12
      
              INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- NOTELINJE
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
         -- Investering - notelinje (Aktivert lønn)
         l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
         l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
         INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF;
            
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 11 THEN 
      IF substr(i_iRollingPeriod,5,2) = 12 THEN  -- HENTE FRA REGNSKAP
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
      ELSIF substr(i_iRollingPeriod,5,2) = 2 THEN  -- HENTE FRA REGNSKAP OG PROGNOSE
        -- Regnskap
        INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromAccountsSplit(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
        -- Prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                 CalculateVATFromPrognosisSplit(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn) - SPLITTET
        l_fInvestment      := CalculateVATFromInvestSplit    (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalarySplit (i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
      ELSE -- HENTE FRA PROGNOSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Hente fra notelinje
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                  CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
           INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
             VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));
        END IF; 
      
     
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
      END IF;               
    WHEN l_iPeriodNo = 12 THEN 
      IF substr(i_iRollingPeriod,5,2) = 2 THEN -- Hente fra regnskap når startperiode er 12 og rullerende er 2
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromAccounts(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));
            
      ELSE
        -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
         VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
                CalculateVATFromPrognosis(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- NOTELINJE
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
          VALUES( i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,
                 CalculateVATFromNoteLine(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,''));
        -- Investering - notelinje (Aktivert lønn)
        l_fInvestment := CalculateVATFromInvestment(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,1,'');  -- OIG 20022015 Sjekk l_iOffsetYEAR
        l_fActivatedSalary := CalculateVATFromActSalary(i_rLiquidityId,i_iPrognosisId,i_rRuleId,i_iRollingPeriod,0,'');
        
        IF l_fInvestment <> 0 THEN  --- Må være investeringsbeløp
          INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period ,amount)
           VALUES (i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,NVL((l_fInvestment+l_fActivatedSalary),0));       
        END IF;
     
     
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        VALUES(i_rLiquidityId,l_iLiquidityVAT,i_iRollingPeriod,
               CalculateVATFromLiquidity(i_rLiquidityId,i_rRuleId,i_iRollingPeriod,l_iYearOffset,l_strPaymentPeriod));    
               
        END IF;
    
    ELSE NULL;
  END CASE;
END GenerateForMVA;

PROCEDURE GenerateForELAvgift        ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_iLiquidityYear   NUMBER(11,0);
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
BEGIN
    l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;
  
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        --AND period_basis =  substr(i_iRollingPeriod,5,2); --SJEKK!!
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,0,4)) INTO l_iLiquidityYear FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  IF substr(i_iRollingPeriod,5,2)  = 2 THEN -- Når utganspunktet er 1 (og rullerende er 2) må det hentes fra regnskap i fjor
  -- Kan Year Offset håndteres i regelen?
    l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor når likviditetsperiode er 1
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
      ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
     FROM general_ledger
    WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
        -- Tall må hentes akkumulert fra periode 00
      AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
      AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
      AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
      GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

  ELSE 
    l_iYearOffset := -1; -- Hente regnskaptall fra i fjor 

    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
    SELECT
      i_rLiquidityId
      ,i_iLiquidityReportLineId
      ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
      ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
    FROM general_ledger
   WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
     -- Tall må hentes akkumulert fra periode 00
     AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
     AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
    AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
    GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

  END IF;
END GenerateForELAvgift;

PROCEDURE GenerateForEnovaAvgift     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_iRowCount        NUMBER(11,0);
  l_iYearOffset      NUMBER(11,0);
  l_iPeriodNo        NUMBER(11,0);
  l_iLiquidityYear   NUMBER(11,0);
  l_strPaymentPeriod RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  
BEGIN
    l_strPaymentPeriod := 'NA';
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    -- Er det utbetalinger på denne rullerende periode?
     SELECT DISTINCT period_payment INTO l_strPaymentPeriod 
       FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);        
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; --l_strPaymentPeriod := 'NA';
  END;

  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  
  -- Hent periode fra likviditetshode for å etablere utgangspunkt for å 
  -- avgjøre om det skal hentes fra regnskap eller prognose
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo      FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  SELECT to_number(substr(period,0,4)) INTO l_iLiquidityYear FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  
  CASE  
    WHEN l_iPeriodNo = 1 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2)  = 2 THEN -- Når utganspunktet er 1 (og rullerende er 2) må det hentes fra regnskap i fjor
        l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
         AND period <= (SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
         AND gl.company_id         =  g_strCompanyId
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
         

/*
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
         FROM general_ledger
        WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  g_strCompanyId --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

*/

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                            -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  = g_strCompanyId -- ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 2 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) = 4 THEN -- Når utganspunktet er 2 (og rullerende er 4) må det hentes fra regnskap
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  =  g_strCompanyId -- ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  =  g_strCompanyId --( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND rp.period_payment = l_strPaymentPeriod
          AND company_id  =  g_strCompanyId -- ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 3 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) = 4 THEN -- Når utganspunktet er 3 (og rullerende er 4) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 4 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (6,4) THEN -- Når utganspunktet er 4 (og rullerende er 6 eller 4) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 5 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (6,4) THEN -- Når utganspunktet er 5 (og rullerende er 6 eller 4) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;

        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 6 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (8,4,6) THEN -- Når utganspunktet er 6 (og rullerende er 8,4 eller 6) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 7 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (8,4,6) THEN -- Når utganspunktet er 7 (og rullerende er 8,4 eller 6) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 8 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (10,4,6,8) THEN -- Når utganspunktet er 8 (og rullerende er 10,4,6 eller 8) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
                  ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
           -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 9 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (10,4,6,8) THEN -- Når utganspunktet er 9 (og rullerende er 10,4,6 eller 8) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 10 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (12,4,6,8,10) THEN -- Når utganspunktet er 10 (og rullerende er 12,4,6,8 eller 10) må det hentes fra regnskap i år
        l_iYearOffset := 0; -- Hente regnskaptall fra i år
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 11 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (12,4,6,8,10) THEN -- Når utganspunktet er 11 (og rullerende er 12,4,6,8 eller 10) må det hentes fra regnskap i fjor
        l_iYearOffset := -1; -- Hente regnskaptall fra i fjor i forhold til rullerende periode
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      ELSE 
      /*
        -- Henter regnskapstall fra i år og i fjor (I den denne rekkefølge - henter først det vi har og supplerer med periodetall fra i fjor)
        -- Inneværende år og sjekk på rullerende periode
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := 0; -- Hente regnskaptall fra inneværende år
        ELSE
          l_iYearOffset := -2; -- Hente regnskaptall fra i fjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
          ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
         FROM general_ledger
        WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo),2,'0')) FROM dual )
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        
        */
        -- Fjorårets eller forfjorårets tall
        IF to_number(substr(i_iRollingPeriod,0,4)) = l_iLiquidityYear THEN
          l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        ELSE 
          l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor siden rullerende periode er over i neste år
        END IF;
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)  -- Legger 1 på l_iPeriodNo for neste periode
          --AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || LPAD(TO_CHAR(l_iPeriodNo+1),2,'0')) FROM dual )  -- Legger 1 på l_iPeriodNo for neste periode
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

      END IF;
    WHEN l_iPeriodNo = 12 THEN 
      -- Første rullerende periode er her 02
      IF substr(i_iRollingPeriod,5,2) IN (4,6,8,10,12) THEN -- Når utganspunktet er 12 (og rullerende er 2,4,6,8,10 eller 12) må det hentes fra regnskap i år
        l_iYearOffset := -1; -- Hente regnskaptall fra i fjor
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);

        ELSE 
        l_iYearOffset := -2; -- Hente regnskaptall fra i forfjor
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
           i_rLiquidityId
          ,i_iLiquidityReportLineId
          ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
         ,SUM(gl.amount*NVL(rp.adjustment_factor,1)*NVL(rp.sign_effect,1)*NVL(gla.sign_effect,1)*NVL(gla.adjustment_factor,1)) 
        FROM general_ledger gl, rule_period_payment rp, rule_gl_assoc gla
       WHERE gl.account_id = gla.account_id
         AND rp.rule_entry_id      = gla.rule_id
         AND rp.rule_entry_id      = i_rRuleId 
         AND rp.period_payment = l_strPaymentPeriod                                  
         -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY i_rLiquidityId,i_iLiquidityReportLineId,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
        
      END IF;
    ELSE NULL;
  END CASE;  
      
  /*
  INSERT INTO liquidity_entry_mth_item_tmp
         (liquidity_entry_head_id
         ,report_level_3_id
         ,period
         ,amount)
  SELECT
    i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod)
    ,NVL(SUM(amount) * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId),0)
   FROM general_ledger
   WHERE account_id       IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
          -- Tall må hentes akkumulert fra periode 00
          AND period >= (SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual)
                                 --rule_period_payment 
                                --WHERE rule_entry_id  = i_rRuleId 
                                --AND period_payment = l_strPaymentPeriod
                        
          AND period <= (SELECT max(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                 FROM rule_period_payment 
                                WHERE rule_entry_id  = i_rRuleId 
                                  AND period_payment = l_strPaymentPeriod)
          AND company_id  =  ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
   GROUP BY 
     i_rLiquidityId
    ,i_iLiquidityReportLineId
    ,to_number(substr(i_iRollingPeriod,0,4) || l_strPaymentPeriod);
  */
END GenerateForEnovaAvgift;

PROCEDURE GenerateForGrunnNaturOverskatt ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                           i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                           i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                           i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                           i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                           i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_fTaxBasis           NUMBER(18,2);
  l_fTaxBasisYear1      NUMBER(18,2);
  l_fTaxBasisYear2      NUMBER(18,2);
  l_fTempAmount         NUMBER(18,2); 
  l_iYearOffset         NUMBER(11,0);
  l_iRowCount           NUMBER(11,0);
  l_iPaymentPeriodCount NUMBER(11,0);
  l_iPeriodNo           NUMBER(11,0);
  l_iPeriodId           NUMBER(11,0);
  l_strPaymentPeriod    RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE;
  l_iZeroIfNegative     RULE_ENTRY.ZERO_IF_NEGATIVE%TYPE;
  l_iZeroIfPositive     RULE_ENTRY.ZERO_IF_POSITIVE%TYPE;

BEGIN
  l_strPaymentPeriod := 'NA';
  -- Sjekk om det er utbetalinger for gjeldende periode
  SELECT count(*) INTO l_iPaymentPeriodCount 
    FROM rule_period_payment 
   WHERE rule_entry_id = i_rRuleId 
     AND period_payment = substr(i_iRollingPeriod,5,2);
  
  IF l_iPaymentPeriodCount = 0 THEN
    RETURN;
  END IF;
  -- Hent evt årsskifte/årsforflytning
  BEGIN
    SELECT DISTINCT NVL(year_offset,0) INTO l_iYearOffset 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2);
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN l_iYearOffset := 0;
  END;
  -- Hent betalingsperiode for den aktuelle rullerende perioden
  BEGIN
    SELECT period_payment INTO l_strPaymentPeriod 
      FROM rule_period_payment 
      WHERE rule_entry_id = i_rRuleId
        AND period_payment =  substr(i_iRollingPeriod,5,2)
        AND period_basis   =  substr(i_iRollingPeriod,5,2);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN; 
  END;
 -- Sett resultat lik 0 dersom negativt beløp
 SELECT nvl(zero_if_negative,0) INTO l_iZeroIfNegative 
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
 -- Sett resultat lik 0 dersom positivt beløp
 SELECT nvl(zero_if_positive,0) INTO l_iZeroIfPositive
    FROM rule_entry 
   WHERE rule_entry_id = i_rRuleId;
  
  -- Sjekk om raden allerede er laget    
    SELECT count(*) INTO l_iRowCount
      FROM liquidity_entry_mth_item_tmp 
     WHERE liquidity_entry_head_id = i_rLiquidityId
       AND report_level_3_id       = i_iLiquidityReportLineId
       AND substr(period,5,2)      = l_strPaymentPeriod;
    
  IF l_iRowCount <> 0 THEN
    RETURN; -- Returner, Har allerede laget raden for denne betalingsperioden
  END IF;

  -- FJERNET: SPESIELL BEHANDLING AV MAI 05
 -- IF substr(i_iRollingPeriod,5,2) <> 5 THEN
  
  /* OIG 04032013 Endret til å hente fra prognose i stedet for regnskap 
     
     Fra mail fra Benete Østby / 03032014:
     
     Som vi snakket om tidligere henter modellen regnskapstall for 2012 i prognose for 2014 p.t. Jeg skulle sjekke med Nett og Kraft hvordan det blir mest riktig å gjøre det 
     og konklusjonen er nå at vi endrer til at modellen isteden henter tall fra resultatprognosen for "betalbar skatt" for fjoråret og 50% legges på februar og 50% på april. 
     Når man står i 2014 hentes prognosetall for bet.skatt 2013, og for 2015 henter man årsprognosen for 2014.


  
    SELECT NVL(SUM(amount * (SELECT NVL(re.adjustment_factor,0) FROM rule_entry re WHERE re.rule_entry_id = i_rRuleId)),0) INTO l_fTaxBasis
      FROM general_ledger
     WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = l_strPaymentPeriod )
       AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
    */
    SELECT period INTO l_iPeriodId FROM liquidity_entry_head WHERE liquidity_entry_head_id =  i_rLiquidityId;
    -- Dersom rullerende periode er i samme år som likviditetsprognosen henter vi fra fjorårets regnskap
    IF  substr(i_iRollingPeriod,0,4) = substr(l_iPeriodId,0,4) THEN

    SELECT SUM(gl.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)) INTO l_fTaxBasis
      FROM general_ledger gl, rule_entry re, report_l3_account_assoc r3a, rule_prognosis_assoc r
     WHERE r3a.report_level_3_id = r.report_level_3_id
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId
       AND gl.account_id         = r3a.account_id
       AND r3a.report_level_3_id = r.report_level_3_id
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = l_strPaymentPeriod )
       AND gl.company_id         = g_strCompanyId --( SELECT company_id FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
       AND gl.activity_id        = '2';       

/*        
        FROM general_ledger
       WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
         AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = l_strPaymentPeriod )
         AND company_id  =  g_strCompanyId; --( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
*/    

    END IF;
    -- Dersom rullerende periode IKKE er i samme år som likviditetsprognosen henter vi fra prognosen    
    IF  substr(i_iRollingPeriod,0,4) <> substr(l_iPeriodId,0,4) THEN
    SELECT NVL(SUM(amount_year*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0) INTO l_fTaxBasis
      FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
     WHERE pe.report_level_3_id  = r.report_level_3_id
       AND pe.prognosis_id       = i_iPrognosisId
       AND r.rule_id             = re.rule_entry_id
       AND re.rule_entry_id      = i_rRuleId;
   END IF;
      
    IF ((l_iZeroIfNegative = 1) AND (l_fTaxBasis < 0)) THEN l_fTaxBasis :=0; END IF;
    IF ((l_iZeroIfPositive = 1) AND (l_fTaxBasis > 0)) THEN l_fTaxBasis :=0; END IF;
    
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,l_fTaxBasis);  
  
  --END IF;
  
  /* Fjernes i følge mld fra Bente 04032014 
  -- SPESIELL BEHANDLING AV MAI 05
  -- SKAL BARE REGNES UT DERSOM LIKVIDITETSPROGNOSEN ER GENERERT I MÅNED 01,02,03 eller 04
  SELECT to_number(substr(period,5,2)) INTO l_iPeriodNo FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId;
  IF l_iPeriodNo IN (1,2,3,4) THEN
  
    IF substr(i_iRollingPeriod,5,2) = 5 THEN
  
    -- HENTER ET ÅR TIDLIGERE (to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset-1) ENN HVA SOM ER OPPGITT PÅ BETALINGSPERIODER 
    SELECT NVL(SUM(amount),0) INTO l_fTaxBasisYear2
      FROM general_ledger
     WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset-1 || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = '04' )
       AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
    
    SELECT NVL(SUM(amount),0) INTO l_fTaxBasisYear1
      FROM general_ledger
     WHERE account_id  IN ( SELECT account_id FROM rule_gl_assoc  WHERE rule_id = i_rRuleId )
       AND period      IN ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis) 
                              FROM rule_period_payment 
                             WHERE rule_entry_id  = i_rRuleId 
                               AND period_payment = '04' )
       AND company_id  =  ( SELECT company_id  FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
  
   -- l_fTempAmount := ABS(l_fTaxBasisYear1)-ABS(l_fTaxBasisYear2);
    
    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,-(l_fTaxBasisYear2-l_fTaxBasisYear1));

--    INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
--      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,i_iRollingPeriod,(l_fTaxBasisYear2-l_fTaxBasisYear1)*-1);
  
    END IF;
  END IF;

*/
END GenerateForGrunnNaturOverskatt;

PROCEDURE GenerateForIBBank ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                              i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                              i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                              i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                              i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                              i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE )
IS
  l_fAmount             NUMBER(18,2);
  l_fAmountLiquidity    NUMBER(18,2);
  l_iPeriodId           PERIOD.ACC_PERIOD%TYPE;
  l_iFirstRollingPeriod PERIOD.ACC_PERIOD%TYPE;
  l_iRollingPeriod      PERIOD.ACC_PERIOD%TYPE;
  
  -- RULLERENDE MND FRA MND 2 -12 
  CURSOR l_curRollingPeriod ( i_rLiquidityId LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE ) IS
   SELECT acc_period 
     FROM period 
    WHERE date_from >= ( SELECT date_from  
                           FROM period   
                          WHERE acc_period = ( SELECT acc_period 
                                                 FROM period 
                                                WHERE date_from = ( SELECT ADD_MONTHS(date_from,2)  -- HOPPER OVER FØRSTE MND SIDEN DENNE REGNES BARE FRA REGNSKAP 
                                                                      FROM period 
                                                                     WHERE acc_period = ( SELECT period 
                                                                                            FROM liquidity_entry_head
                                                                                           WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                         )
                                                                  )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                 
                                             )
                       )
      AND date_from <= ( SELECT date_from
                            FROM period   
                           WHERE acc_period = ( SELECT acc_period 
                                                  FROM period 
                                                 WHERE date_from = ( SELECT ADD_MONTHS(date_from,12) 
                                                                       FROM period 
                                                                       WHERE acc_period = ( SELECT period 
                                                                                              FROM liquidity_entry_head
                                                                                             WHERE liquidity_entry_head_id = i_rLiquidityId
                                                                                          )
                                                                   )
                                                  AND SUBSTR(acc_period,5,2) NOT IN ('00','13')                                                               
                                              )
                       )
      AND SUBSTR(acc_period,5,2) NOT IN ('00','13');
 
BEGIN
  SELECT period INTO l_iPeriodId FROM liquidity_entry_head WHERE liquidity_entry_head_id =  i_rLiquidityId;

  -- Første rullerende periode
  SELECT acc_period INTO l_iFirstRollingPeriod 
   FROM period 
  WHERE date_from = ( SELECT add_months(date_from,1) 
                        FROM period 
                      WHERE acc_period = ( SELECT period 
                                             FROM liquidity_entry_head 
                                            WHERE liquidity_entry_head_id = i_rLiquidityId )
                    )
    AND substr(acc_period,5,2) NOT IN ('00','13');

  -- Beregn IB fra regnskap frem til første rullerende måned
  SELECT SUM(amount) INTO l_fAmount
    FROM general_ledger gl
   WHERE gl.company_id =  ( SELECT company_id FROM liquidity_entry_head        WHERE liquidity_entry_head_id = i_rLiquidityId)
     AND gl.account_id IN ( SELECT account_id FROM rule_gl_assoc WHERE rule_id =  i_rRuleId )
     AND gl.period >=     ( SELECT acc_period FROM period WHERE date_from = to_date('0101' || SUBSTR(l_iPeriodId,0,4),'DDMMYYYY') AND substr(acc_period,5,2) = '00')  -- STARTEN AV ÅRET
     AND gl.period <=     ( SELECT acc_period FROM period WHERE date_from = to_date('01' || SUBSTR(l_iPeriodId,5,2) || SUBSTR(l_iPeriodId,0,4),'DDMMYYYY')); -- TIl FØRSTE RULLERENDE MND
  
  
  INSERT INTO liquidity_entry_mth_item (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,l_iFirstRollingPeriod,l_fAmount);
      
  COMMIT; 

  -- REGNE UT SALDO FOR RULLERENDE MND 2-12
  OPEN l_curRollingPeriod ( i_rLiquidityId );
  FETCH l_curRollingPeriod INTO l_iRollingPeriod;
  WHILE l_curRollingPeriod%FOUND LOOP
  
    SELECT sum(amount) INTO l_fAmountLiquidity
      FROM liquidity_entry_mth_item 
     WHERE liquidity_entry_head_id = i_rLiquidityId
       AND report_level_3_id IN ( SELECT report_level_3_id FROM report_level_3 WHERE report_type_id = 6 )
       AND period = ( SELECT acc_period FROM period WHERE date_from = ( SELECT ADD_MONTHS(date_from,-1) 
                                                                          FROM period 
                                                                         WHERE acc_period = l_iRollingPeriod )
                                                      AND substr(acc_period,5,2) NOT IN ('00','13'));
       
  
    INSERT INTO liquidity_entry_mth_item (liquidity_entry_head_id,report_level_3_id,period,amount)
      VALUES (i_rLiquidityId,i_iLiquidityReportLineId,l_iRollingPeriod,l_fAmountLiquidity);  
    
    COMMIT;
  
  FETCH l_curRollingPeriod INTO l_iRollingPeriod;
  END LOOP;
  
  CLOSE l_curRollingPeriod;
    
  COMMIT;
END GenerateForIBBank;

/* SLUTT HARDKODING */

/*  GENERATEFORMVA ----KODE FRA FØR FLYTTET TIL FUNKSJONER
      
      INSERT INTO liquidity_entry_mth_item_tmp(liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT 
           i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod
          ,NVL(SUM(amount),0)
        FROM general_ledger
        WHERE account_id = ( SELECT closing_balance_account_id FROM rule_entry           WHERE hard_coded_db_proc = 994 )
          AND period     >= ( SELECT to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || '00') FROM dual )
          AND period     <= ( SELECT MAX(to_number(substr(i_iRollingPeriod,0,4)+l_iYearOffset || period_basis)) 
                                    FROM rule_period_payment 
                                   WHERE rule_entry_id  = i_rRuleId 
                                     AND period_payment = l_strPaymentPeriod )
          AND company_id = ( SELECT company_id                 FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId ) 
        GROUP BY 
           i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod;
      
         /*
         -- Hente fra prognose
        INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
        SELECT
          i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod --pe.period
          ,NVL(SUM(pe.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1)),0)
        FROM prognosis_entry pe, rule_entry re, rule_prognosis_assoc r
       WHERE pe.report_level_3_id = r.report_level_3_id
         AND pe.prognosis_id      = i_iPrognosisId
         AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
         AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
         AND r.rule_id            = re.rule_entry_id
         AND re.rule_entry_id     = i_rRuleId
       GROUP BY 
          i_rLiquidityId
          ,l_iLiquidityVAT
          ,i_iRollingPeriod;
         */ 
       -- NOTELINJE
       /*
       INSERT INTO liquidity_entry_mth_item_tmp (liquidity_entry_head_id,report_level_3_id,period,amount)
       SELECT
         i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,i_iRollingPeriod
        ,SUM(pne.amount*NVL(re.adjustment_factor,1)*NVL(r.adjustment_factor,1)*NVL(r.sign_effect,1))
       FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
      WHERE pne.note_line_id         = r.note_line_id
        AND pne.prognosis_entry_id   = pe.prognosis_entry_id
        AND r.rule_id                = re.rule_entry_id
        AND re.rule_entry_id         = i_rRuleId
        AND pe.prognosis_id          = i_iPrognosisId
        AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                          FROM rule_period_payment 
                                         WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                           AND rule_entry_id = i_rRuleId)
        AND substr(pe.period,0,4) = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
        AND r.rule_note_line_included_in = 3 -- Gjelder for utregning av r3 prognose/resultat
      GROUP BY 
        i_rLiquidityId
        ,i_iLiquidityReportLineId
        ,i_iRollingPeriod;
       */
       -- Investering - notelinje (Aktivert lønn)
   
       /*
       SELECT NVL(SUM(pie.amount * NVL(re.adjustment_factor,1) * NVL(r.adjustment_factor,1) * NVL(r.sign_effect,1)),0) INTO l_fInvestment
         FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
        WHERE pie.activity_id          = r.activity_id
          AND pie.prognosis_id         = i_iPrognosisId
          AND substr(pie.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId) 
          AND substr(pie.period,0,4)   = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND r.rule_entry_id          = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId;
        */
        
        /*
       SELECT NVL(SUM(pne.amount* NVL(re.adjustment_factor,1)* NVL(r.adjustment_factor,1)),0) INTO l_fActivatedSalary
         FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
        WHERE pne.note_line_id         = r.note_line_id
          AND pne.prognosis_entry_id   = pe.prognosis_entry_id
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId
          AND pe.prognosis_id          = i_iPrognosisId
          AND r.rule_note_line_included_in  = 5  -- Gjelder for investering
          AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId)
          AND substr(pe.period,0,4)    = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
       */

END LIQUIDITY_API;
       */
       -- Investering - notelinje (Aktivert lønn)
   
       /*
       SELECT NVL(SUM(pie.amount * NVL(re.adjustment_factor,1) * NVL(r.adjustment_factor,1) * NVL(r.sign_effect,1)),0) INTO l_fInvestment
         FROM prognosis_investment_entry pie, rule_entry re, rule_investment_progno_assoc r
        WHERE pie.activity_id          = r.activity_id
          AND pie.prognosis_id         = i_iPrognosisId
          AND substr(pie.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId) 
          AND substr(pie.period,0,4)   = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId )
          AND r.rule_entry_id          = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId;
        */
        
        /*
       SELECT NVL(SUM(pne.amount* NVL(re.adjustment_factor,1)* NVL(r.adjustment_factor,1)),0) INTO l_fActivatedSalary
         FROM prognosis_note_entry pne, prognosis_entry pe, rule_entry re, rule_note_line_assoc r
        WHERE pne.note_line_id         = r.note_line_id
          AND pne.prognosis_entry_id   = pe.prognosis_entry_id
          AND r.rule_id                = re.rule_entry_id
          AND re.rule_entry_id         = i_rRuleId
          AND pe.prognosis_id          = i_iPrognosisId
          AND r.rule_note_line_included_in  = 5  -- Gjelder for investering
          AND substr(pe.period,5,2) IN ( SELECT period_basis 
                                           FROM rule_period_payment 
                                          WHERE period_payment = substr(i_iRollingPeriod,5,2)
                                            AND rule_entry_id  = i_rRuleId)
          AND substr(pe.period,0,4)    = ( SELECT substr(period,0,4) FROM liquidity_entry_head WHERE liquidity_entry_head_id = i_rLiquidityId );
       */

END LIQUIDITY_API;