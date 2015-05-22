 data jan_list;
 infile "jan_list.txt";
 input prop_code $;
 run; 

 data feb_list;
 infile "feb_list.txt";
 input prop_code $;
 run; 

  proc sort data = jan_list nodupkey;
  by prop_code; 
 proc sort data = feb_list nodupkey;
  by prop_code; 

 data comb  ;
 merge jan_list (in=inA)  feb_list (in = inB);
 by prop_code;
  jan_flag = '.';
  feb_flag = '.'; 
 if (inA) then  jan_flag = 'y';  
 if (inB) then  feb_flag = 'y'; 



 file jan_feb_comp;
 put prop_code jan_flag  feb_flag;
 run;


 proc print data = comb;

