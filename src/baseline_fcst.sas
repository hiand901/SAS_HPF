*********************************************************************************;
** Program:  Baseline_fcst modified from  read_baseline_forecast_files_new.    **;
** Purpose:  Reads the baseline fcst files  and creates a SAS data set for a   **;
**           and creates a SAS data set for a specified as of date             **;
**                                                                             **;
** Design Module:                                                              **;
** By:                                                                         **;
**          created by Vasan in Jan 2010                                       **;
** Modified:                                                                   **;
** By Andrew Hamilton Jan 2012, for RNP requirements.                          **;      
**                                                                             **;
*********************************************************************************;

%macro  baseline_fcst (
                 actuals_libref,
                 actuals_table_name,
                 common_base_dir,
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


    %put " ENTERING BASELINE_FCST run date &asofdt  ";


    * Define the input total demand file locations *;

    data _null_ ;


        length dt_under $10;


        date_file = input("&asofdt", mmddyy10.);
        call symput ("run_date", left(date_file));

        base_data_loc = index(lowcase(left("&common_base_dir")),'data');
        if base_data_loc = 0 then call symput('errflg','1');
        else do;
            base_dir = substr(left("&common_base_dir"),1,base_data_loc+4) ;
            call symput ('tzout1', trim(left(base_dir)) || 
                                    trim(left("tz1/out")));
            call symput ('tzout2', trim(left(base_dir)) ||
                                    trim(left("tz2/out")));
            call symput ('tzout3', trim(left(base_dir)) || 
                                    trim(left("tz3/out")));
            dt_under = substr(left("&asofdt"),7) ||'_'||
                       substr(left("&asofdt"),1,2) ||'_'|| 
                       substr(left("&asofdt"),4,2) ;
            call symput('totaldmd_fname',"&bline_fcst_file_prefix" || dt_under ||".txt" );
        end;
    run;

    %put " RUN_DATE &run_date";



    ** Read the TotalDemand_yyyy_mm_dd.txt files **;

    %do j = 1 %to 3 ;

        %put Looking for Total Demand file: &&tzout&j/&totaldmd_fname ;

        %let exist = %sysfunc(fileexist("&&tzout&j/&totaldmd_fname")) ;
        %if &exist = 1 %then %do ;

            %let tdmdexst&j = 1;

            data baseline_fcst&j (drop = junk) ;
                infile "&&tzout&j/&totaldmd_fname"; ;
                input prop_code $1-5 
                      @6 arrival_date yymmdd10. 
                      rmc_code $ 16-16
                      dl 17-19  
                      @21 base_fcst 8.2 
                      junk $ 31-49;  
            run;


            proc sort data=baseline_fcst&j;
                by prop_code;
            run;

        %end;
        %else %let tdmdexst&j = 0;


    %end;

    %if %eval(&tdmdexst1 + &tdmdexst2 + &tdmdexst3) > 0 %then %do;

        data baseline_forecast ;
            set 
                %if &tdmdexst1 = 1 %then baseline_fcst1 ;
                %if &tdmdexst2 = 1 %then baseline_fcst2 ;
                %if &tdmdexst3 = 1 %then baseline_fcst3 ;
            ;
            by prop_code;
        run;

  
        data hpfsys.Baseline_fcst_&run_date (rename = (room_cat = rmc_code ) );
            merge baseline_forecast (in=INA) 
                  prop_code_list (in=INB);   
            by prop_code;
            if INA and INB;
            format arrival_date yymmdd10. 
                   run_date     yymmdd10. ;
            run_date = input("&asofdt",mmddyy10.);      	 
        run;                      
     
    %end;      
    %else %do;

         %let errflg = -1;
         %let errmsg = No input demand files were found by Baseline_fcst;
    %end;

%macrend:

%mend ;




