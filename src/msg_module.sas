%macro msg_module (errflg, errmsg);

	%if &errflg = -1 %then %put Error: &errmsg ;
	%else %if &errflg > &min_warn_errflg %then %put Warning: &errmsg ;

%mend ;
