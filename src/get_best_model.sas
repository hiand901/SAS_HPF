*****************************************************************************;
** Program: Get_Best_Model.sas                                              **;
** Purpose: This program returns the best models for a prop_code or set of  **;
**          prop_codes for which a forecast is being run.                   **;
**                                                                          **;
** Design Module:   Section 3.8 of the HPF Forecast System Design Document  **;
** By:          Andrew Hamilton, July 8th 2008.                             **;
**  revised by Vasan: Feb 2010   in the cleaning process at the end         **; 
**  we are not deleting    best_model_table_name                            **;                       
******************************************************************************;

%macro get_best_model (
                t_or_g,
                event_method,
                prop_code_list_libref,
                prop_code_list_table_name,
                best_model_table_libref,
                Best_Model_Names_Table,
                Best_Model_Details_Table,
                demand_data_libref,
                demand_data_table,
                status_table_libref,
                status_table_name,
                prop_code,
                prop_code_col,
                demand_col,
                by_variables,
                as_of_date,
                output_best_model_table_libref,
                output_best_model_Table_Name,
                output_inest_table_libref,
                output_inest_table_name,
                rundatetm,
                run_mode,
                run_date    
            )
    ;

       
                
        proc sort data = &best_model_table_libref..&best_model_names_table
                   out = best_model_names ;
                where as_of_date <= input("&as_of_date", mmddyy10.) and
                /* Take care that best models are being read for the current by variables */
                %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
                    %if &m > 1 %then and ;
                    index(id, compress(upcase(substr(left("&&cat_var_&m"),1,8)))) > 0
                %end;
                %else compress(byvarvalue) = compress(id)  ;
                ;
                by id byvar byvarvalue as_of_date model_name ;
         run;
       



        data best_model_names_denorm ;
             length prop_code $5 %if &num_cat_vars > 0 %then &by_variables $64 ; ;

             set best_model_names ;
             retain prop_code &by_variables ;

             by id byvar byvarvalue as_of_date model_name  ;

             if first.id then do ;
                 prop_code = '' ;
                 %do i = 1 %to &num_cat_vars ;
                     &&cat_var_&i = '' ;
                 %end;
             end;

             ** Select the latest as_of_date for each id, byvar / byvarvalue group **;
             if last.byvarvalue ;

             if compress(lowcase(byvar)) = lowcase(compress("&prop_code_col")) then prop_code = byvarvalue ;

             %do i = 1 %to &num_cat_vars ;
                 else if compress(lowcase(byvar)) = compress(lowcase("&&cat_var_&i")) then
                 &&cat_var_&i = byvarvalue ;
             %end;

             ** Make sure that only records for the correct prop_code / by_variable values are output **;
             if last.id then do;

                 ** Take care of the possible case where the current set of by_variables are a subset of **;
                 ** another set of by variables for which best models were calculated through ensuring   **;
                 ** an exact match of the id variable and all the values of prop_code and names and      **;
                 ** values of by_variables.                                                              **;
                 if compress(id) = compress(prop_code
                 %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
                     || upcase(substr(left("&&cat_var_&m    "),1,8)) || &&cat_var_&m
                 %end;
                 ) then output ;
             end;

             drop byvar byvarvalue id ;

        run;


        proc sort data = best_model_names_denorm ;
                by prop_code &by_variables as_of_date;
        run;


        %if &prop_code ne ALL %then %do;

                data best_model_table_name ;
                     set best_model_names_denorm ;
                    by prop_code &by_variables as_of_date ;
                    where compress(lowcase(prop_code)) = compress(lowcase("&prop_code")) ;
                run;

        %end;
        %else %do ;

                data best_model_names_denorm ;
                        set best_model_names_denorm ;
                        by prop_code &by_variables as_of_date ;
                run;


                data best_model_table_name best_model_not_found (keep = prop_code &by_variables);
                        merge   best_model_names_denorm (in=best)
                                &prop_code_list_libref..&prop_code_list_table_name (in = prop_list);
                        by prop_code ;
                        if prop_list and best then output best_model_table_name ;
                        else if prop_list and not best then output best_model_not_found ;
                run;

                %dataobs (best_model_not_found) ;

                %if &dataobs > 0 %then %do ;

                    ** In the case of requested prop_code, by_groups that are not found in the **;
                    ** best_model_history data table, remove their associated data from the    **;
                    ** summarized demand data, in order that they will not be forecast.        **;

                    data &demand_data_libref..&demand_data_table  ;
                        merge &demand_data_libref..&demand_data_table (in = dem)
                              best_model_table_name (in = best_mod_found keep = prop_code &by_variables);
                        by prop_code &by_variables ;
                        if best_mod_found and dem ;
                    run;

                    ** Update the status table to keep a record of any prop_code, by_var groups **;
                    ** groups that were removed because they had no associated diagnosed model. **;


                    data best_model_not_found ;
                        length diagnose_or_forecast group_or_transient $1 Mode $20
                               pass_fail $4 status $80 id $64 byvar $32 byvarvalue $64 ;
                        set best_model_not_found ;
                        by prop_code ;

                        diagnose_or_forecast = compress("F") ;
                        mode = compress("&event_method");
                        Group_or_Transient = compress("&t_or_g") ;
                        rundtm = input(compress("&rundatetm"),datetime23.) ;
                        pass_fail = 'NA' ;
                        status = 'No diagnosed model found';

                        id = compress(prop_code);
                    run;


                    %property_code_status_update (best_model_not_found,
                                                  &status_table_libref,
                                                  &status_table_name,
                                                  USE) ;


                    ** Remove the undiagnosed prop_codes from the processing list - if called from run_forecast only **;
                    ** If this program was called from run_forecast_from_diagnose, the prop_code_list data set       **;
                    ** should not be subset.                                                                         **;

                    %if &run_mode = %str(F) %then %do ;

                        proc sql ;
                            create table &prop_code_list_libref..&prop_code_list_table_name
                            as select * from
                            &prop_code_list_libref..&prop_code_list_table_name
                            where prop_code not in (select prop_code from best_model_not_found)
                            order by prop_code ;
                        quit ;

                     %end;

                %end;
        %end;


        ** Sort the denormalized statements data set for merging with the inest-format table **;
        proc sort data = best_model_table_name
                   out = best_model_names2 ;
             by as_of_date model_name ;
        run;


        ** Obtain just the unique model names for output to the statements data set **;
        proc sort data = best_model_table_name
                   out = &output_best_model_table_libref..&output_best_model_table_name
             nodupkey;
             by model_name ;
        run;



        ***************************************************************;
        ** Get the INEST format table coresponding to the best model **;
        ** for use with forecasting HPFEngine procedure.             **;
        ***************************************************************;

        proc sql ;
           create table &output_inest_table_libref..&output_inest_table_name
                       (rename = (model_name = _model_))
           as select a.prop_code,
           %do i = 1 %to &num_cat_vars ;
                     a.&&cat_var_&i ,
                   %end;
           b.*
           from best_model_names2 as a, hpfsys.best_model_history_parm_ests as b
           where a.as_of_date = b.as_of_date
           and a.model_name = b.model_name
           %if %lowcase(&event_method) = eventremoval %then
              and compress(b._component_) ne "SCALE" ;
           ;
        quit;


        ** Sort the output inest data set as necessary **;
        proc sort data = &output_inest_table_libref..&output_inest_table_name ;
            by prop_code &by_variables _model_ _component_ ;
        run;


        ** Clear up. **;
        /*******************************
        proc datasets lib = work mt=data nolist ;
             delete best_model_names best_model_names2
                    best_model_table_name ;
        quit;
           ************************/

            /*** revised code below  VASAN  Feb 2010 ***/
        proc datasets lib = work mt=data nolist ;
             delete best_model_names best_model_names2;
        quit;
%mend;
