data have1;
	set ADSL_LF;
	arm = 'Total';
run;

data EndOfStudy;
	set ADSL_LF have1;
run;

%macro Status_Count(condition=);
proc freq data=EndOfStudy(where=(&condition='Y')) noprint;
	table arm / out=&condition.counts;
run;

data &condition.counts_update;
	set &condition.counts;
	&condition=cat(count, ' ( ', round(percent, 1), '%)');

	/* 	keep ARM dispCount; */
run;

proc transpose data=&condition.counts_update out=&condition.counts_transpose;
	var &condition;
	id ARM;
run;
%mend Status_Count;

%Status_Count(condition=comp24fl);
%Status_Count(condition=disconfl);


data result;
	length _NAME_ $32.;
	set comp24flcounts_transpose disconflcounts_transpose;
	if _NAME_= "comp24fl" then rowLabel="Completed Week 24";
	if _NAME_= "disconfl" then rowLabel="Early Termination (prior to Week 24)";
	run;
	
proc freq data=EndOfStudy(where=(DCSReas ne '')) noprint;
	table DCSReas*Arm / out=Reasons;
	run;

data Reasons_update;
	set Reasons;
	ReasonCount=cat(count, ' ( ', round(percent, 1), '%)');
	/* 	keep ARM dispCount; */
run;

proc transpose data=Reasons_update out=Reasons_Transpose;
	var ReasonCount;
	by DCSReas;
	id ARM;
	run;

data Final;
	length rowLabel $24.;
	set Result(in=a) Reasons_Transpose(in=b);
	if a then groupL=1;
	if b then do;
		rowLabel=DCSReas;
		groupL = 2;
		end;
	run;

/* PROC REPORT DATA=Reasons_Transpose list; */

proc format;
	value group 1="Completion Status: " 2="Reason for Early Termination (prior to Week 24):";
	run;


options nodate pageno=1 linesize=64
        pagesize=60 fmtsearch=(proclib);

ODS LISTING file="/home/u61624959/sasuser.v94/Various/Princeps Training/test.lst"; 

title1 "Summary of End of Study Data";
 PROC REPORT DATA=WORK.Final LS=132 PS=60  SPLIT="/" CENTER ;
 COLUMN  groupL rowLabel Placebo 'Xanomeline Low Dose'n 'Xanomeline High Dose'n Total;
 Compute before groupL;
 	Line @3 groupL group.; 
 endcomp;
 Compute after groupL;
 	line '';
 	endcomp;
 DEFINE groupL / GROUP NOPRINT;
 DEFINE  rowLabel / DISPLAY FORMAT= $24. WIDTH=24    SPACING=2   LEFT "" ;
 DEFINE  Placebo / DISPLAY FORMAT= $200. WIDTH=100   SPACING=2   LEFT "Placebo" ;
 DEFINE  'Xanomeline Low Dose'n / DISPLAY FORMAT= $200. WIDTH=100   SPACING=2   LEFT "Xanomeline Low Dose" ;
 DEFINE  'Xanomeline High Dose'n / DISPLAY FORMAT= $200. WIDTH=100   SPACING=2   LEFT "Xanomeline High Dose" ;
 DEFINE  Total / DISPLAY FORMAT= $200. WIDTH=100   SPACING=2   LEFT "Total" ;
 RUN;
ODS Listing close;
