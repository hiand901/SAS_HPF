%macro convert_ds;

    options mprint symbolgen mlogic ;

    %let dspathname = %sysfunc(sysparm());

    data _null_;
        length dspath dspath2 $200;
        dspathname = sysparm() ;
        dspath2 = dspathname;
        dspath='';
        do while(index(dspath2,'/') > 0);
            dspath = trim(left(dspath)) || substr(dspath2,1,index(dspath2,'/'));
            dspath2 = substr(dspath2,index(dspath2,'/')+1);
        end;
        call symput('ds_path',trim(left(dspath)));
        call symput('ds_name',trim(left(dspath2)));
    run;

    %if %length(&ds_path) = 0 or %length(&ds_name) = 0 %then %do;

        %put Error: Parameter ds_path &ds_path or ds_name &ds_name ;
        %put        were specified incorrectly. ;
        %goto macrend;

	%end;

    libname dspath "&ds_path";

    %let rc = %sysfunc(libref(dspath));
    %if &rc > 0 %then %do;

        %put Error: Unable to assign libref to &ds_path ;
        %goto macrend;

    %end;

    %let rc = %sysfunc(exist(dspath.&ds_name));
    %if &rc = 0 %then %do;

        %put Error: Unable to find the &ds_name data set in the location &ds_path ;
        %goto macrend;

    %end;
    
   
    data &ds_name;
        set dspath.&ds_name;
    run;

    data dspath.&ds_name;
        set &ds_name;
    run;


    %macrend:


%mend;
%convert_ds;
