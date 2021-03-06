**************************************************************************************;
** PROGRAM: pre_forecast_event_dmnd_replace.sas                                     **;
** PURPOSE: Replace demand values in pre-forecast data that co-incide with event    **;
**                      dates with averages from similar days that are a number of  **;
**                      year-intervals or week-intervals from the affected dates.   **;
** BY:          Andrew Hamilton.                                                    **;
**----------------------------------------------------------------------------------**;
**                                                                                  **;
** INPUT DATA                                                                       **;
**      Input Demand Data:                                                          **;
**      Libref.Name - Defined by parameter values                                   **;
**      Columns - Columns representing Property Code, Demand, Stay Date, Segment,   **;
**                and possibly other category variables listed in one of the        **;
**                parameters to this program.                                       **;
**                                                                                  **;
**      Input Event Table:                                                          **;
**      Libref.Name - Defined by parameter values                                   **;
**      Columns - Columns representing Property Code, Type, Event ID, and Event     **;
**                Start Date, and Event End Date.'Type' is optional.                **;
**                                                                                  **;
**  OUTPUT DATA                                                                     **;
**  Amended Demand Table:                                                           **;
**  Libref.Name - Defined by parameter values,                                      **;
**      Columns - PROP_CODE, DATE, Other category variables, Amended Demand.        **;
**                                                                                  **;
**----------------------------------------------------------------------------------**;
** PARAMETERS                                                                       **;
**----------------------------------------------------------------------------------**;
**      POSITIONAL PARAMETERS - The following parameters do not have defaults and   **;
**      must be supplied in any call of the event_demand_replace                    **;
**      macro program, in the order shown below.                                    **;
**----------------------------------------------------------------------------------**;
** input_demand_table_libref - The SAS Libref assigned to the library /             **;
**                             database in which the input table is located.        **;
** input_demand_table_name - Name of the input table.                               **;
** event_table_libref - The SAS Libref assigned to the library / database           **;
**                      in which the event table is located.                        **;
** event_table_name - Name of the events table.                                     **;
** output_table_libref - The SAS Libref assigned to the library / database          **;
**                       in which the output table is located.                      **;
** output_table_name - Name of the output table.                                    **;
** demand_replace_start_date - The date in the input table at which to              **;
**                             begin replacing demand values.                       **;
** demand_replace_end_date - The date within the Demand History Table at            **;
**                           which to end replacing demand values.                  **;
** n_years_back - Number of year-intervals around each event date to                **;
**                compute averages of non-event demand from                         **;
** n_weeks_back - Number of week-intervals around each event date to                **;
**                compute averages of non-event demand from (in the case            **;
**                that no non-event data is found within the n_years_back           **;
**                year-interval range).                                             **;
**                                                                                  **;
** By_Variables - default of 'segment'. Multiple values should be separated         **;
**                                by spaces.                                        **;
** Demand_Prop_Code_Col - default "Prop_Code"                                       **;
** dem_date_col - default "Date"                                                    **;
** Demand_Col - default "Demand"                                                    **;
** Event_Prop_Code_Col - default "Prop_Code"                                        **;
** Event_Type_Col - If this column is in the input event table, the data set        **;
**                  supplied to this macro will already have been subset for the    **;
**                  relevant type value of group_or_transient.                      **;
** Event_ID_Col - default "event_id"                                                **;
** Event_Start_Date_Col - default "start_dt"                                        **;
** Event_End_Date_Col - default "end_dt"                                            **;
**                                                                                  **;
**************************************************************************************;

%macro pre_forecast_event_dmnd_replace (
                        input_demand_table_libref,
                        input_demand_table_name,
                        event_table_libref,
                        event_table_name,
                        output_table_libref,
                        output_table_name,
                        n_years_back,
                        n_weeks_back,
                        dem_rep_startdate,
                        dem_rep_enddate,
                        category_variables,
                        demand_prop_code_col,
                        dem_date_col,
                        demand_col,
                        group_or_transient,
                        event_prop_code_col,
                        event_type_col,
                        event_id_col,
                        event_start_date_col,
                        event_end_date_col) ;


** Initialize the msg macro variable **;
%global msg ;


************************************************;
** CHECK THE VALIDITY OF THE INPUT PARAMETERS **;
************************************************;

** Check that at least one of the two possible demand replacement mechanisms have been  **;
** selected to be performed.                                                            **;

%if &n_years_back = 0 or &n_weeks_back = 0 %then %do;
        %let msg = Neither a n_years_back nor a n_weeks_back valid parameter value was supplied ;
        %goto macrend ;
%end;

** Check the validity of the input_table_libref parameter **;
%let rc = %sysfunc(libref(&input_demand_table_libref)) ;
%if &rc > 0 %then %do;
        %let msg = &input_demand_table_libref Libname unassigned. ;
        %let errflg = -1 ;
        %goto macrend ;
%end;

** Check the validity of the output_table_libref parameter **;
%if &output_table_libref ne %str(work) and
        %lowcase(&output_table_libref) ne %lowcase(&input_demand_table_libref) %then %do;
        %let rc = %sysfunc(libref(&output_table_libref)) ;
        %if &rc > 0 %then %do;
                %let msg = &output_table_libref Libname unassigned. ;
                %let errflg = -1 ;
                %goto macrend ;
        %end;
%end;

** Check the validity of the event_table_libref parameter **;
%if &event_table_libref ne %str(work) and
        %index(%lowcase(&input_demand_table_libref.&output_table_libref), %lowcase(&event_table_libref)) = 0 %then %do;
        %let rc = %sysfunc(libref(&event_table_libref)) ;
        %if &rc > 0 %then %do;
                %let msg = &event_table_libref Libname unassigned. ;
                %let errflg = -1 ;
                %goto macrend ;
        %end;
%end;



** Check the validity of the input table name **;
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
                %let staydtcolid = %sysfunc(varnum(&dsid,&dem_date_col)) ;
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
                        %let msg = Input Demand data set does not have a &dem_date_col column;
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


** Check the validity of the event table name **;
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
                %if %str(&event_type_col) ne %str() %then %let type_colid = %sysfunc(varnum(&dsid,&event_type_col)) ;
                %else %let type_colid = 0 ;
                %let propcdcolid = %sysfunc(varnum(&dsid,&event_prop_code_col)) ;
                %let startdtcolid = %sysfunc(varnum(&dsid,&event_start_date_col)) ;
                %let enddtcolid = %sysfunc(varnum(&dsid,&event_end_date_col)) ;
                %let eventcolid = %sysfunc(varnum(&dsid,&event_id_col)) ;
                %if &numobs = 0 %then %do;
                        %let msg = Event data set has 0 records ;
                        %let errflg = 1 ;
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


** Prepare the input demand data for joining with the event data **;

** Prepare a rename string for the output sorted demand history table, in order **;
** that standard column names can be used in the program.                       **;
%let rename_str = %str() ;
%if %lowcase(&demand_prop_code_col) ne %str(prop_code) %then
%let rename_str = &demand_prop_code_col %str(=) prop_code ;
%if %lowcase(&dem_date_col) ne %str(staydate) %then
%let rename_str = &rename_str &dem_date_col %str(=) staydate ;
%if %lowcase(&demand_col) ne %str(demand) %then
%let rename_str = &rename_str &demand_col %str(=) demand ;


proc sort data = &input_demand_table_libref..&input_demand_table_name
                 (keep = &demand_prop_code_col &dem_date_col &category_variables &demand_col )
           out = &work2_libref..demand_history
           %if %length(&rename_str) > 1 %then %do ;
               (rename = ( &rename_str ))
           %end;
        ;
        by &demand_prop_code_col &dem_date_col &category_variables ;
run;


/*  Staydate_demand no longer created - AH
proc datasets lib = work mt = data nolist ;
    delete staydate_demand ;
quit;
*/


** Merge the events data with the input demand history table **;

data demand_events;

        merge   &work2_libref..demand_history (in = demand_record )
                exploded_events (in = event ) ;

        by prop_code staydate  ;
        if demand_record ;
        event_rec = event ;
run;


proc datasets lib = work mt = data nolist ;
    delete exploded_events ;
quit;

proc datasets lib = &work2_libref mt = data nolist ;
    delete demand_history ;
quit;



** Inner macro to create either non-event averages for year-intervals around each               **;
** event date, or non-event averages for week-intervals around each event date.                 **;
%macro non_event_demand_avg (interval, count_back ) ;

        %if &interval = year %then %let num_of_interval_days = 364 ;
        %else %let num_of_interval_days = 7 ;


        ** Output a record for each year_interval for all records that are not event records    **;
        ** for later averaging into averages of demands at year-intervals from an event demand  **;
        data &work2_libref..&interval._interval_demands ;
                set demand_events (drop = event_id day_within_event) ;
                by prop_code staydate ;
                if not event_rec then do ;
                        date_start = staydate - (&count_back * &num_of_interval_days);
                        do i = 0 to (2 * &count_back) ;
                                calc_date = date_start + (i*&num_of_interval_days) ;

                                ** There is no point in outputing a record that will not match with the         **;
                                ** input data that can be overwritten.                                          **;
                                if calc_date >= &dem_rep_startdate and calc_date <= &dem_rep_enddate
                                and calc_date ne staydate then output;
                        end;
                end;
                drop date_start event_rec i ;
        run;


        ** Summarize the year-interval demand over prop_code, calc_date, and other category variables **;

        proc summary data = &work2_libref..&interval._interval_demands nway ;
                class prop_code &category_variables calc_date ;
                var demand ;
                output out = &interval._calc_demand (drop = _freq_ _type_) mean = &interval._demand_avg  ;
        run;


        proc datasets lib = &work2_libref mt = data nolist ;
            delete &interval._interval_demands ;
        quit;

%mend;

%non_event_demand_avg (year, &n_years_back ) ;
%non_event_demand_avg (week, &n_weeks_back ) ;


** Sort the output data set as required for being input to the forecast process **;
proc sort data = demand_events out= &work2_libref..demand_events ;
   by prop_code &category_variables staydate ;
run;

%if &work2_libref ne work %then %do ;
    proc datasets lib = work mt = data nolist ;
        delete demand_events ;
    quit;
%end;



** Merge the calculated non-event demand means back with original data, in order to replace     **;
** individual demand values with average demand of surrounding years - by preference - or       **;
** the average demand of surrounding weeks, if not. If neither surrounding year average or      **;
** surrounding week average non-event demand is available, the original event demand is         **;
** not replaced.                                                                                **;

data &output_table_libref..&output_table_name ;

    merge   &work2_libref..demand_events (in=edemand drop = event_id day_within_event)
                    year_calc_demand (rename = (calc_date = staydate)
                     where = (staydate between &dem_rep_startdate and &dem_rep_enddate )
                                          in = year_rec)
                    week_calc_demand (rename = (calc_date = staydate)
                     where = (staydate between &dem_rep_startdate and &dem_rep_enddate )
                                          in = week_rec) ;

    by prop_code &category_variables staydate ;


    if edemand ;

    if staydate >= &dem_rep_startdate and staydate <= &dem_rep_enddate then do;
        if event_rec then do ;
            if year_demand_avg ne . then demand = year_demand_avg ;
            else if week_demand_avg ne . then demand = week_demand_avg ;
        end;
    end;

    * Rename columns that may have been renamed for convenience of processing *;
    * back to their original names.                                           *;
    %if &demand_col ne demand %then rename demand = &demand_col %str(;) ;
    %if &demand_prop_code_col ne prop_code %then rename prop_code = &demand_prop_code_col %str(;) ;
    %if &dem_date_col ne staydate %then rename staydate = &dem_date_col %str(;) ;

    drop year_demand_avg week_demand_avg event_rec ;

run;


%macrend:


** Clean up work data sets **;
/*
proc datasets lib = work nolist mt=data ;
    delete   year_calc_demand week_calc_demand
             demand_events ;
quit;

proc datasets lib = &work2_libref nolist mt=data ;
    delete   demand_events ;
quit;
*/
%if %length(&msg) > 1 %then %do;
    %put &msg ;
    %let errmsg = &msg ;
%end;

%mend;
