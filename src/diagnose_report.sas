******************************************************************************;
** Program: diagnose_report.sas                                             **;
** Purpose: generates a report showing thw results of the diagnose process  **;
**          shows the hpf ,baseline fcst errors by property                 **;
**         and the recommended HPF methodology                              **;
** Design Module:                                                           **;
** THIS IS NOT A PART OF THE PROD PROCESS 
*****************************************************************************;


libname hpfsys '/fcst/HPF/SAS/sasdata/transient';

  proc sort data = hpfsys.historical_baseline_weights ;
  by prop_code  id  byvar  as_of_date;

   data blweights     (keep = prop_code weight tfh_rmc as_of_date );
   set  hpfsys.historical_baseline_weights;
   format as_of_date yymmdd10. ; 
   tfh_rmc = substr (id,8,1);
   run;         

  proc print data = blweights (obs = 5);
  title ' base line weights '; 



  proc print data = hpfsys.error_compare_retain    (obs = 5);
  title '  error compare    '; 



  data mrgd  (drop = _type_ _freq_ turn_on3 );
  merge hpfsys.error_compare_retain    
         blweights  ; 
        by prop_code tfh_rmc  ; 

retain hdr 1;
if  (col1 = 1 and col2 = 1 ) or (col1 = 1 and col2 = '.' );
if col2 = '.' then col2 = 0;


 proc print data = mrgd;
 title ' mrgd ' ;
       



/*** list of properties with both weights = 1 for two room properties and weight = 1 
for 1 room property ***/


proc transpose data = hpfsys.historical_baseline_weights
  out =  weights_trns ;
by prop_code  ;
var weight;


data final  (drop = _name_ rename = (col1 = rmc1  col2 = rmc2 ));
set weights_trns;
retain hdr 1;
if  (col1 = 1 and col2 = 1 ) or (col1 = 1 and col2 = '.' );
if col2 = '.' then col2 = 0;


run;

proc print data=final;
run;


proc sql;
select ' nbr of props selected for HPF  '  ,  count(distinct prop_code) from final;



 select 'nbr of total props ' , count (distinct prop_code) from  hpfsys.historical_baseline_weights ;

quit;   
