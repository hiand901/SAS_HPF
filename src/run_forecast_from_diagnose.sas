******************************************************************************;
** Program: Run_Forecast_from_Diagnose.sas                                  **;
** Purpose: This is a control program that calls the components of the      **;
**          HPF Forecast System that forecasts demand values each property  **;
**          and By Variables combination in the data - with the further     **;
**          condition that in batch mode, property codes for which forecast **;
**          values are calculated are taken from a property list table.     **;
**          This program can also be called in 'on-demand' mode, in which   **;
**          case it will be called to provide forecast demand values for    **;
**          a specific property code.                                       **;
** Design Module: Section 3.2 of the HPF Forecast System Design Document    **;
** By:          Andrew Hamilton, Dec 2011.                                  **;
**                                                                          **;
******************************************************************************;

** The following statement was changed to include run_mode, run_date 12-15-2009 VASAN **;

%macro run_forecast_from_diagnose (
    top_dir, 
    config_file_path, 
    config_file_name, 
    run_mode=D, 
    run_date='01JAN2009'D, 
    diagnose_date = '01JAN2009'D,
    overide_out_table=test, 
    demand_data_table=demand_data_summarized1, 
    event_data_table=events_data);


    %let errflg =  0 ;
    %let errmsg = ;
    %let useLatestEventDef = 1;


    ** The following statement was added 12-15-2009 VASAN     **;
    ** aded by julia -- also need to change asofdate variable **;
    ** aded by julia -- also overode output table.            **;

    %if &run_mode = D %then %do; 
        data _null_;
            call symput  ("as_of_date", "&run_date" )  ;
    
            asofdate = input("&run_date", mmddyy10.) ;
            call symput('asofdate', put(asofdate, 8.) ) ;

            call symput('output_table_name',"&overide_out_table");

        run; 

        %put IN FORECASTER AS of date: &as_of_date &asofdate &run_date;

    %end;


    ** Check that the input demand_data_summarized data set exists and is non-empty **;

    %dataobs(&demand_data_table);

    %if &dataobs = 0 %then %goto macrend;


    ** Check that the input events data set exists and is non-empty **;

    %dataobs(&event_data_table);

    %if &dataobs = 0 %then %goto macrend;


    ** Assign the libname for the Baseline Forecast table **;
    libname baselib "&baseline_forecast_path" ;

    ** Check the validity of the baselib libref **;

    %let rc = %sysfunc(libref(baselib)) ;
    %if &rc > 0 %then %do ;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &baseline_forecast_path ;
        %goto macrend ;
    %end;


    ** Assign the indemlib - required by called programs - to work **;

	libname indemlib (work);



    data demand_data_summarized ;
        set &demand_data_table ;
        where &demand_date_col between &first_demand_date and &asofdate ;
    run;


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

            proc sort data = &event_data_table
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



    **%put "running in Diagnose mode run date &run_date before get best model " ;
    ** vasan **;

    %if &run_mode = D %then %do;

        ** Find the best models to use **;
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
            hpfsys,
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
            hpfsys,
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

    %if &errflg < 0 %then %goto macrend ;

    **  Added run_mode and run_date to the parameter list VASAN 12-23-09  **;

         
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
          hpfsys,
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
                hpfsys,
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
    ** of historical event-demand values.                                                   **;

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

    %validate_forecast (
                &group_or_transient,
                work,
                &demand_data_table,
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



    ** Output a list of prop_codes that partially or completely failed diagnosis **;

    %report_failed_prop_codes( hpfsys,
                           &prop_code_status_table_name,
                           &rundtm,
                           failfile,
                           F
                           ) ;


    %macrend:

    %if &errflg ne 0 %then %msg_module(&errflg, &errmsg) ;

    
    data _null_;
        sas_run_date= input("&run_date",mmddyy10.);
        call symput("fcst_date",sas_run_date);
    run;
    
%mend;
