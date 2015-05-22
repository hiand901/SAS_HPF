******************************************************************************;
** Program: compute_baseline_error.sas                                      **;
** Purpose: This program compares baseline forecast values against HPF      **;
**          forecast values, and calculates the difference values.          **;
** Design Module:       Section ? of the HPF Forecast System Design Doc     **;
** By:      Andrew Hamilton, Aug 4th 2008.                                  **;
**                                                                          **;
**--------------------------------------------------------------------------**;
** Modifications                                                            **;
**--------------------------------------------------------------------------**;
** Date    By  Modification                                                 **;
** 111208  AH  Changed the error calculation from MAPE to MAE.              **;
**                                                                          **;
******************************************************************************;

%macro compute_baseline_error ( actuals_table_libref,
                                actuals_table_name,
                                baseline_forecast_libref,
                                Baseline_Forecast_table_name,
                                baseline_error_table_libref,
                                baseline_error_table_name,
                                by_variables,
                                asofdt,
                                actuals_col,
                                actuals_date_col,
                                actuals_prop_code_col,
                                basefcst_demand_col,
                                basefcst_date_col,
                                basefcst_prop_code_col,
                                baseline_by_variables
                              );


    %let errflg = 0;


    *************************************************************************;
    ** Break out the baseline by variables into individual macro variables **;
    *************************************************************************;

    data _null_ ;
        cat_vars = trim(left("&baseline_by_variables")) ;
        num_cat_vars = 0 ;
        i = 1 ;
        do while (compress(scan(cat_vars, i) ne ''));
                cat_var = scan(cat_vars, i, ' ') ;
                call symput("base_by_var_" !! left(put(i, 3.)), cat_var) ;
                i+1 ;
                if i > 10 then leave ;
        end;
        call symput ("num_base_by_vars", left(put(i-1, 3.))) ;
    run;


    ** Check that the number of baseline by variables match up to the number of     **;
    ** by variables used by the HPF system.                                         **;
    %if &num_base_by_vars ne &num_cat_vars %then %do;
        %let errmsg = Error: Mis-match between the number of HPF and Baseline by variables ;
        %let errflg = -1 ;
        %goto macrend ;
    %end;


    %let renflg = 0 ;
    %local renstr ;


    ** Create a rename string for the baseline data. **;
    data _null_ ;
            length renstr $256 ;
            if compress(lowcase("&basefcst_prop_code_col")) ne "&actuals_prop_code_col" then
            renstr = trim(left("&basefcst_prop_code_col = &actuals_prop_code_col")) ;
            if compress(lowcase("&basefcst_date_col")) ne compress(lowcase("&actuals_date_col")) then
            renstr = trim(left(renstr)) !!' '!! trim(left("&basefcst_date_col = &actuals_date_col")) ;

            do i = 1 to &num_base_by_vars ;
               catvar = lowcase(compress(symget('cat_var_'!! left(put(i,4.))))) ;
               basevar = lowcase(compress(symget('base_by_var_'!! left(put(i,4.))))) ;
               if catvar ne basevar then
                renstr = trim(left(renstr)) !!' '!! compress(basevar)!!' = '!! compress(catvar) ;
            end;

            if compress(renstr) ne "" then do ;
                call symput('renstr', trim(left(renstr))) ;
                call symput('renflg', '1') ;
            end;
    run;



    ** Get the statements necessary to convert numeric by variables to character values **;
    %find_numeric_by_vars (&baseline_forecast_libref..&baseline_forecast_table_name,
                           &baseline_by_variables ) ;

    %if &num_numeric_byvars > 0 %then %do ;

        data baseline_forecast  ;
            length &by_variables $64 ;
            set &baseline_forecast_libref..&baseline_forecast_table_name (rename = (&ren_str1)) ;
            &convert_stmnt;
            drop &drop_stmnt ;
        run;

    %end;



    ** Sort the actuals output from the forecast process to           **;
    ** accomodate the following merge step.                           **;

    proc sort data = &actuals_table_libref..&actuals_table_name
               out = actuals;
        by &actuals_prop_code_col &by_variables &actuals_date_col ;
    run;



    ** Likewise sort the baseline forecast values to                  **;
    ** accomodate the following merge step.                           **;

    proc sort data =
        %if &num_numeric_byvars > 0 %then baseline_forecast ;
        %else &baseline_forecast_libref..&baseline_forecast_table_name ;
        out = baseline_forecast
        ;
        by &basefcst_prop_code_col &baseline_by_variables &basefcst_date_col ;
    run;



    ** Merge the amended forecast data output by the best models with the   **;
    ** common dates within the historical demand data.                      **;

    data compare ;
        merge baseline_forecast (in = basefcst
            %if &renflg = 1 %then rename = (&renstr) ;
                                 )
              actuals (in=dmnd) ;

        by &actuals_prop_code_col &by_variables &actuals_date_col;

        if basefcst and dmnd ;

        baseline_error = 0;
        denominator_count = 0 ;
        if &actuals_col + &basefcst_demand_col ne . then do ;
            baseline_error = abs(&actuals_col - &basefcst_demand_col) ;
            denominator_count = 1 ;
        end;

        drop &actuals_col &basefcst_demand_col ;
    run;



    proc summary data = compare nway noprint ;
        class &actuals_prop_code_col &by_variables ;
        var baseline_error denominator_count;
        output out = summed_perc_error (drop= _type_ _freq_) sum = ;
    run;



    ** Create the baseline error update table **;

    data summed_perc_error_denorm (drop= denominator_count &by_variables name_sub) ;
        length id byvarvalue $64 byvar $32 name_sub $8 ;

        set  summed_perc_error ;

        by &actuals_prop_code_col &by_variables ;

        baseline_error = baseline_error / denominator_count ;

        as_of_date = &asofdt ;
        format as_of_date date7. ;

        %if &num_cat_vars > 0 %then %do j = 1 %to &num_cat_vars ;
            if length(compress("&&cat_var_&j")) > 8 then
            name_sub = upcase(substr(compress("&&cat_var_&j"),1,8)) ;
            else name_sub = upcase(compress("&&cat_var_&j")) ;
            id = compress(id !! name_sub !! &&cat_var_&j) ;
        %end;

        %do j = 1 %to &num_cat_vars ;
            byvar = compress("&&cat_var_&j") ;
            byvarvalue = trim(left(&&cat_var_&j)) ;
            output ;
        %end;

    run;



    ** Update the historical baseline error table **;

    %if %sysfunc(exist(&baseline_error_table_libref..&baseline_error_table_name )) = 0 %then %do;

        data &baseline_error_table_libref..&baseline_error_table_name ;
           set summed_perc_error_denorm ;
        run;

    %end;
    %else %do ;
         data &baseline_error_table_libref..&baseline_error_table_name ;
            update &baseline_error_table_libref..&baseline_error_table_name
                   summed_perc_error_denorm ;
            by &actuals_prop_code_col id as_of_date;
        run;
    %end;

    proc datasets lib = &baseline_error_table_libref mt = data ;
        modify &baseline_error_table_name;
        index create comp = (&actuals_prop_code_col id as_of_date) ;
    quit;



 %macrend:

    %if &syserr > 0 and &syserr ne 4 %then %do ;
          %let errflg = -1 ;
          %let errmsg = Error occurred in compute_baseline_error program  ;
    %end;
    %else %if &syserr => 4 %then %do ;
          %let errflg = 1;
          %let errmsg = Warning generated in compute_baseline_error program  ;
    %end;



    proc datasets lib=work nolist mt=data ;
        delete compare actuals summed_perc_error summed_perc_error_denorm
        %if &num_numeric_byvars > 0 %then baseline_forecast ;
        ;
    quit;


%mend;
