# csvcut todos

## additional features
* more output formats
  * markdown (all columns are space padded to maximum needed size)
  * lazyJira (quick and dirty confluence/jira markup)
  * jira (space padded jira/confluence markdown output)
* paged output which formats output in a nice ascii table format for browsing
* option to filter indexed lines at the beginning of the file (i.e. --filterLine 1,3,4 to filter lines 1,3 and 4)
* option to filter the last x lines (trailer), maybe as part of index filter with negative sign (i.e. --filterLine -1,-2 filters last 2 lines)
* add --unique option zo get only unique output lines
* add --count option count of all output combinations
* add --sum option to sum up numeric columns (i.e. --sum 2,3 would output the unique values of the 1st column and the sums of column 2 and 3)

## improvements

### change argument logic
* maybe instead of 2 options to select columns (--fields and --indices) just have --fields and prefix indices with a special character  (e.g. --fields ID,NAME,%5) could com handy for the planned additional --sum feature (else it also needs 2 options)
* single option for input/output formats with argument (i.e. --inputSeparator comma instead of --comma could also accept single characters --inputSeparator ";" )

### speed

### cleanup
* move options to separate file
* move file processing to separate file?