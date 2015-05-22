******************************************************************************;
** Program: Forecast_HPFEvent.sas                                           **;
** Purpose: This program uses the SAS HPFEngine procedure and best models   **;
**          already identified to produce forecast demand values. It is     **;
**          called if the 'Run_Forecast' program that calls this program    **;
**          was set up to run using 'HPFEvent' as the method for            **;
**          dealing with Events.                                            **;
**                                                                          **;
** Design Module: Section 3.9.2 of the HPF Forecast System Design Document  **;
** By:          Andrew Hamilton, July 10th 2008.                            **;
**                                                                          **;
******************************************************************************;


%macro forecast_hpfevent (
                mode,
                group_or_transient,
                input_demand_data_libref,
                input_demand_data_table,
                hpf_spec_libref,
                hpf_spec_catalog_name,
                Inest_Table_Libref,
                Inest_Table_Name,
                hpfevent_table_libref,
                hpfevent_table_name,
                prop_code_list_table_libref,
                prop_code_list_table_name,
                output_forecast_table_libref,
                Output_Forecast_Table_Name,
                status_table_libref,
                status_table_name,
                prop_code,
                prop_code_col,
                demand_col,
                date_col,
                by_variables,
                asofdt,
                hold_out_period,
                History_Window,
                Horizon,
                rundatetm,
                event_obs
        );


        ** Copy the Spec catalog to a temporary location **;

        proc copy in = &hpf_spec_libref out = work mt = cat ;
            select &hpf_spec_catalog_name ;
        run;



        ******************************************************************************************;
        ** Ensure that there will be at least [horizon] records in the output forecast data set **;
        ** for all prop_code, by_variable groupings in the case where the as_of_date config     **;
        ** file option is beyond the last date in the data for at least one prop_code.          **;
        ******************************************************************************************;

        ** First find the lowest last date by prop_code.                                        **;
        ** The output data set from this step also serves as a record of all the prop_code,     **;
        ** by_variable combinations in the input data.                                          **;

        proc summary data = &input_demand_data_libref..&input_demand_data_table noprint nway;
             class &prop_code_col &by_variables ;
             var &date_col ;
             output out = input_combos (drop = _freq_ _type_
                    %if &prop_code_col ne prop_code %then
                                       rename = (&prop_code_col = prop_code) ;
                          ) max = max_date ;
        run;



        ** Get the lowest last date **;

        proc sort data = input_combos out = max_dates ;
           by max_date ;
        run;

        data _null_ ;
            set max_dates end=eof ;
            if _n_ = 1 then do;
               call symput ('min_max_date', put(max_date,8.)) ;
               * Calculate the necessary horizon value to ensure there will be [horizon] *;
               * records beyond the as_of_date for all prop_code, by-group combinations. *;
               if &asofdate > max_date then applied_horizon = &horizon + (&asofdate - max_date) ;
               else applied_horizon = &horizon ;
               if compress(upcase("&group_or_transient")) = "G" then
                call symput ('applied_horizon', put(applied_horizon, 8.)) ;
               else do;
                   ** In the case of Transient, a proc timeseries will   **;
                   ** even-up the prop_code, by_variable group series.   **;
                   call symput ('applied_horizon', put(&horizon, 8.)) ;
               end;
            end;

            ** Always use the as_of date as the end of the series **;
            call symput ('max_max_date', put(&asofdt, date7.)) ;
            stop ;
        run;



        %if &prop_code = ALL %then %do ;

            ** Find the input list of prop_codes **;
            proc freq data = input_combos noprint;
                table prop_code / out = input_prop_codes ;
            run;

            data _null_ ;
                set input_prop_codes end=eof;
                call symput('propcd_'!! compress(put(_n_, 4.)), compress(prop_code)) ;
                if eof then call symput('num_propcds', compress(put(_n_, 4.)) ) ;
            run;

        %end;
        %else %do ;
            %let num_propcds = 1 ;
            %let propcd_1 = &prop_code ;
        %end;



        ** For Transient, run a proc timeseries to fill missing values up to **;
        ** the as_of date (should be the same as the max_max_date).          **;

        %if &group_or_transient = T %then %do;

            proc timeseries data = &input_demand_data_libref..&input_demand_data_table
                             out = timeseries_demand;

                by &prop_code_col &by_variables ;
                id &date_col
                interval = DAY
                end = "&max_max_date"d
                accumulate = total
                setmiss = 0 ;
                var &demand_col ;
            run;

        %end;



        *****************************************************************;
        ** Cycle through the prop_codes in the input prop_code list.   **;
        *****************************************************************;

        %do i = 1 %to &num_propcds ;

            ** Get the demand subset for the current prop_code **;
            data prop_code_demand ;
                set
                %if &group_or_transient = T %then
                    timeseries_demand ;
                %else
                    &input_demand_data_libref..&input_demand_data_table ;
                ;
                by &prop_code_col &by_variables ;
                where &prop_code_col = compress("&&propcd_&i") ;

                %if &prop_code_col ne prop_code %then
                 rename &prop_code_col = prop_code ;
            run;


            ** Get the event names related to the current prop_code - if  any event data  **;
            ** was supplied to this program.                                              **;
            %if &event_obs > 0 %then %do ;
                data hpf_event ;
                    set &hpfevent_table_libref..&hpfevent_table_name  ;
                    where &prop_code_col = compress("&&propcd_&i") ;
                run;


                ** Get the list of event ids associated with the current prop_code ** ;
                proc freq data = hpf_event noprint;
                    tables _name_ / out = event_id_list ;
                run;

                %let num_event_ids = 0 ; ** Allow for the possibility that no events       **;
                                         ** data is defined for a particular prop_code.    **;


                ** Write out all the event ids related to a prop code to a macro variable, **;
                ** for later use by HPFSELECT.                                             **;
                data _null_ ;
                    set event_id_list end = eof ;

                    event_count + 1 ;
                    call symput('eventid'!! left(put(event_count,4.)), compress(_name_) );

                    if eof then call symput ('num_event_ids', compress(put(event_count, 4.)) ) ;
                run;
            %end;



            ** Obtain the INEST data set subset corresponding to the current prop_code **;
            data prop_code_inest ;
                set &inest_table_libref..&inest_table_name ;
                by prop_code &by_variables ;
                where prop_code = compress("&&propcd_&i") ;
            run;



            ** Get by variables associated with each model name **;
            proc sort data = prop_code_inest out = prop_code_models nodupkey ;
                by _model_ &by_variables ;
            run;



            ** Write out to a macro variable a where clause for each by-group within the **;
            ** current prop_code.                                                        **;
            ** Also write out the model name associated with each by-group within the    **;
            ** current prop_code to a macro variable in order that it can be referenced  **;
            ** within the code section run for each by-group.                            **;

            data _null_ ;
                length bv_whr_str $1024 ;

                set prop_code_models end=eof;
                by _model_ &by_variables ;

                retain model_count 0 bv_whr_str ;

                if first._model_ then do ;
                    model_count + 1 ;
                    call symput ('mbv_model_'!! left(put(model_count, 3.)), compress(_model_)) ;
                    if &num_cat_vars > 0 then bv_whr_str = '(' ;
                    else bv_whr_str = '(1=1' ;
                end;
                else bv_whr_str = trim(left(bv_whr_str)) !!' or (' ;

                %do j = 1 %to &num_cat_vars ;
                    %if &j ne 1 %then bv_whr_str = trim(left(bv_whr_str))!! ' and' %str(;) ;
                    bv_whr_str = trim(left(bv_whr_str))!! " compress(&&cat_var_&j) = compress ('"!!
                                 compress(&&cat_var_&j) !!"')" ;
                %end;
                bv_whr_str = trim(left(bv_whr_str)) !!')' ;

                if last._model_ then do ;
                    call symput ('mbv_whrstr_'!! left(put(model_count,3.)), bv_whr_str ) ;
                end;

                if eof then do ;
                    call symput('num_bv_models', left(put(model_count, 3.)) ) ;
                end;
            run;



            %do k = 1 %to &num_bv_models ;

                ** Create a selection of the model repository containing just the model name,  **;
                ** associated with a particular by variable combination - within the current   **;
                ** value of prop_code under consideration.                                     **;
                proc hpfselect repository = work.&hpf_spec_catalog_name name = modall ;
                    spec &&mbv_model_&k /
                     %do m = 1 %to &num_event_ids ;
                         eventmap (symbol=none event = &&eventid&m )
                     %end;
                     inputmap (symbol = Y var = demand ) ;
                run;



                ** Obtain the INEST data set subset corresponding to the current prop_code     **;
                ** and _model_ combination.                                                    **;
                data prop_code_inest_model ;
                    set prop_code_inest ;
                    by prop_code &by_variables ;
                    where &&mbv_whrstr_&k ;
                run;



                proc hpfengine data = prop_code_demand (where = (&&mbv_whrstr_&k))
                    repository = work.&hpf_spec_catalog_name
                    globalselection=modall
                    inest = prop_code_inest_model
                    outest = output_estimates
                %if &num_event_ids > 0 %then
                    inevent = hpf_event ;
                    out = prop_code_forecast
                    %if &prop_code_col ne prop_code %then (rename = (prop_code = &prop_code_col)) ;
                    back = &History_Window
                    lead = &Applied_Horizon
                    task = update ;

                    by prop_code &by_variables ;

                    forecast demand ;
                    id &date_col interval = day ;

                run;


                ** Compile the forecast data sets into one compendium forecast data set **;
                %if &k = 1 and &i = 1 %then %do ;
                    data &output_forecast_table_name ;
                        set prop_code_forecast (where =( &date_col between &asofdt and
                                                         %eval(&asofdate + &horizon) ));
                    run;
                %end;
                %else %do ;
                    proc append base = &output_forecast_table_name
                                data = prop_code_forecast (where =( &date_col between &asofdt and
                                                                    %eval(&asofdate + &horizon) ));
                    run;
                %end;



                proc datasets lib = work mt =data nolist ;
                    delete output_estimates
                    prop_code_inest_model ;
                quit;


            %end;

            proc datasets lib = work mt =data nolist ;
                delete prop_code_forecast output_estimates
                       prop_code_inest prop_code_demand hpf_event prop_code_models ;
            quit;


        %end;


        %if &syserr ne 0 and &syserr < 4 %then %do ;
            %let errflg = -1 ;
            %let errmsg = HPFEngine procedure failed to produce forecast values in program forecast_hpfevent.sas ;
            %goto macrend ;
        %end;
        %else %if &syserr >3 %then %do ;
            %let errflg = 1 ;
            %let errmsg = Warnings occured when running HPFEngine procedure in program forecast_hpfevent.sas ;
        %end;




        *****************************************;
        ** Create the output forecast data set **;
        *****************************************;

        %if &output_forecast_table_libref ne work %then %do ;
            proc copy in = work out = &output_forecast_table_libref mt = data ;
                 select &output_forecast_table_name ;
            run;

            proc datasets lib = work mt=data nolist ;
                delete &output_forecast_table_name ;
            quit;
        %end;




        *******************************************;
        ** Check for successful forecast outputs **;
        *******************************************;

        ** If the prop_code input parameter does not equal ALL, do not update **;
        ** the prop_code status table. This reduces the chance of a file      **;
        ** update contention.                                                 **;

        %if &prop_code = ALL %then %do ;

            ** Get the list of property codes and by variables in the output forecast data **;
            proc freq data = &output_forecast_table_libref..&output_forecast_table_name noprint;
                    tables &prop_code_col
                    %do i = 1 %to &num_cat_vars ;
                            %str(*) &&cat_var_&i
                    %end;
                    / out = forecast_combos ;
            run;




            ** Merge the list of prop_codes and by_variables that were forecasted with      **;
            ** the list of prop_codes and by_variables that were input to the program.      **;

            data groups_output ;

                length pass_fail $4 status $80 ;
                length diagnose_or_forecast group_or_transient $1 Mode $20 ;

                merge input_combos (in=inp)
                      forecast_combos (in=fore
                      %if &prop_code_col ne prop_code %then rename = (&prop_code_col = prop_code) ;
                                       );

                by prop_code &by_variables ;

                diagnose_or_forecast = "F" ;
                group_or_transient = compress("&group_or_transient") ;
                Mode = compress("&mode");
                rundtm = input("&rundatetm", datetime23.) ;

                if inp and fore then pass_fail = 'Pass' ;

                else if inp and not fore then do ;
                    pass_fail = 'Fail';
                    status = 'Not Represented in Output Forecast Data';
                end;

                keep prop_code &by_variables pass_fail status diagnose_or_forecast mode
                     group_or_transient rundtm status ;
            run;



            ** Update the prop_code_Status_table with that pass_fail information. **;

            %property_code_status_update (
                groups_output,
                &status_table_libref,
                &status_table_name,
                USE
            );




            ** Merge the status table with the data set containing the list of      **;
            ** prop_codes to process, to look for further missing prop_codes.       **;
            ** - if prop_code input parameter equals ALL.                           **;

            %if &prop_code eq ALL %then %do ;

                data missing_prop_codes ;
                    merge   groups_output (in = gout)
                            &prop_code_list_table_libref..&prop_code_list_table_name (in=proclist) ;
                    by prop_code ;

                    if proclist and not gout then do;
                        pass_fail = 'Fail' ;
                        status = "Property Code not found in output forecast data";
                        diagnose_or_forecast = "F" ;
                        group_or_transient = compress("&group_or_transient") ;
                        Mode = compress("&mode");
                        rundtm = input("&rundatetm", datetime23.) ;
                        output ;
                    end;

                    keep prop_code pass_fail status diagnose_or_forecast mode
                         group_or_transient rundtm status  ;
                run;


                %dataobs(missing_prop_codes);
                %if &dataobs > 0 %then %do;


                ** Update the property code status table with a record of any **;
                ** property codes that were in the processing list, but that  **;
                ** were not represented in the forecast data.                 **;
                %property_code_status_update (
                    missing_prop_codes,
                    &status_table_libref,
                    &status_table_name,
                    ALL
                 );

            %end;

        %end;

    %end;



    ** Check for overall program error **;

    %if &syserr ne 0 and &syserr < 4 %then %do ;
           %let errflg = -1 ;
           %let errmsg = Error occurred in program forecast_hpfevent.sas ;
    %end;
    %else %if &syserr >3 %then %do ;
         %let errflg = 1 ;
         %let errmsg = Warnings occured in program forecast_hpfevent.sas ;
    %end;


    ** Clean Up **;

    proc datasets lib=work mt=data nolist ;
        delete input_combos forecast_combos groups_output
        %if &prop_code = ALL %then  input_prop_codes missing_prop_codes ;
        ;
    quit;



%macrend:


%mend;
