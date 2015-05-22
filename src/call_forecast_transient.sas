options mprint symbolgen   mrecall sasautos = (Sasautos, "/fcst/SAS_HPF/src") ;
%let prop_code= %sysfunc(sysparm()) ;

%put prop_code = &prop_code ;

%let sas_top_dir = %sysget(SAS_TOP_DIR);

%run_forecast (&sas_top_dir, /fcst/SAS_HPF/lib, forecast_transient_config.txt) ;

