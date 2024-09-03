# csvcut todos

## additional features
* more output formats
  * markdown (all columns are space padded to maximum needed size)
  * jira (space padded jira/confluence markdown output)
* paged output
* paged output which formats output in a nice ascii table format for browsing
* option to filter the last x lines (trailer), maybe as part of index filter with negative sign (i.e. --filterLine -1,-2 filters last 2 lines)
* add --sum option to sum up numeric columns (i.e. --sum 2,3 would output the unique values of the 1st column and the sums of column 2 and 3)

## improvements

### change argument logic
* maybe instead of 2 options to select columns (--fields and --indices) just have --fields and prefix indices with a special character  (e.g. --fields ID,NAME,%5) could come handy for the planned additional --sum feature (else it also needs 2 options)
* single option for input/output formats with argument (i.e. --inputSeparator comma instead of --comma could also accept single characters --inputSeparator ";" )

### speed

### cleanup
* move outputWriter to separate file?