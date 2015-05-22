******************************************************************************;
**  Program: Run_Diagnose.sas                                               **;
** Purpose: This is a control program that calls the components of the      **;
**          HPF Forecast System that finds the best model for each property **;
**          and By Variables combination in the data - with the further     **;
**          condition that property codes codes for which best models are   **;
**          evaluated are taken from a property list table.                 **;
** Design Module:       Section 3.1 of the HPF Forecast System Design Doc   **;
** By:      Andrew Hamilton, June 30th 2008.                                **;
** Revised by Vasan   Feb 2010                                              **;                                         
*** Modified this module so that we can make 3 runs:  One for date D  and   **;
** another for D - 90 and a third run for D - 364. D represents the as of   **;
** date for the Diagnose run. Forecast values are generated for D - 90      **;
** and D - 364 and compared against the actuals.                            **;  
******************************************************************************;

%macro run_diagnose (config_file_path,
                     config_file_name);

    *********************************************************************************************;
    ** add flag useLatestEventDef                                                              **;
    ** 1 means always use the latest event def  0 means use the event defined at asofdate      **;
    ** Added by yizhong wang                                                                   **;
    ** Reason - the original code tries to  get event def at asofdate if asofdate is not       **;
    ** rundate.  But the code is not working.Yizhong added this flag so the we always use      **;  
    ** the latest event def, fix the other branch later                                        **;
    *********************************************************************************************;

    %let useLatestEventDef=1;
    %let run_date = ;
    %let errflg = 0 ;
    %let errmsg = ;

/*
    proc datasets lib = work nolist mt= data kill;
    quit;
*/

    **************************************************;
    ** Initialize the configuration macro variables **;
    **************************************************;

    %local  Group_or_Transient
            Draft_or_Published
            Events_Y_N
            base_directory
            Historical_Demand_Table_Type
            Historical_Demand_Table_Path
            Historical_Demand_Table_Name
            Validation_Table_Name
            Mode
            HoldOut_Period
            Shift_HoldOut_Period
            HistoryWindow
            Horizon
            By_Variables
            Events_DB_Name
            Events_Info_Table_Path
            Events_Info_Table_Name
            Candidate_Models_Data_Set
            Demand_Replace_Year_Intervals
            Demand_Replace_Week_Intervals
            Demand_Replace_Years
            Demand_Replace_End_Date
            Demand_Replace_Max_Data_Points
            Prop_Code_Status_Table_Name
            Baseline_Errors_Table_Name
            Baseline_Weights_Table_Name
            Baseline_Forecast_Path
            Baseline_Forecast_File_Pref
            Baseline_Fname_Date_Format
            Baseline_Num_Days_Forecast
            Baseline_Num_Stored_Error_Yrs
            min_diagnosis_days
            min_warn_errflg
            secondary_work_dir
            prop_code_input_list_path
            prop_code_input_list_name
            prop_code_fail_list_path
            prop_code_fail_list_name
            as_of_date
            years_of_data_to_process
            rates_or_rooms
            bline_forced_mod_indicator
            Max_Combos_To_Run_At_Once
            mae_diff_hpf_switch
            marsha_file_location
            marsha_file_name
            marsha_date_format
       ;


    data _null_;
        call symput('HPF_start', put(datetime(), datetime23.));
    run;


    ************************************;
    ** 1. Read the Configuration File **;
    ************************************;
 
    ** Assign a filename to the config file **;
    filename confile "&config_file_path/&config_file_name" ;

    %let rc = %sysfunc(fexist(confile)) ;
    %if &rc = 0    %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to find the config file &config_file_path\config_file_name ;
        %goto macrend ;
    %end;


    ** Read  the config file settings **;

    data config ;
        length keyval $30 char $1 ;
        infile confile pad;
        input key $1-30 value $31-70 ;
        * Deal with bug that inserts phantom characters into the read key value *;
        do j = 1 to length(compress(key)) ;
            char = substr(compress(key),j,1) ;
            r = rank(char) ;
            if r >=46 and r<=122 and not (r>57 and r<65) and (r not in (47, 91, 92, 93, 94, 96)) then
            keyval = compress(keyval) !! char ;
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
           call symput (compress('dup_keyval_'!! put(dup_count,3.)) , keyval );
        end;
        if eof then call symput('num_dup_keys', put(dup_count, 3.)) ;
    run;

    %if &num_dup_keys > 0 %then %do ;
        %do j = 1 %to &num_dup_keys ;
            put 'Warning: Duplicate Config Key Value ' "&dup_keyval_&j" ' found.';
            put 'The last value defined will be used.' ;
        %end;
    %end;



    **********************************************************************************;
    ** Set macro variables that depend on the type of diagnosis being performed -   **;
    ** Group or Transient.                                                          **;
    **********************************************************************************;

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
    %else %do ;
        %if &rates_or_rooms = rooms %then
        %let demand_col = total_arvl ;
        %else %let demand_col = rate ;
        %let demand_date_col = tfh_arvl_stay_dt ;
        %let prop_code_col = tfh_prop_code ;

        %let event_prop_code_col = prop_code ;
        %let event_mode_col =  ;
        %let event_type_col =  ;
        %let event_id_col = event_id ;
        %let event_start_date_col = startdate ;
        %let event_end_date_col = enddate ;
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
                call symput("cat_var_" !! left(put(i, 3.)), cat_var) ;
                i+1 ;
                if i > 10 then leave ;
            end;
            call symput ("num_cat_vars", left(put(i-1, 3.))) ;
        run;
    %end;
    %else %let num_cat_vars = 0 ;


    ** Set the default max_combos_to_run_at_once value if it is missing from the **;
    ** config file.                                                              **;

    %if %str(&max_combos_to_run_at_once) = %str() %then
    %let max_combos_to_run_at_once = 1000000;



    *******************************************************************************;
    ** Create the timestamp for the 'as_of_date' column in historical best model **;
    ** and historical events data sets. The 'as of' date is also used in         **;
    ** selecting records from the demand and event data sets.                    **;
    *******************************************************************************;

    *******************************************************************************;
    ** Read the single-record Marsha Date file if necessary, to obtain the       **;
    ** relevant Marsha Date.                                                     **;
    *******************************************************************************;

    %if %index(%upcase(&as_of_date), MARSHA) > 0 %then %do ;

        filename marshfil "&marsha_file_location/&marsha_file_name";
    
        %if  ( %sysfunc(fileref(marshfil)) > 0 or
            %sysfunc(fileref(marshfil)) < 0 ) %then %do;
            %let errflg = 1 ;
            %let errmsg = Unable to assign a fileref to the file that holds Marsha Date ;
            %let errmsg = &errmsg.. Using default of today -1 ;

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


    ** Default number of years of demand data to process **;

    %if &years_of_data_to_process = 0 %then %let years_of_data_to_process = 99;

    data _null_;
    
        orig_as_of_date= "&as_of_date";
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


    ** Check for date conversion error **;

    %if &syserr ne 0 and &syserr > 4 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Error occurred in program run_forecast.sas when trying to read as_of_date;
        %let errmsg = &errmsg from the configuration file. The correct format is mmddyy10. ;
    %end;
    %else %if &syserr >3 %then %do ;
        %let errflg = 1 ;
        %let errmsg = Warnings occured attempting to read as_of_datevalue from config file. ;
    %end;


    ** If error occurred with the as_of_date, use todays date **;
    %if &errflg = -1 %then %do;
        %let errflg = 1 ;
        %let errmsg = &errmsg Todays date will be used instead. ;

        data _null_ ;
            call symput('asofdate', put(today(),8.) ) ;
            call symput('as_of_date', put(today(),mmddyy10.) ) ;
            call symput('rundtm', put(datetime(), datetime23.));
        run;
    %end;



    ********************;
    ** Assign Librefs **;
    ********************;

    libname hpfsys
    %if &Group_or_Transient = G %then "&base_directory/group" %str(;);
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


    ** Assign the libname for the Baseline Forecast table **;
    libname baselib "&baseline_forecast_path" ;

    ** Check the validity of the baselib libref **;

    %let rc = %sysfunc(libref(baselib)) ;
    %if &rc > 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &baseline_forecast_path ;
        %goto macrend ;
    %end;


    ** Assign the libname for a secondary work directory that can hold large files **;

    %if %index(&secondary_work_dir, %str(/) ) > 0 %then %do;

        libname work2 "&secondary_work_dir" ;

        ** Check the validity of the work2 libref **;

        %let rc = %sysfunc(libref(work2)) ;
        %if &rc > 0 %then %do ;
            %let errflg = -1 ;
            %let errmsg = Unable to assign a libref to the library &secondary_work_dir ;
            %let work2_libref = work;
        %end;
        %else %let work2_libref = work2 ;
    %end;
    %else %let work2_libref = work;


    ** Assign filename to the output prop_code fail list file **; 

    filename propsinf "&prop_code_input_list_path/&prop_code_input_list_name";

    %if %sysfunc(fileref(propsinf)) > 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a fileref to the file that holds input prop_codes ;
        %goto macrend ;
    %end;


    ** Assign filename to the output prop_code fail list file **;

    filename failfile "&prop_code_fail_list_path/&prop_code_fail_list_name";

    %if %sysfunc(fileref(failfile)) > 0 %then %do;
        %let errflg = 1 ;
        %let errmsg = Unable to assign a fileref to the file that will hold failed prop_codes ;
        %goto macrend ;
    %end;




    **********************************************************;
    ** Set up the event replace start and end dates         **;
    **********************************************************;

    ** Check the input demand_replace_end_date, if it was provided **;
    %if %length(&demand_replace_end_date) > 1 %then %do;

        %let outreped = 0;

        data _null_ ;
            outreped =  input("&demand_replace_end_date", mmddyy10.) ;
            call symput ('outreped', put(outreped, 8.));
        run;

        %if outreped = 0 %then %do ;
            %let errflg = 4 ;
            %let errmsg = Warning: Input demand_replace_end_date &demand_replace_end_date is not of the correct mmddyy10. format. ;
            %let errmsg = &errmsg.. Todays date will be used. ;
            %let demand_replace_end_date = ;
        %end;
    %end;
    %else %let outreped = 0  ;

    data _null_;
        call symput('marsha_date', put(today() -1, mmddyy8.)) ;
    run;



    ** Define values of demand_replace_start_date in all cases, and demand_replace_end_date **;
    ** in the case where it was not defined in the config file.                             **;

    data _null_;
        if &outreped = 0 then do;
            dem_rep_end_date = min(&asofdate, today()) ;
            demand_replace_end_date = put(today(), mmddyy10.) ;
    		call symput("outreped",put(dem_rep_end_date,10.0));
        end;
        else dem_rep_end_date = &outreped ;
        if &demand_replace_years = 0 then dmnd_replace_years = 100; * default *;
        else dmnd_replace_years = &demand_replace_years ;


        *put " marsha date &marsha_date " *;
        demand_replace_start_date = put(intnx('year', dem_rep_end_date, -1 * dmnd_replace_years ), mmddyy10.) ;
        call symput ("demand_replace_start_date", demand_replace_start_date) ;
        call symput ("outrepsd", input(demand_replace_start_date, mmddyy10.)) ;
        call symput ("marsha_date_sas", input (" &marsha_date " ,mmddyy10. ) ) ;
     
    run;



    ** Concatenate the time-zone-dependant demand data and events data **;

    %prepare_diagnose_inputs(&Historical_Demand_Table_Path,
                             &Historical_Demand_Table_Name,
                             &Events_Info_Table_Path,
                             &Events_Info_Table_Name,
                             &base_directory,
                             &prop_code_input_list_name,
                             &as_of_date,
                             work.concatenated_demand,
                             work.concatenated_events,
                             work.concatenated_prop_list) ;

    %if &errflg = -1 %then %goto macrend;



    ****************************************************************************;
    ** Obtain the filter of input demand data that corresponds to the list of **;
    ** property codes that should be processed.                               **;
    ****************************************************************************;

    proc sort data = work.concatenated_demand
        out = &work2_libref..demand_data
        %if %lowcase(&prop_code_col) ne prop_code %then (rename = (&prop_code_col = prop_code)) ;
        ;
        by &prop_code_col &by_variables ;

    run;


    ** Look for numeric by variables in the input demand data and get statements necessary **;
    ** to convert them to character variables.                                             **;

    %if &num_cat_vars > 0 %then %do ;
         %find_numeric_by_vars (&work2_libref..demand_data, &by_variables) ;
    %end;
    %else %let num_numeric_byvars = 0 ;


    ** Obtain the input prop_code list **;

    proc sort data = concatenated_prop_list out = prop_code_list nodupkey;
        by prop_code ;
    run;



    %if &group_or_transient = T %then %do ;

        ** Remove all prop_codes, by_variable combos associated with BASELINE forced models **;

        %remove_baseln_fmodel_bygroups (
             &work2_libref..demand_data,
             hpfsys.best_model_overwrite_data,
             hpfsys,
             &prop_code_status_table_name,
             prop_code_list,
             ALL,
             &bline_forced_mod_indicator ,
             &by_variables,
             &mode,
             D,
             &group_or_transient,
             &rundtm,
             &asofdate
        ) ;

    %end;



    ****************************************************************************;
    ** Match incoming demand data with the list of property codes to process. **;
    ** Also in this step convert any numeric by variables to character.       **;
    ****************************************************************************;

    data &work2_libref..demand_data_filtered
        missing_prop_codes (keep = prop_code) ;

        ** Set the length of all by_variables - which must be character - to 64         **;
        ** characters width, in order that they will correctly match with               **;
        ** 'byvarvalue' values read from Best_Model_Overwrite_Data or Best_Model_       **;
        ** History_Names, etc.                                                          **;

        %if &num_cat_vars > 0 %then
        length &by_variables $64 %str(;) ;

        merge &work2_libref..demand_data (in = dem
            %if &num_numeric_byvars > 0 %then rename = (&ren_str1) ;
        )
        prop_code_list (in=prop)
        ;

        by prop_code ;

        if not dem then output missing_prop_codes ;

        %if &num_numeric_byvars > 0 %then %do ;
            &convert_stmnt
        %end;

        if dem and prop then output &work2_libref..demand_data_filtered ;

        %if &num_numeric_byvars > 0 %then
        drop &drop_stmnt %str(;) ;

        %if &num_cat_vars > 0 and &num_cat_vars > &num_numeric_byvars %then %do ;
            * Ensure that by variables are alligned consistently            *;
            * to allow for the possibility that by vars are numeric in      *;
            * data to be merged with the demand data - like baseline data - *;
            * but are text variables in demand data.                        *;

            %do i = 1 %to &num_cat_vars;
                &&cat_var_&i = trim(left(&&cat_var_&i)) ;
            %end;
        %end;
    run;



    %dataobs (missing_prop_codes) ;

    %if &dataobs > 0 %then %do ;

        data missing_prop_codes ;
            length diagnose_or_forecast group_or_transient $1 Mode $20
                   pass_fail $4 status $80 ;

            set missing_prop_codes ;
            by prop_code ;

            diagnose_or_forecast = 'D' ;
            mode = compress("&mode") ;
            Group_or_Transient = compress("&group_or_transient") ;
            rundtm = input("&rundtm",datetime23.) ;
            pass_fail = 'Fail' ;
            status = 'Missing from demand data' ;

            keep prop_code diagnose_or_forecast mode Group_or_Transient rundtm pass_fail status ;
       run;

       %property_code_status_update (work.missing_prop_codes, hpfsys, &prop_code_status_table_name, ALL) ;


       ** Remove the missing prop_codes from the prop_code processing list data set **;

       proc sql ;
           create table prop_code_list as select * from prop_code_list
           where prop_code not in (select prop_code from missing_prop_codes)
           order by prop_code;
       quit;

   %end;



    ** Summarize the demand data to the necessary grouping level **;

    proc summary data = &work2_libref..demand_data_filtered nway noprint ;
        class prop_code &by_variables &demand_date_col;
        var &demand_col ;
        output out  = demand_data_summarized1 (drop=_freq_ _type_) sum = demand ;
    run;

    proc datasets nolist lib=&work2_libref ;
       delete demand_Data demand_data_filtered ;
    quit;

    ** demand data summarized  Eliminate properties that have gone through   ;
    ** room config changes    Feb-2010                                       ;    

   
    proc means noprint data = demand_data_summarized1;
        by prop_code tfh_rmc;
        var demand;
        output out = totals
        sum (demand) = prop_rmc_total ;
    run;


    data room_config_list;
        merge totals(in=inA) prop_code_list(in=inB) ;
        by prop_code;
        if tfh_rmc = 2;
        if cap2 = 0 and prop_rmc_total > 0;
	run;


    proc sort data = demand_data_summarized1;
        by prop_code;
    run;


    proc sort data = room_config_list;
        by prop_code; 
    run;


    data demand_data_summarized;
        merge demand_data_summarized1 (in =inA
              where = (&demand_date_col between &first_demand_date and &asofdate)) 
              room_config_list(in=inB);
        by prop_code;
        if (inA) and not (inB); 
	    
    run; 


    ******************************************************************************************; 
    ** Further check that there is enough data for every prop_code / by variable grouping   **;
    ** to allow diagnosis. Prop_code / by variable groupings that have less demand history  **;
    ** than required will be removed from the returned data, and a record will be added to  **;
    ** the prop code status table for any prop code / by variable group that did not have   **;
    ** enough demand history data.                                                          **;
    ******************************************************************************************;

    %validate_historical_demand (
        work,
        demand_data_summarized,
        hpfsys,
        &prop_code_status_table_name,
        prop_code_list,
        &prop_code_col,
        demand,
        &by_variables,
        &min_diagnosis_days,
        &mode,
        &group_or_transient,
        D,
        &rundtm
    );


    ** Check the return code **;
    %if &errflg < 0 %then %goto macrend ;
    %else %if &errflg > &min_warn_errflg %then %put &errmsg ;


    ** Check that at least some of the demand records survived validation **;
    %dataobs(demand_data_summarized) ;

    %if &dataobs = 0 %then %do ;
        %let errflg = 1 ;
        %let errmsg = No historical demand records passed validation ;
        %goto macrend ;
    %end;



    ********************************************;
    ** Obtain the necessary Event data subset **;
    ********************************************;

    %if &events_Y_N = Y %then %do ;

        %dataobs(hpfsys.historical_hpf_events) ;
        %let hist_obs = &dataobs ;

        %if &useLatestEventDef eq 1 or &asofdate = &rundt or &dataobs = 0 %then %do;

            proc sort data = work.concatenated_events
                       out = event_data
            %if %lowcase(&event_prop_code_col) ne prop_code %then
                   (rename = (&event_prop_code_col = prop_code)) ;
                ;
                where startdate ne . 
                  and enddate ne .
            %if &group_or_transient = G %then %do;
                  and compress(upcase(&event_type_col)) = compress(upcase("&group_or_transient"))
            %end ;
            %if &draft_or_published ne NA %then
                  and compress(upcase(&event_mode_col)) = compress(upcase("&draft_or_published")) ;
                ;
                by &event_prop_code_col ;
            run;

        %end;


        ** Run the build_hpf_event program to store the just found events in the      **;
        ** Historical_HPF_Events table.                                               **;
        ** Note that if the preceding code section was not run, build_hpf_events will **;
        ** return events data from the hpfsys.historical_hpf_events table that were   **;
        ** the latest stored before the as_of_date.                                   **;

        %build_hpf_event(
            work,
            event_data,
            hpfsys,
            historical_HPF_events,
            work,
            hpf_events_table,
            D,
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


        ** If there will be any use made of the returned HPF events table returned by      **;
        ** the call to build_hpf_events, subset it for prop_codes that are being diagnosed.**;

        %if %lowcase(&mode) = hpfevent %then %do ;

            data hpf_events_table ;
                merge hpf_events_table (in=events )
                      prop_code_list (in = prop) ;
                by prop_code ;
                if events and prop ;
            run;

        %end;



        %if &asofdate ne &rundt and &hist_obs ne 0 and useLatestEventDef eq 0 %then %do ;

            ** If the as_of_datevalue supplied to this program differs from the current days      **;
            ** date, the events on a particular as_of_datereturned from the Historical_HPF_Events **;
            ** table by the build_hpf_event program will need to be reformatted.                  **;

            ** Rename the columns of the returned historical events table to be compatible with **;
            ** the rest of this program.                                                        **;

            proc sort data = hpf_events_table (keep = prop_code _startdate_ _dur_after_
                                                      &event_id_col &event_type_col )
                       out = event_data ;
               by prop_code _startdate_ ;
            run;


            data event_data ;
                set event_data ;
               &event_start_date_col = _startdate_;
               &event_end_date_col = _startdate_ + _dur_after_ ;
               drop _startdate_ _dur_after_ ;
            run;

        %end;


        ** Subset the events table for just prop_codes that are being diagnosed. **;

        data event_data_filtered2 ;
            merge event_data (in=events )
                  prop_code_list (in = prop) ;
            by prop_code ;
            if events and prop ;
        run;
    %end;

    %if %cmpres(&demand_replace_years) = %str() %then    
     %let demand_replace_years = 10 ; ** The default **;



    *************************************;
    ** Call the Build HPF Spec Program **;
    *************************************;

    %build_hpf_spec(hpfsys, &Candidate_Models_Data_Set, hpfsys, CandidateModels, D, demand) ;

    ** Check the return code **;
    %if &errflg < 0 %then %goto macrend ;
    %else %if &errflg > &min_warn_errflg %then %put &errmsg ;

    %if &Events_Y_N = Y %then %do ;

        %if %lowcase(&mode) = eventremoval %then %do;

            ** Call the macro program to replace event-demand values with averages of **;
            ** non-event demand values on similar days.                               **;

            %pre_forecast_event_dmnd_replace (
            work,
            demand_data_summarized,
            work,
            event_data_filtered2,
            work,
            demand_data_summarized,
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


            %if &errflg < 0 %then %goto %macrend ;

            %let dataobs = 0;
            %dataobs (demand_data_summarized) ;
            %if &dataobs = 0 %then %do ;
                    %let errflg = -1 ;
                    %let errmsg = Error: Empty data table returned from pre_forecast_event_demand_replace.sas program ;
                    %goto macrend ;
            %end;

        %end;

    %end;



    ** Call the Diagnose and Store Best Model Program **;
    %if %lowcase(&mode) = eventremoval or &events_y_n = N %then %do ;

        %diagnose_event_remove (
                &mode,
                &group_or_transient,
                work,
                demand_data_summarized,
                hpfsys,
                CandidateModels,
                hpfsys,
                Best_Model_History_Names,
                Best_Model_History_Parm_Ests,
                hpfsys,
                Best_Model_Overwrite_Data,
                hpfsys,
                &candidate_models_data_set,
                work,
                prop_code_list,
                hpfsys,
                &prop_code_status_table_name,
                work,
                output_diagnose_table1,
                prop_code,
                demand,
                &demand_date_col,
                &by_variables,
                &holdout_period,
                &shift_holdout_period,
                &HistoryWindow,
                &Horizon,
                &asofdate,
                &rundtm,
                &max_combos_to_run_at_once
                

        );

    %end ;
    %else %do ;
        %diagnose_hpfevent (
                &mode,
                &group_or_transient,
                work,
                demand_data_summarized,
                hpfsys,
                CandidateModels,
                hpfsys,
                Best_Model_History_Names,
                Best_Model_History_Parm_Ests,
                hpfsys,
                Best_Model_Overwrite_Data,
                hpfsys,
                &candidate_models_data_set,
                work,
                prop_code_list,
                hpfsys,
                &prop_code_status_table_name,
                work,
                hpf_events_table,
                work,
                output_diagnose_table1,
                prop_code,
                demand,
                &demand_date_col,
                &by_variables,
                &event_id_col,
                &holdout_period,
                &shift_holdout_period,
                &HistoryWindow,
                &Horizon,
                &asofdate,
                &rundtm
        );

    %end;

    %if &errflg < 0 %then %goto macrend ;

    %dataobs( work.output_diagnose_table1 ) ;
    %if &dataobs = 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Error: No forecast records returned by the Diagnose Best Model program. ;
        %goto macrend ;
    %end;


    ** Call the post_forecast_event_replace macro program to add back events using averages **;
    ** of historical event-demand values.                                                   **;

    %if %lowcase(&mode) = eventremoval and &events_y_n = Y %then %do ;

        %post_forecast_event_dmnd_replace (
                work,
                demand_data_summarized,
                work,
                output_diagnose_table1,
                work,
                event_data_filtered2,
                work,
                output_diagnose_table1,
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
                predict    
        );

        %if &errflg < 0 %then %goto macrend ;

        %dataobs( work.output_diagnose_table1) ;
        %if &dataobs = 0 %then %do ;
                %let errflg = -1 ;
                %let errmsg = Error: No forecast records returned by the Post Forecast Event Demand Replace program. ;
                %goto macrend ;
        %end;

    %end;


    ** TEMPORARY  **;
    PROC SQL;

        DROP TABLE REJECTED_PROP_CODES;
        DROP TABLE EVENT_DATA_FILTERED;
        DROP TABLE CANDIDATE_MODELS;
        DROP TABLE DEMAND_EVENTS;
        DROP TABLE PARAMETER_ESTIMATES;
        DROP TABLE PARM_ESTS;

    QUIT;



    ******* ROUTINE ONLY FOR TRANSIENTS  *****;
    ****** Chooses which hotels to turn HPF for *****;

    %if &group_or_transient = T %then %do ;
  
   
        **  Call run_forecast in diagnose mode  12-15-2009  VASAN **;
        %put " Message from run_diagnose run mode &run_mode &prop_code";
   
        %let run_date_1 = &as_of_date; 
 
        ** changed on Jan 5, 2010  **;

        **this is the diagnose as of date in the diagnose config file  **;

        %let diag_as_of_date = &as_of_date;
 

        %put " Message from run_diagnose RUN_DATE  from run_diagnose  &run_date_1 " ; 

        data _null_;
            D_date = input ("&run_date_1",mmddyy10.);

            run_date_1_sas = D_date - 364;
            run_date_1     = put(run_date_1_sas,mmddyy10.);
            call symput("run_date_1", run_date_1); 

            run_date_2_sas = D_date - 90;
            run_date_2     = put(run_date_2_sas,mmddyy10.);
            call symput("run_date_2", run_date_2); 

            run_date_3_sas   = D_date;
            run_date_3       = put(run_date_3_sas,mmddyy10.); 
            call symput("run_date_3", run_date_3); 

        run;
        %put " Message from run_diagnose &run_date_1  &run_date_2  &run_date_3 " );



        *************************************************************************;
        * Run with as of date = D - 364 ;
        *************************************************************************;

        %run_forecast_from_diagnose(
            config_file_path = &config_file_path ,
            config_file_name = &config_file_name ,
            run_mode= &run_mode,
            diagnose_date=&diag_as_of_date,
            run_date= &run_date_1 ,
            overide_out_table= results1,
            demand_data_table = demand_data_summarized1,
            event_data_table = event_data_filtered2
         );


        data hpfsys.results1 (rename = (fcst_date = run_date 
                                 tfh_arvl_stay_dt = arrival_date  
                                           demand = hpf_fcst
                                          tfh_rmc = rmc_code ) );
            set results1 ;
            format fcst_date yymmdd10. ;
            fcst_date = input("&run_date_1",mmddyy10.);
        run;



        ***********************************************************************;
        *Run with D - 90;
        ***********************************************************************;

        %run_forecast_from_diagnose(
            config_file_path = &config_file_path ,
            config_file_name = &config_file_name ,
            run_mode= &run_mode   ,
            run_date= &run_date_2 , 
            diagnose_date= &diag_as_of_date,
            overide_out_table= results2,
            demand_data_table = demand_data_summarized1,
            event_data_table = event_data_filtered2
        );


        data hpfsys.results2 (rename = (fcst_date = run_date 
                                 tfh_arvl_stay_dt = arrival_date  
                                           demand = hpf_fcst
                                          tfh_rmc = rmc_code ) );
            set results2 ;
            format fcst_date yymmdd10. ;
            fcst_date = input("&run_date_2",mmddyy10.);
        run;


        **********************************************************************;
        *Run with D ;
        **********************************************************************;

        %run_forecast_from_diagnose(
            config_file_path = &config_file_path ,
            config_file_name = &config_file_name ,
            run_mode= &run_mode   ,
            run_date= &run_date_3 , 
            diagnose_date=&diag_as_of_date,
            overide_out_table= results3,
            demand_data_table = demand_data_summarized1,
            event_data_table = event_data_filtered2
        );


        data hpfsys.results3 (rename = (fcst_date = run_date 
                                 tfh_arvl_stay_dt = arrival_date  
                                           demand = hpf_fcst
                                          tfh_rmc = rmc_code ) );
            set results3 ;
            format fcst_date yymmdd10. ;
            fcst_date = input("&run_date_3",mmddyy10.);

        run;


        ** Combine the results into one table  **;

        proc sql;

            create  table hpfsys.HPF_FORECAST as
            select * from hpfsys.results1
            union
            select * from hpfsys.results2
            union
            select * from hpfsys.results3;


            drop table hpfsys.results1;
            drop table hpfsys.results2;
            drop table hpfsys.results3;

        quit;


        ** Compute baseline error values by comparing baseline forecast to actual values **;

        %if &run_mode = D %then %do;

            %do i = 1 %to 3;    

                data _null_;
                    run_date_x = "&&run_date_&i";
                    call symput("run_date", run_date_x);  
                 run;  
                 %put " run_date " &run_date;

	            %let bl_result&i = 1;

                %baseline_fcst(
                     work,
                     demand_data_summarized,
                     &base_directory,
                     &Baseline_Forecast_File_Pref,
                     &baseline_fname_date_format,
                     hpfsys,
                     &baseline_errors_table_name,
                     &by_variables,
                     &&run_date_&i,
                     demand,
                     &demand_date_col,
                     prop_code,
                     &Baseline_Num_Days_Forecast,
                     &first_demand_date,
                     &Baseline_Num_Stored_Error_Yrs
                     );

                 %if &errflg = -1 %then %let bl_result&i=0;
                 %let errflg = 0;

 	        %end; 

            ** combine them into one file;   **;

            %let bl_reslt_tot = %eval(&bl_result1 + &bl_result2 + &bl_result3) ;
            %if &bl_reslt_tot > 0 %then %do;

                data _null_;
                    sas_date_1 = input("&run_date_1",mmddyy10.);
                    call symput("sas1",left(sas_date_1) );
    
                    sas_date_2 = input("&run_date_2",mmddyy10.);
                    call symput("sas2",left(sas_date_2) );

                    sas_date_3 = input("&run_date_3",mmddyy10.);
                    call symput("sas3",left(sas_date_3) );

                run;
	

                proc sql;

                    create  table hpfsys.BASELINE_FORECAST as
                    %if &bl_result1 = 1 %then %do;
                        select * from hpfsys.baseline_fcst_&sas1 
                        %if &bl_reslt_tot > 1 %then
                        union ;
                    %end;
                    %if &bl_result2 = 1 %then %do;
                        select * from hpfsys.baseline_fcst_&sas2 
                        %if &bl_result3 = 1 %then union ;
                    %end;
                    %if &bl_result3 = 1 %then 
                    select * from hpfsys.baseline_fcst_&sas3; 
                    ;
                quit;
            %end;
            %else %do;
                 %let errflg = -1;
                 %let errmsg = Unable to find any &Baseline_Forecast_File_Pref files;
                 %goto macrend;
            %end;
        %end;
        %else %do;

            %read_baseline_forecast_files_new(
                 work,
                 demand_data_summarized,
                 &baseline_forecast_path,
                 &Baseline_Forecast_File_Pref,
                 &baseline_fname_date_format,
                 hpfsys,
                 &baseline_errors_table_name,
                 &by_variables,
                 &asofdate,
                 demand,
                 &demand_date_col,
                 prop_code,
                 &Baseline_Num_Days_Forecast,
                 &first_demand_date,
                 &Baseline_Num_Stored_Error_Yrs
                 );

        %end;


        ** run_mode and run_date parameters added to the above call. VASAN 12-19-2009  **;

        %if &errflg = -1 %then %goto macrend ;

        proc sql;
            drop table DAILY_ERROR;
            drop table HPF_AGG_ERROR;
            drop table FCST_CAP;
        run;


        ** combine HPF fcst with Baseline Fcst **; 

        proc sort data = hpfsys.hpf_forecast;
            by prop_code rmc_code  arrival_date run_date;
        run;


        proc sort data = hpfsys.baseline_forecast   ;
            by prop_code rmc_code  arrival_date run_date;
        run;


        data comb_fcst;
            merge hpfsys.hpf_forecast (in=inA) 
                  hpfsys.baseline_forecast (in= inB);
            by prop_code rmc_code  arrival_date run_date;
            if (inA) and (inB);
        run;
  

        proc sort data = non_forced_forecast ;
            by prop_code tfh_rmc tfh_arvl_stay_dt;
        run;
  

        data hpfsys.daily_master  ( drop = cap1 cap2 junk );
               
            merge comb_fcst (in= inA rename=(rmc_code = tfh_rmc) )     
            demand_data_summarized ( rename = ( tfh_arvl_stay_dt = arrival_date 
                                                          demand = actual ));
            by prop_code tfh_rmc arrival_date;
            format arrival_date yymmdd10.    
                   actual hpf_fcst base_fcst 8.2
                   base_error hpf_error 8.2;
            if (inA);
            if tfh_rmc = 1 then  do;
	            cap = cap1;
	            if cap > 0 then do;
                    hpf_error = 100*abs((hpf_fcst - actual))/cap ;
                    base_error = 100*abs((base_fcst - actual))/cap;
                end;
            end;
            else if tfh_rmc = 2 then  do;
                cap = cap2; 
                if cap > 0 then do;
                    hpf_error =  100*abs((hpf_fcst - actual))/cap ;
                    base_error = 100*abs((base_fcst - actual))/cap;
                end; 
            end; 
        run;



         ** Update the Baseline Weights table with the calculated weights obtained through **;
         ** combining baseline and HPF error values.                                       **;

         /*  %calculate_baseline_weights (
                &group_or_transient,
                &mode,
                hpfsys,
                best_model_history_names ,
                prop_code,
                demand,
                &by_variables,
                &asofdate,
                &as_of_date,
                hpfsys,
                &baseline_errors_table_name,
                hpfsys,
                &baseline_weights_table_name,
                prop_code_list,
                error,
                &shift_holdout_period,
                hpfsys,
                &prop_code_status_table_name,
                &rundtm,
                &mae_diff_hpf_switch
                ) ;
        */

        %turn_on_hpf (
                hpfsys,
                &baseline_weights_table_name,
                prop_code_list,
                &by_variables,
                hpfsys.daily_master,
                &run_date_1, 
                &run_date_2,
                &mace_diff_hpf_switch ,
                &fcst_max_hpf_switch  ,
                &diag_as_of_date
                );


        %daily_filter ( 
                 &llimit,
                 &ulimit,
                 &daily_fail_threshold
                 );

    %end;


    ** Output a list of prop_codes that partially or completely failed diagnosis **;

    %report_failed_prop_codes( hpfsys,
                           &prop_code_status_table_name,
                           &rundtm,
                           failfile,
                           D ) ;


    data hpfsys.ERROR_COMPARE_retain;
        set error_compare ;
    run;


    %macrend:

    %if &errflg ne 0 %then %msg_module(&errflg, &errmsg) ;

    %if &errflg eq -1 %then %do ;

        data _null_ ;
            abort return ;
        run;

    %end;


    /***  DROP UNIMPORTANT TABLES  VASAN 12-15-2009**/
    proc sql;
        drop table group_freq;
        drop table rejected_groups;
        drop table year_calc_demand ;
        drop table week_calc_demand  ;
        drop table groups_output;
    quit;


  
%mend;
