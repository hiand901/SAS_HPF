 ************************************************************************************;
 ** Program: Diagnose_Event_Remove.sas                                             **;
 ** Purpose: This program uses the SAS HPFEngine procedure to find the best        **;
 **          models and output forecast demand values, if the 'Run Diagnose'       **;
 **          program that calls this program was set up to run using               **;
 **          'EventRemoval' as the method for dealing with Events. The input       **;
 **          demand data will have been pre-processed to replace demand on         **;
 **          events with averages of demand on like non-event dates.               **;
 **                                                                                **;
 ** Output Data Sets:                                                              **;
 ** Best Model Names data set - Contains names of best diagnosed models along with **;
 **                      prop_code, by-variable, as_of_date, and _error_ values.   **;
 **        The prop_code and other by-variables related to each                    **;          
 **                      model are held in 'id', byvar, and byvarvalue columns.    **;
 ** Best Model 'Parm Ests' data set - Contains names of best diagnosed models      **;
 **                      along with as_of_date, and parameter estimates produced   **;
 **                      by the HPFEngine procedure and sent to 'outest' data set. **;
 ** Output Error Table - Holds HPF-calculated error values along with a prop_code  **;
 **                      column, and a column for each by-variable.                **;
 **                                                                                **;
 ** Design Module:       Section 3.7.1 of the HPF Forecast System Design Document  **;
 ** By:          Andrew Hamilton, July 7th 2008.                                   **;
 ** revised by Vasan: Feb 2010  added routine to calculate daily error             **;
 ************************************************************************************;

 %macro diagnose_event_remove (
                 mode,
                 group_or_transient,
                 input_demand_data_libref,
                 input_demand_data_table,
                 hpf_spec_libref,
                 hpf_spec_catalog_name,
                 best_model_libref,
                 Best_Model_Names_Table,
                 Best_Model_Details_Table,
                 Force_Model_Table_Libref,
                 Force_Model_Table_Name,
                 candidate_models_libref,
                 candidate_models_table_name,
                 prop_code_list_table_libref,
                 prop_code_list_table_name,
                 status_table_libref,
                 status_table_name,
                 output_forecast_table_libref,
                 Output_Forecast_Table_Name,
                 prop_code_col,
                 demand_col,
                 date_col,
                 by_variables,
                 hold_out_period,
                 shift_Hold_Out_Period,
                 History_Window,
                 Horizon,
                 rundtm,
                 rundatetm,
                 max_combos
				 
         );
           
         **********************************************************************************;
         ** Find the maximum value of date values in the input demand data, for each     **;
         ** prop_code and by_variables grouping.                                         **;
         **********************************************************************************;

         ** Also in the same step find the input prop_code and by variables that are     **;
         ** represented in the input data. These will be used to check for missing       **;
         ** combos in the output best model data of this program.                        **;


         proc sort data = &input_demand_data_libref..&input_demand_data_table
                    out = demand_data_hold_out;
                 by &prop_code_col &by_variables ;
         run;

         proc summary data = demand_data_hold_out nway noprint ;
                 class &prop_code_col &by_variables ;
                 var &date_col ;
                 output out = input_combos (drop = _freq_ _type_) max = max_date ;
         run;


         ** The output max_dates data set in the data step below will hold maximum date  **;
         ** values per prop_code, by_variables after the holdout shift has been applied. **;

         data demand_data_hold_out (drop = shifted_max_date max_date)
              max_dates (keep = &prop_code_col &by_variables shifted_max_date);
                 merge demand_data_hold_out
                       input_combos ;
                 by &prop_code_col &by_variables ;

                 if &shift_holdout_period > 0 then shifted_max_date = max_date - &shift_holdout_period ;
                 else shifted_max_date = max_date ;

                 %if &num_cat_vars > 0 %then
                  if last.&&cat_var_&num_cat_vars ;
                 %else
                  if last.prop_code ;

                 then output max_dates ;

                 * The following if statement is not applied for Transient, since  *;
                 * a single cut-off date will be used for all by_groups in that    *;
                 * case, and it will be based on the highest max_date in the data. *;
                 %if &shift_holdout_period > 0 and &group_or_transient = G %then
                   if &date_col > shifted_max_date then delete %str(;) ;

                 output demand_data_hold_out ;
         run;



         ** Find the maximum of the max_date values. **;

         proc sort data = max_dates out = descending_max_dates;
             by descending shifted_max_date ;
         run;

         data _null_ ;
             set descending_max_dates nobs = numobs;
             call symput ('max_date', put(shifted_max_date, date7.)) ;
             call symput('num_combos', put(numobs,8.)) ;
             stop;
         run;



         ** Run proc timeseries to fill in missing dates in the demand data **;

         proc timeseries data = demand_data_hold_out
                          out = timeseries_demand;

             by &prop_code_col &by_variables ;
             id &date_col
             interval = DAY
             end = "&max_date"d
             accumulate = total
             setmiss = 0 ;
             var  &demand_col ;
         run;


         ** Remove dates that have been added in the previous step that were beyond the **;
         ** original prop_code, by-groups maximum date in the data.                     **;
         ** This is not carried out for transient, since it is necessary in that case   **;
         ** to always use the same date range for each by group.                        **;

         %if %upcase(&group_or_transient) = G %then %do ;
             data timeseries_demand ;
                 merge timeseries_demand max_dates ;
                 by prop_code &by_variables ;
                 if &date_col > shifted_max_date then delete ;
                 drop shifted_max_date ;
             run;
         %end;


         proc datasets lib=work nolist mt = data ;
             delete demand_data_holdout ;
         quit;



         *********************************************************************************;
         ** Reorganize the forced model data set so that it has one column per by group **;
         *********************************************************************************;
         %dataobs (&force_model_table_libref..&force_model_table_name) ;

         %if &dataobs > 0 %then %do;
                 proc sort data = &force_model_table_libref..&force_model_table_name
                         out = sorted_forced_models ;
                         by model_name byvar byvarvalue ;
                 run;


                 data forced_models ;
                         length prop_code $5
                         %if &num_cat_vars > 0 %then &by_variables $64 ;
                         ;

                         set sorted_forced_models ;
                         retain prop_code &by_variables ;
                         by model_name byvar byvarvalue ;

                         if first.model_name then do ;
                                 prop_code = '' ;
                                 %do i = 1 %to &num_cat_vars ;
                                         &&cat_var_&i = '' ;
                                 %end;
                         end;

                         if compress(lowcase(byvar)) = lowcase(compress("&prop_code_col")) then prop_code = byvarvalue ;

                         %do i = 1 %to &num_cat_vars ;
                                 else if compress(lowcase(byvar)) = compress(lowcase("&&cat_var_&i")) then
                                 &&cat_var_&i = byvarvalue ;
                         %end;

                         if last.model_name then output ;

                         drop byvar byvarvalue ;

                 run;

                 proc sort data = forced_models ;
                         by prop_code &by_variables ;
                 run;



                 ** Obtain demand records associated with forced models, and those associated with    **;
                 ** HPF Engine 'selected' models.                                                     **;

                 data &work2_libref..demand_data (drop = model_name)
                          demand_ow_data ;
                         merge timeseries_demand (in = dmnd
                         %if %lowcase(&prop_code_col) ne %str(prop_code) or
                             %lowcase(&demand_col) ne %str(demand) %then %do;
                                         rename = (
                                         %if %lowcase(&prop_code_col) ne %str(prop_code)
                                         %then &prop_code_col = prop_code ;
                                         %if %lowcase(&demand_col) ne %str(demand)
                                         %then &demand_col = demand ;
                                 )
                         %end;
                         )

                         forced_models (in = forced);

                         by prop_code &by_variables ;

                         if dmnd ;

                         if forced then output demand_ow_data ;
                         else output &work2_libref..demand_data ;
                 run;
         %end;
         %else %do ;

                 data &work2_libref..demand_data ;
                         set timeseries_demand
                         %if %lowcase(&prop_code_col) ne %str(prop_code) or
                                 %lowcase(&demand_col) ne %str(demand) %then %do;
                                         (rename = (
                                         %if %lowcase(&prop_code_col) ne %str(prop_code)
                                         %then &prop_code_col = prop_code ;
                                         %if %lowcase(&demand_col) ne %str(demand)
                                         %then &demand_col = demand ;
                                 ))
                         %end;
                         ;
                 run;


         %end;

/*
         proc datasets nolist mt=data lib=work;
             delete timeseries_demand  ;
         quit;
*/


         %if &num_combos > &max_combos %then %do;

             data _null_ ;
                num_iterations = int(&num_combos / &max_combos) + 1 ;
                call symput('num_iterations', put(num_iterations, 8.)) ;
             run;


             %do j = 1 %to &num_iterations ;
                data bg_list_&j ;
                   set input_combos ;
                   if _n_ > (&j-1) * &max_combos
                   and _n_ <= &j * &max_combos
                   then output ;
                run;
             %end;
         %end ;
         %else %let num_iterations = 1 ;


         %do j = 1 %to &num_iterations ;


             %if &num_combos > &max_combos %then %do ;

                 ** Get the demand data subset relating to the current iteration **;

                 data demand_iter_sub ;
                     merge &work2_libref..demand_data
                           bg_list_&j (in = current_iteration) ;
                     by prop_code &by_variables ;
                     if current_iteration then output ;
                 run;
             %end;


             ** Run the HPFEngine procedure on data not associated with forced models.       **;

             proc hpfengine data =
                 %if &num_combos > &max_combos %then demand_iter_sub ;
                 %else                               &work2_libref..demand_data  ;
                     repository = &hpf_spec_libref..&hpf_spec_catalog_name
                     globalselection = modall
                 %if &num_combos > &max_combos %then
                     outest = non_forced_outest_sub
                     outfor = non_forced_forecast_sub
                 ;
                 %else
                     outest = non_forced_outest
                     outfor = non_forced_forecast
                 ;
                     out = _null_
					 print = (select summary)
                     back = &History_Window
                     lead = &Horizon
                     task = select (criterion = mae holdout = &hold_out_period) ;
                     by prop_code &by_variables ;
                     id &date_col interval = day ;
                     forecast demand ;
             run;


             ** Concatenate forecast and outest data sets in the case where HPFEngine is being **;
             ** run more than once due to the number of input by_group combos being greater    **;
             ** than the maximum allowed.                                                      **;

             %if &num_combos > &max_combos %then %do ;

                 proc append base = non_forced_outest data = non_forced_outest_sub ; run;

                 proc append base = non_forced_forecast data = non_forced_forecast_sub ; run;

                 proc datasets nolist lib = work mt = data ;
                     delete non_forced_forecast_sub non_forced_outest_sub ;
                 quit;
             %end;

         %end ;


         ******************************************************************************;
         ** If there are any demand records associated with forced models, run the   **;
         ** HPFEngine procedure for each unique combination of prop_code and         **;
         ** by variable values within the demand data associated with forced models. **;
         ******************************************************************************;

         %dataobs (demand_ow_data) ;
         %let demand_ow_obs = &dataobs ;
         %if &dataobs > 0 %then %do;

                 proc datasets lib=work nolist ;
                         delete forced_outest forced_forecast ;
                 quit;


                 proc freq data = demand_ow_data noprint ;
                         table prop_code
                         %do i = 1 %to &num_cat_vars ;
                                 %str(*) &&cat_var_&i
                         %end;
                         %str(*) model_name / out = ow_combos ;
                 run ;


                 ** Output information on prop_code, by_variable groupings to macro variables **;

                 data _null_ ;
                         length whrstr $1024 ;
                         set ow_combos end = eof;
                         ** build a where clause for each grouping **;
                         whrStr = 'lowcase(compress(prop_code)) = lowcase(compress("'!! prop_code !!'"))'
                         %do i = 1 %to &num_cat_vars ;
                                 !! ' and lowcase(compress('!! compress("&&cat_var_&i")
                                 !! ')) = lowcase(compress("'!! compress(&&cat_var_&i) !!'"))'
                         %end;
                         ;
                         call symput('whrstr_'!! left(put(_n_,4.)), whrstr ) ;
                         call symput('modelname_'|| left(put(_n_,4.)), model_name ) ;

                         if eof then call symput ('num_whrstrs', left(put(_n_,4.)) );
                 run;


                 ** Copy the existing hpfspec catalog to a temporary location **;

                 proc copy in= &hpf_spec_libref out = work mt = cat ;
                         select &hpf_spec_catalog_name ;
                 run;


                 ** Loop through the prop_code, by_variable combinations, running hpfengine for each **;

                 %do j = 1 %to &num_whrstrs ;

                         ** Create a selection of the model repository containing just one model name **;

                         proc hpfselect repository = work.&hpf_spec_catalog_name name = modall ;
                                 spec &&modelname_&j / inputmap (symbol = Y var = demand );
                         run;


                         ** Run the HPFSelect Procedure to obtain OUTEST details on the forced model **;

                         proc hpfengine data = demand_ow_data (where = (&&whrstr_&j))
                                 repository = work.&hpf_spec_catalog_name
                                 globalselection = modall
                                 outest = forced_outest_sub
                                 outfor = forced_forecast_sub
                                 out = _null_
                                 back = &History_Window
                                 lead = &Horizon
                                 task = select (criterion = mape holdout = &hold_out_period) ;

                                 by prop_code &by_variables ;
                                 id &date_col interval = day ;
                                 forecast demand ;
                         run;


                         ** Compile the outest and forecast data sets created for one prop_code  **;
                         ** and by_variable grouping.                                            **;

                         proc append base = forced_outest data = forced_outest_sub force; run;

                         proc append base = forced_forecast data = forced_forecast_sub force; run;


                         ** Ensure no duplicate records are added. **;
                         proc datasets lib = work mt = data nolist ;
                                 delete forced_forecast_sub forced_outest_sub ;
                         quit;


                 %end ;


                 ** Add the forced model OUTEST compendium data set to the non-forced model      **;
                 ** OUTEST data set to output parameter estimates table.                         **;

                 data parameter_estimates;
                         length forced $1 ;
                         set non_forced_outest (in = nonf)
                                 forced_outest (in = forc);
                         as_of_date = &rundtm ;
                         
                         
                         if nonf then forced = 'N';
                         else if forc then forced = 'Y';
                 run;


                 ** Add the forced model forecast compendium data set to the non-forced          **;
                 ** model forecast data set.                                                     **;

                 data &output_forecast_table_libref..&output_forecast_table_name ;
                         set non_forced_forecast
                                 forced_forecast ;
                         where &date_col > "&max_date"d ;
                         as_of_date = &rundtm ;
                 run;
                 
         %end ;
         %else %do ;

                 ** If no forced models were specified, add an 'as_of_date' column to the        **;
                 ** outest and forecast data sets that were output by the single run of          **;
                 ** of the hpfengine procedure.                                                  **;

                 data parameter_estimates ;
                         length forced $1 ;
                         set non_forced_outest ;
                         as_of_date = &rundtm ;
                         forced = 'N';
                 run;


                 ** Output the non-forced model forecast data set to the output forecast         **;
                 ** data set.                                                                    **;

                 data &output_forecast_table_libref..&output_forecast_table_name ;
                         set non_forced_forecast ;
                         where &date_col > "&max_date"d ;
                         as_of_date = &rundtm ;
                 run;

                 /*** added on Dec 15, 2009 VASAN   ***/
				  /*** Commented out by JULIA***                
                  proc sort data = non_forced_forecast;
				  by prop_code;
			  
                   data fcst_cap;
				   merge non_forced_forecast hpfsys.cap_table;
				   by prop_code;
				   run;

                  data daily_error  ;
				  format as_of_date yymmdd10. tfh_arvl_stay_dt yymmdd10. ;
                         set fcst_cap;
                         where &date_col <    "&max_date"d ;
                         as_of_date = &rundtm ;
                         
                         daily_err  = 100* abs(actual- predict)/ (cap1 + cap2) ;
                   
                   run;

                   proc sort data = daily_error;
				   by prop_code as_of_date;

                   proc means data= daily_error  noprint;
				   by prop_code as_of_date;
				   var daily_err;
                   output out= HPF_AGG_ERROR (drop = _type_ _freq_ ) mean(daily_err ) = hpf_avg_error  ;
                     **** End of changes   **/
              %end;

         ** Check for success of creation of output forecast table               **;
         %if &syserr > 0 and &syserr ne 4 %then %do ;
                 %let errflg = -1 ;
                 %let errmsg = Unable to create forecast table, &output_forecast_table_libref..&output_forecast_table_name ;
                 %let errmsg = &errmsg in program diagnose_event_remove.sas ;
                 %goto macrend ;
         %end;

         ** Create the Best Model Parameter Model Names update data set.    **;

         proc sort data = parameter_estimates
                    out = parms_names_update (
                          rename = (_model_ = model_name)) nodupkey ;
             by prop_code &by_variables  ;
         run;



         ** Create the Best Model Parameter Estimates update data set.   **;
         proc sort data = parameter_estimates
                 out = parm_ests (drop = prop_code &by_variables
                                rename = (_model_ = model_name) ) nodupkey ;
                 by as_of_date _model_ _parm_;
         run;



         ******************************************************************;
         ** Begin steps to update the Best Model Names data set          **;
         ******************************************************************;

         ** Reorganize the outest data set so that there is one column holding   **;
         ** by variable names, another holding by variable values.               **;

         data trans_parm_ests ;
                 length byvar $32 byvarvalue $64 id $64 name_sub $8;
                 set parms_names_update (keep = as_of_date model_name prop_code
                                          &by_variables _stderr_ forced) ;
                 by prop_code &by_variables ;

                 ** Select the first of repeated records for the same by group **;
                 %if &num_cat_vars > 0 %then
                  if first.&&cat_var_&num_cat_vars %str(;) ;
                 %else
                  if first.prop_code %str(;) ;

                 * Construct an id character variable that uniquely identifies a prop_code,  *;
                 * by-variables group, in order that that variable can later be used to      *;
                 * associate byvar and byvarvalue values with the prop_code, by-variable     *;
                 * group it originally belonged to, to be used when de-normalizing records   *;
                 * of this data set. Also include by-variable names - or at least an excerpt *;
                 * of the names - to ensure that IDs for different by-variable groups that   *;
                 * happen to have similar values can be differentiated from each other.      *;
                 id = compress(prop_code) ;
                 %do i = 1 %to &num_cat_vars ;
                         ** Allow for implicit converson of any numeric By variables to **;
                         ** character values.                                           **;
                         if length(compress("&&cat_var_&i")) > 8 then
                          name_sub = upcase(substr(compress("&&cat_var_&i"),1,8)) ;
                         else name_sub = upcase(compress("&&cat_var_&i")) ;
                         id = compress(id !! name_sub !! &&cat_var_&i) ;
                 %end;

                 byvar = "prop_code";
                 byvarvalue = prop_code ;
                 output ;
                 %do i = 1 %to &num_cat_vars ;
                         byvar = "&&cat_var_&i" ;
                         ** Allow for implicit converson of any numeric By variables to **;
                         ** character values.                                           **;
                         byvarvalue = &&cat_var_&i ;
                         output ;
                 %end;

                 drop prop_code &by_variables name_sub ;

                 rename _stderr_ = error ;

         run;

         proc sort data = trans_parm_ests ;
                 by model_name  ;
         run;


         ** Merge the transposed model names data set with the Candidate Models  **;
         ** data set to add 'model_type' and 'Statement' columns to the data set.**;

         proc sort data = &candidate_models_libref..&candidate_models_table_name ;
                 by model_name model_type ;
         run;

         data trans_parm_statements ;
                 merge   trans_parm_ests (in=parm)
                         &candidate_models_libref..&candidate_models_table_name
                 ;
                 by model_name ;
                 if parm ;
         run;


         ** Further sort the parameter estimates table with model type and       **;
         ** procedure statement values, ahead of updating the historical best    **;
         ** model names data table.                                              **;

         proc sort data = trans_parm_statements ;
                 by as_of_date id byvar byvarvalue ;
         run;



         **************************************************************************;
         ** Update the historical best model names data set.                     **;
         **************************************************************************;

         %if %sysfunc(exist(&best_model_libref..&best_model_names_table)) = 0 %then %do;

                 data &best_model_libref..&best_model_names_table ;
                         set  trans_parm_statements ;
                         by as_of_date id byvar byvarvalue ;
                         format as_of_date mmddyy10. ;
                 run;

                 proc datasets lib = &best_model_libref nolist ;
                         modify &best_model_names_table ;
                         index create comp = (as_of_date id model_name byvar byvarvalue) ;
                         index create no_model = (as_of_date id byvar byvarvalue) ;
                 quit;

         %end;
         %else %do ;
                 data &best_model_libref..&best_model_names_table ;
                         update  &best_model_libref..&best_model_names_table
                                         trans_parm_statements ;
                         by as_of_date id byvar byvarvalue ;
                 run;
         %end ;

         ** Check for success **;
         %if &syserr > 0 and &syserr ne 4 %then %do ;
                 %let errflg = -1 ;
                 %let errmsg = Unable to update the Historical Best Model Names Table, &best_model_libref..&best_model_names_table ;
                 %let errmsg = &errmsg in program diagnose_event_remove.sas ;
                 %goto macrend ;
         %end;
         %else %if &syserr => 4 %then %do ;
                 %let errflg = 1;
                 %let errmsg = Warning generated for update operation of table &best_model_libref..&best_model_names_table ;
                 %let errmsg = &errmsg in program diagnose_event_remove.sas ;
         %end;



         ** Update the Best Model Estimates data set **;


         %if %sysfunc(exist(&best_model_libref..&best_model_details_table)) = 0 %then %do;

                 data &best_model_libref..&best_model_details_table ;
                         set  parm_ests  ;
                         by as_of_date model_name _parm_ ;
                         format as_of_date mmddyy10. ;
                 run;

                 proc datasets lib = &best_model_libref nolist ;
                         modify &best_model_details_table ;
                         index create comp = (as_of_date model_name _parm_ ) ;
                 quit;

         %end;
         %else %do ;

                 data &best_model_libref..&best_model_details_table ;
                         update  &best_model_libref..&best_model_details_table
                                 parm_ests ;
                         by as_of_date model_name _parm_ ;
                 run;

         %end;


         ** Check for success **;
         %if &syserr > 0 and &syserr ne 4 %then %do ;
                 %let errflg = -1 ;
                 %let errmsg = Unable to update the Historical Best Model Details Table, &best_model_libref..&best_model_details_table ;
                 %let errmsg = &errmsg in program diagnose_event_remove.sas ;
                 %goto macrend ;
         %end;
         %else %if &syserr => 4 %then %do ;
                 %let errflg = 1;
                 %let errmsg = Warning generated for update operation of table &best_model_libref..&best_model_details_table ;
                 %let errmsg = &errmsg in program diagnose_event_remove.sas ;
         %end;



         ** Look for prop_codes, by_variable groupings in the input data that are not    **;
         ** represented in the output best model data.                                   **;

         data groups_output ;
              length pass_fail $4 status $80 ;
              merge parms_names_update (in = inparms keep = prop_code &by_variables model_name )
                    input_combos (in = incombo) ;
              retain prop_code_count fail_count 0 ;
              by prop_code &by_variables;

              if incombo and not inparms then do ;
                 pass_fail = 'Fail';
                 status = 'Not represented in Diagnosis Output';
              end;
              else if incombo and inparms then do;
                  pass_fail = 'Pass';
                  if model_name = 'ESMBEST' then status = "Did not converge";
              end;

              diagnose_or_forecast = 'D' ;
              mode = compress("&mode") ;
              Group_or_Transient = compress("&group_or_transient") ;
              rundtm = input("&rundatetm", datetime23.) ;
              keep prop_code &by_variables pass_fail status diagnose_or_forecast mode
                   group_or_transient rundtm status ;
         run;

         ** Update the prop_code_Status_table with that pass_fail information. **;                                                          **;

         %property_code_status_update (
             groups_output,
             &status_table_libref,
             &status_table_name,
             USE
         );



         ** Merge the status table with the data set containing the list of      **;
         ** prop_codes to process, to look for further missing prop_codes.       **;
         data prop_codes_missing ;
             merge   groups_output (in = gout
                                    %if &num_cat_vars > 0 %then drop = &by_variables ;
                                    )
                     &prop_code_list_table_libref..&prop_code_list_table_name (in=proclist) ;
             by prop_code ;
             if proclist and not gout then do;
                 diagnose_or_forecast = 'D' ;
                 mode = compress("&mode") ;
                 Group_or_Transient = compress("&group_or_transient") ;
                 rundtm = input("&rundatetm",datetime23.) ;
                 pass_fail = 'Fail' ;
                 status = "Property Code not found in Diagnosis Output" ;
                 output;
             end;
         run;

         %dataobs(prop_codes_missing);
         %if &dataobs > 0 %then %do;
             %property_code_status_update (
                 prop_codes_missing,
                 &status_table_libref,
                 &status_table_name,
                 ALL
             );

         %end;




         ** Clean up ** ;
            /*******   temporarily commented out VASAN 
         proc datasets lib = work nolist ;
                 delete
                 %if &demand_ow_obs > 0 %then demand_ow_data  ;
                 non_forced_outest non_forced_forecast parms_names_update parameter_estimates
                 trans_parm_ests trans_parm_statements parm_ests groups_output input_combos
                 %if &dataobs > 0 %then forced_outest forced_forecast sorted_forced_forecast
                                        forced_models ow_combos;
                 forecast prop_codes_missing;
         quit;

         proc datasets lib = &work2_libref nolist ;
                 delete demand_data  ;
         quit;
          ****************/
 %macrend:


 %mend;
