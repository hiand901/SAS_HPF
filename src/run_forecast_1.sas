******************************************************************************;
** Program: Run_Forecast.sas                                                **;
** Purpose: This is a control program that calls the components of the      **;
**          HPF Forecast System that forecasts demand values each property  **;
**          and By Variables combination in the data - with the further     **;
**          condition that in batch mode, property codes for which forecast **;
**          values are calculated are taken from a property list table.     **;
**          This program can also be called in 'on-demand' mode, in which   **;
**          case it will be called to provide forecast demand values for    **;
**          a specific property code.                                       **;
** Design Module: Section 3.2 of the HPF Forecast System Design Document    **;
** By:          Andrew Hamilton, July 1st 2008.                             **;
**                                                                          **;
******************************************************************************;

/**The following statement was changed to include run_mode, run_date 12-15-2009 VASAN*/

%macro run_forecast (top_dir, config_file_path, config_file_name, run_mode=F, 
   run_date='01JAN2009'D, diagnose_date = '01JAN2009'D,
   overide_out_table=test);


%let errflg =  0 ;
%let errmsg = ;
%let useLatestEventDef=1;

**************************************************;
** Initialize the configuration macro variables **;
**************************************************;

%local
        Group_or_Transient
        Draft_or_Published
        Events_Y_N
        Base_Directory
        Mode
        By_Variables
        Pre_Summarized_Demand
        prop_code_demand_ds
        Historical_Demand_Table_Type
        Historical_Demand_Table_Path
        Historical_Demand_Table_Name
        Events_DB_Name
        Event_Info_Table_Name
        Validation_Table_Name
        Demand_Replace_Year_Intervals
        Demand_Replace_Week_Intervals
        Demand_Replace_Years
        Demand_Replace_End_Date
        Demand_Replace_Max_Data_Points
        HPF_Spec_Catalog_Name
        HistoryWindow
        Baseline_Weights_Table_Name
        As_of_date
        Years_of_data_to_process
        Horizon
        prop_code_status_table_name
        individual_pc_forecast_tname
        output_forecast_base_dir
        output_forecast_file_name
        Min_warn_errflg
        secondary_work_dir
        prop_code_input_list_path
        prop_code_input_list_name
        prop_code_fail_list_path
        prop_code_fail_list_name
        rates_or_rooms
        marsha_file_location
        marsha_file_name
		marsha_date
        marsha_date_format
;
%let marsha_date=;/*initialize*/
%let test_date = today();
%let forecast_test_mode=0; /*initialize*/
/** The following if statement was modified 12-15-09 VASAN  **/

%if &run_mode  = D  %then
   /**** %put "running in Diagnose mode run date &run_date " ;   **/
    
%else %do;
  %put ' running in forecast  mode ';
  proc  datasets lib=work kill nolist ; quit;
%end;
 
************************************;
** 1. Read the Configuration File **;
************************************;

** Assign a filename to the config file **;
filename confile "&config_file_path/&config_file_name" ;

%let rc = %sysfunc(fexist(confile)) ;
%if rc = 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to find the config file &config_file_path\config_file_name ;
        %goto macrend ;
%end;


** Read the config file settings **;

    data config ;

        length tmz_dir $4 subvalue $40 ;
        retain tmz_dir ; 
        if _n_ = 1 then do ;
            top_dir = compress("&top_dir");
            tz_pos = index(top_dir,'tz');
            if tz_pos > 0 then tmz_dir = substr(top_dir, tz_pos, 3); 
        end;

        infile confile pad;
        length keyval $30 char $1;
        input key $1-30 value $31-70 ;
        keyval = '';
        ** Deal with bug that objects to phantom characters in the key value **;
        do j = 1 to length(compress(key)) ;
            char = substr(compress(key),j,1) ;
            x = rank(char) ;
            if not( x > 122 or x < 48 or (x > 57 and x < 65) or (x > 90 and x < 95) ) 
            then keyval = compress(keyval) || char ;
        end;

        if (index(value, 'TOP_DIR') + index(value,'TMZ_DIR')) > 0 then do;
            topdir_pos = index(compress(value), 'TOP_DIR') ;
            tmzdir_pos = index(compress(value), 'TMZ_DIR') ;
            if tmzdir_pos > topdir_pos then subvalue = compress(tmz_dir);
            else subvalue = compress("&top_dir") ;
            sub_pos = max(topdir_pos, tmzdir_pos);
            if sub_pos > 1 then 
            value = compress( substr(compress(value),1,(sub_pos -1)) || compress(subvalue) !! 
                              substr(compress(value), sub_pos +7 ));
            else
            value = compress( subvalue !! substr(compress(value), sub_pos +7 ));
        end;

        call symput (compress(keyval), trim(left(value))) ;
run;


**********************************************;
** Look for duplicate configuration options **;
**********************************************;

proc sort data = config ;
   by keyval ;
run;

%let num_dup_keys = 0;

data _null_ ;
    set config end = eof;
        by keyval ;
        dup_count = 0 ;
        if not first.keyval then do ;
           dup_count + 1;
           call symput (compress('dup_keyval_' !! put(dup_count,3.)) , keyval );
    end;
    if eof then call symput('num_dup_keys', put(dup_count, 3.)) ;
 run;

 %if &num_dup_keys > 0 %then %do ;
    %do j = 1 %to &num_dup_keys ;
        put 'Warning: Duplicate Config Key Value ' "&dup_keyval_&j" ' found.';
        put 'The last value defined will be used.' ;
    %end;
 %end;



*******************************************************************************;
** Read the single-record Marsha Date file if necessary, to obtain the       **;
** relevant Marsha Date.                                                     **;
*******************************************************************************;

%if %index(%upcase(&as_of_date), MARSHA) > 0 %then %do ;

    filename marshfil "&marsha_file_location/&marsha_file_name";

    %if ( %sysfunc(fileref(marshfil)) > 0 %or
	      %sysfunc(fileref(marshfil)) < 0  )
          %then %do;
        %let errflg = 1 ;
        %let errmsg = Unable to assign a fileref to the file that holds Marsha Date ;
        %let errmsg = &errmsg.  Using default of today -1 ;

        data _null_;
           call symput('marsha_date', put(today() -1, mmddyy8.)) ;

           run;
    %end;
    %else %do ;
        data _null_ ;
            length rec $80 date_str $15 date_length_text $3 ;
            infile marshfil pad;
            input @1 rec ;
            quote_loc = index(left(rec),"'") ;
            date_length_text = substr(left("&marsha_date_format"),
                                      length(compress("&marsha_date_format")) -1 ) ;
            r = rank(substr(date_length_text,1,1)) ;

            if r >= 48 and r <= 57 then
             format_length = input(date_length_text,3.) ;
            else format_length = input(substr(date_length_text,2,1),3.) ;

            date_str = substr(left(rec),quote_loc+1, format_length);
            if lowcase(compress("&marsha_date_format")) ne "mmddyy10" then
             date_str = put(input(date_str, &marsha_date_format.. ), mmddyy10.) ;
            call symput('marsha_date', date_str);
        run;
    %end;

%end;


*******************************************************************************;
** Create the timestamp for the 'as_of_date' column in historical best model **;
** and historical events data sets. The 'as of' date is also used in         **;
** selecting records from the demand and event data sets.                    **;
*******************************************************************************;

** Default number of years of demand data to process **;
%if &years_of_data_to_process = 0 %then %let years_of_data_to_process = 5 ;

data _null_;
    orig_as_of_date = "&as_of_date";
    if upcase(compress("&as_of_date")) not in("0","TODAY")
        and index(upcase("&as_of_date"), "MARSHA") = 0  then do;
        call symput('asofdate', put(input("&as_of_date", mmddyy10.),8.) ) ;
        asofdate = input("&as_of_date", mmddyy10.) ;
        end;
    else if index(upcase("&as_of_date"), "MARSHA") ne 0 then do;
        asofdate = input("&marsha_date", mmddyy10.) ;
        call symput ("as_of_date", "&marsha_date") ;
        call symput('asofdate', put(asofdate, 8.) ) ;
         
    end;
    else do;
        asofdate = today() ;
        call symput('asofdate', put(today(),8.) ) ;
        call symput('as_of_date', put(today(),mmddyy10.) ) ;
       
    end;
    dayoyear = asofdate - intnx('year', asofdate, 0) ;
    firstdt = intnx('year', asofdate, -&years_of_data_to_process) + dayoyear ;
    call symput ('first_demand_date', put(firstdt, 8.)) ;

    if index(upcase(orig_as_of_date), "MARSHA") ne 0 then
     call symput('rundt', put(asofdate, 8.) );
    else
     call symput('rundt', put(today(),8.) );
     call symput('rundtm', put(datetime(), datetime23.));
run;

/** The following statement was added 12-15-2009 VASAN  **/
/** aded by julia -- also need to change asofdate variable ***/
/** aded by julia -- also overode output table ***/
%if &run_mode = D %then %do; 
    data _null_;
    call symput  ("as_of_date", "&run_date" )  ;
    
    asofdate = input("&run_date", mmddyy10.) ;
    call symput('asofdate', put(asofdate, 8.) ) ;

	call symput('output_table',"&overide_out_table");

    run; 

%put IN FORECASTER AS of date: &as_of_date &asofdate &run_date;

%end;


** Check for date conversion error **;

%if &syserr ne 0 and &syserr < 4 %then %do ;
    %let errflg = -1 ;
    %let errmsg = Error occurred in program run_forecast.sas when trying to read as_of_date ;
    %let errmsg = &errmsg from the configuration file. The correct format is mmddyy10. ;
%end;
%else %if &syserr >3 %then %do ;
    %let errflg = 1 ;
    %let errmsg = Warnings occured attempting to read as_of_date value from config file. ;
%end;

** If error occurred with the as_of_date, use todays date **;
%if &errflg ne 0 %then %do;
   %let errflg = 1 ;
   %let errmsg = &errmsg Todays date will be used instead. ;
   data _null_ ;
        call symput('asofdate', put(today(),8.) ) ;
        call symput('as_of_date', put(today(),mmddyy10.) ) ;
        call symput('rundtm', put(datetime(), datetime23.));

        
run;
/** change format of the diagnose date variable to a date(same as as_of_date)
   the variable will be present only if forecast_test_mode = 1 
   code needs to run if either of forecast_test_mode or diagnose_date exists
***/
%end;
*********************************************************** ;
** Set other options that depend on config file settings ** ;
*********************************************************** ;

%if %length(&prop_code) < 1 %then %let prop_code = ALL ;

** Set macro variables that depend on the type of diagnosis being performed -   **;
** Group or Transient.                                                          **;

%if &group_or_transient = G %then %do;
    %if &rates_or_rooms = rooms %then %let demand_col = demand ;
    %else %let demand_col = rate ;
        %let demand_date_col = staydate ;
        %let prop_code_col = prop_code ;

        %let event_prop_code_col = ged_prop_code ;
        %let event_mode_col = ged_mode ;
        %let event_type_col = ged_type ;
        %let event_id_col = ged_event_id ;
        %let event_start_date_col = ged_start_dt ;
        %let event_end_date_col = ged_end_dt ;
%end;
%else %if %upcase(&group_or_transient) = T %then %do ;
    %if &rates_or_rooms = rooms %then
        %let demand_col = total_arvl ;
    %else %let demand_col = rate ;
        %let demand_date_col = tfh_arvl_stay_dt ;
        %let prop_code_col = tfh_prop_code ;

        %let event_prop_code_col = prop_code ;
        %let event_type_col =  ;
        %let event_mode_col = ;
        %let event_id_col = event_id ;
        %let event_start_date_col = startdate ;
        %let event_end_date_col = enddate ;
%end;
%else %do ;
        %let errflg = -1 ;
        %let errmsg = Group_or_Transient input configuration option undefined ;
        %goto macrend;
%end;

****************************************************************;
** Break out the by variables into individual macro variables **;
****************************************************************;

%if %length(&by_variables) > 0 %then %do;
        data _null_ ;
                cat_vars = "&by_variables" ;
                num_cat_vars = 0 ;
                i = 1 ;
                do while (compress(scan(cat_vars, i) ne ''));
                        cat_var = scan(cat_vars, i, ' ') ;
                        call symput("cat_var_" !! left(put(i, 3.)), compress(cat_var)) ;
                        i+1 ;
                        if i > 10 then leave ;
                end;
                call symput ("num_cat_vars", left(put(i-1, 3.))) ;
        run;
%end;
%else %let num_cat_vars = 0 ;



********************;
** Assign Librefs **;
********************;

libname hpfsys
%if %upcase(&Group_or_Transient) = G %then "&base_directory/group" %str(;);
%else "&base_directory/transient" %str(;) ;

** Check the hpfsys libref **;
%let rc = %sysfunc(libref(hpfsys)) ;
%if &rc > 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the ;
        %if &Group_or_Transient = G %then %let errmsg = &errmsg &base_directory\group directory %str(;) ;
        %else %let errmsg = &errmsg &base_directory\transient directory %str(;) ;
        %goto macrend ;
%end;

libname statlib "&status_table_location"  ;

** Check the statlib libref **;
%let rc = %sysfunc(libref(statlib)) ;
%if &rc > 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the status table location &status_table_location ;
        %goto macrend ;
%end;


** Assign the libref for events data ** ;
%if &events_y_n eq Y %then %do;

    %if &group_or_transient = G %then %assign_events_libref(&Events_DB_Name) %str(;) ;
    %else libname eventlib "&events_info_table_path" %str(;) ;


    ** Check the eventlib libref **;
    %let rc = %sysfunc(libref(eventlib)) ;
    %if &rc > 0 %then %do ;
            %let errflg = -1 ;
            %let errmsg = Unable to assign a libref to the directory or rdbms containing the event info table ;
            %goto macrend ;
    %end;
  %end;



** Assign the libname for Historical Demand table **;
%if &Historical_Demand_Table_Type = DB2 %then %do ;
        libname indemlib DB2 &Historical_Demand_Table_Path ;
%end;
%else %do;
    %if &prop_code_demand_ds = Y and &prop_code ne ALL %then
        libname indemlib "&Historical_Demand_Table_Path/&prop_code" %str(;) ;
    %else
        libname indemlib "&Historical_Demand_Table_Path" %str(;) ;
%end;


** Check the validity of the indemlib libref **;

%let rc = %sysfunc(libref(indemlib)) ;
%if &rc > 0 %then %do ;
        %let errflg = -1 ;
        %if &Historical_Demand_Table_Type = DB2 %then
        %let errmsg = Unable to assign a libref to the DB2 library &Historical_Demand_Table_Path ;
        %else %let errmsg = Unable to assign a libref to the library &Historical_Demand_Table_Path  ;
        %goto macrend ;
%end;



** Assign the libname for the Baseline Forecast table **;
libname baselib "&baseline_forecast_path" ;

** Check the validity of the baselib libref **;

%let rc = %sysfunc(libref(baselib)) ;
%if &rc > 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &baseline_forecast_path ;
        %goto macrend ;
%end;



** Assign a secondary libref to use in place of the work library, when the work library   **;
** is likely to become full. Assign it to a sub_directory to avoid most access conflicts. **;

%if %index(%lowcase(&secondary_work_dir), none) = 0 %then %do ;

   %let dirid = %sysfunc(fileexist(&secondary_work_dir/&prop_code));
    %if &dirid = 0 %then %do ;
        %let rc = %sysfunc(system(mkdir &secondary_work_dir/&prop_code)) ;
    %end;
    %let dirid = %sysfunc(dclose(&dirid)) ;

    ** Attempt to assign a libref to the relevant directory ** ;
    libname work2 "&secondary_work_dir/&prop_code" ;

    %let rc = %sysfunc(libref(work2)) ;
    %if &rc > 0 %then %do ;
        %let errflg = 2 ;
        %let errmsg = Unable to assign a libref to the secondary work library &secondary_work_dir ;
        %let work2_libref = work ;
    %end;
    %else %let work2_libref = work2 ;
%end ;
%else %let work2_libref = work ;


** Assign filename to the output prop_code fail list file **;

%if &prop_code_input_list_name ne %str() %then %do;

    filename propsinf "&prop_code_input_list_path/&prop_code_input_list_name";


    %if %sysfunc(fileref(propsinf)) > 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a fileref to the file that holds input prop_codes ;
        %goto macrend ;
    %end;
%end;


** Assign filename to the output prop_code fail list file **;

filename failfile "&prop_code_fail_list_path/&prop_code_fail_list_name";

%if %sysfunc(fileref(failfile)) > 0 %then %do;
    %let errflg = 1 ;
    %let errmsg = Unable to assign a fileref to the file that will hold failed prop_codes ;
    %goto macrend ;
%end;



** Check for the existence of the input demand table **;
%let rc = %sysfunc(exist(indemlib.&historical_demand_table_name)) ;
%if &rc = 0 %then %do;
    %let errflg = -1 ;
        %let errmsg = Demand table indemlib.&historical_demand_table_name cannot be found ;
        %goto macrend ;
%end;


** Check for the existence of the input events table **;
%if &events_y_n = Y %then %do;
    %let rc = %sysfunc(exist(eventlib.&event_info_table_name)) ;
    %if &rc = 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Event definition table eventlib.&event_info_table_name cannot be found ;
        %goto macrend ;
    %end;
%end;



** Look for numeric by variables in the input demand data and get statements necessary **;
** to convert them to character variables.                                             **;

%find_numeric_by_vars (indemlib.&historical_demand_table_name, &by_variables) ;



** Subset the large demand data set for the prop_code / prop_codes that the **;
** forecast will be performed for.                                          **;

proc sort data = indemlib.&historical_demand_table_name
           out =
    %if &pre_summarized_demand = Y %then demand_data_summarized  ;
    %else                                &work2_libref..demand_data_filtered  ;
    %if &prop_code_col ne prop_code %then (rename = (&prop_code_col = prop_code)) ;
    ;

    by &prop_code_col &by_variables ;

    %if &prop_code ne ALL %then %do ;
        where compress(lowcase(&prop_code_col)) = compress(lowcase("&prop_code")) and
    %end ;
    %else where ;
              &demand_date_col between &first_demand_date and &asofdate ;
run;


%if %upcase(&prop_code) = ALL %then %do ;

    ** Obtain the input prop_code list ** ;
    %if &run_mode ne D and &prop_code_input_list_name ne %str() %then %do;

        data prop_code_list ;
            infile propsinf ;
            input prop_code $1-5  ;
         run;
    %end;
    %else %do;

         ** If no input prop_code list text file specified, get the list of prop_codes to **;
         ** process from the input demand data.                                           **;

         proc sql;
             create table prop_code_list
             as select distinct prop_code
             from 
                 %if &pre_summarized_demand = Y %then demand_data_summarized  ;
                 %else                                &work2_libref..demand_data_filtered  ;
             ;
         quit;

    %end;


    proc sort data = prop_code_list ;
        by prop_code ;
    run;


    ** Filter out prop_codes that are not found in the input prop_code processing list. **;
    ** Also convert numeric by variables to character values of the correct length.     **;

    data
        %if &pre_summarized_demand = Y %then demand_data_summarized ;
        %else &work2_libref..demand_data_filtered ;
        missing_prop_codes (keep = prop_code)
        prop_code_list (keep = prop_code) ;

        %if &num_cat_vars > 0 %then
         length &by_variables $64 %str(;) ;

        merge
        %if &pre_summarized_demand = Y %then demand_data_summarized ;
        %else                                &work2_libref..demand_data_filtered ;
             (in = dem
              %if &num_numeric_byvars > 0 %then rename = (&ren_str1) ;
              )
             prop_code_list (in=prop) ;

        by prop_code ;

        %if &num_numeric_byvars > 0 %then %do;
            &convert_stmnt
        %end;

        if first.prop_code and dem and prop then output prop_code_list ;

        if dem and prop then output

        %if &pre_summarized_demand = Y %then demand_data_summarized %str(;) ;
        %else &work2_libref..demand_data_filtered %str(;) ;

        if not dem then output missing_prop_codes ;

        %if &num_numeric_byvars > 0 %then drop &drop_stmnt %str(;) ;

    run;


    %dataobs (missing_prop_codes) ;

    %if &dataobs > 0 %then %do ;

        data missing_prop_codes ;
            length diagnose_or_forecast group_or_transient $1 pass_fail $4 Mode $20 status $80 ;

            set missing_prop_codes ;
            by prop_code ;

            diagnose_or_forecast = 'F' ;
            mode = compress("&mode") ;
            Group_or_Transient = compress("&group_or_transient") ;
            rundtm = input("&rundtm", datetime23.) ;

            pass_fail = 'Fail' ;
            status = 'Missing from input data' ;

            keep prop_code diagnose_or_forecast mode Group_or_Transient rundtm pass_fail status ;

        run;

        %property_code_status_update (work.missing_prop_codes, 
                                      statlib,
                                      &prop_code_status_table_name, 
                                      ALL) ;


        ** Remove the missing prop codes from the processing list, **;
        ** so they are not reported on twice.                      **;
        data prop_code_list ;
            merge prop_code_list
                  missing_prop_codes (keep = prop_code in = missing) ;
            by prop_code ;
            if missing then delete ;
        run;

    %end;


     /*** added by julia -- only when is not run in the diagnose mode ***/
    %if &group_or_transient = T and not ( &run_mode = D ) %then %do ;

        ** Remove all prop_codes, by_variable combos associated with BASELINE forced models **;
        %remove_baseln_fmodel_bygroups (

            %if &pre_summarized_demand = Y %then demand_data_summarized, ;
            %else &work2_libref..demand_data_filtered, ;

            hpfsys.&Baseline_Weights_Table_Name ,
            statlib,
            &prop_code_status_table_name,
            prop_code_list,
            &prop_code,
            &bline_forced_mod_indicator ,
            &by_variables,
            &mode,
            F,
            &group_or_transient,
            &rundtm,
            &asofdate
        ) ;

    %end;

%end;
%else %do;

    ** Convert numeric by variables of prop_code-specific data to character values **;
    ** of the correct length, if necessary.                                        **;
    %if &num_numeric_byvars > 0 %then %do ;

        data
            %if &pre_summarized_demand = Y %then
             demand_data_summarized ;
            %else
              &work2_libref..demand_data_filtered ;
            ;
            set
            %if &pre_summarized_demand = Y %then demand_data_summarized ;
            %else                                &work2_libref..demand_data_filtered ;
            (rename = (&ren_str1) );

            &convert_stmnt ;
            drop &drop_stmnt ;
        run;

    %end;
%end;


** Summarize the demand data to the necessary grouping level.     **;
** - If the demand / rate data set is not already pre-summarized. **;
%if &pre_summarized_demand = N %then %do;

    proc summary data = &work2_libref..demand_data_filtered nway noprint ;
        class prop_code &by_variables &demand_date_col;
        var &demand_col ;
        output out  = demand_data_summarized (drop=_freq_ _type_) sum = demand ;
    run;

    proc datasets lib = &work2_libref mt = data nolist;
       delete demand_data_filtered ;
    quit;
%end;



********************************************;
** Obtain the necessary Event data subset **;
********************************************;

%if &events_Y_N = Y %then %do ;

    %dataobs(hpfsys.historical_hpf_events) ;
    %let hist_obs = &dataobs ;
	%let rundtx   = &rundt;  /*** VASAN **/
    %put " asofdate  &asofdate   rundt  &rundtx "  ; 
    %if &useLatestEventDef=1 or (&asofdate = &rundt or &dataobs = 0)
                           %then %do;  
        ** Obtain the necessary Event data subset **;

        proc sort data = eventlib.&event_info_table_name
                   out = event_data_filtered2
            %if &event_prop_code_col ne prop_code %then
               (rename = (&event_prop_code_col = prop_code)) ;
            ;
            where
            %if %str(&event_type_col) ne %str() %then
                  compress(upcase(&event_type_col)) = compress(upcase("&group_or_transient"));
            %else 1 = 1 ;
            %if &prop_code ne ALL %then %do ;
                and compress(lowcase(&event_prop_code_col)) = compress(lowcase("&prop_code"))
            %end;
            %if &draft_or_published ne NA %then  %do ;
                and compress(lowcase(&event_mode_col)) = compress(lowcase("&draft_or_published"))
            %end;
            ;
            by &event_prop_code_col ;
        run;



        data event_data_filtered2 ;
            length eventid_col $15 _name_ $40 ;

            %if &prop_code = ALL %then %do ;
                merge event_data_filtered2 (in=events)
                prop_code_list (in = prop) ;
                by prop_code ;
                if events and prop ;
            %end;
            %else %do ;
                set event_data_filtered2 ;
            %end;

            * Add the _name_ variable which is necessary for HPF event data set *;
            * when used as an events data set with HPFEngine.                   *;
            * Remove apostrophies and dashes from any event ids,                *;
            * before adding the value to the _name_ variable                    *;
            eventid_col = substr(left(compress(&event_id_col, "'-/\.,")),1,15) ;

            _name_ = compress(prop_code !! eventid_col || put(&event_start_date_col, 8.)||'_'!!
                     put(&event_end_date_col, 8.), '. ' ) ;

            drop eventid_col ;
        run;


    %end;

    %else %do ;

        ** Run the build_hpf_event program to store the just found events in the      **;
        ** Historical_HPF_Events table.                                               **;
        ** Note that if the preceding code section was not run, build_hpf_events will **;
        ** return events data from the hpfsys.historical_hpf_events table that were   **;
        ** the latest stored before the as_of_date.                                   **;

        %build_hpf_event(
                work,
                null,
                hpfsys,
                historical_HPF_events,
                work,
                hpf_events_table,
                F,
                &group_or_transient,
                &event_id_col,
                &event_start_date_col,
                &event_end_date_col,
                &event_type_col,
                &event_mode_col,
                &asofdate,
                &rundt,
                &draft_or_published
        );

        %if &errflg < 0 %then %goto macrend ;

        %let dataobs = 0;
        %dataobs (work.hpf_events_table) ;
        %if &dataobs = 0 %then %do ;
           %let errflg = 1 ;
           %let errmsg = Error: Empty data table returned from build_hpf_event.sas program ;
        %end;


        proc sort data = hpf_events_table ;
           by prop_code _startdate_ ;
        run;



        data hpf_events_table ;
           %if &prop_code = ALL %then %do;
              merge hpf_events_table (in=events )
                    prop_code_list (in = prop) ;
              by prop_code ;
              if events and prop ;
           %end;
           %else %do;
              set hpf_events_table ;
              where upcase(compress(prop_code)) = upcase(compress("&prop_code")) ;
           %end;
        run;


      ** Rename the columns of the returned historical events table to be compatible with **;
      ** the rest of this program.                                                        **;

      data event_data_filtered2 ;
         set hpf_events_table (keep = prop_code _startdate_ _dur_after_
                                      &event_id_col &event_type_col );
         &event_start_date_col = _startdate_;
         &event_end_date_col = _startdate_ + _dur_after_ ;
         drop _startdate_ _dur_after_ ;
      run;

    %end;
%end;


%let evnt_obs = 0 ;
%dataobs(event_data_filtered2);
%let evnt_obs = &dataobs ;


** Check the input demand_replace_end_date, if it was provided **;
%if %length(&demand_replace_end_date) >= 1 %then %do;
        %let outreped = 0;
        data _null_ ;
                if compress("&demand_replace_end_date") not in ("0", "TODAY") then
                 orig_outreped =  input("&demand_replace_end_date", mmddyy10.) ;
                else do;
                    orig_outreped = &asofdate;
                    call symput ('demand_replace_end_date', put(orig_outreped, mmddyy10.)) ;
                end;
                call symput ('orig_outreped', put(orig_outreped, 10.)) ;
                outreped =  min(&asofdate, orig_outreped ) ;
                call symput ('outreped', put(outreped, 10.)) ;
        run;

        %if &outreped = 0 %then %do ;
                %let errflg = 4 ;
                %let errmsg = Warning: Input demand_replace_end_date &demand_replace_end_date is not of the correct mmddyy10. format. ;
                %let errmsg = &errmsg As_of date will be used instead. ;
                %let demand_replace_end_date = &as_of_date;
        %end;
        %else %if &outreped < &orig_outreped %then %do ;
                %let errflg = 4 ;
                %let errmsg = Warning: Input demand_replace_end_date &demand_replace_end_date is less than the suppllied as_of date ;
                %let errmsg = &errmsg &as_of_date. The as_of date will be used instead. ;
                %let demand_replace_end_date = &as_of_date ;
        %end;

%end;

%if %length(%cmpres(&demand_replace_years)) = 0 %then
 %let demand_replace_years = 100 ; ** The default **;


** Set up the event-demand replace start and end dates **;

data _null_;
        if compress("&demand_replace_end_date") = "" then do;
                dem_rep_end_date = &asofdate ;
                demand_replace_end_date = put(dem_rep_end_date, mmddyy10.) ;
        end;
        else dem_rep_end_date = min(&asofdate, input("&demand_replace_end_date", mmddyy10.));

        doy = dem_rep_end_date - intnx('year', dem_rep_end_date,0) ;
        demand_replace_start_date =
         intnx('year', dem_rep_end_date, - &demand_replace_years);
        call symput ("outrepsd", demand_replace_start_date) ;
        call symput ("demand_replace_start_date", put(demand_replace_start_date, mmddyy10.) ) ;
run;
/**%put "running in Diagnose mode run date &run_date before get best model " ;*/
 /*** vasan ***/

%if &run_mode = D %then %do;
/*** Find the best models to use **;*/
%get_best_model (
        &Group_or_Transient,
        &mode,
        work,
        prop_code_list,
        hpfsys,
        best_model_history_names,
        best_model_history_parm_ests,
        work,
        demand_data_summarized,
        statlib,
        &prop_code_status_table_name,
        &prop_code,
        prop_code,
        demand,
        &by_variables,
        &diagnose_date,
        work,
        best_models,
        work,
        inest_model_dataset,
        &rundtm,
		&run_mode,
		&diagnose_date
        );
		%end;
		%else %do;
%get_best_model (
        &Group_or_Transient,
        &mode,
        work,
        prop_code_list,
        hpfsys,
        best_model_history_names,
        best_model_history_parm_ests,
        work,
        demand_data_summarized,
        statlib,
        &prop_code_status_table_name,
        &prop_code,
        prop_code,
        demand,
        &by_variables,
        &As_of_Date,
        work,
        best_models,
        work,
        inest_model_dataset,
        &rundtm,
		&run_mode,
		&diagnose_date
        );

		%end;
/**Added run_mode and run_date to the parameter list VASAN 12-23-09  ;*/
        %if &errflg < 0 %then %goto macrend ;

/**  %put " run_mode &run_mode  run_date &run_date  "; */

         
        %dataobs(work.best_models);
        %if &dataobs = 0 %then %do ;
		        %put "FOUND ZERO Observations Run date" &run_date &as_of_date;
                %let errflg = -1 ;
                %let errmsg = Error: Empty model details data table returned from the get_best_model.sas program ;
                %goto macrend ;
        %end;
                     
        * %put " run_mode &run_mode  run_date &run_date line 902  "; 


** Call the Build HPF Spec Program to create best models from the best model **;
** details from the best model details returned from above.                  **;

%build_hpf_spec(work, best_models, work, HistoricalCandidateModels, F, demand) ;

** Check the return code **;
%if &errflg < 0 %then %goto macrend ;
%else %if &errflg > &min_warn_errflg %then %put &errmsg ;


%if %lowcase(&mode) = eventremoval and &events_y_n = Y %then %do;

    ****************************************************************************;
    ** Call the macro program to replace event-demand values with averages of **;
    ** non-event demand values on similar days.                               **;
    ****************************************************************************;


    %if &evnt_obs > 0 %then %do ;

        %pre_forecast_event_dmnd_replace (
        work,
        demand_data_summarized,
        work,
        event_data_filtered2,
        work,
        demand_data_pre_forecast,
        &demand_replace_year_intervals,
        &demand_replace_week_intervals,
        &outrepsd,
        &outreped,
        &by_variables,
        prop_code,
        &demand_date_col,
        demand,
        &group_or_transient,
        prop_code,
        &event_type_col,
        &event_id_col,
        &event_start_date_col,
        &event_end_date_col
        );

        %if &errflg < 0 %then %goto macrend ;

        %let dataobs = 0;
        %dataobs (demand_data_summarized) ;
        %if &dataobs = 0 %then %do ;
                %let errflg = -1 ;
                %let errmsg = Error: Empty data table returned from pre_forecast_event_demand_replace.sas program ;
                %goto macrend ;
        %end;
    %end;
%end;
%else %do;
	data demand_data_pre_forecast;
		set demand_data_summarized;
	run;
%end;
** Call the Forecast Program **;
%if %lowcase(&mode)  = eventremoval or &events_y_n = N %then %do ;

    %forecast_event_remove(
          &mode,
          &group_or_transient,
          work,
          demand_data_pre_forecast,
          work,
          HistoricalCandidateModels,
          work,
          inest_model_dataset,
          work,
          prop_code_list,
          work,
          Output_Forecast_Table2,
          statlib,
          &prop_code_status_table_name,
          &prop_code,
          prop_code,
          demand,
          &demand_date_col,
          &by_variables,
          &AsofDate,
          &holdout_period,
          &HistoryWindow,
          &Horizon,
          &rundtm
        );

%end ;
%else %do ;
        %forecast_hpfevent (
                &mode,
                &group_or_transient,
                work,
                demand_data_summarized,
                work,
                HistoricalCandidateModels,
                work,
                inest_model_dataset,
                work,
                event_data_filtered2,
                work,
                prop_code_list,
                work,
                Output_Forecast_Table2,
                statlib,
                &prop_code_status_table_name,
                &prop_code,
                prop_code,
                demand,
                &demand_date_col,
                &by_variables,
                &Asofdate,
                &holdout_period,
                &HistoryWindow,
                &Horizon,
                &rundtm,
                &evnt_obs
        );

%end;


%if &errflg < 0 %then %goto macrend ;

%dataobs( work.output_forecast_table2 ) ;
%if &dataobs = 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Error: No forecast records returned by the Generate Forecast program. ;
        %goto macrend ;
%end;


** Call the post_forecast_event_replace macro program to add back events using averages **;
** of historical event-demand values.                                                                                                   **;
%if %lowcase(&mode) = eventremoval and &events_y_n = Y %then %do ;

    data _null_ ;
        call symput('forecast_dem_start_date', put(today() - &HistoryWindow, mmddyy8.)) ;
        call symput('forecast_dem_end_date', put( today() + &Horizon, mmddyy8.)) ;
    run;

    %if &evnt_obs >0 %then %do ;
        %post_forecast_event_dmnd_replace (
        work,
        demand_data_summarized,
        work,
        Output_Forecast_Table2,
        work,
        event_data_filtered2,
        work,
        output_forecast_table2,
        &demand_replace_max_data_points,
        &By_Variables,
        &Group_or_Transient,
        prop_code,
        &demand_date_col,
        demand,
        prop_code,
        &event_type_col,
        &event_id_col,
        &event_start_date_col,
        &event_end_date_col,
        prop_code,
        &demand_date_col,
        demand
    );

        %if &errflg < 0 %then %goto macrend ;

        %dataobs( work.output_forecast_table2 ) ;
        %if &dataobs = 0 %then %do ;
                %let errflg = -1 ;
                %let errmsg = Error: No forecast records returned by the Post Forecast Event Demand Replace program. ;
                %let errmsg = &errmsg called by the run_forecast.sas program ;
                %goto macrend ;
        %end;
    %end;
%end;


** Validate the forecast demand values by comparing them against historical values, and **;
** applying rules to replace negative or abnormally high values.                        **;

%if &group_or_transient = G %then %let output_table_name = UnconstrainedGroupDemandForecast ;
%else %let output_table_name = UnconstrainedTransDemandForecast ;

%validate_forecast (
                &group_or_transient,
                indemlib,
                &historical_demand_table_name,
                work,
                output_forecast_table2,
                hpfsys,
                &validation_table_name,
                work,
                &output_table_name,
                prop_code,
                demand,
                &by_variables,
                &demand_date_col
);

/**** %put "   run forecast by variables &by_variables  " ; ***/
/** VASAN **/

%if &group_or_transient = G %then %do;
    ** Call a program to break-out records for individual prop_codes found in  **;
    ** the output data, and save the records to a data set for each prop_code, **;
    ** in a directory named for that prop_code.                                **;

    %write_prop_code_forecast_demand (
        work,
        &output_table_name,
        &output_forecast_base_dir,
        &individual_pc_forecast_tname,
        &prop_code,
        statlib,
        &prop_code_status_table_name,
        &rundtm
    );
%end;
%else %do ;

   ** Otherwise, if group_or_transient equals T, a program to combine weight values with **;
   ** forecast values and output the values to a single text file.                       **;

   %write_transient_forecast_file (
        work,
        &output_table_name,
        hpfsys,
        &baseline_weights_table_name,
        &output_forecast_base_dir,
        &output_forecast_file_name,
        &prop_code,
        prop_code_list,
        &asofdate,
        prop_code,
        &demand_date_col,
        demand,
        weight
   );

%end;


** Output a list of prop_codes that partially or completely failed diagnosis **;

%report_failed_prop_codes( statlib,
                           &prop_code_status_table_name,
                           &rundtm,
                           failfile,
                           F
                          ) ;


%macrend:

%if &errflg ne 0 %then %msg_module(&errflg, &errmsg) ;

 %if &errflg eq -1 %then %do;
     data _null_ ;
      *  abort return ;
     run;
 %end;

 /*** Added VASAN Dec 23, 2009 **/

%if &run_mode  = D  %then  %do;
    
  data _null_;
  sas_run_date= input("&run_date",mmddyy10.);
  call symput("fcst_date",sas_run_date);
  run;
    /****
   %put "RUN DATE run_date &run_date  fcst_date   &fcst_date  ";
     **/
  data hpfsys_test 
  (rename = (fcst_date = run_date tfh_arvl_stay_dt = arrival_date  demand = hpf_fcst
             tfh_rmc = rmc_code          ) );
   set work.output_forecast_table2;
   format fcst_date yymmdd10. ;
  fcst_date     = &fcst_date;
  run;

 %end;
/*********************************/
%mend;
