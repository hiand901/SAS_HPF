***************************************************************************************;
** PROGRAM: remove_baseln_fmodel_bygroups.sas                                        **;
** PURPOSE: Remove by-variable groups from input transient demand data, when the     **;
**          by-variable groups are associated with Baseline forced models.           **;
** BY:      Andrew Hamilton.                                                         **;
**-----------------------------------------------------------------------------------**;
** PARAMETERS:                                                                       **;
**                                                                                   **;
**  input_demand_table  - Name of sorted input demand/rates table.                   **;
**  forced_model_table  - Name of the 'best_model_overwrite_data' table - or the     **;
**                        name of historical_baseline_weights table, when the        **;
**                        program is being called from run_forecast.sas              **;
**  status_table_libref - Libref of the table that holds results of diagnosing all   **;
**                        prop_code, by-variable combos in the data.                 **;
**  status_table_name         - Name of the table that holds results of diagnosing   **;
**                              all prop_code, by-variable combos in the data.       **;
**  prop_code_process_list_ds - Data set containing list of prop_codes to process.   **;
**  initparm_prop_code - When called from run_forecast, the value of the prop_code   **;
**                       for which the forecast is being run.                        **;
**  bline_force_mod_ind       - The model_name value in the 'best_model_ovewrite..'  **;
**                              table that signifies that the prop_code, by-variable **;
**                              of the associated records are only to be forecasted  **;
**                              using the Baseline forecast process, and not this    **;
**                              HPF-based process.                                   **;
**  by_variables - The by variables read from the config properties file.            **;
**  event_mode - 'EventRemoval' or 'HPFEvent'                                        **;
**  d_or_f - 'D' for diagnose, 'F' for forecast.                                     **;
**  g_or_t - 'G' for Group, 'T' for Transient                                        **;
**  rundatetm - Date time, in SAS datetime numerical format, of the current run.     **;
**  asofdt - The date, in SAS date numerical format, of the selected as_of_date of   **;
**           the current run.                                                        **;
**                                                                                   **;
** INPUT DATA                                                                        **;
**      Input Demand Table Data:                                                     **;
**      Libref.Name - Defined by parameter value input_demand_table.                 **;
**      Columns: Prop_code, By_Variables (if any), demand/rate value                 **;
**                                                                                   **;
**      Input Forced Model Table Data:                                               **;
**      Libref.Name - Defined by parameter value forced_model_table                  **;
**      Columns: ByVar, ByVarValue, Model_Name                                       **;
**                                                                                   **;
**      Input Property Code Update Table:                                            **;
**      Input Property Code Status Table Data:                                       **;
**      Libref.Name - Defined by parameter values status_table_libref and            **;
**      status_table_name.                                                           **;
**      Columns: Prop_code, By_Variables (if any), Diagnose_or_Forecast, Mode,       **;
**      Group_or_Transient, rundtm, Pass_Fail, Status                                **;
**                                                                                   **;
**      Input Process List Data:                                                     **;
**      Libref.Name - Defined by parameter value prop_code_process_list_ds           **;
**      Columns: Prop_code                                                           **;
**                                                                                   **;
**                                                                                   **;
**  OUTPUT DATA                                                                      **;
**      Same as Input Demand Table.                                                  **;
**                                                                                   **;
**  Revised : Feb 2010                                                               **;
**                                                                                   **;
**                                                                                   **;
***************************************************************************************;

%macro remove_baseln_fmodel_bygroups (
         input_demand_table,
         forced_model_table,
         status_table_libref,
         status_table_name,
         prop_code_process_list_ds,
         initparm_prop_code,
         bline_force_mod_ind,
         by_variables,
         event_mode,
         d_or_f,
         g_or_t,
         rundatetm,
         asofdt
       ) ;



     ** Obtain all prop_codes, by_variable combos associated with BASELINE forced models **;
     ** to remove them from the input data.                                              **;

     proc sort data = &forced_model_table
                out = baseline_forced_models (keep = id byvar byvarvalue
                                                     %if &d_or_f = F %then prop_code as_of_date weight;
                                              );
         by
             %if &d_or_f = F %then prop_code id as_of_date ;
             %else id byvar byvarvalue ;
         ;
         where
               %if &d_or_f = D %then
               compress(upcase(model_name)) = compress(upcase("&bline_force_mod_ind")) ;
               %else
               as_of_date <= &asofdt;
         ;
     run;



     %dataobs (baseline_forced_models) ;
     %let baseline_forced_obs = &dataobs ;

     %if &d_or_f = D %then %do ;

         %if &baseline_forced_obs > 0 %then %do ;


             ** If this program is being called in Diagnose mode, the table that determines **;
             ** whether prop_code / by-variable groupings that should not be go through the **;
             ** remainder of process is the 'overwrite_best_model' table.                   **;
             data baseline_forced_models_denorm ;
                 length prop_code $5
                 %if &num_cat_vars > 0 %then &by_variables $64 ;
                 ;

                 set baseline_forced_models;

                 by id byvar ;

                 retain prop_code &by_variables ;

                 if first.id then do ;
                     prop_code = '';
                     %do i = 1 %to &num_cat_vars ;
                         &&cat_var_&i = '' ;
                     %end;
                 end;

                 if compress(lowcase(byvar)) = 'prop_code' then prop_code = byvarvalue ;
                 %do i = 1 %to &num_cat_vars ;
                     if byvar = "&&cat_var_&i" then &&cat_var_&i = byvarvalue ;
                 %end;

                 if last.id then output ;

                 drop byvar byvarvalue ;
             run;
         %end;
     %end;
     %else %if &d_or_f = F %then %do ;


         %if &baseline_forced_obs = 0 %then %do ;

             ** If no weights were found before the as_of_date find the closest set of weights **;
             ** after the as_of_date.                                                          **;

             proc sort data = &forced_model_table
                        out = baseline_forced_models (keep = id byvar byvarvalue weight
                                                             prop_code as_of_date
                                              );
                 by prop_code id descending as_of_date ;
             run;


             %dataobs (baseline_forced_models) ;

             %if &dataobs = 0 %then %do ;
                 %let errflg = -1 ;
                 %let errmsg = Unable to find any weight values before or after the as_of_date;
                 %goto macrend ;
             %end;

         %end;

         data baseline_forced_models_denorm ;
             %if &num_cat_vars > 0 %then
             length &by_variables $64 %str(;) ;

             set baseline_forced_models;

             by prop_code id
                %if &baseline_forced_obs = 0 %then descending ;
                              as_of_date  ;

             %if &num_cat_vars > 0 %then
             retain &by_variables %str(;) ;

             if first.id then do ;
                 %do i = 1 %to &num_cat_vars ;
                     &&cat_var_&i = '' ;
                 %end;
             end;

             %do i = 1 %to &num_cat_vars ;
                 %if &i > 1 %then else ;
                 if byvar = "&&cat_var_&i" then &&cat_var_&i = byvarvalue ;
             %end;

             if last.id then output ;

             drop byvar byvarvalue ;
         run;


         ** Find the prop_code, by_variable groupings of the historical weights data - that **;
         ** are closest to the as_of_date - that are associated with weights of 0.          **;

         data  baseline_forced_models_denorm ;
             set baseline_forced_models_denorm ;
             where (weight = 0 or weight=.);
         run;

         %let baseline_forced_obs = &dataobs ;

     %end;


     %if &baseline_forced_obs > 0 %then %do ;

         proc sort data = baseline_forced_models_denorm ;
             by prop_code &by_variables ;
         run;



         ** Merge the Baseline Forced Models with the input data to remove all prop_code, **;
         ** by_variables that are associated with the Baseline forced models.             **;

         data &input_demand_table
              removed_by_groups  (keep = prop_code &by_variables)
              prop_codes_all_bgs_removed (keep = prop_code by_groups_removed by_group_count)
             ;

             merge &input_demand_table (in = dmnd)
                   baseline_forced_models_denorm (in = base) ;

/*            by prop_code &by_variables ;*/
             by prop_code ;

             retain by_groups_removed by_group_count 0 ;

             if first.prop_code then do;
                by_groups_removed = 0 ;
                by_group_count = 0 ;
             end;

             if dmnd ;

             %if &num_cat_vars > 0 %then
             if first.&&cat_var_&num_cat_vars  ;
             %else if first.prop_code ;
               then do ;
                 by_group_count + 1 ;

                 if base then do ;
                    output removed_by_groups ;
                    by_groups_removed + 1;
                 end;
             end;

             if last.prop_code and by_groups_removed = by_group_count then output prop_codes_all_bgs_removed ;

             if not base then output &input_demand_table ;
         run;



         %dataobs(removed_by_groups) ;

         %if &dataobs > 0 %then %do ;

             data removed_by_groups ;
                 length diagnose_or_forecast group_or_transient $1 Mode $20
                        pass_fail $4 status $80 ;
                 set removed_by_groups ;

                 diagnose_or_forecast = compress("&d_or_f") ;
                 mode = compress("&event_mode") ;
                 Group_or_Transient = compress("&g_or_t") ;
                 rundtm = input(compress("&rundatetm"),datetime23.) ;
                 pass_fail = 'NA' ;
                 status = 'Associated with Baseline Forecast' ;
             run;


             %property_code_status_update (removed_by_groups,
                                           &status_table_libref,
                                           &status_table_name,
                                           USE) ;



             ** Remove any prop_codes for which all by_groupings were removed from the processing list **;

             %dataobs(prop_codes_all_bgs_removed);
             %if &dataobs > 0 %then %do ;

                 proc sql ;
                     create table &prop_code_process_list_ds
                     as select * from &prop_code_process_list_ds
                     where prop_code not in (select prop_code from prop_codes_all_bgs_removed)
                     order by prop_code;
                 quit;


             %end;
         %end;
     %end;

     %macrend:

%mend;
