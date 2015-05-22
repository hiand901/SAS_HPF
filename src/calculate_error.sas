******************************************************************************;
** Program: Calculate_Error.sas                                             **;
** Purpose: This program calculates the average error, using Mean Absolute  **;
**          percentage error, or MAPE. It is called after event replacement **;
**          in the forecast values in the case where 'Event Removal' is the **;
**          selected method for dealing with events.                        **;
**                                                                          **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:            Andrew Hamilton, July 16th 2008.                          **;
**                                                                          **;
**--------------------------------------------------------------------------**;
** Modifications                                                            **;
**--------------------------------------------------------------------------**;
** Date   By  Modification                                                  **;
** 111208 AH  Changed the error calculation from MAPE to MAE                **;
**                                                                          **;
******************************************************************************;


%macro calculate_error (
        historical_demand_data_libref,
        historical_demand_data_name,
        forecast_demand_data_libref,
        forecast_demand_data_table,
        historical_best_model_libref,
        historical_best_model_name,
        by_variables,
        rundtm,
        demand_col,
        demand_date_col,
        demand_prop_code_col,
        forecast_demand_col,
        forecast_date_col,
        forecast_prop_code_col
);


        %let renflg = 0 ;
        %local renstr ;

        data _null_ ;
                length renstr $256 ;
                if compress(lowcase("&forecast_prop_code_col")) ne "prop_code" then
                renstr = trim(left(renstr)) !! trim(left("&forecast_prop_code_col = prop_code")) ;
                if compress(lowcase("&forecast_date_col")) ne compress(lowcase("&demand_date_col")) then
                renstr = trim(left(renstr)) !!' '!! trim(left("&forecast_date_col = &demand_date_col")) ;

                if compress(renstr) ne "" then do ;
                        call symput('renstr', trim(left(renstr))) ;
                        call symput('renflg', '1') ;
                end;
        run;


        ** If forced forecasts are appended to non-forced forecast results, the **;
        ** prop_codes are likely to be out of order in the forecast data set.   **;

        proc sort data = &forecast_demand_data_libref..&forecast_demand_data_table ;
            by &forecast_prop_code_col &by_variables &forecast_date_col ;
        run;



        %let errflg = 0;

        ** Merge the amended forecast data output by the best models with the   **;
        ** common dates within the historical demand data.                      **;

        data compare ;
                merge &forecast_demand_data_libref..&forecast_demand_data_table
                      (in = forecast rename = (&forecast_demand_col = forecast_dmnd
                                               %if &forecast_prop_code_col ne prop_code %then
                                                &forecast_prop_code_col = prop_code ;
                                               %if &forecast_date_col ne &demand_date_col %then
                                                &forecast_date_col = &demand_date_col ;
                                ))
                &historical_demand_data_libref..&historical_demand_data_name (in=dmnd) ;
                by &demand_prop_code_col &by_variables &demand_date_col;


                perc_error = 0 ;
                divisor = 0 ;

                if forecast and dmnd and &demand_col + forecast_dmnd ne . then do;
                    divisor = 1 ;
                    abs_error = abs(&demand_col - forecast_dmnd) ;
					output;
                end;
        run;



        ** Calculate the sum of absolute percentage error and divisor **;

        proc summary data = compare nway noprint ;
                class &demand_prop_code_col &by_variables ;
                var abs_error divisor;
                output out = summed_error sum = ;
        run;
             

        ** Calculate the MAE ** ;

        data summed_error ;
                set summed_error ;
                new_error = abs_error / divisor ;
                as_of_date = &rundtm ;
                drop _freq_ _type_  perc_error divisor ;
        run;

        proc sort data = summed_error ;
                by as_of_date &demand_prop_code_col &by_variables ;
        run;

              


        ** Transpose the error values ahead of merging with the best model names        **;
        ** / error tables.                                                              **;

        data trans_error ;
                length id $256 name_sub $8;
                set summed_error (keep = as_of_date new_error &demand_prop_code_col
                                                                &by_variables ) ;
                by &demand_prop_code_col &by_variables ;

                ** Select the first of repeated records for the same by group **;
                %if &num_cat_vars > 0 %then
                if first.&&cat_var_&num_cat_vars %str(;) ;
                %else
                if first.&demand_prop_code_col %str(;) ;

                id = compress(&demand_prop_code_col) ;

                %do i = 1 %to &num_cat_vars ;
                    ** Allow for implicit converson of any numeric By variables to **;
                    ** character values.                                           **;
                    if length(compress("&&cat_var_&i")) > 8 then
                    name_sub = upcase(substr(compress("&&cat_var_&i"),1,8)) ;
                    else name_sub = upcase(compress("&&cat_var_&i")) ;
                    id = compress(id !! name_sub !! &&cat_var_&i) ;
                %end;

                drop &demand_prop_code_col &by_variables name_sub;
         ;

        run;


        proc sort data = trans_error ;
                by as_of_date id  ;
        run;



        *******************************************************************************;
        ** Update the historical best model data table with the updated error values **;
        *******************************************************************************;

        data &historical_best_model_libref..&historical_best_model_name;
                merge  &historical_best_model_libref..&historical_best_model_name (in=bmods)
                       trans_error (in = trans);
                by as_of_date id ;
                retain prev_error 0 ;

                if bmods ;

                if trans then do ;
                    if first.id then do ;
                       error = new_error ;
                       prev_error = error ;
                    end;

                    else error = prev_error ;
                end;

                drop new_error prev_error ;
        run;



        proc datasets lib=work nolist mt=data ;
            delete trans_error summed_error compare  ;
        quit;



 %macrend:

        %if &syserr > 0 and &syserr ne 4 %then %do ;
                %let errflg = -1 ;
                %let errmsg = Error occurred in calculate_error program updating the historical best model table, ;
                %let errmsg = &errmsg &historical_best_model_libref..&historical_best_model_name ;
        %end;
        %else %if &syserr => 4 %then %do ;
                %let errflg = 1;
                %let errmsg = Warning generated in calculate_error program updating the historical best model table ;
                %let errmsg = &errmsg &historical_best_model_libref..&historical_best_model_name ;
        %end;


%mend;
