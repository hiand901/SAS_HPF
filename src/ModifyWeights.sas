libname tmp '/fcst/HPF/SAS/sasdata/transient';



data temp;

	set TMP.HISTORICAL_BASELINE_WEIGHTS;

	if(prop_code='ABQFI') then weight=0;

Run;



data TMP.HISTORICAL_BASELINE_WEIGHTS;

	set temp;

Run;
