create or replace PACKAGE             "LIQUIDITY_API" AS 
  g_ReturnCode NUMBER(11,0);
  
  PROCEDURE Generate                 ( i_strParam IN VARCHAR );
  
  PROCEDURE GenerateRowFromPreModule ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                       i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE);

  PROCEDURE GenerateRowFromAccounts  ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                       i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE);
  PROCEDURE GenerateRowFromGL5050 ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                          i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                          i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                          i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                          i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE);

  PROCEDURE GenerateRowFromBudget    ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                                 i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                                 i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                                 i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                                 i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                                 i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE,
                                                 i_rRulePerPaySrcCalcId   IN RULE_PERIOD_PAYMENT_SRC_CALC.RULE_PER_PAY_SRC_CALC_ID%TYPE);
  PROCEDURE GenerateRowFromPrognosis ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
  PROCEDURE GenerateRowFromPrognosis5050 ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                             i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                             i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                             i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                             i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                             i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
  PROCEDURE GenerateRowFromNoteLine  ( i_rLiquidityId          IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                       i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                       i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                       i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                       i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                       i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
  PROCEDURE GenerateRowFromInvestment  ( i_rLiquidityId        IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                        i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                        i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                        i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                        i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                        i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );

  PROCEDURE GenerateRowForDay ( i_rLiquidityEntryMonth IN LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE
                              
                           /* i_rLiquidityEntryMonth    IN LIQUIDITY_ENTRY_MTH_ITEM.LIQUIDITY_ENTRY_MTH_ITEM_ID%TYPE, 
                              i_rLiquidityId            IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                              i_rRuleId                 IN RULE_ENTRY.RULE_ENTRY_ID%TYPE,  
                              i_iLiquidityReportLineId  IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE, 
                              i_iRollingPeriod          IN PERIOD.ACC_PERIOD%TYPE */
                            );
                                       
  PROCEDURE GenerateForNettleieNaering ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                         i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                         i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );

  PROCEDURE GenerateForNettleiePrivat  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                         i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                         i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
 
  PROCEDURE GenerateForLonn            ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                         i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                         i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
                                         
  PROCEDURE GenerateForFeriePenger     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                         i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                         i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
                                        
  PROCEDURE GenerateForMVA             ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                         i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                         i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );                                       

  PROCEDURE GenerateForELAvgift        ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                         i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                         i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );                                       
  
 
  PROCEDURE GenerateForEnovaAvgift     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                        i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                        i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                        i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                        i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                        i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );

  PROCEDURE GenerateForArbGiverAvgift  ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                        i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                        i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                        i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                        i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                        i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );

  PROCEDURE GenerateForSkattetrekk     ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                        i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                        i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                        i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                        i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                        i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
 
  PROCEDURE GenerateForGrunnNaturOverskatt ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                            i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                            i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                            i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                            i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                            i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );

  PROCEDURE GenerateForIBBank              ( i_rLiquidityId           IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                             i_rRuleId                IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                             i_iPrognosisId           IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                             i_iLiquidityReportLineId IN REPORT_LEVEL_3.REPORT_LEVEL_3_ID%TYPE,
                                             i_iRollingPeriod         IN PERIOD.ACC_PERIOD%TYPE,
                                             i_dtCurrentRolling       IN CALENDAR.CALENDAR_DATE%TYPE );
                                             
  PROCEDURE GetRuleProperties               ( i_rRuleId IN RULE_ENTRY.RULE_ENTRY_ID%TYPE );                                           
                                       
  FUNCTION  IsHoliday                      ( i_iDate                   IN DATE) RETURN NUMBER;
  
  FUNCTION GetSalaryWorkTaxAmountMAX       ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                            ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                            ,l_iYearOffset      IN NUMBER
                                            ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                            ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER; 

  FUNCTION GetSalaryWorkTaxAmountIN        ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                            ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                            ,l_iYearOffset      IN NUMBER
                                            ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                            ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER; 
  FUNCTION GetSalaryTaxAmountMAX       ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                            ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                            ,l_iYearOffset      IN NUMBER
                                            ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                            ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER; 

  FUNCTION GetSalaryTaxAmountIN        ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE
                                            ,i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE
                                            ,l_iYearOffset      IN NUMBER
                                            ,i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE 
                                            ,l_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER; 


 
  FUNCTION  CalculateTaxFromAccounts   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                         i_iYearOffset      IN NUMBER,
                                         i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER;
                                        
  FUNCTION  CalculateTaxFromPrognosis  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                         i_iYearOffset      IN NUMBER,
                                         i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;

   FUNCTION  CalculateVATFromLiquidity  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                          i_iYearOffset      IN NUMBER,
                                          i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER;
                                          
   FUNCTION  CalculateVATFromAccounts   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                          i_iYearOffset      IN NUMBER,
                                          i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER;
 
  FUNCTION  CalculateVATFromAccountsSplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                            i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                            i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                            i_iYearOffset      IN NUMBER,
                                            i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE ) RETURN NUMBER;
                                       
  FUNCTION  CalculateVATFromPrognosis  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                         i_iYearOffset      IN NUMBER,
                                         i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;    

  FUNCTION  CalculateVATFromPrognosisSplit  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                              i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                              i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                              i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                              i_iYearOffset      IN NUMBER,
                                              i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;    

  FUNCTION  CalculateVATFromNoteLine   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                         i_iYearOffset      IN NUMBER,
                                         i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;    

  FUNCTION  CalculateVATFromNoteLineSplit   ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                              i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                              i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                              i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                              i_iYearOffset      IN NUMBER,
                                              i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;    

  FUNCTION  CalculateVATFromInvestment ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                         i_iYearOffset      IN NUMBER,
                                         i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;

  FUNCTION  CalculateVATFromInvestSplit ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                          i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                          i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                          i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                          i_iYearOffset      IN NUMBER,
                                          i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;
 
                                       
  FUNCTION  CalculateVATFromActSalary  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                         i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                         i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                         i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                         i_iYearOffset      IN NUMBER,
                                         i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;

  FUNCTION  CalculateVATFromActSalarySplit  ( i_rLiquidityId     IN LIQUIDITY_ENTRY_HEAD.LIQUIDITY_ENTRY_HEAD_ID%TYPE, 
                                              i_iPrognosisId     IN PROGNOSIS.PROGNOSIS_ID%TYPE, 
                                              i_rRuleId          IN RULE_ENTRY.RULE_ENTRY_ID%TYPE, 
                                              i_iRollingPeriod   IN PERIOD.ACC_PERIOD%TYPE,
                                              i_iYearOffset      IN NUMBER,
                                              i_strPaymentPeriod IN RULE_PERIOD_PAYMENT.PERIOD_PAYMENT%TYPE) RETURN NUMBER;

END LIQUIDITY_API;