*********************************************************************************;
** Program:   build_prop_list                                                 ***;
** Purpose: This program creates property_list.txt from the fcst prop control ***;
**          file.                                                              **;
** Design Module:                                                              **;
** By:       Vasan Jan 2010                                                    **;
**                                                                             **;
** Modified:                                                                   **;
** By:      Andrew Hamilton Jan 2012                                           **;
** Reason:  Modified for call from run_forecast to output both a prop_list     **;
**          data set and a file that will be read by the diagnose process.     **;
**                                                                             **;
*********************************************************************************;

%macro  build_prop_list (prop_code_base_path,
                         input_cntrl_list_name,
                         tz,
                         output_prop_code_list_ds,
                         tz_top_dir,
                         output_prop_code_file_name
		            );

    %let errflg=0;


    filename propcntl "&prop_code_base_path/&input_cntrl_list_name";


    ** Check the fileref of the input property control file **;
 
    %let rc = %sysfunc(fileref(propcntl));

    %if &rc ne 0 %then %do;

         %let errflg = -1 ;
         %let errmsg = Unable to associate a fileref with the input property control file ;
         %let errmsg = &errmsg &prop_code_base_path/&input_cntrl_list_name ;
         %goto macrend;
    %end;


    ** Assign fileref to the output property list file **;

    filename plout "&tz_top_dir/in/&output_prop_code_file_name";

    ** Check the fileref **;

    %let rc = %sysfunc(fileref(plout));

    %if &rc > 0 %then %do;

         %let errflg = 1 ;
         %let errmsg = Unable to associate a fileref with the output property list file ;
         %let errmsg = &errmsg &tz_top_dir/in/&output_prop_code_file_name ;
         %goto macrend;
    %end;




    data prop_cntl   (keep = prop_code rmc_code cap );
 	    infile propcntl;  
        input  type $  @;
        if type = '01' then delete;  
        input prop_code $4-8    rmc_code $10-10  junk $ 9-39  cap 40-44  ; 
    run;
      

    proc transpose data = prop_cntl 
                   out = &output_prop_code_list_ds (drop = _NAME_  
                                                  RENAME = (COL1 = CAP1 
                                                            COL2 = CAP2 )) ;
        by prop_code  ;
        var cap;
    run;


    data _null_; 
        set &output_prop_code_list_ds;
        if cap2 = '.' then cap2 = 0;

        file plout ;
        put prop_code $ 1-5  
            cap1 10-14    
            cap2  20-24 ; 

    run;

    %if %syserr ge 4 %then %do;
         %let errflg = 1;
         %let errmsg = Error encountered writing to the output property list file ;
         %let errmsg = &errmsg &tz_top_dir/in/&output_prop_code_list_name ;
    %end;

    %macrend:

%mend;





