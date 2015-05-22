******************************************************************************;
** Program: Calculate_Baseline_Weights.sas                                  **;
** Purpose: This program returns a data set containing weight values for    **;
**          prop_code and by-variables groupings in the input demand data   **;
**          that are calculated by comparing error values from baseline     **;
**          forecast and HPF best diagnosed models.                         **;
**                                                                          **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
**                                                                          **;
** By:          Andrew Hamilton, Oct 21st 2008.                             **;
**                                                                          **;
******************************************************************************;

%macro calculate_baseline_weights (
                t_or_g,
                event_method,
                Best_Model_Err_Tbl_Libref,
                Best_Model_Error_Table,
                prop_code_col,
                demand_col,
                by_variables,
                asofdt,
                as_of_dt,
                baseline_error_table_libref,
                baseline_error_table_name,
                baseline_weights_libref,
                baseline_weights_table,
                prop_code_process_list_table,
                hpf_error_col,
                shift_holdout,
                status_table_libref,
                status_table_name,
                rundatetm,
                switch_diff
        )
    ;



    *************************************************************************************;
    ** Obtain the baseline error values that are closest to the supplied as_of_date    **;
    *************************************************************************************;
    ** It is necessary to look for baseline errors on the as_of_date minus the current **;
    ** shift_holdout_period config file option value, since the errors for HPF that    **;
    ** they will be compared to are calculated for the as_of_date minus the            **;
    ** shift_holdout_period value - though they are stored with an 'as_of_date'        **;
    ** column value of simply the as_of_date value.                                    **;

    proc sort data = &baseline_error_table_libref..&baseline_error_table_name out = blerrors ;
        by &prop_code_col id as_of_date ;
        where as_of_date <= (&asofdt - &shift_holdout) and
           /* Take care that best models are being read for the current by variables */
           %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
               %if &m > 1 %then and ;
               index(id, upcase(substr(compress("&&cat_var_&m"),1,8))) > 0
           %end;
           %else compress(byvar) = ''  ;
        ;
    run;


    %dataobs(blerrors) ;

    %if &dataobs = 0 %then %do ;

        %let errflg = 1 ;
        %put Warning: No Baseline Error values found before the as_of_date &As_of_date ;

    
        ** If no records were found before the as_of_date, sort the data in preparation    **;
        ** for finding the earliest set of error values after the as_of_date.              **;
        proc sort data = &baseline_error_table_libref..&baseline_error_table_name out = blerrors ;
            by &prop_code_col id descending as_of_date ;
            where
            %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
              %if &m > 1 %then and ;
          
              index(id, upcase(substr(compress("&&cat_var_&m"),1,8))) > 0
            %end;
            %else compress(byvar) = ''  ;
            ;
        run;


        %dataobs (blerrors) ;
        %if &dataobs = 0 %then %do;
            %let errflg = -1 ;
            %put Error: No Baseline Error values found before or after as_of_date &as_of_date ;
            %goto macrend ;
        %end;
    %end;



    data  blerrors_normal;
        %if &num_cat_vars > 0 %then
        length  &by_variables $64 %str(;) ;

        set blerrors ;
        retain prop_code &by_variables ;
        by &prop_code_col id
         %if &dataobs = 0 %then descending ;
                                           as_of_date ;

        if first.id then do ;
            %do i = 1 %to &num_cat_vars ;
                &&cat_var_&i = '' ;
            %end;
        end;

        %do i = 1 %to &num_cat_vars ;
            if compress(lowcase(byvar)) = compress(lowcase("&&cat_var_&i")) then
             &&cat_var_&i = byvarvalue ;
        %end;

        if last.id then do ;
            ** Take care of the possible case where the current set of by_variables are a subset of **;
            ** another set of by variables for which best models were calculated through ensuring   **;
            ** an exact match of the id variable and all the values of prop_code and names and      **;
            ** values of by_variables.                                                              **;
            %if &num_cat_vars > 0 %then %do;
                if compress(id) = compress(' '
                %do m = 1 %to &num_cat_vars ;
                       %put 'VASAN '   "&&cat_var_&m"; /** TEMPORARY**/
                    || upcase(substr(left("&&cat_var_&m"),1,7)) || &&cat_var_&m
                %end;
                ) then output ;
            %end;
            %else output %str(;) ;
        end;

        %if &prop_code_col ne prop_code %then
        rename &prop_code_col = prop_code ;

        drop id byvar byvarvalue ;
    run;


    proc sort data = blerrors_normal ;
        by prop_code &by_variables  ;
    run;


    ** Restrict the baseline errors to just the prop_codes being dealt with currently, since **;
    ** the historical weights table should only be updated for the weights resulting from    **;
    ** comparing baseline errors to just-calculated hpf errors for just-diagnosed prop_codes.**;

    data blerrors_normal ;
        merge blerrors_normal (in = bl)
              &prop_code_process_list_table (in = proc) ;
        by prop_code ;
        if bl and proc ;
    run;
*/

    **********************************************************************************;
    ** Obtain the HPF error values that are closest to the supplied as_of_date      **;
    **********************************************************************************;

    proc sort data = &best_model_err_tbl_libref..&best_model_error_table out = bmerrors ;
        by id as_of_date ;

        where as_of_date <= &asofdt and
           /* Take care that best models are being read for the current by variables */
           %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
               %if &m > 1 %then and ;
               index(id, upcase(substr(compress("&&cat_var_&m"),1,8))) > 0
           %end;
           %else compress(byvarvalue) = compress(id)  ;
        ;

    run;


    %dataobs(bmerrors) ;

    %if &dataobs = 0 %then %do ;

        %let errflg = 1 ;
        %put Warning: No HPF Best Model error values found before the as_of_date &As_of_date ;


        ** If no records were found before the as_of_date, sort the data in preparation **;
        ** for finding the earliest set of error values after the as_of_date.           **;
        proc sort data = &best_model_err_tbl_libref..&best_model_error_table
                         (keep = id byvar byvarvalue as_of_date error)
                   out = bmerrors ;
           where
           %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
                 %if &m > 1 %then and ;
                 index(id, upcase(substr(compress("&&cat_var_&m"),1,8))) > 0
           %end;
           %else compress(byvarvalue) = compress(id)  ;
           ;

           by id descending as_of_date ;
        run;


        %dataobs (bmerrors) ;
        %if &dataobs = 0 %then %do;
            %let errflg = -1 ;
            %put Error: No HPF Best Model Error values found before as_of_date &as_of_date ;
            %goto macrend ;
        %end;
    %end;



    data  bmerrors_normal;
        length  prop_code $5
        %if &num_cat_vars > 0 %then &by_variables $64  ;
        ;

        set bmerrors ;

        retain prop_code &by_variables ;
        by id
        %if &dataobs = 0 %then descending ;
                                           as_of_date ;

        if first.id then do ;
            prop_code = '' ;
            %do i = 1 %to &num_cat_vars ;
                &&cat_var_&i = '' ;
            %end;
        end;

        if compress(lowcase(byvar)) = 'prop_code' then prop_code = trim(left(byvarvalue)) ;
        %do i = 1 %to &num_cat_vars ;
            else if compress(lowcase(byvar)) = compress(lowcase("&&cat_var_&i")) then
             &&cat_var_&i = byvarvalue ;
        %end;

        if last.id then do ;
            ** Take care of the possible case where the current set of by_variables are a subset of **;
            ** another set of by variables for which best models were calculated through ensuring   **;
            ** an exact match of the id variable and all the values of prop_code and names and      **;
            ** values of by_variables.                                                              **;
            if compress(id) = compress(prop_code
            %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
                || upcase(substr(left("&&cat_var_&m"),1,8)) || &&cat_var_&m
            %end;
            ) then output ;
        end;

        drop id byvar byvarvalue ;
    run;


    proc sort data = bmerrors_normal ;
        by prop_code &by_variables  ;
    run;

    ** Merge the best_models on the as_of_date denormalized data set with the       **;
    ** current prop_code processing list, so that the historical weights table      **;
    ** is only updated for the errors relating to just-diagnosed best_models.       **;
    ** (This does not take into account the possibility that no best models were    **;
    ** diagnosed for the as_of_date in the current run, and the earliest models     **;
    ** from after the as_of date were instead used - assuming there were any. But   **;
    ** that should not happen  - or if it did, the job should have ended before     **;
    ** this point is reached.)                                                      **;


    data bmerrors_normal ;
        merge bmerrors_normal (in = bm)
              &prop_code_process_list_table (in = proc) ;
        by prop_code ;
        if bm and proc ;
    run;



    **********************************************************************************;
    ** Find if any prop_code and by_variable combos are associated with Baseline    **;
    ** forced models.                                                               **;
    **********************************************************************************;

    proc sort data = &status_table_libref..&status_table_name
               out = forced_baseline (keep = prop_code id byvar byvarvalue );
        by prop_code id ;
        where rundtm = input(compress("&rundatetm"), datetime23.)
          and compress(lowcase(status)) = "associatedwithbaselineforecast" ;
    run;


    %dataobs(forced_baseline) ;

    %if &dataobs > 0 %then %do ;


        data  forced_baseline_normal;
            %if &num_cat_vars > 0 %then
            length &by_variables $64 %str(;) ;

            set forced_baseline ;

            %if &num_cat_vars > 0 %then
            retain &by_variables %str(;) ;

            by prop_code id ;

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
                if compress(id) = compress(' '
                %if &num_cat_vars > 0 %then %do m = 1 %to &num_cat_vars ;
                    || upcase(substr(left("&&cat_var_&m"),1,8)) || &&cat_var_&m
                %end;
                ) then output ;
            end;

            keep prop_code &by_variables ;
        run;


        proc sort data = forced_baseline_normal ;
            by prop_code &by_variables ;
        run;

    %end ;



    ** Calculate baseline/ hpf combination weight values through combining baseline **;
    ** and HPF calculated error values.                                             **;
    ** Also normalize the calculated weights table, to deal with the possible case  **;
    ** of different number of by variables.                                         **;

    data baseline_weights ;
        length byvar $32 id byvarvalue $64 name_sub $8;

        merge blerrors_normal (in = base )
              bmerrors_normal (in = hpf
                  keep = prop_code &by_variables &hpf_error_col )
              %if &dataobs > 0 %then forced_baseline_normal (in=forced) ;
        ;

        by prop_code &by_variables ;

        if hpf ;
        if &hpf_error_col = . then weight = 0 ;
        else if not base then weight = 1 ;
        else if &hpf_error_col + &switch_diff <= baseline_error then weight = 1 ;
        else weight = 0 ;

        * Set the weight to zero for any prop_code, by_variable combos that are *;
        * associated with forced baseline models.                               *;
        %if &dataobs > 0 %then %do;
           if forced then weight = 0 ;
        %end;

        as_of_date = &asofdt ;
        format as_of_date mmddyy10. ;

        %if &num_cat_vars > 0 %then %do ;

            %do i = 1 %to &num_cat_vars ;
                if length(compress("&&cat_var_&i")) > 8 then
                 name_sub = upcase(substr(compress("&&cat_var_&i"),1,8)) ;
                else name_sub = upcase(compress("&&cat_var_&i")) ;
                id = compress(id !! name_sub !! &&cat_var_&i) ;
            %end;

        %end ;
        %else output %str(;) ;

        %do i = 1 %to &num_cat_vars ;
            byvar = compress("&&cat_var_&i") ;
            byvarvalue = trim(left(&&cat_var_&i)) ;
            output ;
        %end;

        drop &by_variables baseline_error &hpf_error_col name_sub ;
    run;



    ************************************************************;
    ** Update the output Baseline Weights Table               **;
    ************************************************************;

    %if %sysfunc(exist(&baseline_weights_libref..&baseline_weights_table )) = 0 %then %do;

        data &baseline_weights_libref..&baseline_weights_table ;
           set baseline_weights ;
        run;

        proc datasets lib = &baseline_weights_libref nolist mt = data ;
            modify &baseline_weights_table ;
            index create comp = (&prop_code_col id byvar as_of_date) ;
        quit;
    %end;
    %else %do ;

        proc sort data = baseline_weights ;
            by prop_code id byvar as_of_date ;
        run;

        data &baseline_weights_libref..&baseline_weights_table ;
            update &baseline_weights_libref..&baseline_weights_table
                   baseline_weights
            ;
            by &prop_code_col id byvar as_of_date ;
        run;

    %end ;


    proc datasets lib = work mt=data nolist ;
       delete blerrors blerrors_normal bmerrors bmerrors_normal baseline_weights ;
    quit;



 %macrend:

    %if &syserr > 0 and &syserr ne 4 %then %do ;
          %let errflg = 1 ;
          %let errmsg = Error occurred in calculate_baseline_weights program  ;
    %end;
    %else %if &syserr => 4 %then %do ;
          %let errflg = 2;
          %let errmsg = Warning generated in calculate_baseline_weights program  ;
    %end;


%mend;
