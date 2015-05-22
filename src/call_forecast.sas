
/* %let prop_code = %sysfunc(sysparm()) ; */

%let prop_code =ALL ;

proc printto log = "/ty/ah/log/fore_&prop_code._1001_1.log" new ; run;

%put prop_code = &prop_code ;

options mprint nosymbolgen nomlogic   sasautos = (Sasautos, "/tpr/trans_fcst/SASCode/HPF") ;

%run_forecast(/ty/ah, forecast_group_config.txt) ;

proc printto; run;
