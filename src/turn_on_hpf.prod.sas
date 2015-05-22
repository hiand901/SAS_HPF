*****************************************************************************;
** Program:  turn_on_hpf                                                    **;
** Purpose: This program figures out for what hotels and by groups to       **;
**          tuop_code and by-variables groupings in the input demand data   **;
**          that are calculated by comparing error values from baseline     **;
**          forecast and HPF best diagnosed models.                         **;
**                                                                          **;
** Design Module:                                                           **;
**                                                                          **;
** By:          Julia morrison dec 2009                                     **;
**                                                                          **;
******************************************************************************;

%macro turn_on_hpf (
               baseline_weights_libref,
                baseline_weights_table,
                prop_code_process_list_table,
                  by_variables,
                Daily_master,
                run_date_1,
				run_date_2,
				switch_diff,
				fcst_diff,
				as_of_date)
    ;


	/*** keep only properties on the prop_code_process_list_table***/
   	
    proc sort data = &Daily_master;
	   by prop_code &by_variables run_date;
	   run;
    
	proc means data = &Daily_master noprint;
	   by prop_code &by_variables run_date;
	   output out=error_compare
	          mean(base_error) = base_error
			  mean(hpf_error) = hpf_error
              mean(base_fcst) = base_fcst
              mean(hpf_fcst) = hpf_fcst;
	run;

	data error_date1;
	   set error_compare;
	   where run_date = input("&run_date_1",mmddyy10.);
	   turn_on1 = 0;
	   if hpf_error <= base_error - &switch_diff then turn_on1 = 1;
	   run;

	data error_date2;
	   set error_compare;
	   where run_date = input ("&run_date_2",mmddyy10.);;
	   turn_on2 = 0;
	   if hpf_error <= base_error - &switch_diff then turn_on2 = 1;
	   run;

	   data fcst_test;
	   set error_compare;
	   where run_date = input ("&as_of_date",mmddyy10.);;
	   turn_on3 = 0;
	   if (hpf_fcst <= base_fcst * (1+ &fcst_diff)) and 
          (hpf_fcst >= base_fcst * (1 - &fcst_diff)) then turn_on3 = 1;
	   run;

	   data baseline_weights;
	      merge error_date1 error_date2 fcst_test;
		  by  prop_code &by_variables;
		  weight = turn_on1*turn_on2*turn_on3 ;
		  length byvar $32.;
          length byvarvalue $64.;
          byvar  = 'TFH_RMC';
            
          byvarvalue = &by_variables;
		  id = compress(byvar !! byvarvalue) ;
          format as_of_date MMDDYY10.;
          as_of_date = input ("&as_of_date",mmddyy10.);
          run_date   = as_of_date;      
		  keep id byvar byvarvalue prop_code weight as_of_date run_date ;

		  run;

 proc sort data = baseline_weights ;
            by prop_code  ;
        run;

proc sort data = &prop_code_process_list_table;
            by prop_code  ;
        run;


data baseline_weights;

       merge baseline_weights &prop_code_process_list_table
                         (keep = prop_code in=in2);   
                             

 by prop_code  ;
 if (in2);
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
            index create comp = (prop_code id byvar as_of_date) ;
        quit;
    %end;
    %else %do ;

        proc sort data = baseline_weights ;
            by prop_code id byvar as_of_date ;
        run;

 *update historic baseline weights ;
        data &baseline_weights_libref..&baseline_weights_table 
               (keep= prop_code id byvar as_of_date weight  ) ;
            update &baseline_weights_libref..&baseline_weights_table
                   baseline_weights
            ;
            by prop_code id byvar as_of_date ;
                 if run_date = as_of_date;
			*  if weight = '.' then weight = 0  ;
          *  if as_of_date ne '.' ;  
         run;

    %end ;
quit;



%mend;
