******************************************************************************;
** Program: Call_Diagnose_Group_EventRem.sas                                **;
** Purpose: Call the run_diagnose program with a configuration file that is **;
**          set up for Group Model selection using Event Removal.           **;
** Design Module:                                                           **;
** By:      Andrew Hamilton, Aug 20th 2008.                                 **;
**                                                                          **;
******************************************************************************;

options mprint symbolgen mlogic sasautos = (Sasautos, "/tpr/trans_fcst/SASCode/HPF") ;

%run_diagnose (/g4cast/lib , diagnose_group_eventrem_config.txt) ;
