******************************************************************************;
** Program: Forecast_Event_Remove.sas                                       **;
** Purpose: This program uses the SAS HPFEngine procedure and best models   **;
**          already identified to produce forecast demand values. It is     **;
**          called if the 'Run_Forecast' program that calls this program    **;
**          was set up to run using     'EventRemoval' as the method for    **;
**          dealing with Events. The input demand data will have been       **;
**          pre-processed to replace demand on events with averages of      **;
**          demand on like non-event dates.                                 **;
**                                                                          **;
** Design Module: Section 3.9.1 of the HPF Forecast System Design Document  **;
** By:      Andrew Hamilton, July 9th 2008.                                 **;
**                                                                          **;
******************************************************************************;

%macro forecast_event_remove (
                mode,
                group_or_transient,
                input_demand_data_libref,
                input_demand_data_table,
                hpf_spec_libref,
                hpf_spec_catalog_name,
                Inest_Table_Libref,
                Inest_Table_Name,
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
                rundatetm
        );



        ******************************************************************************************;
        ** Ensure that there will be at least [horizon] records in the output forecast data set **;
        ** for all prop_code, by_variable groupings in the case where the as_of_date config     **;
        ** file option is beyond the last date in the data for at least one prop_code.          **;
        ******************************************************************************************;

        ** First find the lowest last date by prop_code **;
        ** The output data set from this step will also serve as a record of all the prop_code, **;
        ** by_variable combos in the input data.                                                **;

        proc summary data = &input_demand_data_libref..&input_demand_data_table noprint nway;
             class prop_code &by_variables ;
             var &date_col ;
             output out = input_combos (drop = _freq_ _type_
              %if &prop_code_col ne prop_code %then rename = (&prop_code_col = prop_code) ;
                                        ) max = max_date ;
        run;


        ** Get the lowest and highest last date **;

        proc sort data = input_combos out = max_dates  ;
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



        proc hpfengine data =

           %if &group_or_transient = T %then timeseries_demand ;
           %else &input_demand_data_libref..&input_demand_data_table ;

                repository = &hpf_spec_libref..&hpf_spec_catalog_name
                globalselection = modall
                inest = &Inest_Table_Libref..&Inest_Table_Name
                        %if &prop_code_col ne prop_code %then (rename = (prop_code = &prop_code_col)) ;

                out = &work2_libref..output_forecasts
                outest = output_estimates
                back = &History_Window
                lead = &Applied_Horizon
                task = update ;
                by &prop_code_col &by_variables ;
                id &date_col interval = day ;
                forecast &demand_col ;
        run;


        %if &syserr ne 0 and &syserr < 4 %then %do ;
                %let errflg = -1 ;
                %let errmsg = HPFEngine procedure failed to produce any forecast values in program forecast_event_remove.sas ;
                %goto macrend ;
        %end;
        %else %if &syserr >3 %then %do ;
                %let errflg = 1 ;
                %let errmsg = Warnings occured when running HPFEngine procedure in program forecast_event_remove.sas ;
        %end;



        ** Remove dates from the output forecast data set that are earlier than the as_of date. **;
        ** Also ensure that there are no more than [Horizon] days beyond the as_of date.        **;
        data &output_forecast_table_libref..&output_forecast_table_name ;
            set &work2_libref..output_forecasts ;
            where &date_col between &asofdt and %eval(&asofdate + &horizon) ;
        run;


        %if &group_or_transient = T %then %do ;
            proc datasets lib = &work2_libref mt = data nolist ;
                delete  max_dates;
            quit;
        %end;


        proc datasets lib = &work2_libref mt = data nolist ;
            delete output_forecasts ;
        quit;


        ** Check for successful forecast outputs **;

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
    ** - If the prop_code parameter equals 'ALL'.                         **;

    %if &prop_code = ALL %then %do ;

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
                        diagnose_or_forecast = "F" ;
                        group_or_transient = compress("&group_or_transient") ;
                        Mode = compress("&mode");
                        rundtm = input("&rundatetm", datetime23.) ;
                        pass_fail = 'Fail' ;
                        status = "Property Code not found in output forecast data";
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
                %let errmsg = Error occurred in program forecast_event_remove.sas ;
        %end;
        %else %if &syserr >3 %then %do ;
                %let errflg = 1 ;
                %let errmsg = Warnings occured in program forecast_event_remove.sas ;
        %end;


        ** Clean Up **;

        proc datasets lib=work mt=data nolist ;
           delete input_combos forecast_combos groups_output
           %if &prop_code eq ALL %then missing_prop_codes  ;
           ;
        quit;


%macrend:


%mend;
