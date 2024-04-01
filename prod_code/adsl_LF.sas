%macro import_xpt(dataset);
	%LET path = /home/u61624959/sasuser.v94/Clinical Data/&dataset..xpt;
	libname sdtm xport "&path";

	proc copy inlib=sdtm out=work;
	run;

%mend import_xpt;

***** Importing Data *****;
%import_xpt(dm);
%import_xpt(ds);
%import_xpt(sv);
%import_xpt(vs);
%import_xpt(ex);
%import_xpt(ds);
%import_xpt(qs);
%import_xpt(sc);
%import_xpt(adsl);
%import_xpt(mh);
***** Determining Site Groups****


** Step 1: Determine the number of patients in each treatment arm at each site;

proc freq data=dm noprint;
	TABLE siteid*ARM / out=site_counts NOPERCENT;
run;

** Step 2: Determine which sites have fewer than 3 patients in at least one treatment arm;

data pooled_sites;
	set site_counts;
	where count <3 and arm ne "Screen Failure";
	by SITEID;
run;

** Step 3: Create a list of just the sites which should be mapped to SITEGR1 = 900;

proc sort data=pooled_sites out=pooled_sites nodupkey;
	by SITEID;
run;

** Step 4: Merge SITEGR1 into the main dataset. This would be part of the main ADSL datastep in the full code;

data dm;
	merge dm(in=a) pooled_sites(in=b);
	by siteid;

	if b then
		SITEGR1='900';
	else
		SITEGR1=SITEID;
run;

**** Treatment Start, End, and Duration **;

DATA startDates;
	/*
	Purpose: Need to use SV domain to determine TRTSDT.
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
	KEEP usubjid trtsdt;
run;

DATA endDates1;
	set ex;
	by usubjid;

	if last.usubjid;
	TRTEDT=input(EXENDTC, yymmdd10.);
	FORMAT TRTEDT date9.;
	keep usubjid trtedt;
run;

DATA endDates;
	merge ds endDates1 dm;
	by usubjid;

	if arm ne "Screen Failure";

	if TRTEDT="." AND DSCAT="DISPOSITION EVENT" then
		TRTEDT=input(DSSTDTC, yymmdd10.);
	FORMAT TRTEDT date9.;

	if last.usubjid;
	keep usubjid TRTEDT;
run;

DATA dm;
	merge dm startDates endDates;
	by usubjid;
	TRTDURD=TRTEDT-TRTSDT+1;
run;

**** Dosages: cumdose, avgdd;

/* data ex2; */
/* 	merge ex dm; */
/* 	by usubjid; */
/*  */
/* 	if arm="Xanomeline High Dose" then */
/* 		do; */
/* 			intervalDuration=input(EXENDTC, yymmdd10.) - input(EXSTDTC, yymmdd10.); */
/* 			intervalCumDose=EXDOSE * intervalDuration; */
/*  */
/* 			if first.usubjid then */
/* 				cumdose=intervalCumDose; */
/* 			else */
/* 				cumdose+intervalCumDose; */
/* 		end; */
/*  */
/* 	if last.usubjid; */
/* 	keep usubjid cumdose; */
/* run; */

****Dosages: Jagadish Way;
data ds_qc;
set ds;
where dscat = 'DISPOSITION EVENT';
dsdt=input(dsdtc,yymmdd10.);
keep usubjid dsdt;
format dsdt date9.;
run;

data ex_qc;
merge ex(in=a) ds_qc;
by usubjid;
if a;
exstdt=input(exstdtc,yymmdd10.);
exendt=input(exendtc,yymmdd10.);
if exendt = . then exendt=dsdt;
format exstdt exendt date9.;
dur=exendt-exstdt+(exendt>=exstdt);
dose=exdose*dur;
run;

data ex2;
set ex_qc;
by usubjid;
if first.usubjid then cumdose=dose;
else cumdose+dose;
if last.usubjid;
keep usubjid cumdose;
run;

**** Define format for race;

proc format;
	invalue RACEN 'AMERICAN INDIAN OR ALASKA NATIVE'=1 'ASIAN'=2 
		'BLACK OR AFRICAN AMERICAN'=3 'NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER'=5 
		'WHITE'=6;
run;

**** Define format for DCreason;

proc format;
	invalue DSREASCD 'COMPLETED'=1 'ADVERSE EVENT'=2 'DEATH'=3 
		'LACK OF EFFICACY'=4 'LOST TO FOLLOW-UP'=5 'WITHDRAWAL BY SUBJECT'=6 
		'STUDY TERMINATED BY SPONSOR'=8 'PHYSICIAN DECISION'=9 
		'PROTOCOL VIOLATION'=10;
run;

proc format;
	value $DCDECODE
	'STUDY TERMINATED BY SPONSOR' = 'Sponsor Decision'
	'WITHDRAWAL BY SUBJECT' = 'Withdrew Consent'
	'LOST TO FOLLOW-UP' = 'Lost to Follow-up'
	'PROTOCOL VIOLATION' = 'Protocol Violation'
	'LACK OF EFFICACY' = 'Lack of Efficacy'
	'ADVERSE EVENT' = 'Adverse Event'
	'PHYSICIAN DECISION' = 'Physician Decision'
	'DEATH' = 'Death';
run;


**** Define format for AGEGR1 from AGEGR1N;
proc format;
	value AGEGR
		1 = '<65'
		2 = '65-80'
		3 = '>80';
		run;

proc format;
	value $armdecode
	'Xan_Lo' = 'Xanomeline Low Dose'
	'Xan_Hi' = 'Xanomeline High Dose'
	'Pbo' = 'Placebo';
	run;

**** Determine EFFL;

data qs_qc;
	set qs;
	by usubjid qstestcd;
	where qstestcd in ('CIBIC', 'ACTOT') and visitnum>3;

	if last.qstestcd;
run;

data qs_qc2;
	set qs_qc;
	by usubjid qstestcd;
	retain cnt;

	if first.usubjid then
		cnt=1;
	else
		cnt+1;

	if last.usubjid and cnt>1;
	EFFFL='Y';
run;

proc sort data=qs_qc(keep=qstestcd qstest qscat) nodupkey;
	by qstestcd qstest qscat;
run;

****COMP__FL;

data comp8Flag;
	merge dm sv;
	by usubjid;

	if VISITNUM=8;

	if input(RFENDTC, yymmdd10.) >=input(SVSTDC, yymmdd10.) then
		COMP8FL='Y';
	else
		COMP8FL='N';
run;

data comp16Flag;
	merge dm sv;
	by usubjid;

	if VISITNUM=10;

	if input(RFENDTC, yymmdd10.) >=input(SVSTDC, yymmdd10.) then
		COMP16FL='Y';
	else
		COMP16FL='N';
run;

data comp24Flag;
	merge dm sv;
	by usubjid;

	if VISITNUM=12;

	if input(RFENDTC, yymmdd10.) >=input(SVSTDC, yymmdd10.) then
		COMP24FL='Y';
	else
		COMP24FL='N';
run;

data dm;
	merge dm comp8Flag(keep=usubjid COMP8FL) comp16Flag(keep=usubjid COMP16FL) 
		comp24Flag(keep=usubjid COMP24FL);
	by usubjid;
run;

**** WeightBL and HeightBL;

proc sort data=vs;
	by usubjid;
run;

data weight;
	set vs;

	IF VISITNUM=3 And VSTESTCD='WEIGHT' THEN
		WEIGHTBL=Round(VSSTRESN,0.1);

	IF WEIGHTBL NE ".";
	keep usubjid WEIGHTBL;
run;

data height;
	set vs;

	IF VISITNUM=1 And VSTESTCD='HEIGHT' THEN
		HEIGHTBL=Round(VSSTRESN,0.1);

	IF HEIGHTBL NE ".";
	keep usubjid HEIGHTBL;
run;


**** Finding VISNUMEN;
**Note: May be able to refactor this.
	IMPORTANT: Jagadish's ADSL dataset differs from the explicit specs. Specs suggest that VISNUMEN is essentially just the visitnumber when the DSTERM is 'Protocol Complete'
	Jagadish's dataset seems to have visnumen correspond to the last visit number for the subject.
;
data visNumEn;
	set ds(keep=usubjid visitnum dscat dsterm dsdecod where=(DSDECOD ne 'SCREEN FAILURE'));
	if DSCAT='DISPOSITION EVENT';
	if DSTERM = "PROTOCOL COMPLETED" THEN visnumen =12;
	else visnumen=visitnum;
run;

**** Finding MMSETOT;
DATA MMSE;
	set qs(where=(QSCAT='MINI-MENTAL STATE') keep=QSCAT usubjid qsorres);
	by usubjid;
	if first.usubjid then MMSETOT = input(QSORRES,best.);
	else MMSETOT+input(QSORRES,best.); 
	if last.usubjid;
	drop QSCAT QSORRES;
run;

**** Main Data Step ****;

DATA adsl_lf;

	merge dm 
		qs_qc2 
		ds(keep=usubjid DSDECOD DSCAT where=(DSCAT="DISPOSITION EVENT")) 
		weight 
		height
		ex2
		sc(keep=usubjid sctestcd scstresn WHERE=(sctestcd='EDLEVEL')) 
		mh(keep=usubjid mhcat mhstdtc WHERE=(MHCAT='PRIMARY DIAGNOSIS'))
		sv(keep=usubjid svstdtc visitnum where=(visitnum=1))
		visNumEn
		MMSE
		;

	/* Most data comes from DM here. SV and DS imported to get info about discontinuation, etc */
	by usubjid;

	if arm="Screen Failure" then
		delete;
	arm = put(ARMCD,$armdecode.);
	EDUCLVL=scstresn;
	VISIT1DT = input(svstdtc, yymmdd10.);
	FORMAT VISIT1DT date9.;
	DISONSDT=input(MHSTDTC,yymmdd10.);
	FORMAT DISONSDT date9. DURDSGR1 $4.;
	DURDIS = intck('month',DISONSDT,VISIT1DT);
	IF DURDIS < 12 THEN DURDSGR1 = "<12";
	ELSE DURDSGR1 =">=12";
	**** NOTE: Specs claim there's no difference between actual and randomized treatments, but some subjects DO have a different ARM and ACTARM!;
	TRT01P=arm;
	TRT01A=arm;
	BMIBL=ROUND(WEIGHTBL / ((HEIGHTBL/100)**2),0.1);

	IF .<BMIBL<25 then
		BMIBLGR1="<25   ";
	ELSE IF 25<=BMIBL<30 then
		BMIBLGR1="25-<30";
	ELSE IF BMIBL>=30 then BMIBLGR1=">=30";

	IF arm="Placebo" then
		do;
			TRT01PN=0;
		END;
	ELSE IF arm="Xanomeline Low Dose" then
		do;
			TRT01PN=54;
		END;
	ELSE
		TRT01PN=81;
	TRT01AN=TRT01PN;
	AVGDD=ROUND(CUMDOSE/TRTDURD,0.1);
	RACEN=input(race, racen.);

	if age<65 then do;
		AGEGR1N=1;
		end;
	else if age <81 then
		AGEGR1N=2;
	else
		AGEGR1N=3;
	AGEGR1=PUT(AGEGR1N, AGEGR.);

	IF ARMCD ne '' then
		ITTFL='Y';
	ELSE
		ITTFL='N';

	IF ITTFL='Y' AND TRTSDT ne '.' then
		SAFFL='Y';
	ELSE
		SAFFL='N';
		
	IF EFFFL ne 'Y' then EFFFL = 'N';

	IF COMP8FL ne "Y" then
		COMP8FL="N";

	IF COMP16FL ne "Y" then
		COMP16FL="N";

	IF COMP24FL ne "Y" then
		COMP24FL="N";
	DCREASCD=input(DSDECOD, DSREASCD.);

	IF DCREASCD=2 THEN
		DSRAEFL='Y';

	FORMAT DCSREAS $18.;
	IF DSDECOD ne "COMPLETED" then
		do;
			EOSSTT="DISCONTINUED";
			DISCONFL="Y";
			DCSREAS=put(DSDECOD,$DCDECODE.);
		end;
		ELSE EOSSTT="COMPLETED";
	
	RFENDT = input(RFENDTC,yymmdd10.);
	FORMAT RFENDT date9.;
	
	DCDECOD = DSDECOD;
	
	*OTHER Formats;
	FORMAT BMIBL 8.1;
	
	keep STUDYID USUBJID SUBJID SITEID SITEGR1 ARM TRT01P TRT01PN TRT01A TRT01AN 
		TRTSDT TRTEDT TRTDURD AVGDD CUMDOSE AGE AGEGR1 AGEGR1N AGEU RACE RACEN SEX 
		ETHNIC SAFFL ITTFL EFFFL COMP8FL COMP16FL COMP24FL DISCONFL DSRAEFL DTHFL 
		BMIBL BMIBLGR1 HEIGHTBL WEIGHTBL EDUCLVL DISONSDT DURDIS DURDSGR1 VISIT1DT 
		RFSTDTC RFENDTC VISNUMEN RFENDT DCDECOD EOSSTT DCSREAS MMSETOT;
run;

data adsl_lf;
	retain STUDYID USUBJID SUBJID SITEID SITEGR1 ARM TRT01P TRT01PN TRT01A TRT01AN 
		TRTSDT TRTEDT TRTDURD AVGDD CUMDOSE AGE AGEGR1 AGEGR1N AGEU RACE RACEN SEX 
		ETHNIC SAFFL ITTFL EFFFL COMP8FL COMP16FL COMP24FL DISCONFL DSRAEFL DTHFL 
		BMIBL BMIBLGR1 HEIGHTBL WEIGHTBL EDUCLVL DISONSDT DURDIS DURDSGR1 VISIT1DT 
		RFSTDTC RFENDTC VISNUMEN RFENDT DCDECOD EOSSTT DCSREAS MMSETOT;
		set adsl_lf;
		run;

**** Comparison Step*;

proc sort data=adsl_lf;
	by usubjid;
	run;
proc sort data=adsl;
	by usubjid;
	run;

proc compare base =adsl compare=adsl_lf;
run;

****NOTES****
Questions: Proper procedure for rounding and length? Ex. BMIBL, HEIGHTBL, WEIGHTBL, etc.

Observed problems:
- Specs indicate that there is no difference between actual arm and randomized arm. 
	This isn't true in the data.
- Jagadish's recommended method for CUMDOSE and AVGDD will give results for actual dosages based on EX data. 
		Specs say these should be *as planned*. I'm going to follow the specs.
- 3 observations have DCSREAS="I/E Not Met" for no discernable reason. Look into this later, ignore for now.
- Specs say for BMIBL to be length 8 with 1 significant digit. Presumably that should be format 8.1, 
	but Jagadish's ADSL is just truncated to 1 decimal place then displayed with 4 significant digits. 
	I'm sticking with my version. Values differ slightly due to truncation vs. rounding
- There are 4 observations where ARM in Jagadish's ADSL differs regardless of logic. There are 16 observations in DM where ARM ne ACTARM.
	If we set ARM in the ADSL = DM.ACTARM, there are 4 values which don't match. If we set ARM in the ADSL = DM.ARM, then there are still 4 values which don't match.


VERIFICATION CHECKLIST:                                                                                                                                
Variable	| Explanation:
ARM			| Unexplained variations in comparison data.
TRT01P		| As above
TRT01PN		| As above
TRT01A		| As above
TRT01AN		| As above
AVGDD		| Rounding error
BMIBL		| Rounding Error
HEIGHTBL	| Rounding Error
WEIGHTBL	| Rounding Error
DURDIS		| Rounding Error -> Need to check how to get DURDIS to 1 decimal place. Tried several methods.
DURDSGR1	| Result of rounding error
VISNUMEN	| Anomalous result: One record does not have "PROTOCOL COMPLETED", yet the final visit was visit 13. 
				Jagadish's data has VISNUMEN set to 12 like those for protocol completed. This contradicts the specs.
DCSREAS		| 3 values of "I/E Not Met" for no known reason