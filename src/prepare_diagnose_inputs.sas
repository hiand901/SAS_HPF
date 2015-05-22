***********************************************************************;
** Program : prepare_diagnose_inputs.sas                             **;
** Purpose : Concatenate time zone-group dependant input data sets   **;
**           to the SAS HPF diagnose process.                        **;
**                                                                   **;
**                                                                   **;
** By      : Andrew Hamilton, Nov 21, 2011.                           **;
**                                                                   **;
** Modified                                                          **;
**                                                                   **;
***********************************************************************;

%macro prepare_diagnose_inputs (historical_demand_path,
                                historical_demand_table,
                                events_info_path,
                                events_info_table,
                                common_base_dir,
                                prop_list_file_name,
                                asofdt,
                                output_demand_data,
                                output_event_data,
                                prop_list_output_data
                                );



    ** Obtain the locations of the three timezone-dependant input **;
    ** demand data sets. The following assumes that the data path **;
    ** of all the input data conforms to the current standard:    **;
    ** ie. []/data/tz[1-3]/[].                                    **;
    ** The same is done for the input events tables.              **;

	data _null_;

        length dt_under $10 ;

        * Find the location up to 'data' *;
        dmd_data_loc = index(lowcase(left("&historical_demand_path")),'data');
        if dmd_data_loc = 0 then call symput('errflg','1');
        else do;
            dmd_tz_top_loc = substr(left("&historical_demand_path"),
                                    1,dmd_data_loc+4) ;
            dmd_tz1_loc = trim(left(dmd_tz_top_loc)) ||'tz1/out';
            dmd_tz2_loc = trim(left(dmd_tz_top_loc)) ||'tz2/out';
            dmd_tz3_loc = trim(left(dmd_tz_top_loc)) ||'tz3/out';
            call symput('dmd_tz1_loc', trim(left(dmd_tz1_loc)));
            call symput('dmd_tz2_loc', trim(left(dmd_tz2_loc)));
            call symput('dmd_tz3_loc', trim(left(dmd_tz3_loc)));
        end;
        event_data_loc = index(lowcase(left("&events_info_path")),'data');
        if event_data_loc = 0 then call symput('errflg','1');
        else do;
            event_tz_top_loc = substr(left("&events_info_path"),
                                      1,event_data_loc+4) ;
            event_tz1_loc = trim(left(event_tz_top_loc)) ||'tz1/out';
            event_tz2_loc = trim(left(event_tz_top_loc)) ||'tz2/out';
            event_tz3_loc = trim(left(event_tz_top_loc)) ||'tz3/out';
            call symput('event_tz1_loc', trim(left(event_tz1_loc)));
            call symput('event_tz2_loc', trim(left(event_tz2_loc)));
            call symput('event_tz3_loc', trim(left(event_tz3_loc)));
        end;
        
        * Define the input prop_list locations *;
        base_data_loc = index(lowcase(left("&common_base_dir")),'data');
        if base_data_loc = 0 then call symput('errflg','1');
        else do;
            base_dir = substr(left("&common_base_dir"),1,base_data_loc+4) ;

            call symput ('plistf1', trim(left(base_dir)) || 
                                    trim(left("tz1/in/&prop_list_file_name")));
            call symput ('plistf2', trim(left(base_dir)) ||
                                    trim(left("tz2/in/&prop_list_file_name")));
            call symput ('plistf3', trim(left(base_dir)) || 
                                    trim(left("tz3/in/&prop_list_file_name")));
        end;

    run;


    %if &errflg > 0 %then %do ;
        %put Error: Unable to determine location of input time zone demand / event data / prop_list file;
        %goto sub_macrend;
    %end;

    libname dmdout "&historical_demand_path";

	%if %sysfunc(libref(dmdout)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &historical_demand_path  ;
        %goto sub_macrend ; 
    %end;


    libname dmddta1 "&dmd_tz1_loc";
    libname dmddta2 "&dmd_tz2_loc";
    libname dmddta3 "&dmd_tz3_loc";


    ** Check the libname **;
    %if %sysfunc(libref(dmddta1)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &dmd_tz1_loc  ;
        %goto sub_macrend ; 
    %end;

    %if %sysfunc(libref(dmddta2)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &dmd_tz2_loc  ;
        %goto sub_macrend ; 
    %end;

    %if %sysfunc(libref(dmddta3)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &dmd_tz3_loc  ;
        %goto sub_macrend ; 
    %end;



    libname eventout "&Events_Info_Path";
	%if %sysfunc(libref(eventout)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &Events_Info_Path  ;
        %goto sub_macrend ; 
    %end;


    libname evntdta1 "&event_tz1_loc";
    libname evntdta2 "&event_tz2_loc";
    libname evntdta3 "&event_tz3_loc";
    

    ** Check the event libname **;
    %if %sysfunc(libref(evntdta1)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &event_tz1_loc  ;
        %goto sub_macrend ; 
    %end;

    %if %sysfunc(libref(evntdta2)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &event_tz2_loc  ;
        %goto sub_macrend ; 
    %end;
    
    %if %sysfunc(libref(evntdta3)) > 0 %then %do;

        %let errflg = -1 ;
        %let errmsg = Unable to assign a libref to the library &event_tz3_loc  ;
        %goto sub_macrend ; 
    %end;

    filename plistf1 "&plistf1";
    %if %sysfunc(fileref(plistf1)) ne 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a fileref to &plistf1  ;
        %goto sub_macrend ; 
    %end;


    filename plistf2 "&plistf2";    
    %if %sysfunc(fileref(plistf2)) ne 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a fileref to &plistf2  ;
        %goto sub_macrend ; 
    %end;


    filename plistf3 "&plistf3";
    %if %sysfunc(fileref(plistf3)) ne 0 %then %do;
        %let errflg = -1 ;
        %let errmsg = Unable to assign a fileref to &plistf3  ;
        %goto sub_macrend ; 
    %end;



    ** Output the Concatenated Demand data. **;

    data &output_demand_data ;
        set dmddta1.&Historical_Demand_Table 
            dmddta2.&Historical_Demand_Table 
            dmddta3.&Historical_Demand_Table ;
    run;


    ** Output the Concatenated Event data. **;

    data &output_event_data ;
        set evntdta1.&Events_Info_Table
            evntdta2.&Events_Info_Table 
            evntdta3.&Events_Info_Table ;
    run;


    ** Output the concatenated property list data set ;
    data prop_list1 ;
        infile plistf1 pad;
        input prop_code $1-5 cap1  10-14    cap2  20-24  ;
    run;

    data prop_list2 ;
        infile plistf2 pad;
        input prop_code $1-5 cap1  10-14    cap2  20-24  ;
    run;

	data prop_list3;
        infile plistf3 pad;
        input prop_code $1-5 cap1  10-14    cap2  20-24  ;
    run;

    data &prop_list_output_data;
        set prop_list1
            prop_list2
            prop_list3 ;
    run;



    proc datasets lib=work nolist;
        delete prop_list1 prop_list2 prop_list3;
    quit;


%sub_macrend:

%mend;
