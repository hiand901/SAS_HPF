#! /usr/bin/ksh
# /usr/bin/umask 000

if [[ $# = 1 ]] 
then  
       tz=`echo $1`;
       echo tz =  $tz ;
	
	if [[ "$tz" = "1" || "$tz" = "2" || "$tz" = "3" ]] 
	then  
           if [ "$tz" = "1" ] 
           then 
               SAS_TOP_DIR=/fcst/SAS_HPF/data/tz1;
           else 
               if [ "$tz" = "2" ] 
               then 
                   SAS_TOP_DIR=/fcst/SAS_HPF/data/tz2;
               else 
                   SAS_TOP_DIR=/fcst/SAS_HPF/data/tz3;
               fi;
           fi;

           export SAS_TOP_DIR;

           cd $SAS_TOP_DIR/log;
           rm -f $SAS_TOP_DIR/log/run_forecast_transient.log;

       else
              echo expecting a time zone parameter between 1 and 3;
        	exit 1;
	fi;
else 
	echo ERROR: expecting a time zone parameter between 1 and 3;
	exit 1;
fi;

TODAYDATE=`date +"%d"`

/sashome/SAS/SASFoundation/9.3/sas -nodms /fcst/SAS_HPF/src/call_forecast_transient.sas -sysparm = ALL

if [[ $? -gt 1 ]]
    then
    echo "Failed call_forecast_transient.sas, exiting" >> $SAS_TOP_DIR/log/run_forecast_transient.log;
    exit 2;
    #else
    echo "Successfully ran call_forecast_transient.sas" >> $SAS_TOP_DIR/log/run_forecast_transient.log;
fi;
