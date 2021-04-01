**************************************************************************************;
*  Purpose of this code:                                                             *;
*  1) Read "VA- FY19 Summary of Expenditures by state and county.xlsx" and extract   *;
*     "Veteran Population","County", and "state" for all the 52 states (worksheets). *;
*  2) Read "2019 Poverty and Median Household Income Estimates.xlsx" and extract     *;
*     "Median Household Income" and "county" for all the states.                     *;
*  3) Create the joined table of Veteran Population and Median Household Income by   *;
*     state and county (match on all counties including counties with different      *;
*     written names such as "FAIRBANKS NORTH STAR"and "FAIRBANKS N. STAR" or         *;
*     "STE. GENEVIEVE" and "SAINTE GENEVIEVE").                                      *;
*  4) Exploratory analysis of the relationship between Veteran Population and Median *;
*     Household Income in different counties across the states.                      *;
**************************************************************************************;

/*Location of the files. MODIFY IT.*/
%let dir=/folders/myfolders/SAS assignment;

*******************************;
*  Read the first Excel file: *;
*******************************;
options validvarname=v7;
libname Mylib xlsx "&dir.\VA- FY19 Summary of Expenditures by state and county.xlsx";

proc sql;
	create table sheetnames as 
		select memname as sheets 
		from sashelp.vstabvw 
		where libname="MYLIB" and memname not in ('DATA GUIDE' , 'STATE LEVEL EXPENDITURES');
quit;

data _null_;
	set sheetnames end=last;
	by sheets;
	i+1;
	call symputx('name'||trim(left(put(i, 8.))), sheets);

	if last then
		call symputx('count', i);
run;

%macro combdsheets;
	%do i=1 %to &count;
		%put Reading Worksheet: &&name&i;

		/* select the useful part of the worksheets and create the tables */
		proc sql;
			create table sheet&i as 
				select "&&name&i" as State, 
				        /* remove "(city)" and "city" from the counties names*/
/* 				       strip(prxchange('s/\(CITY\)|CITY//',-1, FY19_Summary_of_Expenditures_by)) as County, */
						upcase(FY19_Summary_of_Expenditures_by) as County,
						B as Veteran_Population 
				from Mylib.&&name&i (firstobs=2) 
				where Veteran_Population is not missing and
				      calculated County not like '%(CITY)' and
				      calculated County not like '%TOTALS' and
					  calculated County not like '%(TOTALS)' and 
					  calculated County not like 'CONG%';
		quit;

		/* change the format of the Veteran_Population column from numeric to character */
		data sheet&i(drop=tempvar);
			length Veteran_Population 8;
			format Veteran_Population COMMA15.;
			Veteran_Population=round(Veteran_Population);
			set sheet&i(rename=(Veteran_Population=tempvar));
			Veteran_Population=input(tempvar, 8.);
		run;

		/* append the sheets for all states*/
		proc append base=VAP_states data=sheet&i force;
		run;

	%end;
%mend combdsheets;
%combdsheets

libname Mylib clear;

*******************************;
* Read the second Excel file: *;
*******************************;
libname Mylib xlsx "&dir./2019 Poverty and Median Household Income Estimates.xlsx";

/* proc contents data=Mylib.EST19ALL; run; */

/* select the useful part of the worksheet and create the table */
proc sql;
	create table MHI_states (drop=FIPS_Code) as 
		select B as FIPS_Code, 
			   C as State_ID,
			   /* removing 'borough', 'census area', 'county', "parish", and "city" from the counties names in county_id*/
			   strip(prxchange('s/BOROUGH|CENSUS AREA|COUNTY|PARISH//', -1, upcase(D))) as County_ID, 
			   W as Median_Household_Income 
	    	from Mylib.EST19ALL (firstobs=4) 
	    	where FIPS_Code ne'000' and calculated County_ID not like '%CITY' 
			order by State_id , county_id;
quit;

/* change the format of the Median_Household_Income column from numeric to character */
data MHI_states(drop=tempvar replace=yes);
	length Median_Household_Income 8;
	format Median_Household_Income COMMA15.;
	set MHI_states(rename=(Median_Household_Income=tempvar));
	Median_Household_Income=input(tempvar, 8.);
run;

libname Mylib clear;

****************************************************;
* Create the joined able of the Veteran Population *;
* and Median Household Income by state and county: *;
****************************************************;

/* join on the matching state and county names that have the same written names on both files */
proc sql;
	create table joined1 as
	select * 
		from MHI_states as ms inner join VAP_states as vs 
			on ms.state_id=vs.state and ms.county_id=vs.county;
quit;

/* find the unmatched cases of the first table*/
proc sql;
	create table unmatchd1 as 
	select VAP_states.* 
		from MHI_states as ms right join VAP_states as vs
			on ms.state_id=vs.state and ms.county_id=vs.county 
			where ms.county_id is NULL;
quit;

/* find the unmatched cases of the second table*/
proc sql;
	create table unmatchd2 as 
	select MHI_states.* 
		from MHI_states as ms left join VAP_states as vs
			on ms.state_id=vs.state and ms.county_id=vs.county 
			where vs.county is NULL;
quit;

/* match the counties that had different written names"*/
proc sql;
	create table joined2 as 
	select unmatchd2.*, unmatchd1.* 
		from unmatchd2 inner join unmatchd1 
			on unmatchd1.state=unmatchd2.state_id and compged(unmatchd1.county, strip(unmatchd2.county_id)) le 400;
quit;

/* create the final joined table for all counties over the states*/
proc sql;
	create table finaltable (keep=State County median_household_income Veteran_Population) as 
	select joined2.* from joined2 
	union 
	select joined1.* from joined1 
	where median_household_income ne .;
quit;

********************************;
* Exploratory analysis: Graphs *;
********************************;
ods graphics on / imagename="VAP_MHI_USA";
ods listing gpath="&dir.";

proc sgplot data=finaltable noautolegend;
	scatter x=median_household_income y=Veteran_Population;
	xaxis grid type=log label="Median Household Income of the county (Log)";
	yaxis grid type=log label="Veteran Population of the county (Log)";
	title "Association of the population of the veterans and the median household income of the counties across the US";
run;


ods graphics on / imagename="VAP_MHI_STATES";
PROC SGPANEL data=finaltable aspect=1;
	panelby state /colheaderpos=top columns=3 rows=3 skipemptycells;
	scatter X=median_household_income Y=Veteran_Population;
	colaxis type=log label="Median Household Income of the county (Log)";
	rowaxis type=log label="Veteran Population of the county(Log)";
	title "Association of the population of the veterans and the median household income of the counties in each state";
RUN;

ods html close;

