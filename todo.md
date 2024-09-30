# csvcut todos

## additional features
* diff 2 csv files
* paged output
* option to filter the last x lines (trailer), maybe as part of index filter with negative sign (i.e. --filterLine -1,-2 filters last 2 lines)
* add --sum option to sum up numeric columns (i.e. --sum 2,3 would output the unique values of the 1st column and the sums of column 2 and 3)
* even more output formats
  * table output with extra lines between rows (and double lines for header/last line)
  * table output with alternating BG color every 2nd row
  * xml
  * excel

## fixes
* figure out why stdin processing is much slower then file processing
* --count causes segfault fith aligned outputs

## improvements
* add option to read (default) arguments from file, searched in ~/.config/csvcut or CWD
  
### change argument logic
* maybe instead of 2 options to select columns (--fields and --indices) just have --fields and prefix indices with a special character  (e.g. --fields ID,NAME,%5) could come handy for the planned additional --sum feature (else it also needs 2 options)

### speed

### cleanup
