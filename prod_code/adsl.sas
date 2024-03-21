/* Purpose: Construct the ADSL dataset according to the given specs  */
/* Author: Lucas Finney  */
/*
To Do:
- Group ages
- Much more...
*/
/*
Questions for Jagadish:
- Proper formatting. Is it acceptable to have a whole bunch of datasteps for each task?
*/
/* Define Macros and Functions */
/*
Macro 1
Name: import_xpt
Input: File name before .xpt suffix. Typically the domain code (dm, lb, etc...)
Purpose: Imports the desired XPT dataset as a SAS dataset
-> This was largely copied from stack exchange then made into a macro.
Need to check SAS docs and clean this up.
*/
%macro import_xpt(dataset);
	%LET path = /home/u61624959/sasuser.v94/Clinical Data/&dataset..xpt;
	libname sdtm xport "&path";

	proc copy inlib=sdtm out=work;
	run;

%mend import_xpt;

%import_xpt(dm);
%import_xpt(sv);
%import_xpt(ex);
%import_xpt(ds);

DATA startDates;
	/*
	Purpose: Need to use SV domain to determine TRTSDT.
	Notes: For the time being, I'll only keep the values I need for finding those variables above. May change later.
	*/
	set work.sv(keep=USUBJID VISITNUM SVSTDTC);
	WHERE VISITNUM=3;

	/* For efficiency: Only load up data from the visits we're interested in. */
	/*
	Specs -> TRTSDT SV.SVSTDTC when SV.VISITNUM=3, converted to SAS date. TRTSDT is date9 format.
	*/
	OPTION DATESTYLE=YMD;

	/* Dates were given like 2014-01-24, etc */
	TRTSDT=input(SVSTDTC, anydtdte10.);
	FORMAT TRTSDT date9.;
	DROP VISITNUM SVSTDTC;
run;

/* SECTION START: Finding end date! */
proc sort data=work.ex;
	by usubjid visitnum;
run;

DATA lastDose;
	/* Find last EX record	 */
	/* Spec-> Date of final dose (from the CRF) is EX.EXENDTC on the subject's last EX record  */
	set work.ex;
	by usubjid;

	if last.usubjid;

	if exseq=3 then
		do;
			TRTEDT=input(EXENDTC, anydtdte10.);
			allDoses="Y";
		end;
	keep usubjid TRTEDT allDoses;
run;

DATA endDates;
	/* Purpose: Need to use EX domain to find TRTEDT*/
	/* Specs: The date of final dose (from the CRF) is EX.EXENDTC on the subject's last EX record.
	If the date of final dose is missing for the subject and the subject discontinued after visit 3,
	use the date of discontinuation as the date of last dose. Convert the date to a SAS date.	 */
	/* Notes: Need to determine which subjects discontinued after visit 3 and which are missing final dose*/
	/* To determine when a subject discontinued -> Use RFPENDTC*/
	/* Question: Which dose is the final dose? 	 */
	merge work.dm lastdose(keep=usubjid TRTEDT allDoses);
	by usubjid;

	if allDoses ne "Y" then
		TRTEDT=input(RFPENDTC, anydtdte10.);
	FORMAT TRTEDT DATE9.;
run;

/* SECTION END */
DATA ADSL;
	/*
	Purpose:
	- Merge start dates back into the main dataset
	- Copy over the variables which are unchanged from SDTM.
	- Preliminary filtering (remove screen failures)
	- Assignment of basic derived variables (TRT01P, TRT01A, TRT01PN, TRT01AN)
	*/
	merge work.dm(keep=studyid usubjid subjid siteid ARM RFXSTDTC RFXENDTC dthfl 
		age ageu sex race ethnic RFSTDTC RFENDTC RFPENDTC RFXSTDTC RFXENDTC RFPENDTC) 
		startDates endDates;
	by USUBJID;

	/*
	Remove screen failures:
	According to specs, "structure is one record per subject, screen failures excluded"
	*/
	if arm="Screen Failure" then
		delete;

	/*
	Assign TRT01P(N) and TRT01A(N).
	Specs -> "no difference between actual and randomized treatment in this study"
	Numeric coded versions correspond to dosage amounts (see specs for more details)
	*/
	TRT01P=arm;
	TRT01A=TRT01P;

	IF arm="Placebo" then
		TRT01PN=0;
	ELSE IF arm="Xanomeline Low Dose" then
		TRT01PN=27;
	ELSE
		TRT01PN=54;

	/*
	Group sites.
	Specs -> SITEGR1 = SITEID. Pooled sites have SITEGR1=900
	Note:
	*/
	IF SITEID=702 OR SITEID=706 THEN
		SITEGR1=900;
	ELSE
		SITEGR1=SITEID;

	/*
	Calculate TRTDURD: TRTEDT-TRTSDT+1
	*/
	TRTDURD=TRTEDT-TRTSDT+1;
run;

/*
Determine Site Groups
---------------------
In the main data step, I've done this by essentially hard-coding the sites which should be pooled.
The following code was how I determined which sites had fewer than 3 patients and thus should get pooled.
*/
/* DATA sites; */
/* 	set work.dm(keep=siteid); */
/* run; */
/*  */
/* tabulate number of patients at each site */
/* proc freq data=sites; */
/* 	tables siteid / out=siteFreqs; */
/* run; */