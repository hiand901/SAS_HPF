******************************************************************************;
** Program: write_prop_code_forecast_demand.sas                             **;
** Purpose: This program creates an output dataset containing forecast      **;
**          demand values for each prop_code in the previously forecasted   **;
**          and verified data. Each data set will be stored in its own      **;
**          sub-directory of the base output directory, which will be named **;
**          with the prop_code value the data set contains.                 **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:          Andrew Hamilton, Aug 27th 2008.                             **;
**                                                                          **;
******************************************************************************;

%macro write_prop_code_forecast_demand (
    forecast_table_libref,
    forecast_table_name,
    output_base_dir,
    prop_code_frcst_table_name,
    prop_code_param_value,
    status_list_libref,
    status_list_table,
    rundatetm
);


    ** Obtain a list of all prop_codes represented in the data **;
    proc sort data = &status_list_libref..&status_list_table out = pcs ;
        by prop_code status ;
        where rundtm = input("&rundatetm", datetime23.) ;
    run;


    %let num_pcs_out = 0 ;

    data passed_pcs ;
        set pcs end=eof;
        by prop_code status ;
        retain fail_found num_pcs 0 ;
        if first.prop_code then fail_found = 0 ;
        if compress(lowcase(pass_fail)) = "fail" then fail_found +1 ;
	    if last.prop_code and not fail_found then do ;
            num_pcs + 1;
            output;
            call symput ('out_pc_'!! left(put(num_pcs,4.)), compress(prop_code)) ;
        end;

        if eof then call symput ('num_pcs_out', put(num_pcs,4.)) ;
    run;


    ** Check for the existence of sub-directories of the base output directory **;
    ** named with the prop_codes represented in the output forecast data.      **;

    %do i = 1 %to &num_pcs_out ;

        %let dirid = %sysfunc(fileexist(&output_base_dir./&&out_pc_&i));
        %if &dirid = 0 %then %do ;
            %let rc = %sysfunc(system(mkdir &output_base_dir/&&out_pc_&i)) ;
        %end;
        %let dirid = %sysfunc(dclose(&dirid)) ;

        ** Attempt to assign a libref to the relevant directory ** ;
        libname outf&i "&output_base_dir/&&out_pc_&i" ;
        %let rc = %sysfunc(libref(outf&i)) ;
        %if &rc > 0 %then %do ;
            %let errflg = 1 ;
            %let errmsg = Unable to assign a libref to the library &output_base_dir./&&out_pc_&i ;
        %end;
        %else %do ;
            ** Output forecast records for the prop_code to a 'room_demand_forecast' **;
            ** data set in the output directory specific to that prop_code.          **;
            data outf&i..&prop_code_frcst_table_name ;
                set &forecast_table_libref..&forecast_table_name ;
                where compress(prop_code) = compress("&&out_pc_&i") ;
            run;

            ** Reset the libname for the specific directory **;
            libname outf&i ;
        %end;

    %end;


%macrend:

%mend;
