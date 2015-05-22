******************************************************************************;
** Program: build_hpf_spec.sas                                              **;
** Purpose: This program reads HPF model-specification procedure statements **;
**          from a supplied data set, and runs the relevant procedures,     **;
**          storing the resultant model definitions in the repository       **;
**          catalog named in the input parameters.                          **;
** Design Module: Section 3.3 of the HPF Forecast System Design Document    **;
** By:          Andrew Hamilton, July 3rd 2008.                             **;
**                                                                          **;
******************************************************************************;

%macro build_hpf_spec (
        potential_model_table_libref,
        potential_model_table_name,
        hpf_spec_libref,
        hpf_spec_catalog_name,
        D_or_F,
        dem_col
        );

       ** The following macro variables will hold long strings that contain lists **;
       ** of model names built by the HPF...SPEC procedures run below. There are  **;
       ** more than one of them since the number of models produced can grow      **;
       ** beyond the ability of one macro variable to contain them all.           **;
        %global all_model_names1 all_model_names2 all_model_names3 ;


        ** Check that the potential models table can be opened **;

        ** Check the validity of the input table name **;
        %let dsid = %sysfunc(open(&potential_model_table_libref..&potential_model_table_name, i)) ;
        %if &dsid = 0 %then %do;
                %let errflg = -1 ;
                %let errmsg = Unable to open input table &potential_model_table_libref..&potential_model_table_name;
                %goto macrend ;
        %end;
        %else %do;
        ** Check the number of obs in the input demand table, and check whether the column names **;
        ** given in the input parameters to this program are found in the table.                 **;
        %let obsknown = %sysfunc(attrn(&dsid, ANOBS));
        %if &obsknown = 1 %then %let numobs = %sysfunc(attrn(&dsid,NLOBS));
        %if &numobs = 0 %then %do;
            %let errflg = -1 ;
            %let errmsg = The table &potential_model_table_libref..&potential_model_table_name has zero records;
            %goto macrend ;
        %end;
    %end;
    %let dsid = %sysfunc(close(&dsid)) ;


        proc sort data = &potential_model_table_libref..&potential_model_table_name
                   out = candidate_models ;
                by model_name ;
        run;


        ** Read in the candidate models and write out procedure code **;
        data _null_ ;
                length initstmnt laststmnt all_model_names $10000 ;

                set candidate_models end=eof ;
                ** Remove ESMBEST from the list of candidate diagnose models.  **;
                ** The ESMBEST model is only included in candidate_models so   **;
                ** that it can be merged with the output diagnosed models      **;
                ** data set below in the case that no actual candidate model   **;
                ** was selected by HPFEngine, and ESMBEST is selected instead. **;
                ** The where clause is only applied for the case where the     **;
                ** the program is being run from run_diagnose rather than      **;
                ** run_forecast.                                               **;
                %if &d_or_f = D %then
                where compress(upcase(model_name)) ne 'ESMBEST' %str(;) ;

                by model_name ;
                retain proc_count 0 statement_count all_model_count 0 all_model_names  ;
                proc_count + 1 ;
                call symput ('model_name_'!! left(put(proc_count,4.)), compress(model_name) ) ;
                call symput ('proc_name_'!! left(put(proc_count,4.)), compress(model_type) ) ;
                call symput ('proc_option_'!! left(put(proc_count,4.)), trim(left(procedure_options)) ) ;

                all_model_names = trim(left(all_model_names)) !!' '!! compress(model_name) ;
                if length (trim(left(all_model_names))) > 3900 then do ;
                    * If the current string holding model names is getting too long, *;
                    * output the current contents to a macro variable and reset the  *;
                    * string holding the model names.                                *;
                    all_model_count + 1;
                    call symput(compress('all_model_names' !! put(all_model_count,3.)) ,
                    trim(left(all_model_names)) ) ;
                    all_model_names = '';
                end;

                loop_check = 0 ;
                do while (index(statement, 'SEMICOLON') > 0) ;
                        semindex = index (statement, 'SEMICOLON') ;
                        initstmnt = substr (statement, 1, semindex-1) ;
                        laststmnt = substr (statement, semindex+9 ) ;
                        statement = trim(left(initstmnt)) !!'; '!! left(laststmnt) ;
                        loop_check + 1 ;
                        if loop_check > 20 then leave ;
                end;
                call symput (compress( 'statement_'!! put(proc_count,3.)), trim(left(statement)) ) ;

                if eof then do;
            call symput('num_models', put(proc_count,4.)) ;
            all_model_count + 1;
            call symput(compress('all_model_names' !! put(all_model_count,3.)) ,
                        trim(left(all_model_names)) ) ;
        end;
        run;


        ** Run through the spec procedure definitions to create model definitions in the **;
        ** selected repository catalog.                                                  **;

        %do i = 1 %to &num_models ;

            proc HPF&&proc_name_&i..SPEC repository = &hpf_spec_libref..&hpf_spec_catalog_name
                 name = &&model_name_&i &&proc_option_&i ;
                 &&statement_&i ;
            run;
        %end;


        %if &syserr ne 0 and (&syserr <= 3 or &syserr > 4) %then %do;
                %let errmsg = Error: Unable to complete model creation in program build_hpf_spec.sas called by ;
                %if &d_or_f = F %then %let errmsg = &errmsg run_diagnose.sas ;
                %else %let errmsg = &errmsg run_forecast.sas ;
                %goto macrend ;
        %end;
        %else %if &syserr = 4 %then %let errmsg = Warning: Non-fatal error occurred in model creation in program build_hpf_spec.sas ;



        *************************************************************************;
        ** Collect all the model definitions into one selection named 'modall' **;
        *************************************************************************;

        proc hpfselect repository = &hpf_spec_libref..&hpf_spec_catalog_name name = modall ;
                spec
                %do i = 1 %to &num_models ;
                &&model_name_&i
                %end;
                / inputmap (symbol = Y var = &dem_col );
        run;

        %if &syserr ne 0 %then %do ;
            %if &syserr <= 3 or &syserr > 4 %then %do;
                    %let errmsg = Error: Unable to complete hpfselect step in program build_hpf_spec.sas called by ;
                    %if &d_or_f = F %then %let errmsg = &errmsg run_diagnose.sas ;
                    %else %let errmsg = &errmsg run_forecast.sas ;
            %end;
           %else %if &syserr = 4 %then %let errmsg = Warning: Non-fatal error occurred in hpfselect proc in program build_hpf_spec.sas ;


            %macrend:
            %if errflg = 0 %then %do ;
                    %if &syserr = 0 %then %let errflg = 0 ;
                    %else %if &syserr <= 3 or &syserr >4 %then %let errflg = -1;
                    %else %let errflg = 1 ; ** Warning Message **;
            %end;
        %end;

%mend;
