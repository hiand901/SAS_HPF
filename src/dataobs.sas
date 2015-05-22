******************************************************************************;
** Program: dataobs.sas                                                     **;
** Purpose: This program calculates the number of records in the data set   **;
**          supplied to the program in the input parameter.                 **;
**                                                                          **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:          Andrew Hamilton, July 17th 2008.                            **;
**                                                                          **;
******************************************************************************;

%macro   dataobs (dsname) ;

        %global dataobs ;

        ** Initialize **;
        %let dataobs = 0 ;


        %let ex_rc = %sysfunc(exist(&dsname)) ;
        %if &ex_rc = 0 %then %do ;
                %let errflg = 1 ;
                %let errmsg = Error occurred in dataobs module - unable to find data table &dsname ;
                %goto macrend ;
        %end;


        data _null_ ;
                set &dsname nobs = numobs ;
                call symput('dataobs', put(numobs,8.)) ;
                stop ;
        run;


        %if &syserr ne 0 %then %do ;

                %if &syserr < 4 %then %do ;
                        %let errflg = -1 ;
                        %let errmsg = Error occurred in dataobs module operating on data table &dsname ;
                %end;
                %else %if &syserr >= 4 %then %do ;
                        %let errflg = 2 ;
                        %let errmsg = Warning occurred in dataobs module operating on data table &dsname ;
                %end;
        %end;


        
         %macrend:

       
%mend dataobs;

