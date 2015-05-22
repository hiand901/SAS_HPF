*********************************************************************************;
** Program:  Baseline_fcst modified from  read_baseline_forecast_files_new.    **;
** Purpose:  Reads the baseline fcst files  and creates a SAS data set for a   **;
**           and creates a SAS data set for a specified as of date             **;
**                                                                             **;
** Design Module:                                                              **;
** By:                                                                         **;
**          created by Vasan in Jan 2010                                       **;
*********************************************************************************;

%macro  Baseline_fcst (
                 actuals_libref,
                 actuals_table_name,
                 bline_fcst_path,
                 bline_fcst_file_prefix,
                 bline_file_name_date_format,
                 bline_error_libref,
                 bline_error_table_name,
                 by_variables,
                 asofdt,
                 actual_col,
                 actual_date_col,
                 prop_code_col,
                 num_blfcst_days,
                 actual_start_sasdt,
                 Baseline_Stored_Error_Yrs
		            );


    %let errflg = 0 ;


    filename dirref "&bline_fcst_path" ;
    %put " ENTERING BASELINE_FCST run date &asofdt  ";

    %let rc = %sysfunc(fileref(dirref)) ;
   %if rc = 0 %then %do ;
       %let errflg = -1 ;
       %let errmsg = Unable to open for input the directory that contains baseline forecast files ;
       %goto macrend ;
    %end;

    * change the as of date into yymmdd10. ;

    data _null_;
    	X = input("&asofdt",mmddyy10.);
    	mod_date = put(X,yymmdd10.);
    	put " modified date " mod_date;
         * substitute - with _ ;
		mod_date = substr(mod_date, 1,4) || '_' ||
                   substr(mod_date,6,2)||  '_'  ||
                   substr(mod_date,9,2);
        put " modified date " mod_date;
        call symput("mod_date_x",mod_date);
    run;
    %put "mod_date &mod_date_x"; 

    data _null_; 
	      date_file = input("&asofdt", mmddyy10.);
          call symput ("run_date", left(date_file));
   run;
        %put " RUN_DATE ********** &run_date";

          
%let exist = %sysfunc(fileexist("&bline_fcst_path/TotalDemand_&mod_date_x..txt")) ;
%if &exist = 1 %then %do ;

*filename fname pipe "gzip -dc &bline_fcst_path/&mod_date_x/out/totfcst.txt.gz  " ;
filename fname "&bline_fcst_path/TotalDemand_&mod_date_x..txt " ;

 
	data baseline_forecast (drop = junk) ;
             infile fname ;
             input prop_code $1-5 @6 arrival_date yymmdd10. rmc_code $ 16-16
                   dl 17-19  @21 base_fcst 8.2 junk $ 31-49;
                     
     run;
        

	  data hpfsys.Baseline_fcst_&run_date (drop= _type_ _freq_    
                                           rename = (room_cat = rmc_code ) );
      	merge baseline_forecast (in=INA) prop_code_list (in=INB);   
      	by prop_code;
     	if (INB);
      	format arrival_date  yymmdd10. run_date yymmdd10. ;
      	run_date = &run_date;
      	 
      run;
                          
     
%end;      
 %macrend:
 %mend ;




