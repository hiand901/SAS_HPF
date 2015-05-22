
*********************************************************************************;
** Program:  daily_filter                                                      **;
** Purpose:  This module analyzes the hpf and base line fcst at the daily level**;
** If the proportional variance between hpf and base line fcst is within       **;
** an acceptable threshold values in addition to the tests specified in        **; 
** turn_on_hpf it is considered as a qualified candidate                       **;
** for HPF forecasting                                                         **;
**                                                                             **;
** proportional variance = (hpf_fcst  - base_fcst)/base_fcst                   **;
** Design Module:                                                              **;
** By: Vasan Feb,   2010                                                       **;
*********************************************************************************;

%macro daily_filter
(   llimit,
    ulimit,
	daily_fail_threshold
)
;
*%let llimit = -0.5;
*%let ulimit =  0.5;
*%let daily_fail_threshold = 15 ;

%put &llimit  &ulimit  &daily_fail_threshold ;

libname  hpfsys  "/fcst/HPF/SAS/sasdata/transient" ;
**proc print data = hpfsys.historical_baseline_weights; 

proc transpose data = hpfsys.historical_baseline_weights
  out =  weights_trns ;
by prop_code  ;
var weight;
  
proc print data= weights_trns;
title ' weights_trns  - contains all properties ';

* list of valid properties based on weights only;
data valid_list   (rename = (col1 = rmc1 col2 = rmc2 ))  ; 
set weights_trns ;

if col1 = 0  and col2 = 0 then delete;  
if col1 = 0  and   '.' then delete ;

run;

proc sort data = hpfsys.daily_master;
by prop_code;

proc sort data = valid_list ;
by prop_code;
 
proc print data= valid_list;
title ' valid_list ';


* apply the day level criterion to daily master;
data  selected (drop = actual base_error hpf_error )    ; 
merge hpfsys.daily_master (in = A )  
       valid_list         (in = B);
by prop_code;
format daily_diff 5.3;
if (B) and arrival_date ge  today ();
if base_fcst  > 0 then do;  
   daily_diff = ( hpf_fcst-base_fcst)/base_fcst;
end;
else daily_diff = 0;
* flag = 0 indicates rejection at day level;
if daily_diff < &llimit or daily_diff > &ulimit then flag = 0;
else flag = 1;
run;

proc means data = selected sum;
by prop_code tfh_rmc ;
var flag;
output out = sel_sum  (drop = _type_ _freq_ );
run;

* cnt_flag is the count of rejections   ;
proc sql;
create table sel_prop as 
select prop_code, tfh_rmc, cnt_flag  from (
select prop_code, tfh_rmc, count(flag)as  cnt_flag  from selected 
where flag = 0
group by prop_code, tfh_rmc  )  A
where cnt_flag <  &daily_fail_threshold
;

quit;

*data hpfsys.historical_baseline_weights2;

data hpfsys.historical_baseline_weights;
merge hpfsys.historical_baseline_weights (in= inA)
             sel_prop (in = inB);
by prop_code; 
if (inA) and (inB);
if weight  in (0,1 );
if tfh_rmc = substr(id,8,1);
run;


%mend;

 *%daily_filter ( ); 

 * before moving to prod do the following;
 * NOTE: IMPORTANT rename weights2 weights; comment out %daily_filter  :
