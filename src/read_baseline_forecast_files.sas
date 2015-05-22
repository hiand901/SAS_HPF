******************************************************************************;
** Program: read_baseline_forecast_files.                                   **;
** Purpose: This program reads a number of test files that hold baseline    **;
**          forecast values, checks to see if the dates contained in each   **;
**          file are covered by actuals. If so, the file is read and the    **;
**          Calculate_Baseline_Error is called for the forecast values read.**;
**                                                                          **;
**                                                                          **;
** Design Module:       Section ? of the HPF Forecast System Design Doc     **;
** By:      Andrew Hamilton, Aug 4th 2008.                                  **;
**                                                                          **;
******************************************************************************;

%macro read_baseline_forecast_files (
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


    %let rc = %sysfunc(fileref(dirref)) ;

    %if rc = 0 %then %do ;
       %let errflg = -1 ;
       %let errmsg = Unable to open for input the directory that contains baseline forecast files ;
       %goto macrend ;
    %end;



    data filenames ;
        length date_length_text $2 ;
        dirid = dopen('dirref') ;
        num_fcst_files = 0 ;
        put dirid = ;
        if dirid > 0 then do;
           numfiles = dnum(dirid) ;
           do i = 1 to numfiles ;
              fname = dread(dirid,i) ;

              length_prefix = length(compress("&bline_fcst_file_prefix")) ;
              date_length_text = substr(left("&bline_file_name_date_format"), length(compress("&bline_file_name_date_format")) -1 ) ;

              r = rank(substr(date_length_text,1,1)) ;

              if r >= 48 and r <= 57 then
               format_length = input(date_length_text,3.) ;
              else format_length = input(substr(date_length_text,2,1),3.) ;

              if substr(left(fname),1,length_prefix) = compress("&bline_fcst_file_prefix")
              and index(fname,'.txt') > 0 then do ;
                  num_fcst_files + 1;
                  call symput('fname_' !! left(put(num_fcst_files, 4.)), fname) ;
                  date_of_file = substr(fname,length_prefix+1, format_length ) ;
                  put date_of_file = ;
                  call symput('fdate_' !! left(put(num_fcst_files, 4.)), date_of_file) ;
                  call symput('fsasdate_' !! left(put(num_fcst_files, 4.)),
                              put(input(date_of_file, &bline_file_name_date_format..),8.) ) ;
                  output ;
              end;
           end;

           call symput('num_blfiles',  left(put(num_fcst_files, 4.)) ) ;

        end;
    run;


    %do i = 1 %to &num_blfiles ;

        ** Compare the date value in the baseline forecast file with the dates contained **;
        ** in the input demand data.                                                     **;
        %if &&fsasdate_&i >= &actual_start_sasdt
        and %eval(&&fsasdate_&i + &num_blfcst_days) <= &asofdt %then %do;

            filename fname "&bline_fcst_path/&&fname_&i" ;

            data baseline_forecast_&&fdate_&i ;
                length room_cat $64 ;
                infile fname pad ;
                input prop_code $1-5 @6 arrival_date yymmdd10. room_cat $16-17 @21 fcst_base 9.2 ;
                room_cat = left(room_cat) ;
            run;

            filename fname ;


            %compute_baseline_error (
                               &Actuals_libref,
                               &Actuals_table_name,
                               work,
                               baseline_forecast_&&fdate_&i,
                               hpfsys,
                               &bline_error_table_name,
                               &by_variables,
                               &&fsasdate_&i,
                               &actual_col,
                               &actual_date_col,
                               &prop_code_col,
                               fcst_base,
                               arrival_date,
                               prop_code,
                               &by_variables
            )

            %if &errflg = 0 %then %do;

                ** Delete the file if it has been successfully processed **;
                %let rc = %sysfunc(system(rm &bline_fcst_path/&&fname_&i)) ;

            %end;
            %else %if &errflg = -1 %then %goto macrend ;

        %end;
    %end;


    ***********************************************************************************;
    ** Remove historical baseline errors from more than a configured number of years **;
    ** before the current date, using the config properties file option              **;
    ** 'baseline_stored_error_yrs'.                                                  **;
    ***********************************************************************************;

    data _null_;
        cut_off_date =  ( intnx('year', today(), -1* &baseline_stored_error_yrs) +
                           (today() - intnx('year',today(),0)) );
        call symput ('cut_off_date', put(cut_off_date,8.) ) ;
    run;


    data hpfsys.&bline_error_table_name ;
        set hpfsys.&bline_error_table_name ;
        where as_of_date > &cut_off_date ;
    run;



 %macrend:


 %mend ;
