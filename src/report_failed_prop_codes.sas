******************************************************************************;
** Program: report_failed_prop_codes.sas                                    **;
** Purpose: This program creates a text file that contains all prop_codes   **;
**          for which one or more by variable groupings were not            **;
**          represented in the output model selection data, for any reason. **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:          Andrew Hamilton, Aug 26th 2008.                             **;
**                                                                          **;
******************************************************************************;

%macro report_failed_prop_codes (
    status_list_libref,
    status_list_table,
    rundtm,
    fail_file_fileref,
    diagnose_or_forecast
);

    ** Obtain all prop_codes from the current run that had failing by groups **;
    ** or failed entirely.                                                   **;
    ** Note the clause in the where clause that does not count - for the     **;
    ** purposes of failing the prop_code - by-groups that failed due to a    **;
    ** lack of historical demand data.                                       **;

    data failed_prop_codes ;
        set &status_list_libref..&status_list_table ;
        where compress(lowcase(pass_fail)) = 'fail'
          and index(lowcase(compress(status)),'notenoughdemand') = 0
          and compress(diagnose_or_forecast) = compress("&diagnose_or_forecast")
          and rundtm = input("&rundtm", datetime23.) ;
    run;

    %dataobs (failed_prop_codes);

    %if &dataobs > 0 %then %do ;

        proc sort data = failed_prop_codes ;
            by prop_code ;
        run;

        data _null_ ;
            file &fail_file_fileref ;
            set failed_prop_codes ;
            by prop_code ;
            if first.prop_code then do ;
               put prop_code $1-5 ;
            end;
        run;
    %end;


     %if &syserr > 0 and &syserr ne 4 %then %do ;
          %let errflg = -1 ;
          %let errmsg = Error occurred when writing failed property codes in report_failed_prop_codes.sas;
     %end;
     %else %if &syserr => 4 %then %do ;
          %let errflg = 3;
          %let errmsg = Warning generated in report_failed_prop_codes.sas ;
     %end;



     proc datasets lib=work nolist mt=data ;
         delete failed_prop_codes ;
     quit;


%mend;
