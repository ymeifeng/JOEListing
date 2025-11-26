********************************************************************************
* Project: AEA JOE Job Ads (Cleaning & Exploration)
* File : script_clean_JOE.do
* Author: Meifeng Yang
* Date Created: 11/22/2025
* Date Modified: 11/26/2025
* Stata: SE 18.0
*
* Overview:
*   - Download current AEA JOE listings as Excel (users will need to do so manually)
*   - Clean and filter to US-based jobs
*   - Flag academic vs non-academic jobs
*   - Aggregate to weekly counts
*   - Produce exploratory graphs
*
* Inputs :
*   - Online JOE export (Excel) at:
*       https://www.aeaweb.org/joe/listings
*
* Outputs:
*   - data/joe_resultset_non_academia_YYYYMMDD.dta
*   - data/joe_resultset_non_academia_YYYYMMDD.xlsx
*   - figures/weekly_job_additions_overall.png
*   - figures/weekly_job_additions_broad_sections.png
*   - figures/weekly_job_additions_detailed_sections.png
*
* Usage :
*   - Open this .do file in Stata and run from top.
*   - Adjust `global root` (project folder) before running.

********************************************************************************

* --- Setup and Download ---
* Set your working directory (need to change if used by others)
cd "C:\Users\ymeifeng\OneDrive - Umich\Desktop\JobMarket\JOEListing"

* 1. Get Today's Date and Format It:
* Get today's date in Stata's internal format
local today = date(c(current_date), "DMY")
* Format the date as YYYYMMDD (e.g., 20251125) for use in the filename
local date_postfix : display %tdCCYYNNDD `today'


* 2. Define filenames for raw and processed data
*    NOTE: You must manually download the Excel file from:
*          https://www.aeaweb.org/joe/listings
*          by clicking "XLS/XML" and saving it in this folder as:
*          joe_resultset_full_YYYYMMDD.xlsx
global raw_filename       "joe_resultset_full_`date_postfix'.xlsx"
global processed_filename "joe_resultset_non_academia_`date_postfix'"

* 3. Import the manually downloaded Excel file
import excel "$raw_filename", sheet("JOE Listings Export") firstrow clear


* --- Import ---
* Import the newly downloaded file using the dynamic raw filename
import excel "$raw_filename", sheet("JOE Listings Export") firstrow clear

* --- Data Processing and Filtering (Existing Optimized Steps) ---
rename location full_location
keep full_location jp_institution jp_title jp_full_text jp_salary_range jp_section Application_deadline Date_Active jp_id

* 1. Filter for USA locations:
keep if strmatch(full_location, "UNITED STATES*")

* 2. Extract City:
gen city = trim(substr(full_location, 17, .))
drop full_location


* --- Date Processing ---
gen deadline = date(substr(Application_deadline, 1, 10), "YMD")
format deadline %td
drop Application_deadline

* --- Final Sorting and Export ---
sort deadline
// order city jp_institution jp_title deadline Date_Active
order deadline jp_institution jp_title jp_id Date_Active jp_salary_range jp_full_text	city

* academia vs. non-academia 
gen nonacademia = strpos(jp_section, "Academic") == 0
label define acadlbl 0 "Academic" 1 "Non-academic"
label values nonacademia acadlbl


*** section 1: download excel file with non-academia OR academia information ***

*** for people who do not want academia jobs, only care about posting for non-academia ***
preserve 
* 3. Select Non-Academia:
keep if nonacademia==1 // change to 0 if only want to keep academia information; also need to modify processed_filename

* Export using the dynamic processed filename
export excel using "$processed_filename.xlsx", firstrow(variables) replace
restore 


save "$processed_filename", replace 



**************************************************************
* ---------- Checkpoint ----------
* If you already have a processed .dta file in $data, you can
* comment out the download/import/cleaning section above and
* start from here:
*     use "$processed_filename", clear
* ---------------------------------

**************************************************************

*** section 2: visualizing number of job posting each week ***
use "$processed_filename", clear 

* --- Data Preparation  ---
* Convert the 'Date_Active' string to a Stata date variable
cap drop active_date week_start_date week weeknum
gen active_date = date(substr(Date_Active, 1, 10), "YMD")
format active_date %td
sort active_date

gen week = wofd(active_date)
format week %tw
// gen weeknum = week(active_date)

* rebuild value labels so weeks show as 2025w16 etc.
cap label drop weeklbl

levelsof week, local(wlist)

local first = 1
foreach w of local wlist {
    local lab : display %tw `w'
    if `first' {
        label define weeklbl `w' "`lab'", replace
        local first = 0
    }
    else {
        label define weeklbl `w' "`lab'", add
    }
}

label values week weeklbl

* --- Aggregation ---
preserve 

contract week, freq(overall_weekly_count)

* --- Visualization ---
* 1. Declare the data to be a time series based on the 'week' variable
// tsset week, weekly

* 2. bar chart 
gr bar overall_weekly_count, over(week, label(angle(45))) ///
 title("Jobs Added Per Week") ytitle("Number of Jobs Added")

* Export the graph to a file
graph export "weekly_job_additions_overall.png", replace

restore 


*********** Section 2.1: broad category ********************
*** side-by-side bar graph by academia vs. non-academia ***
preserve 

* 1. Collapse to week x nonacademia counts
contract week nonacademia, freq(section2_weekly_count)

* 2. Reshape wide: one variable per group (0 = academic, 1 = non-academic)
reshape wide section2_weekly_count, i(week) j(nonacademia)

* Optional: treat missing as zero, in case some weeks have only one type
foreach v of varlist section2_weekly_count0 section2_weekly_count1 {
    replace `v' = 0 if missing(`v')
}

* 3. Label the new variables for legend
label var section2_weekly_count0 "Academic"
label var section2_weekly_count1 "Non-academic"

* 4. Side-by-side (clustered) bars: 2 bars per week
graph bar section2_weekly_count0 section2_weekly_count1, ///
    over(week, label(angle(45))) ///
    title("Jobs Added Per Week: Academic vs Non-academic") ///
    ytitle("Number of Jobs Added") ///
    legend(pos(6) row(1) ///
           label(1 "Academic") ///
           label(2 "Non-academic"))

* Export the graph to a file
graph export "weekly_job_additions_broad_sections.png", replace

restore 


*********** Section 2.2: detailed category ********************
*** stack by section (detailed) ***
preserve 

contract week jp_section, freq(section_weekly_count)
encode jp_section, gen(jp_section_i)

drop jp_section
reshape wide section_weekly_count, i(week) j(jp_section_i)

* Then label the new variables for a nice legend
label var section_weekly_count1 "Full-Time Nonacademic"
label var section_weekly_count2 "International: Other Academic"
label var section_weekly_count3 "Other Nonacademic"
label var section_weekly_count4 "US: Full-Time Academic"
label var section_weekly_count5 "US: Other Academic (Part-time or Adj)"
label var section_weekly_count6 "US: Other Academic (Visiting or Temp)"

* Stacked bar chart by section within week
graph bar section_weekly_count1 section_weekly_count2 section_weekly_count3 ///
section_weekly_count4 section_weekly_count5 section_weekly_count6, ///
    over(week, label(angle(45))) ///
    stack ///
	bar(1, color(gold)) ///
    bar(2, color(blue)) ///
    bar(3, color(red)) ///
    bar(4, color(teal)) ///
    bar(5, color(purple)) ///
    bar(6, color(navy)) ///
    title("Jobs Added Per Week by Section") ///
    ytitle("Number of Jobs Added") legend(pos(6) row(3) ///
           label(1 "Full-Time Nonacademic") ///
		   label(2 "International: Other Academic") ///
           label(3 "Other Nonacademic") /// 
		   label(4 "US: Full-Time Academic") ///
		   label(5 "US: Other Academic (Part-time or Adj)") ///
           label(6 "US: Other Academic (Visiting or Temp)")) 
		   
* Export the graph to a file
graph export "weekly_job_additions_detailed_sections.png", replace
		   
restore 

