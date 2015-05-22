

data hpfsys.best_model_overwrite_data ;

    length Id $256 byvar $32 ByVarValue $64 Model_Name $8 ;

    id = "ABQNMLARGEHUGE" ;

    byvar = "prop_code";

    ByVarValue = "ABQNM" ;

    Model_Name = "SPEC00" ;

    output ;

    byvar = "segment";

    ByVarValue = "LARGE" ;

    output ;

    byvar = "segment_huge_tiny";

    ByVarValue = "HUGE" ;

    output ;



    id = "ATLEGSMALLTINY" ;

    byvar = "prop_code";

    ByVarValue = "ATLEG" ;

    Model_Name = "SPEC10" ;

    output ;

    byvar = "segment";

    ByVarValue = "SMALL" ;

    output ;

    byvar = "segment_huge_tiny";

    ByVarValue = "TINY" ;

    output ;

 run;

