options   mprint mlogic nosymbolgen sasautos = (Sasautos, "/fcst/SAS_HPF/src") ;

data _null_;
  call symput('HPF_TIME', put(datetime(), datetime23.));
run;

%put " ENTERING  HPF  &HPF_TIME  ";

* REMOVE THE ABOVE BEFORE moving TO PROD ;

%let prop_code = ALL;  /** added VASAN ***/

%run_diagnose (/fcst/SAS_HPF/lib, diagnose_transient_config.txt) ;

%put " EXITING  HPF  &HPF_TIME  ";
