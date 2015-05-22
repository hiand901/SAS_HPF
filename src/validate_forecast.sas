******************************************************************************;
** Program: Validate_Forecast.sas                                           **;
** Purpose: This program validates the forecast demand values produced by   **;
**          the HPF                                                         **;
** Design Module: Section 3.10 of the HPF Forecast System Design Document   **;
** By:      Andrew Hamilton, July 15th 2008.                                **;
**                                                                          **;
******************************************************************************;

%macro validate_forecast (
                group_or_transient,
                original_demand_table_libref,
                original_demand_table_name,
                forecast_demand_table_libref,
                forecast_demand_table_name,
                max_values_table_libref,
                max_values_table_name,
                output_forecast_table_libref,
                Output_Forecast_Table_Name,
                prop_code_col,
                demand_col,
                by_variables,
                date_col
        );


        ******************************************************************************************;
        ** Reorganize the validation max values data set so that it has one column per by group **;
        ******************************************************************************************;
        %put "VASANZ   validate forecast by variables &by_variables  " ;  /** VASAN **/


        proc sort data = &max_values_table_libref..&max_values_table_name
            out = sorted_max_values ;
            by prop_code id  byvar byvarvalue ;

            %if &prop_code ne ALL %then
            where compress(lowcase(prop_code)) = lowcase(compress("&prop_code")) %str(;) ;
        run;



        data max_values ;
            %if &num_cat_vars > 0 %then length &by_variables $64 %str(;) ;
            set sorted_max_values ;
            %if &num_cat_vars > 0 %then retain &by_variables %str(;) ;
            by prop_code id byvar byvarvalue ;

            if first.id then do ;
               %do i = 1 %to &num_cat_vars ;
                   &&cat_var_&i = '' ;
                %end;
            end;

            %do i = 1 %to &num_cat_vars ;
                if compress(lowcase(byvar)) = compress(lowcase("&&cat_var_&i")) then
                &&cat_var_&i = byvarvalue ;
            %end;

            if last.id then do;
                if id = upcase(compress( ' '
                %do i = 1 %to &num_cat_vars ;
                    || substr(left("&&cat_var_&i"),1,7) || &&cat_var_&i
                %end;
                )) then output ;
            end;

            drop id byvar byvarvalue ;

        run;

        proc sort data = max_values ;
            by prop_code &by_variables ;
        run;


         ******************************************************************;
         ** Merge the demand table with the reorganized max_values table **;
         ******************************************************************;
         proc sql ;
            create table max_demand_values
            as select a.prop_code, a.&demand_date_col,
            %do i = 1 %to &num_cat_vars ;
                a.&&cat_var_&i ,
            %end;
            case when a.&demand_col > b.max_demand and b.max_demand ne . then 'Y'
                 else 'N' end as replace,
            max (0, a.&demand_col) as &demand_col, b.max_demand
            from output_forecast_table2 as a left join max_values as b
            on a.prop_code = b.prop_code
            %do i = 1 %to &num_cat_vars ;
                and compress(a.&&cat_var_&i) = compress(b.&&cat_var_&i)
            %end;
            ;
         quit;





        ** Sort the max_demand_values **;

        proc sort data = max_demand_values ;
            by prop_code &by_variables &date_col ;
        run;




        **********************************************************************************;
        ** Apply rules for replacement of demand values greater than the allowed        **;
        ** maximum for Group Forecast demand values.                                    **;
        **********************************************************************************;

        ** Obtain demand values that could be used for replacement on neighbouring days **;

        data next_days_demand ;
            set max_demand_values ;
            by prop_code &by_variables &date_col ;
            where replace = 'N' ;
            &date_col = &date_col -1 ;

            %if &num_cat_vars > 0 %then
             if not first.&&cat_var_&num_cat_vars %str(;) ;
            %else
             if not first.&date_col %str(;) ;

            keep prop_code &by_variables &date_col &demand_col ;
            rename &demand_col = next_demand ;
        run;


        ** Find which by_variables were originally numeric values **;
        %find_numeric_by_vars (&original_demand_table_libref..&original_demand_table_name,
                               &by_variables) ;


        ***********************************************************************;
        ** Merge back previous and next days demand with the original demand **;
        ** Also switch by variables that were converted to character back to **;
        ** numeric values.                                                   **;
        ***********************************************************************;

        data  %if &num_numeric_byvars = 0 %then
            &output_forecast_table_libref..&output_forecast_table_name ;
              %else output_forecast ;
            ;
            merge max_demand_values (in = original)
                  next_days_demand (in = next ) ;

            by prop_code &by_variables &date_col ;

            * Obtain the previous days demand using the lag function.    *;
            * Blank it if it relates to the previous by group, or it     *;
            * relates to a record where the demand is above max allowed. *;
            lag_demand = lag(&demand_col) ;
            if lag(replace) = 'Y' or
            %if &num_cat_vars > 0 %then
             first.&&cat_var_&num_cat_vars ;
            %else first.&date_col ;
             then lag_demand = . ;

            if replace = 'Y' then do;
                if lag_demand ne . then &demand_col = lag_demand ;
                else if not
                 %if &num_cat_vars > 0 %then
                  last.&&cat_var_&num_cat_vars ;
                 %else
                  last.&date_col ;

                  and next_demand ne . then &demand_col = next_demand ;
                else &demand_col = max_demand ;
            end;
            drop max_demand replace lag_demand next_demand ;

        run;

        %if &num_numeric_byvars %then %do ;
            ** Convert back character By Variables that were originaly numeric **;

            data  &output_forecast_table_libref..&output_forecast_table_name ;
                set output_forecast (rename = (&ren_str1)) ;
                &reverse_convert_stmnt ;
                drop &drop_stmnt ;
            run;

         %end;



        %if (&syserr > 0 and &syserr < 4) or &syserr > 4 %then %do;
            %let errflg = -1 ;
            %let errmsg = Error occurred in the validate forecast module ;
            %if &prop_code ne ALL %then %let errmsg = &errmsg for property code &prop_code ;
        %end;
        %else %if &syserr = 4 %then %do ;
            %let errflg = 1 ;
            %let errmsg = Warning occurred in the validate forecast module ;
            %if &prop_code ne ALL %then %let errmsg = &errmsg for property code &prop_code ;
        %end;
        %else %let errflg = 0 ;


        ** Clear Up **;

        proc datasets lib = work mt = data nolist ;
                    delete sorted_max_values max_values max_demand_values demand_values
                           %if &num_numeric_byvars > 0 %then
                           output_forecast ;
                               %if &group_or_transient = G %then next_days_demand ;
                                   %else baseline_weights baseline_forecast_sum ;
            ;
        quit;

%mend;
