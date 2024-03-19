/* Purpose: Construct the ADSL dataset according to the given specs  */
/* Author: Lucas Finney  */

DATA ADSL;
set work.dm(keep=studyid usubjid subjid siteid ARM RFXSTDTC RFXENDTC dthfl age ageu sex race ethnic RFSTDTC RFENDTC RFPENDTC Rename=(RFXSTDTC = TRTSDT RFXENDTC = TRTEDT RFPENDTC=RFENDT));
/* Note: Need to determine pooled site group. 
    From SAP -> Sites that enroll fewer than 3 patients in any one treatment group will 
	be grouped together, with a new pooled site identifier assigned for the purpose of analysis  */
/* Note: Need to determine age groups	 */
/* Note: Remember to correct the format of the date variables! Maybe have an intermediate data step? */
run;

/* Determine Site Groups */
DATA sites;
set work.dm(keep=siteid);
run;

/* tabulate number of patients at each site */
proc freq data=sites;
tables siteid  / out=siteFreqs;
run;

/* Sort sites by frequency */
proc sort data=siteFreqs;
by count;
run;

/* To Do: Figure out how to pool the results in a general way */