******************************************************************************;
** Program: build_hpf_event.sas                                             **;
** Purpose: This program reads HPF event-specification table and runs the   **;
**          HPFEvent procedure for each prop_code to create an HPF events   **;
**          data set for the prop_code. These data sets are appended        **;
**          together so that they are contained in one data set that can    **;
**          be later subset for particular prop_code values.                **;
**          In the case that this program is called from the run_diagnose   **;
**          program, the historical_events HPF Forecasting System data set  **;
**          is appended to with the compendium events data set produced     **;
**          by this program.                                                **;
**                                                                          **;
** Design Module: Section 3.4 of the HPF Forecast System Design Document    **;
** By:          Andrew Hamilton, July 3rd 2008.                             **:
**                                                                          **;
******************************************************************************;

%macro build_hpf_event (
        event_table_libref,
        event_table_name,
        historical_event_table_libref,
        historical_event_table_name,
        output_hpf_event_table_libref,
        output_hpf_event_table_name,
        D_or_F,
        G_or_T,
        eventid_col,
        startdt_col,
        enddt_col,
        type_col,
        mode_col,
        asofdt,
        rundate,
        drft_or_pub
        );


        ** Check the validity of the input events table name **;
        %let event_numobs = 0;
        %let dsid = %sysfunc(open(&event_table_libref..&event_table_name, i)) ;
        %if &dsid = 0 %then %do;
                %let errflg = 1 ;
                %let errmsg = Unable to open input table &event_table_libref..&event_table_name;
        %end;
        %else %do;
                ** Check the number of obs in the input demand table, and check whether the column names **;
                ** given in the input parameters to this program are found in the table.                 **;
                %let obsknown = %sysfunc(attrn(&dsid, ANOBS));
                %if &obsknown = 1 %then %let event_numobs = %sysfunc(attrn(&dsid,NLOBS));
                %if &event_numobs = 0 %then %do;
                        %let errflg = 1 ;
                        %let errmsg = The table &event_table_libref..&event_table_name has zero records;
                %end;
        %end;
        %let dsid = %sysfunc(close(&dsid)) ;


        ** Check the validity of the input historical events table name **;
        %let dsid = %sysfunc(open(&historical_event_table_libref..&historical_event_table_name, i)) ;
        %let hist_numobs = 0 ;
        %if &dsid = 0 %then %do;
                %let errflg = 1 ;
                %let errmsg = Unable to open input table &historical_event_table_libref..&historical_event_table_name;
        %end;
        %else %do;
                ** Check the number of obs in the input demand table, and check whether the column names **;
                ** given in the input parameters to this program are found in the table.                 **;
                %let obsknown = %sysfunc(attrn(&dsid, ANOBS));
                %if &obsknown = 1 %then %let hist_numobs = %sysfunc(attrn(&dsid,NLOBS));
                %if &hist_numobs = 0 %then %do;
                        %let errflg = 1 ;
                        %let errmsg = The table &historical_event_table_libref..&historical_event_table_name has zero records;
                %end;
        %end;
        %let dsid = %sysfunc(close(&dsid)) ;


        ** If the rundate is either the asofdt - meaning the Marsha date - or today, **;
        ** then get events from the input event table pointed to by the config file. **;

        %if &asofdt = &rundate or &hist_numobs = 0 %then %do;

            %if &event_numobs = 0 %then %do;
                    %let errflg = 1 ;
                    %let errmsg = No records retrieved from the input current events table. ;
                    %goto macrend ;
            %end;


            data hpf_event_table_name ;
                length eventid_col $15 _name_ $40 ;
                set &event_table_libref..&event_table_name
                    (rename = (&startdt_col = _startdate_ &enddt_col = _enddate_ )) ;
                    * Remove apostrophies and dashes from any event ids, *;
                    * before adding the value to the _name_ variable *;
                    eventid_col = substr(left(compress(&eventid_col, "'-/\.,")),1,15) ;

                    _name_ = compress(prop_code !! eventid_col || put(_startdate_, 8.)||'_'!! put(_enddate_,8.), '. ' ) ;
                    _type_ = "LS" ;
                    _class_ = "SIMPLE" ;
                    _PULSE_ = "DAY" ;
                    _RULE_ = "ADD" ;
                    _SHIFT_ = 0;
                    _TCPARM_ = 0.5;
                    _SLOPE_BEF_ = "GROWTH";
                    _SLOPE_AFT_ = "GROWTH";
                    _dur_after_ =  (_enddate_ - _startdate_) +1;
                    _enddate_ = . ;
                    _dur_before_ = 0 ;
                    as_of_date = &asofdt ;
                    format as_of_date mmddyy10. ;
                    drop eventid_col ;
            run;


            data &output_hpf_event_table_libref..&output_hpf_event_table_name ;
                set hpf_event_table_name ;
                drop &eventid_col &type_col &mode_col as_of_date;
            run;


            ** If the program is being run in Diagnose mode, add the events defined **;
            ** to the historical events data set, along with an ' As_of_date' value **;
            ** set to the current date.                                             **;

            %if &d_or_f = D %then %do ;

                ** If the historical events table already exists, update it with the current    **;
                ** HPF events data set.                                                         **;

                %if %sysfunc (exist(&historical_event_table_libref..&historical_event_table_name)) = 1
                 %then %do;

                    proc sort data = hpf_event_table_name ;
                        by as_of_date prop_code &mode_col &type_col _name_ _startdate_ ;
                    run;


                    data &historical_event_table_libref..&historical_event_table_name ;
                        update &historical_event_table_libref..&historical_event_table_name
                               hpf_event_table_name ;
                        by as_of_date prop_code &mode_col &type_col _name_ _startdate_ ;
                    run;

                %end;
                %else %do;

                     ** If the historical events table does not already exist, create it from the    **;
                     ** output events data set of the current run, and index it appropriately.       **;

                     data &historical_event_table_libref..&historical_event_table_name ;
                         set hpf_event_table_name ;
                     run;

                     proc datasets lib = &historical_event_table_libref nolist ;
                         modify &historical_event_table_name ;
                         index create as_of_prop = (as_of_date prop_code &mode_col &type_col
                                                    _name_ _startdate_) ;
                     quit ;

                %end;
            %end;
        %end;
        %else %do;

            ** Get events defined on the supplied as_of date **;

            %if &hist_numobs = 0 %then %do;
                    %let errflg = 1 ;
                    %goto macrend ;
            %end;


            proc sort data = &historical_event_table_libref..&historical_event_table_name
                       out = historical_events ;
                where as_of_date <= &asofdt
                %if &g_or_t = G %then %do ;
                  and upcase(&mode_col) = compress(upcase("&drft_or_pub"))
                  and upcase(&type_col) = compress(upcase("&g_or_t"))
                %end;
                ;
                by prop_code _name_ as_of_date ;
            run;


            %dataobs(historical_events) ;
              %if &dataobs = 0 %then %do;  

                %let errflg = 1;
                %let errmsg = Warning. No events were found for before the as_of_date. ;
                %let errmsg = &errmsg The events closest to the as_of_date will be used instead. ;

                proc sort data = &historical_event_table_libref..&historical_event_table_name
                           out = historical_events ;

                    %if &g_or_t = G %then %do ;
                        where upcase(&mode_col) = compress(upcase("&drft_or_pub"))
                          and upcase(&type_col) = compress(upcase("&g_or_t")) ;
                    %end;
                    by prop_code _name_ descending as_of_date ;
                run;

            %end;



            data &output_hpf_event_table_libref..&output_hpf_event_table_name ;
        /***        set historical_events(rename=(id=event_id)) ;   ***/
      
              set historical_events ;  

                by prop_code _name_
                %if &dataobs = 0 %then descending ;
                   as_of_date  ;

                ** Select the latest as_of_date for each prop_code, _name_ group **;
                if last._name_ then output ;

                drop as_of_date draft_or_published ;
            run;

            
            proc datasets lib=work mt=data nolist ;
               delete historical_events ;
            quit;
             
        %end;

%macrend:



%mend;
