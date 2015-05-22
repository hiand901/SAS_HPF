**************************************************************************************;
** PROGRAM: property_code_status_update.sas                                         **;
** PURPOSE: Update the property code status table with the contents of an update    **;
**          table. If the property code status table does not already exist, it is  **;
**          created by this program.                                                **;
** BY:          Andrew Hamilton.                                                    **;
**----------------------------------------------------------------------------------**;
** PARAMETERS:                                                                      **;
**                                                                                  **;
**                                                                                  **;
**                                                                                  **;
** INPUT DATA                                                                       **;
**      Input Property Code Status Table Data:                                      **;
**      Libref.Name - Defined by parameter values status_tab_libref and status_tab_ **;
**      name.                                                                       **;
**      Columns: Prop_code, By_Variables (if any), Diagnose_or_Forecast, Mode,      **;
**      Group_or_Transient, rundtm, Pass_Fail, Status                               **;
**                                                                                  **;
**      Input Property Code Update Table:                                           **;
**      Libref.Name - Defined by parameter value update_table                       **;
**      Columns: Rundate, Prop_Code, ID, ByVar, ByVarValue, Status, Diagnose_or-    **;
**               _Forecast, Mode, Group_or_Transient, Pass_Fail.                    **;
**                                                                                  **;
**  OUTPUT DATA                                                                     **;
**      Same as Input Property Code Status Table.                                   **;
**                                                                                  **;
**************************************************************************************;

%macro property_code_status_update (
       update_table,
       prop_code_status_libref,
       prop_code_status_table_name,
       id_indicator
       ) ;


    data trans_rej_groups;
        length id $64 byvar $32 byvarvalue $32 name_sub $8;
        set &update_table ;

        format rundtm datetime16. ;

        %if &id_indicator ne ALL %then %do i = 1 %to &num_cat_vars ;
            ** Allow for implicit converson of any numeric By variables to **;
            ** character values.                                           **;

            if length(compress("&&cat_var_&i")) > 8 then
             name_sub = upcase(substr(compress("&&cat_var_&i"),1,8)) ;
            else name_sub = upcase(compress("&&cat_var_&i")) ;
            id = compress(id !! name_sub !! &&cat_var_&i) ;
        %end;

        %if &id_indicator ne ALL %then %do i = 1 %to &num_cat_vars ;
            byvar = "&&cat_var_&i" ;
            ** Allow for implicit converson of any numeric By variables to **;
            ** character values.                                           **;
            byvarvalue = &&cat_var_&i ;
            output ;
        %end;

        %if &id_indicator = ALL %then %do ;
                    id = "ALL" ;
        %end;
        %else %if %length(&by_variables) > 1 %then drop &by_variables %str(;) ;
        drop name_sub ;
    run;


    proc sort data = trans_rej_groups ;
        by rundtm diagnose_or_forecast group_or_transient mode  prop_code id ;
    run;


    ** Update the 'prop_code' status table with information on any prop_code,   **;
    ** by _variable grouping that was found not to have enough data for model   **;
    ** selection.                                                               **;
    %if %sysfunc(exist(&&prop_code_status_libref..&prop_code_status_table_name)) = 0 %then %do;

        data &prop_code_status_libref..&prop_code_status_table_name ;
            set trans_rej_groups   ;
        run;

        proc datasets lib = &prop_code_status_libref nolist ;
            modify &prop_code_status_table_name ;
            index create comp =
               (rundtm diagnose_or_forecast group_or_transient mode  prop_code id  ) ;
        quit;

    %end;
        %else %do ;

        proc append base = &prop_code_status_libref..&prop_code_status_table_name
                    data = trans_rej_groups force;
        run;
    %end;


    proc datasets lib = work nolist mt=data ;
            delete trans_rej_groups ;
        quit;

%mend;
