******************************************************************************;
** Program: write_transient_forecast_file.sas                               **;
** Purpose: This program creates an output text file containing forecast    **;
**          transient demand values from previously verified HPF forecast   **;
**          values - which were potentially subject to event replacement.   **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:          Andrew Hamilton, Oct 31st 2008.                             **;
**                                                                          **;
******************************************************************************;


%macro write_transient_forecast_file (
    forecast_table_libref,
    forecast_table_name,
    weights_table_libref,
    weights_table_name,
    output_base_dir,
    output_file_name,
    prop_code_sysparm,
    prop_code_list_ds,
    asofdt,
    prop_code_col,
    date_col,
    predict_col,
    weight_col
    );


    ** Check for the existence of sub-directories of the base output directory **;
    ** named with the prop_codes represented in the output forecast data.      **;
    %let dirid = %sysfunc(fileexist(&output_base_dir));
    %if &dirid = 0 %then %do ;
        %let rc = %sysfunc(system(mkdir &output_base_dir) ;
    %end;
    %let dirid = %sysfunc(dclose(&dirid)) ;


    ** Attempt to assign a filename to the output text file ** ;

    *filename outfl "&output_base_dir/&output_file_name.&asofdt" ;
     * changed by VASAN ;
    filename outfl "&output_base_dir/&output_file_name" ;  


    ** Verify the output file fileref **;
    %let rc = %sysfunc(fileref(outfl));

    %if &rc > 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a fileref to the output forecast file &output_base_dir/&output_file_name ;
        %goto macrend ;
    %end;



    *********************************************************;
    ** Add a weight column to the output forecast data set **;
    *********************************************************;

    ** Denormalize the weights data set **;

    proc sort data = &weights_table_libref..&weights_table_name 
               out = weights_table  ;
        by prop_code id as_of_date ;
        where as_of_date <= &asofdt ;
    run;

    %dataobs(weights_table) ;
    %let weights_obs = &dataobs ;

    %if &dataobs = 0 %then %do;

        %let errflg = 1 ;
        %let errmsg = Warning: No historical HPF/Baseline weight values found before as_of_date ;

        ** If no weights found before the as_of_date, look for weights closest to the as_of_date **;
        proc sort data = &weights_table_libref..&weights_table_name out = weights_table ;
            by prop_code id descending as_of_date ;
        run;

        %dataobs (weights_table) ;

        %if &dataobs = 0 %then %do;
            %let errflg = -1 ;
            %let errmsg = Unable to find weight values before or after the as_of_date ;
            %goto macrend ;
        %end;
    %end;

    %if &prop_code_sysparm = ALL %then %do ;

        data forecast_weights  ;  
		    merge weights_table (in=wts) &prop_code_list_ds (in=pclist)  ;
            by prop_code ;
            if wts and pclist ;
        run;

    %end;


    data forecast_weights  ;
        set weights_table ;

        by prop_code id
        %if &weights_obs = 0 %then  descending ;
                         as_of_date ;

        if first.id then do ;
            %do i = 1 %to &num_cat_vars ;
                &&cat_var_&i = '' ;
            %end;
        end;

        %do i = 1 %to &num_cat_vars ;
           if compress(lowcase(byvar)) = lowcase(compress("&&cat_var_&i")) then
           &&cat_var_&i = byvarvalue ;
        %end;
         tfh_rmc = substr(id, 8,1);  /** added VASAN Fe 15, 2010 **/
        if last.id then output ;
    run;


    proc sort data = forecast_weights ;
        by prop_code &by_variables ;
    run;


    proc sort data = &forecast_table_libref..&forecast_table_name
               out = forecast_table 
               %if &prop_code_col ne prop_code %then
                   (rename = (&prop_code_col = prop_code)) ;
        ;
        by &prop_code_col &by_variables &date_col ;
    run;



    ** Output the forecast values to the output file.                           **;
    ** The single by variable of room cat is hardcoded in the output statement, **;
    ** since any change in by variables will require a new file format.         **;

    data FINAL_FCST   ;
        merge forecast_table (in=fore )
              forecast_weights (in=wts);

        by prop_code &by_variables ;
        if fore ;
        if weight = 1;  
        file outfl ;
        put @1 prop_code @7 &cat_var_1 @9 &Date_col yymmdd10. @20 &predict_col z16.5  @37 weight z16.5;
    run;

     proc sql;

    select count (distinct prop_code) from FINAL_FCST;
      quit;


 %macrend:

%mend;
