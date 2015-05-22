
proc printto log = "/ty/ah/log/diag_0930_1.log" new ; run;

options mprint symbolgen mlogic sasautos = (Sasautos, "/g4cast/SAS/codes/HPF") ;

%run_diagnose (/ty/ah, diagnose_group_config.txt) ;


proc printto; run;
