****************************************************************************;
** Program:   build_prop_list                                                 ***;
** Purpose: This program creates property_list.txt from the fcst prop control ***;
**          file.                                                              **;
** Design Module:      Section ? of the HPF Forecast System Design Doc         **;
** By:       Vasan Jan 2010                                                    **;
**                                                                             **;
*********************************************************************************;

%macro  build_prop_list (
   &config_file_path,
		            );

data _null_;
  call symput('HPF_start', put(datetime(), datetime23.));
run;

%put " ENTERING build_Prop_List  &HPF_start ";
 
filename  propcntl  "&config_file_path/prop_control.txt";
data prop_cntl   (keep = prop_code rmc_code cap );
 	infile propcntl;  
    input  type $  @;
    if type = '01' then delete;  
    input prop_code $4-8    rmc_code $10-10  junk $ 9-39  cap 40-44  ; 
 run;
      
proc transpose data = prop_cntl out = prop_cntl1 (drop = _NAME_  RENAME = (COL1 = CAP1 COL2 = CAP2 ) )  ;
by prop_code  ;
var cap;

data _null_; 
set prop_cntl1;
if cap2 = '.' then cap2 = 0;
if prop_code <  "AGSFS" ;  /** temporary   VASAN  **/
 
file  "&config_file_path/transient_prop_list.txt" ;
put  prop_code    $ 1-5   cap1  10-14    cap2  20-24 ; 

run;
%mend;





