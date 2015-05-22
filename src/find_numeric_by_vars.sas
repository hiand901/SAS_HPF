******************************************************************************;
** Program: find_numeric_by_vars.sas                                        **;
** Purpose: Look for numeric by variables in the input demand data, and     **;
**          write statements necessary to convert them to character         **;
**          variables, to macro variables.                                  **;
**                                                                          **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:          Andrew Hamilton, Aug 4th 2008.                              **;
**                                                                          **;
******************************************************************************;


%macro find_numeric_by_vars (
    input_table,
    byvars) ;


    %global num_numeric_byvars ren_str1 convert_stmnt reverse_convert_stmnt drop_stmnt ;

    %let num_numeric_byvars = 0 ;


    data _null_ ;

        length variname $32 ren_str1 convert_stmnt reverse_convert_stmnt drop_stmnt $400 ;

        set &input_table (obs = 1) ;

        ** Obtain all numeric variables in the demand data table **;
        array numvars {*} _numeric_ ;
        * Set a flag that will indicate whether any of the by_variables are numeric *;
        numeric_byvars = 0 ;

        do i = 1 to dim(numvars);
            call vname(numvars(i),variname);
            put variname = ;
            if index(lowcase("&byvars"),lowcase(compress(variname)) ) > 0 then do ;
                numeric_byvars +1 ;
                ren_str1 = trim(left(ren_str1)) !!' '!! compress(variname) !!' = '!!
                compress(variname !!'_num') ;
                convert_stmnt = trim(left(convert_stmnt)) !!' '!! compress(variname) !!
                                ' = trim(left(put('!! compress(variname !!'_num') !!',best8.)));' ;

                reverse_convert_stmnt = trim(left(reverse_convert_stmnt)) !!' '!! compress(variname) !!
                                ' = input(compress('!! compress(variname !!'_num') !!'), best8.);' ;

                drop_stmnt = trim(left(drop_stmnt)) !!' '!! compress(variname ||'_num') ;
            end;
        end;

        if numeric_byvars > 0 then do ;
            call symput('num_numeric_byvars', put(numeric_byvars,4.)) ;
            call symput('ren_str1', trim(left(ren_str1))) ;
            call symput('convert_stmnt', trim(left(convert_stmnt))) ;
            call symput('reverse_convert_stmnt', trim(left(reverse_convert_stmnt))) ;
            call symput('drop_stmnt', trim(left(drop_stmnt))) ;
        end;
    run;


%mend;
