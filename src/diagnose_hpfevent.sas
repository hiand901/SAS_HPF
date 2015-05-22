 ************************************************************************************;
 ** Program: Diagnose_HPFEvent.sas                                                 **;
 ** Purpose: This program uses the SAS HPFEngine procedure to find the best        **;
 **          models and output forecast demand values, if the 'Run Diagnose'       **;
 **          program that calls this program was set up to run using               **;
 **          'HPF Events' as the method for dealing with Events.                   **;
 **                                                                                **;
 ** Design Module: Section 3.7.2 of the HPF Forecast System Design Document        **;
 ** By:            Andrew Hamilton, July 7th 2008.                                 **;
 **                                                                                **;
 ** Required Global Macro Variables:                                               **;
 ** all_model_names: A macro variable built by the build_hpf_spec program          **;
 **                  that contains all model names.                                **;
 ** num_cat_vars: The number of By Variables used in diagnosis.                    **;
 ** cat_vars_1 - cat_vars_N: By Variables 1 to N, where N equals                   **;
 **                          num_cat_vars                                          **;
 **                                                                                **;
 **                                                                                **;
 ** Output Data Sets:                                                              **;
 ** Best Model Names data set - Contains names of best diagnosed models along with **;
 **                      prop_code, by-variable, as_of_date, and _error_ values.   **;
 **                      The prop_code and other by-variables related to each      **;                                                      **;
 **                      model are held in 'id', byvar, and byvarvalue columns.    **;
 ** Best Model 'Parm Ests' data set - Contains names of best diagnosed models      **;
 **                      along with as_of_date, and parameter estimates produced   **;
 **                      by the HPFEngine procedure and sent to 'outest' data set. **;
 ** Output Error Table - Holds HPF-calculated error values along with a prop_code  **;
 **                      column, and a column for each by-variable.                **;
 **                                                                                **;
 ************************************************************************************;

 %macro diagnose_hpfevent (
                 mode,
                 group_or_transient,
                 input_demand_data_libref,
                 input_demand_data_table,
                 hpf_spec_libref,
                 hpf_spec_catalog_name,
                 best_model_table_libref,
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
                 hpf_event_table_libref,
                 hpf_event_table_name,
                 output_forecast_table_libref,
                 Output_Forecast_Table_Name,
                 prop_code_col,
                 demand_col,
                 date_col,
                 by_variables,
                 event_id_col,
                 hold_out_period,
                 shift_Hold_Out_Period,
                 History_Window,
                 Horizon,
                 rundtm,
                 rundatetm
         );



     ** Find the input prop_code and by variables that are represented in the input data **;
     ** These will be used to check for missing combos in the output best model data     **;
     ** of this program. Also get the related max_date per combo.                        **;

     proc summary data = &input_demand_data_libref..&input_demand_data_table
             nway noprint ;
         class &prop_code_col &by_variables ;
         var &Date_col ;
         output out = input_combos (drop = _freq_ _type_) max = max_date ;
      run;



     ** Find the highest max_date in the data **;
     proc sort data = input_combos out = combos_sorted ;
         by descending max_date ;
     run;


     ** Write out the max date found in the data to a macro variable **;
     data _null_;
         set combos_sorted ;
         call symput ('all_max_date', put(max_date, 8.)) ;
         stop ;
     run;



     **********************************************************************************;
     ** If the shift_hold_out_period parameter is non-zero,                          **;
     ** Find the maximum value of date values in the input demand data, for each     **;
     ** prop_code and by_variables grouping.                                         **;                                          **;
     **********************************************************************************;

     %if &shift_hold_out_period ne 0 or &hold_out_period ne 0 %then %do ;

          proc sort data = &input_demand_data_libref..&input_demand_data_table
                     out = demand_data_hold_out;
              by &prop_code_col &by_variables ;
          run;


          data demand_data_hold_out ;
              merge   demand_data_hold_out
                      input_combos ;
              by &prop_code_col &by_variables ;
              %if &hold_out_period = 0 %then
              if &date_col > (max_date - &shift_hold_out_period) then delete %str(;) ;
              %else %do;
                   %if &shift_hold_out_period = 0 %then
                   if &date_col > (max_date - &hold_out_period)  %str(;) ;
                   %else %do;
                       if &date_col > (max_date - &hold_out_period - &shift_hold_out_period)
                       /* Only apply following restriction for Group, since Transient
                          will use a single cut off date for all by groups, based on the
                          highest max_date minus the shift_holdout value                 */
                       %if &group_or_transient = G %then
                        and &date_col <= (max_date - &shift_hold_out_period) ;
                       ;
                   %end;
              %end;
          run;

     %end ;




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
                     set sorted_forced_models ;
                     retain prop_code &by_variables ;

             by model_name byvar byvarvalue ;

             if first.model_name then do ;
                 prop_code = '' ;
                 %do i = 1 %to &num_cat_vars ;
                     &&cat_var_&i = '' ;
                 %end;
             end;

            if compress(lowcase(byvar)) = lowcase(compress("&prop_code_col"))
             then prop_code = byvarvalue ;

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


         ** Merge the forced models data set with the input prop_code, by_variables combos    **;

         data input_combos ;
             length forcedmodel $1 ;
             merge input_combos (in = incombo
             %if &prop_code_col ne prop_code %then
              rename = (&prop_code_col = prop_code) ;
             )
             forced_models (in = forcemod keep = prop_code &by_variables model_name )
             end = eof;

             by prop_code &by_variables ;

             if _n_ = 1 then numcombos = 0 ;

             if forcemod then forcedmodel = 'Y' ;
             else forcedmodel = 'N' ;

             if incombo then do ;
                 numcombos + 1 ;
                 output ;
             end;

             if eof then call symput ('num_combos', put(numcombos, 4.)) ;

         run;

     %end;
     %else %do ;

         data input_combos ;
             length forcedmodel $1 ;
             set input_combos (in = incombo
                 %if &prop_code_col ne prop_code %then
                     rename = (&prop_code_col = prop_code) ;
             )
             end = eof;

             by prop_code &by_variables ;

             if _n_ = 1 then numcombos = 0 ;

             forcedmodel = 'N' ;
             model_name = '' ;

             numcombos + 1;

             if eof then call symput ('num_combos', put(numcombos, 4.)) ;

         run;

     %end;



     ******************************************************************************;
     ** Create a rename string to be applied to demand data, in the case where   **;
     ** the demand and prop_code columns are not named demand and prop_code.     **;
     ******************************************************************************;

     %let rename_flg = 0;
     %if &demand_col ne demand or &prop_code_col ne prop_code %then %do ;
         %let rename_flg = 1 ;
         %let rename_str = rename %str(=) ( ;
         %if &demand_col ne demand %then %let rename_str = &rename_str &demand_col %str(=) demand ;
         %if &prop_code_col ne prop_code %then %let rename_str = &rename_str &prop_code_col %str(=) prop_code ;
         %let rename_str = &rename_str ) ;
     %end;



     ** Copy the existing hpfspec catalog to a temporary location **;

     proc copy in= &hpf_spec_libref out = work mt = cat ;
         select &hpf_spec_catalog_name ;
     run;



     ** Loop through the prop_code, by_variable combinations, running hpfengine for each **;

     %do j = 1 %to &num_combos ;

         ** Output information on prop_code, by_variable groupings to macro variables **;

         data _null_ ;
             length whrstr $512 ;
             pointobs = &j ;
             set input_combos point = pointobs;
             ** build a where clause for each grouping **;
             whrStr = 'lowcase(compress(prop_code)) = lowcase(compress("'!! compress(prop_code) !!'"))' ;

             call symput('event_whrstr', trim(left(whrstr)) ) ;

             %do i = 1 %to &num_cat_vars ;
                 whrstr = trim(left(whrstr)) !! ' and lowcase(compress('!! compress("&&cat_var_&i")
                          !! ')) = lowcase(compress("'!! compress(&&cat_var_&i) !!'"))' ;
             %end;

             call symput('whrstr', trim(left(whrstr)) ) ;
             call symput('modelname', model_name ) ;
             call symput('pc', compress(prop_code)) ;
             call symput('max_date', put(&all_max_date - &shift_hold_out_period, date7.)) ;
             call symput('forced', forcedmodel ) ;

             stop ;
         run;



         ************************************************************************;
         ** Get the demand data subset for the current prop_code, by_variables **;
         ************************************************************************;

         ** Run proc timeseries to fill in missing dates in the demand data **;
         proc timeseries data=
             %if &shift_hold_out_period ne 0 or &hold_out_period ne 0 %then
                    demand_data_hold_out ;
             %else &input_demand_data_libref..&input_demand_data_table ;
                     ( where =(&whrstr)
             %if &rename_flg = 1 %then &rename_str ;
                     )
             out=current_combo_demand;
             id &date_col
             interval = DAY
             end = "&max_date"d
             accumulate = total
             setmiss = 0 ;
             by prop_code &by_variables ;
             var &demand_col ;
         run;



         ***********************************************************************;
         ** Obtain a subset of the events data set for the current prop_code  **;
         ***********************************************************************;

         data hpf_event ;
             set &hpf_event_table_libref..&hpf_event_table_name (where = (&event_whrstr)) ;
         run;


         %dataobs(hpf_event) ;

         %if &dataobs > 0 %then %do ;
             ** Get the list of event ids associated with the current prop_code   **;
             proc freq data = hpf_event noprint;
                 tables _name_ / out = event_id_list ;
             run;


             ** Write out all the event ids related to a prop code to macro variables,  **;
             ** for later use by the HPFEVENTS procedure, below.                        **;
             data _null_ ;
                 set event_id_list end = eof ;

                 event_count + 1 ;
                 call symput('eventid'!! left(put(event_count,4.)), compress(_name_) );

                 if eof then call symput ('num_event_ids', compress(put(event_count, 4.)) ) ;
             run;
         %end;
         %else %let num_event_ids = 0 ;

         /*
             ** Create a combined event that utilizes all events ** ;
             ** defined for the current prop_code                ** ;

             proc hpfevents data = current_combo_demand ;
                id &date_col interval = day ;
                eventdata  in= hpf_event ;
                eventcomb all_&pc._events = &event_name_str / rule = max ;
                eventdata out = hpf_all_events ;
                eventdummy out = hpf_all_events_dummy ;
             run;
         */


         %if &forced = Y %then %do ;
             ** Create a selection of the model repository containing just one model name,  **;
             ** for forced models, including all combined events related to the current     **;
             ** prop_code, in the eventmap option.                                          **;
             proc hpfselect repository = work.&hpf_spec_catalog_name name = modall ;
                 spec &modelname /
                      %do m = 1 %to &num_event_ids ;
                          eventmap (symbol=none event = &&eventid&m )
                      %end;
                      inputmap (symbol = Y var = demand ) ;
             run;
         %end;
         %else %do ;
             ** If the prop_code, by variables grouping is not related to a forced model    **;
             ** name, create a selection of the model repository that includes all possible **;
             ** model names, and including all related combined events.                     **;
             proc hpfselect repository = work.&hpf_spec_catalog_name name = modall ;
                 spec &all_model_names1 &all_model_names2 &all_model_names3 /
                      %do m = 1 %to &num_event_ids ;
                          eventmap (symbol=none event = &&eventid&m )
                      %end;
                      inputmap (symbol = Y var = demand ) ;
             run;

         %end;



         ** Run the HPFEngine Procedure to obtain OUTEST details on selected or forced models **;

         proc hpfengine data = current_combo_demand

             repository = work.&hpf_spec_catalog_name

             globalselection = modall
             inevent = hpf_event
             outest = outest_sub
             outfor = forecast_sub
             out = _null_
             back = &History_Window
             lead = &Horizon
             task = select (criterion = mae holdout = &hold_out_period) ;

             by prop_code &by_variables ;
             id &date_col interval = day ;
             forecast demand ;
         run;


         ** Compile the outest and forecast data sets created for one prop_code  **;
         ** and by_variable grouping.                                            **;
         ** Also add the as_of_date value to the parameter_estimates data set.   **;

         %if &j = 1 %then %do ;

             data parameter_estimates ;
                 length forced $1 ;
                 set outest_sub;
                 forced = compress("&forced") ;
                 as_of_date = &rundtm ;
             run;

         %end;
         %else %do ;

             data parameter_estimates ;
                 set parameter_estimates
                 outest_sub (in=outes) ;
                 if outes then forced = compress("&forced") ;
                 as_of_date = &rundtm ;
             run;

         %end;

         proc append base = forecast data = forecast_sub; run;

         ** Ensure no duplicate records are added. **;

         proc datasets lib = work mt = data nolist ;
             delete hpf_event  forecast_sub outest_sub
                    current_combo_demand ;
         quit;

     %end ;



     ** Output the forecast data set to the output forecast          **;
     ** data set.                                                    **;

     data &output_forecast_table_libref..&output_forecast_table_name ;
             set forecast ;
             where &date_col > "&max_date"d ;
             as_of_date = &rundtm ;
     run;


     ** Check for success of creation of output forecast table **;
     %if &syserr > 0 and &syserr ne 4 %then %do ;
             %let errflg = -1 ;
             %let errmsg = Unable to create forecast table &output_forecast_table_libref..&output_forecast_table_name ;
             %let errmsg = &errmsg in program diagnose_event_remove.sas ;
             %goto macrend ;
     %end;





     ** Create the Best Model Parameter Model Names update data set.    **;

     proc sort data = parameter_estimates
                out = parms_names_update (
                      rename = (_model_ = model_name)) nodupkey ;
         by _model_ prop_code &by_variables ;
     run;


     ** Ensure only one record per prop_code, by_variable group. **;
     data parms_names_update ;
        set parms_names_update ;
        by model_name prop_code &by_variables ;
        %if &num_cat_vars > 0 %then
         if first.&&cat_var_&num_cat_vars %str(;) ;
        %else
         if first.prop_code %str(;) ;
     run;


     ** Create the Best Model Parameter Estimates update data set.   **;
     proc sort data = parameter_estimates
                out = parm_ests (drop = prop_code &by_variables
                      rename=(_model_ = model_name) ) nodupkey ;
         by _model_ _parm_;
    run;



    *********************************************************;
    ** Begin steps to update the Best Model Names data set **;
    *********************************************************;

    ** Reorganize the outest data set so that there is one column holding   **;
    ** by variable names, another holding by variable values.               **;

     data trans_parm_ests ;
         length byvar $32 byvarvalue $64 id $64 name_sub $8 ;
         set parms_names_update (keep = as_of_date model_name prop_code
                                 &by_variables _stderr_) ;
         by model_name prop_code &by_variables ;

         ** Select the first of repeated records for the same by group      **;
         %if &num_cat_vars > 0 %then
          if first.&&cat_var_&num_cat_vars %str(;) ;
         %else
          if first.prop_code %str(;) ;

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


     ** Further sort the parameter estimates table with model type and                **;
     ** procedure statement values, ahead of updating the historical best             **;
     ** model names data table.                                                       **;

     proc sort data = trans_parm_statements ;
             by as_of_date id byvar byvarvalue  ;
     run;



     ** Update the historical best model names data set.                              **;

     %if %sysfunc(exist(&best_model_table_libref..&best_model_names_table)) = 0 %then %do;

             data &best_model_table_libref..&best_model_names_table ;
                     set trans_parm_statements;
                     by as_of_date id byvar byvarvalue ;
                     format as_of_date mmddyy10. ;
             run;

             proc datasets lib = &best_model_table_libref nolist ;
                     modify &best_model_names_table ;
                     index create comp = (as_of_date id byvar byvarvalue model_name) ;
                     index create no_model = (as_of_date id byvar byvarvalue) ;
             quit;

     %end;
     %else %do ;
             data &best_model_table_libref..&best_model_names_table ;
                     update  &best_model_table_libref..&best_model_names_table
                             trans_parm_statements ;
                     by as_of_date id byvar byvarvalue ;
             run;
     %end ;


     ** Check for success **;
     %if &syserr > 0 and &syserr ne 4 %then %do ;
             %let errflg = -1 ;
             %let errmsg = Unable to update the Historical Best Model Names Table &best_model_libref..&best_model_names_table ;
             %let errmsg = &errmsg in program diagnose_hpfevent.sas ;
             %goto macrend ;
     %end;
     %else %if &syserr => 4 %then %do ;
             %let errflg = 1;
             %let errmsg = Warning generated for update operation of table &best_model_libref..&best_model_names_table ;
             %let errmsg = &errmsg in program diagnose_hpf_event.sas ;
     %end;



     ** Update the Best Model Estimates data set **;

     %if %sysfunc(exist(&best_model_table_libref..&best_model_details_table)) = 0 %then %do;

             data &best_model_table_libref..&best_model_details_table ;
                     set parm_ests ;
                     by as_of_date model_name _parm_;
                     format as_of_date mmddyy10. ;
             run;

             proc datasets lib = &best_model_table_libref nolist ;
                     modify &best_model_details_table ;
                     index create comp = (as_of_date model_name _parm_) ;
             quit;

     %end;
     %else %do ;

             data &best_model_table_libref..&best_model_details_table ;
                     update  &best_model_table_libref..&best_model_details_table
                             parm_ests ;
                     by as_of_date model_name _parm_;
             run;

     %end;


     ** Check for success **;
     %if &syserr > 0 and &syserr ne 4 %then %do ;
         %let errflg = -1 ;
         %let errmsg = Unable to update the Historical Best Model Details Table &best_model_table_libref..&best_model_details_table;
         %let errmsg = &errmsg in program diagnose_event_remove.sas ;
         %goto macrend ;
     %end;
     %else %if &syserr => 4 %then %do ;
         %let errflg = 1;
         %let errmsg = Warning generated for update operation of table &best_model_table_libref..&best_model_details_table ;
         %let errmsg = &errmsg in program diagnose_event_remove.sas ;
     %end;



     **********************************************************************************;
     ** Look for prop_codes, by_variable groupings in the input data that are not    **;
     ** represented in the output best model data.                                   **;
     **********************************************************************************;

     proc sort data = parms_names_update ;
         by prop_code &by_variables ;
     run;



     data groups_output ;
         length pass_fail $4 status $80 ;
         merge parms_names_update (in = inparms keep = prop_code &by_variables )
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
             rundtm = input("&rundtm",datetime23.) ;
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

     proc datasets lib = work nolist ;
             delete max_dates
             %if &shift_holdout_period > 0 %then demand_data_holdout ;
             outest sorted_forced_models forced_models hpf_event forecast parameter_estimates
             parms_names_update trans_parm_ests trans_parm_statements parm_ests groups_output input_combos
             forecast prop_codes_missing;
     quit;



 %macrend:


 %mend;
