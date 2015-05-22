**************************************************************************************;
** PROGRAM: post_forecast_event_dmnd_replace.sas                                    **;
** PURPOSE: Replace forecast demand values in post-forecast data that co-incide     **;
**          with event dates with averages of demand from similar days in the past  **;
**          for the same event.                                                     **;
** BY:          Andrew Hamilton.                                                    **;
**----------------------------------------------------------------------------------**;
**                                                                                  **;
** INPUT DATA                                                                       **;
**  Input Demand Data:                                                              **;
**  Libref.Name - Defined by parameter values                                       **;
**  Columns - Columns representing Property Code, Demand, Stay Date, Segment,       **;
**                and possibly other category variables listed in one of the        **;
**                parameters to this program.                                       **;
**                                                                                  **;
**  Input Event Table:                                                              **;
**  Libref.Name - Defined by parameter values                                       **;
**  Columns - Columns representing Property Code, Type, Event ID, and Event Start   **;
**            Date, and Event End Date.                                             **;
**                                                                                  **;
**  Input Forecast Table:                                                           **;
**  Libref.Name - Defined by parameter values                                       **;
**  Columns - Columns representing Property Code, Demand, Date, and possibly other  **;
**                        category variables listed in the 'by_variables' parameter.**;                                    **;
**                                                                                  **;
** OUTPUT DATA                                                                      **;
**  Amended Forecast Demand Table:                                                  **;
**  Libref.Name - Defined by parameter values,                                      **;
**      Columns - PROP_CODE, DATE, Segment, Possibly other category variables,      **;
**                        Amended Demand.                                           **;
**                                                                                  **;
**----------------------------------------------------------------------------------**;
** PARAMETERS                                                                       **;
**----------------------------------------------------------------------------------**;
** POSITIONAL PARAMETERS - The following parameters do not have defaults and must   **;
**                         be supplied in any call of the event_demand_replace      **;
**                         macro program, in the order shown below.                 **;
**----------------------------------------------------------------------------------**;
** input_demand_table_libref - The SAS Libref assigned to the library /             **;
**                             database in which the input table is located.        **;
** input_demand_table_name - Name of the input demand table.                        **;                         **;
** input_forecast_demand_libref - The SAS Libref assigned to the library /          **;
**                                database in which the input table is located.     **;
** input_forecast_demand_table - Name of the input table.                           **;                           **;
** event_table_libref - The SAS Libref assigned to the library / database           **;
**                      in which the event table is located.                        **;
** event_table_name - Name of the events table.                                     **;
** output_table_libref - The SAS Libref assigned to the library / database          **;
**                       in which the output table is located.                      **;
** output_table_name - Name of the output table.                                    **;
** n_max_data_points - the number of similar event days to be used in               **;
**                     calculating replacement demand values for forecast data.     **;
**                                                                                  **;
** By_Variables -  default of 'segment'. Multiple values should be                  **;
**                 separated by spaces.                                             **;
** Demand_Prop_Code_Col                                                             **;
** Demand_Date_Col                                                                  **;
** Demand_Col                                                                       **;
** Event_Prop_Code_Col                                                              **;
** Event_Type_Col                                                                   **;
** Event_ID_Col                                                                     **;
** Event_Start_Date_Col                                                             **;
** Event_End_Date_Col                                                               **;
** Forecast_Prop_Code_Col                                                           **;
** Forecast_Date_Col                                                                **;
** Forecast_Demand_Col                                                              **;
**                                                                                  **;
**************************************************************************************;

%macro post_forecast_event_dmnd_replace (
                        input_demand_table_libref,
                        input_demand_table_name,
                        input_forecast_demand_libref,
                        input_forecast_demand_table,
                        event_table_libref,
                        event_table_name,
                        output_table_libref,
                        output_table_name,
                        n_max_data_points,
                        by_variablest,
                        group_or_transient,
                        demand_prop_code_col,
                        demand_date_col,
                        demand_col,
                        event_prop_code_col,
                        event_type_col,
                        event_id_col,
                        event_start_date_col,
                        event_end_date_col,
                        forecast_prop_code_col,
                        forecast_date_col,
                        forecast_demand_col
 ) ;

** Initialize the msg macro variable **;
%global msg ;
%let msg = ;


** Determine if the input historical demand table is the same table as the      **;
** input forecast demand table, and set a flag based on the result.             **;
%if &input_demand_table_libref.&input_demand_table_name ne
        &input_forecast_demand_libref.&input_forecast_demand_table
%then %let same_table = 0;
%else %let same_table = 1;



************************************************;
** CHECK THE VALIDITY OF THE INPUT PARAMETERS **;
************************************************;

** Check the validity of the input_table_libref parameter **;
%let rc = %sysfunc(libref(&input_demand_table_libref)) ;
%if &rc > 0 %then %do;
        %let msg = &input_demand_table_libref Libname unassigned. ;
        %let errflg = -1 ;
        %goto macrend ;
%end;


** Check the validity of the input_table_libref parameter **;
%if &input_forecast_demand_libref ne %str(work) and
        %lowcase(&input_forecast_demand_libref) ne %lowcase(&input_demand_table_libref) %then %do;
        %let rc = %sysfunc(libref(&input_forecast_demand_libref)) ;
        %if &rc > 0 %then %do;
                %let msg = &input_forecast_demand_libref Libname unassigned. ;
                %let errflg = -1 ;
                %goto macrend ;
        %end;
%end;


** Check the validity of the output_table_libref parameter **;
%if &output_table_libref ne %str(work) and
 %index(%lowcase(&input_demand_table_libref.&input_forecast_demand_libref), %lowcase(&output_table_libref)) = 0
%then %do;
        %let rc = %sysfunc(libref(&output_table_libref)) ;
        %if &rc > 0 %then %do;
                %let msg = &output_table_libref Libname unassigned. ;
                %goto macrend ;
        %end;
%end;


** Check the validity of the event_table_libref parameter **;
%if &event_table_libref ne %str(work) and
        %index(%lowcase(&input_demand_table_libref.&output_table_libref.&input_forecast_demand_libref),
        %lowcase(&event_table_libref)) = 0 %then %do;
        %let rc = %sysfunc(libref(&event_table_libref)) ;
        %if &rc > 0 %then %do;
                %let msg = &event_table_libref Libname unassigned. ;
                %let errflg = -1 ;
                %goto macrend ;
        %end;
%end;



** Check the validity of the input demand table name then check the number of records   **;
** in the table, and whether the expected columns are found in the table.               **;
%let dsid = %sysfunc(open(&input_demand_table_libref..&input_demand_table_name, i)) ;
%if &dsid = 0 %then %do;
        %let msg = Unable to open input table &input_demand_table_libref..&input_demand_table_name ;
        %let errflg = -1 ;
        %goto macrend ;
%end;
%else %do;
        ** Check the number of obs in the input demand table, and check whether the column names **;
        ** given in the input parameters to this program are found in the table.                 **;
        %let obsknown = %sysfunc(attrn(&dsid, ANOBS));
        %if &obsknown = 1 %then %do ;
                %let numobs = %sysfunc(attrn(&dsid,NLOBS));
                ** Check the columns **;
                %let staydtcolid = %sysfunc(varnum(&dsid,&demand_date_col)) ;
                %let propcdcolid = %sysfunc(varnum(&dsid,&demand_prop_code_col)) ;
                %let demandcolid = %sysfunc(varnum(&dsid,&demand_col)) ;
                %do i = 1 %to &num_cat_vars ;
                        %let cvar_colid_&i = %sysfunc(varnum(&dsid, &&cat_var_&i )) ;
                %end;
                %let dsid = %sysfunc(close(&dsid)) ;

                %if &numobs = 0 %then %do;
                        %let msg = Input data set has 0 records ;
                       %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %else %if &staydtcolid = 0 %then %do ;
                        %let msg = Input Demand data set does not have a &demand_date_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %else %if &propcdcolid = 0 %then %do ;
                        %let msg = Input Demand data set does not have a &demand_prop_code_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %else %if &demandcolid = 0 %then %do ;
                        %let msg = Input Demand data set does not have a &demand_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %do i = 1 %to &num_cat_vars ;
                        %if &&cvar_colid_&i = 0 %then %do ;
                                %let msg = Input Demand data set does not have a &&cat_var_&i column;
                                %let errflg = -1 ;
                                %goto macrend ;
                        %end;
                %end;

        %end;
        %let dsid = %sysfunc(close(&dsid)) ;
%end;


** Check the validity of the event table name, then check the number of records in the  **;
** table, and whether the expected columns are found in the table.                      **;
%let dsid = %sysfunc(open(&event_table_libref..&event_table_name, i)) ;
%if &dsid = 0 %then %do;
        %let msg = Unable to open event table &event_table_libref..&event_table_name;
        %let errflg = -1 ;
        %goto macrend ;
%end;
%else %do;
        ** Check the number of obs in the input event table **;
        %let obsknown = %sysfunc(attrn(&dsid, ANOBS));
        %if &obsknown = 1 %then %do ;
                %let numobs = %sysfunc(attrn(&dsid, NLOBS));
                ** Check the columns **;
                %let type_colid = %sysfunc(varnum(&dsid,&event_type_col)) ;
                %let propcdcolid = %sysfunc(varnum(&dsid,&event_prop_code_col)) ;
                %let startdtcolid = %sysfunc(varnum(&dsid,&event_start_date_col)) ;
                %let enddtcolid = %sysfunc(varnum(&dsid,&event_end_date_col)) ;
                %let eventcolid = %sysfunc(varnum(&dsid,&event_id_col)) ;
                %if &numobs = 0 %then %do;
                        %let msg = Event data set has 0 records ;
                        %let errflg = 1 ;
                        %goto macrend ;
                %end;
                %else %if &type_colid = 0 %then %do ;
                        %let msg = Event data set does not have a &event_type_col column;
                        %let errflg = 1 ;

                %end;
                %else %if &propcdcolid = 0 %then %do ;
                        %let msg = Event data set does not have a &event_prop_code_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %else %if &startdtcolid = 0 %then %do ;
                        %let msg = Event data set does not have a &event_start_date_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %else %if &enddtcolid = 0 %then %do ;
                        %let msg = Event data set does not have a &event_end_date_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
                %else %if &eventcolid = 0 %then %do ;
                        %let msg = Event data set does not have a &event_id_col column;
                        %let errflg = -1 ;
                        %goto macrend ;
                %end;
        %end;
        %let dsid = %sysfunc(close(&dsid)) ;
%end;



** Check the validity of the input forecast demand table name check the number of       **;
** records in the table, and whether the expected columns are found in the table.       **;
%if &same_table = 0 %then %do;

        %let dsid = %sysfunc(open(&input_forecast_demand_libref..&input_forecast_demand_table, i)) ;
        %if &dsid = 0 %then %do;
                %let msg = Unable to open event table &input_forecast_demand_libref..&input_forecast_demand_table;
                %goto macrend ;
        %end;
        %else %do;
                ** Check the number of obs in the input event table **;
                %let obsknown = %sysfunc(attrn(&dsid, ANOBS));
                %if &obsknown = 1 %then %do ;
                        %let numobs = %sysfunc(attrn(&dsid, NLOBS));
                        ** Check the columns **;
                        %let propcdcolid = %sysfunc(varnum(&dsid,&forecast_prop_code_col)) ;
                        %let dtcolid = %sysfunc(varnum(&dsid,&forecast_date_col)) ;
                        %let demandcolid = %sysfunc(varnum(&dsid,&forecast_demand_col)) ;
                        %do i = 1 %to &num_cat_vars ;
                                %let cvar_colid_&i = %sysfunc(varnum(&dsid, &&cat_var_&i )) ;
                        %end;
                        %if &numobs = 0 %then %do;
                                %let errflg = -1 ;
                                %let msg = Forecast data set has 0 records ;
                                %goto macrend ;
                        %end;
                        %else %if &propcdcolid = 0 %then %do ;
                                %let errflg = -1 ;
                                %let msg = Forecast Demand set does not have a &forecast_prop_code_col column;
                                %goto macrend ;
                        %end;
                        %else %if &dtcolid = 0 %then %do ;
                                %let errflg = -1 ;
                                %let msg = Forecast Demand data set does not have a &forecast_date_col column;
                                %goto macrend ;
                        %end;
                        %else %if &demandcolid = 0 %then %do ;
                                %let errflg = -1 ;
                                %let msg = Forecast Demand data set does not have a &forecast_demand_col column;
                                %goto macrend ;
                        %end;
                        %do i = 1 %to &num_cat_vars ;
                                %if &&cvar_colid_&i = 0 %then %do ;
                                        %let errflg = -1 ;
                                        %let msg = Input Demand Forecast data set does not have a &&cat_var_&i column;
                                        %goto macrend ;
                                %end;
                        %end;
                %end;
                %let dsid = %sysfunc(close(&dsid)) ;
        %end;
%end;



** Prepare a rename string for the output sorted demand forecast table, in order        **;
** that standard column names can be used in the program.                               **;
%let rename_str = %str() ;
%if %lowcase(&forecast_prop_code_col) ne %str(prop_code) %then
%let rename_str = &forecast_prop_code_col %str(=) prop_code ;
%if %lowcase(&forecast_date_col) ne %str(staydate) %then
%let rename_str = &rename_str &demand_date_col %str(=) staydate ;
%if %lowcase(&forecast_demand_col) ne %str(demand) %then
%let rename_str = &rename_str &demand_col %str(=) demand ;



*****************************;
** END OF PARAMETER CHECKS **;
*****************************;



***************************************************************;
** BEGIN APPLYING DEMAND REPLACEMENT RULES TO THE INPUT DATA **;
***************************************************************;


** Pre-process the Event data set for later merging with the demand data set **;
%let rename_str = %str() ;
%if %lowcase(&event_prop_code_col) ne %str(prop_code) %then
%let rename_str = &event_prop_code_col %str(=) prop_code ;
%if %lowcase(&event_id_col) ne %str(event_id) %then
%let rename_str = &rename_str &event_id_col %str(=) event_id ;

data exploded_events
        %if %length(&rename_str) > 1 %then (rename = (&rename_str)) %str(;) ;
        ;
        set &event_table_libref..&event_table_name;

        day_within_event = 0 ;

        do j = &event_start_date_col to &event_end_date_col ;
                staydate = j ;
                day_within_event + 1 ;
                output ;
        end;
        format staydate yymmdd10. ;
        keep staydate &event_prop_code_col &event_id_col day_within_event ;
run;


proc sort data = exploded_events nodupkey;
        by prop_code staydate ;
run;


** Prepare the input summarized demand history data for joining with the event data **;

proc sort data = &input_demand_table_libref..&input_demand_table_name
                                 (keep = &demand_prop_code_col &demand_date_col &by_variables &demand_col
                                %if &same_table = 1 %then &forecast_demand_col ;
                                  )
                        out = demand_history

                        %if %lowcase(&demand_date_col) ne staydate or
                        %lowcase(&demand_prop_code_col) ne prop_code or
                        %lowcase(&demand_col) ne demand %then %do;
                        ( rename = (
                        %if %lowcase(&demand_date_col) ne staydate %then
                                &demand_date_col = staydate ;
                        %if %lowcase(&demand_prop_code_col) ne prop_code %then
                                &demand_prop_code_col = prop_code ;
                        %if %lowcase(&demand_col) ne demand %then
                                &demand_col = demand ;
                        ))
                %end;
                ;

        by &demand_prop_code_col &demand_date_col &by_variables ;
run;



** Merge the events data with the input demand history table **;

data demand_events
        %if &same_table = 1 %then %do;
                forecast_demand_events
                %if &forecast_demand_col ne demand %then (rename =(&forecast_demand_col = demand)) ;
        %end;
        ;

        merge   demand_history (in = demand_record )
                        exploded_events (in = event ) ;

        by prop_code staydate ;
        if demand_record and event then output demand_events ;

        event_rec = event ;

        %if &same_table = 1 %then
        if demand_record then output forecast_demand_events  %str(;) ;
run;



** If the Input Forecast data set is not the same as the input demand data set, **;
** then sort it and merge it with the exploded events data set, to add event    **;
** information to the data set.                                                                                                 **;

%if &same_table = 0 %then %do ;

        proc sort       data = &input_forecast_demand_libref..&input_forecast_demand_table
                                (keep = &forecast_prop_code_col &forecast_date_col &forecast_demand_col
                                                &by_variables)
                                out = forecast_demand
                                %if &forecast_demand_col ne demand or
                                        &forecast_date_col ne staydate or
                                        &forecast_prop_code_col ne prop_code %then %do;
                                                (rename = (
                                                        %if &forecast_demand_col ne demand %then &forecast_demand_col = demand ;
                                                        %if &forecast_date_col ne staydate %then &forecast_date_col = staydate ;
                                                        %if &forecast_prop_code_col ne demand %then &forecast_prop_code_col = prop_code
                                                ))
                                %end;
                                ;
                by &forecast_prop_code_col &forecast_date_col &by_variables;
        run;


        ** Output the forecast demand with added event_id and day_within_event values, and      **;
        ** a data set representing future events that are found in the forecast demand data.    **;

        data forecast_demand_events;

                merge   forecast_demand (in=sfdemand)
                        exploded_events (in = event) ;

                by prop_code staydate ;

                if sfdemand;

        run;

%end;


** Sort the historical demand table, previously joined with event data, by the variables        **;
** that will merge with the event_ids found in forecast demand data                             **;

proc sort data = demand_events ;
        by prop_code &by_variables event_id day_within_event descending staydate;
run;



** Obtain the most recent Max_Data_Points demand values for each event_id and   **;
** day-within-event in the historical demand data.                                                              **;

data past_event_ids ;
        set demand_events (in=edemand) ;
        by prop_code &by_variables event_id day_within_event ;

        retain data_points 0;

        if first.day_within_event then data_points = 0 ;

        data_points +1 ;

        if data_points <= &n_max_data_points then output ;

        drop data_points ;
run;


** Proc Summarize the past event demand data by event_id and day_within_event - within          **;
** prop_code and any other category variables that were supplied to the program.                **;

proc summary data = past_event_ids nway ;
        class prop_code &by_variables event_id day_within_event ;
        var demand ;
        output out = past_event_demand_avgs (drop = _freq_ _type_) mean = past_event_avg ;
run ;



** Merge back the averaged past event demand data with the forecast demand values, and          **;
** replace forecast demand values for particular event_ids and day_within_events with           **;
** averaged past demand values for those event_ids and day_within_event values.                 **;
** Also take account of the forecast demand replace date range represented by the input         **;
** parameters demand_replace_start_date and demand_replace_end_date.                            **;

** Sort the forecast data set for merging with past averaged event demand data.                 **;
proc sort data = forecast_demand_events ;
        by prop_code &by_variables event_id day_within_event ;
run;


data &output_table_libref..&output_table_name ;
        merge past_event_demand_avgs (in = pastavg)
                  forecast_demand_events (in=fdemand) ;
        by prop_code &by_variables event_id day_within_event ;
        if fdemand ;

        * Implicit conversion of numeric event_id to character, in the case that it is *;
        * originally numeric.                                                          *;
        if compress(event_id) ne '' and past_event_avg ne .
        then demand = past_event_avg ;

        drop event_id day_within_event past_event_avg ;
        ** Rename back the columns that may have been renamed by this program **;
        %if &forecast_prop_code_col ne prop_code %then rename prop_code = &forecast_prop_code_col %str(;) ;
        %if &forecast_demand_col ne demand %then rename demand = &forecast_demand_col %str(;) ;
        %if &forecast_date_col ne staydate %then rename staydate = &forecast_date_col %str(;) ;

run ;


proc sort data = &output_table_libref..&output_table_name ;
        by &forecast_prop_code_col &by_variables &forecast_date_col ;
run;


*************************************** ;
** Delete unnecessary work data sets ** ;
*************************************** ;

proc datasets lib = work nolist ;
        delete  event_data exploded_events demand_history past_event_ids
                        past_event_demand_avgs forecast_demand forecast_demand_events ;
quit;


%macrend:

 %if %length(&msg) > 1 %then %do;
    %put &msg ;
    %let errmsg = &msg ;

    ** If a warning occurred, but no error, then copy the input table to the output table **;
    %if &errflg > 0 %then %do;

        proc sort data = &input_forecast_demand_libref..&input_forecast_demand_table
                  out = &output_table_libref..&output_table_name ;
            by &forecast_prop_code_col &by_variables &forecast_date_col ;
        run;

    %end;

 %end;


 %mend;
