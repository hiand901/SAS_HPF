******************************************************************************;
** Program: assign_events_libref.sas                                        **;
** Purpose: This program assigns the 'eventlib' libref to the DB2 database  **;
**          that contains the oyt_gf_event_dtl table that holds event       **;
**          information.                                                    **;
**                                                                          **;
** Design Module: Section ? of the HPF Forecast System Design Document      **;
** By:      Andrew Hamilton, Oct 1st 2008.                                  **;
**                                                                          **;
** Note that this program is designed to work with development.             **;
******************************************************************************;

%macro assign_events_libref (db_name) ;

    %let MF_DB = DSNT;
    %let schema = YMT;

    %if &DB_Name = MF %then
        libname eventlib DB2 DB=&MF_DB USER=C195722 USING=staple2 SCHEMA=&schema;
    %else %if &DB_Name = UDB %then
        libname eventlib DB2 DB=OYSASDV1 USER=gfctdev USING=Agd4pb!
                                            SCHEMA=forecaster;

%mend ;
