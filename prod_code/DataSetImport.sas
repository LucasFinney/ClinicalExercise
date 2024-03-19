/* Purpose: Use a macro to translate the XPT data files into SAS datasets. */
/* Author: Lucas Finney */

%macro import_xpt(dataset);
%LET path = /home/u61624959/sasuser.v94/Clinical Data/&dataset..xpt;
libname nhanes xport "&path";
proc copy inlib=nhanes out=work; run;
%mend import_xpt;

%import_xpt(dm);