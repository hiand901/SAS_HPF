libname tgt '/fcst/HPF/SAS/sasdata/transient';

data tgt.best_model_overwrite_data;

infile '/fcst/HPF/SAS/code/Transient_Forced_Model_Poduction.txt' dlm='09'x;

length id $ 64 byvar $32 byvarvalue $64 model_name $32;

input id $ byvar $ byvarvalue $ model_name$;

Run;



/*

data temp;

infile datalines;

length id $ 64 byvar $32 byvarvalue $64 model_name $32;

input id $ byvar $ byvarvalue $ model_name$;

datalines;

NYCMH1 prop_code NYCMH BASELINE

NYCMH1 tfh_rmc 1 BASELINE

NYCMH2 prop_code NYCMH BASELINE

NYCMH2 tfh_rmc 2 BASELINE

;

Run;



data temp2;

    set tgt.best_model_overwrite_data temp;

run;



proc sort data=temp2;

by id byvar byvarvalue;

run;



data tgt.best_model_overwrite_data;

    set temp2;

RUn;

*/
