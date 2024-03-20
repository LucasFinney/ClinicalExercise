/* Purpose: Construct the ADSL dataset according to the given specs  */
/* Author: Lucas Finney  */

%macro import_xpt(dataset);
%LET path = /home/u61624959/sasuser.v94/Clinical Data/&dataset..xpt;
libname sdtm xport "&path";
proc copy inlib=sdtm out=work; run;
%mend import_xpt;

%import_xpt(dm);


DATA ADSL;
set work.dm(keep=studyid usubjid subjid siteid ARM RFXSTDTC RFXENDTC dthfl age ageu sex race ethnic RFSTDTC RFENDTC RFPENDTC Rename=(RFXSTDTC = TRTSDT RFXENDTC = TRTEDT RFPENDTC=RFENDT));
/* Note: Need to determine pooled site group. 
    From SAP -> Sites that enroll fewer than 3 patients in any one treatment group will 
	be grouped together, with a new pooled site identifier assigned for the purpose of analysis  */
/* Note: Need to determine age groups	 */
/* Note: Remember to correct the format of the date variables! Maybe have an intermediate data step? */
if arm = "Screen Failure" then delete;
run;

/* Determine Site Groups */
DATA sites;
set work.dm(keep=siteid);
run;

/* tabulate number of patients at each site */
proc freq data=sites;
tables siteid  / out=siteFreqs;
run;


/* Pool the results in a general way */
proc sort data=siteFreqs;
by siteid;
run;

/* Note: Found that sites 702 and 706 should be pooled */

DATA ADSL;
	set ADSL;
	IF SITEID = 702 OR SITEID=706 THEN SITEGR1=900;
	ELSE SITEGR1=SITEID;
	RUN;
	
/* According to specs, trt01p = DM.ARM. TRT01PN is assigned as numerical dose level */
DATA ADSL;
	set ADSL;
	TRT01P = arm;
	TRT01A = TRT01P;
	IF arm = "Placebo" then TRT01PN = 0;
	ELSE IF arm = "Xanomeline Low Dose" then TRT01PN= 27;
	ELSE TRT01PN=54;
	TRT01AN = TRT01PN;
	TRTDUR = TRTEDT-TRTSDT;
	run;
	
/* Note to self: Make sure that the treatment dates are in the right format */