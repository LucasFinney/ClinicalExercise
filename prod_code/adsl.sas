/* Purpose: Construct the ADSL dataset according to the given specs  */
/* Author: Lucas Finney  */
/*
To Do:
- Group ages
- Much more...

Current Task: Finding Cumulative and average doses <- Need to find treatment intervals for high dosage group first
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
%import_xpt(ds);
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

/* SECTION A START: Finding end date! */
proc sort data=work.ex;
	by usubjid visitnum;
run;

DATA lastDose;
	/* Find last EX record	 */
	/*Spec-> Date of final dose (from the CRF) is EX.EXENDTC on the subject's last EX record*/
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

/* SECTION A END */
/* SECTION B START: Find visit dates*/
DATA startVisit;
	/* Purpose: Use SV domain info to find dates of first visit. Need to convert to SAS date format */
	set sv(keep=USUBJID SVSTDTC VISITNUM);
	where VISITNUM=1;
	VISIT1DT=input(SVSTDTC, anydtdte10.);
	FORMAT VISIT1DT date9.;
	KEEP USUBJID VISIT1DT;
run;

DATA endVisit;
	/* Purpose: Use DS domain to find date of end visit
	Specs -> if DS.VISITNUM=13 where DSTERM='PROTCOL COMPLETED' then VISNUMEN=12,
	otherwise VISNUMEN=DS.VISITNUM where DSTERM='PROTCOL COMPLETED'
	*/
	set ds(keep=USUBJID VISITNUM DSTERM);
	where DSTERM="PROTOCOL COMPLETED";

	if VISITNUM=13 then
		VISNUMEN=12;
	else
		VISNUMEN=VISITNUM;
run;

/*SECTION B END*/
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
		startDates endDates startVisit endVisit keyVisits;
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
		TRT01PN=54;
	ELSE
		TRT01PN=81;

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

/*SECTION D START: Finding treatment periods (for high dose group)  */
DATA visit4dates;
	/* Purpose: Need to know date of visit 4 and visit 12 in order to determine dosages */
	set sv;
	where VISITNUM=4;
	visit4date=INPUT(SVSTDTC, anydtdte10.);
	FORMAT visit4date date9.;
	KEEP USUBJID visit4date;
run;

DATA visit12dates;
	/* Purpose: Need to know date of visit 4 and visit 12 in order to determine dosages */
	set sv;
	where VISITNUM=12;
	visit12date=INPUT(SVSTDTC, anydtdte10.);
	FORMAT visit12date date9.;
	KEEP USUBJID visit12date;
run;

DATA keyVisits;
	/* 	Purpose: Add a flag to each subject indicating which intervals they've completed -> Use to calculate interval durations */
	merge visit4dates visit12dates endDates startDates;
	by USUBJID;

	/* Determine number of days in first dosing interval */
	if visit4date ne "." then
		Int1Fl="Y";

	if visit12date ne "." then
		Int2Fl="Y";
run;

DATA intervaldurs;
	/* Purpose: Check flags and use to calculate treatment intervals */
	/* NOTE: THIS SHOULD GET REFACTORED! Can probably do this in the same step as the keyVisits */
	set keyVisits;

	if Int1Fl="Y" then
		Int1DurD=visit4date-TRTSDT+1;
	else
		Int1DurD=TRTEDT-TRTSDT+1;

	if Int2Fl="Y" then
		Int2DurD=visit12date-visit4date+1;
	else
		Int2DurD=TRTEDT-visit4date+1;

	If allDoses="Y" then
		Int3DurD=TrtEdt-visit12date+1;
run;

/* SECTION C END */
/*
Next Task: Find CUMDOSE. <- Need to find visit days first.
Specs -> VISIT1DT=SV.SVSTDTC when SV.VISITNUM=1, converted to SAS date
*/
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