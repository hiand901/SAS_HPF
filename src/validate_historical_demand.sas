******************************************************************************;
** Program: validate_historical_demand.sas                                  **;
** Purpose: This program checks that there is enough historical demand      **;
**          values available for each property code and other by variables  **;
**          combination to allow for finding the best forecasting model     **;
**          for each combination. If there is not enough historical demand  **;
**          values for a property code and by variables combination, all    **;
**          records associated with that combination will be removed from   **;
**          the data set returned from this program.                        **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:          Andrew Hamilton, July 2nd 2008.                             **;
**                                                                          **;
******************************************************************************;


%macro validate_historical_demand (
        input_demand_table_libref,
        input_demand_table_name,
        prop_code_status_libref,
        prop_code_status_table_name,
        prop_code_list_ds,
        prop_code_col,
        demand_col,
        by_variables,
        min_diagnosis_days,
        mode,
        g_or_t,
        d_or_f,
        rundatetm
       ) ;



        ** Find the number of days historical data for each property code and by variables group **;
        ** in the data.                                                                          **;

        proc freq data = &input_demand_table_libref..&input_demand_table_name noprint ;
                where &demand_col ne . ;
                table prop_code
                %if &num_cat_vars > 0 %then %do i = 1 %to &num_cat_vars ;
                        %str(*) &&cat_var_&i
                %end;
                / out = group_freq ;
        run;


        ** Merge the frequencies with the input demand tables, and delete records from the      **;
        ** original demand data where there are not enough records to allow valid model         **;
        ** selection.                                                                           **;

        data &input_demand_table_libref..&input_demand_table_name

             rejected_groups (keep = prop_code &by_variables)
             rejected_prop_codes (keep = prop_code) ;

                merge &input_demand_table_libref..&input_demand_table_name (in = dmnd)
                          group_freq (drop = percent) ;
                by prop_code &by_variables ;

                retain by_group_count by_groups_rejected  0 ;

                if first.prop_code then do;
                    by_group_count = 0 ;
                    by_groups_rejected = 0 ;
                end;

                %if &num_cat_vars > 0 %then
                 if first.&&cat_var_&num_cat_vars ;
                %else
                 if first.prop_code ;
                then by_group_count +1 ;

                if count < &min_diagnosis_days then do;
                    %if &num_cat_vars > 0 %then
                        if first.&&cat_var_&num_cat_vars ;
                    %else
                        if first.prop_code ;
                    then do ;
                        output rejected_groups ;
                        by_groups_rejected +1 ;
                    end;
                end;
                else output &input_demand_table_libref..&input_demand_table_name ;

                if last.prop_code and by_group_count = by_groups_rejected then
                 output rejected_prop_codes ;

        run;


        %dataobs (rejected_groups);

        ** If any groups were rejected because of lack of data, update the prop_code_Status_list **;
        ** table with that information.                                                          **;
        %if &dataobs ne 0 %then %do ;

            data rejected_groups ;

                length mode $20 group_or_transient diagnose_or_forecast $1 pass_fail $4
                       status $80;

                set rejected_groups ;

                mode = compress("&mode") ;
                group_or_transient = compress("&g_or_t") ;
                diagnose_or_forecast = compress("&d_or_f") ;
                rundtm = input("&rundatetm", datetime23.) ;
                pass_fail = 'Fail';
                status = 'Not enough Demand History';

                keep mode group_or_transient diagnose_or_forecast pass_fail rundtm status
                prop_code &by_variables ;
            run;


            %property_code_status_update (
                rejected_groups,
                &prop_code_status_libref,
                &prop_code_status_table_name,
                USE
            );

        %end;


        %dataobs (rejected_prop_codes);


        ** If all by_groups of a prop_code were rejected because of lack of data, remove the     **;
        ** prop_code from the process list, in order that it is not reported on again.           **;
        %if &dataobs ne 0 %then %do ;

            proc sql ;
                create table &prop_code_list_ds as select * from &prop_code_list_ds
                where prop_code not in (select prop_code from rejected_prop_codes)
                order by prop_code;
            quit;

        %end;



%macrend:


%mend;
