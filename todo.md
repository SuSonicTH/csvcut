# csvcut todos

## additional features
* paged output
* option to filter the last x lines (trailer), maybe as part of index filter with negative sign (i.e. --filterLine -1,-2 filters last 2 lines)
* add --sum option to sum up numeric columns (i.e. --sum 2,3 would output the unique values of the 1st column and the sums of column 2 and 3)
* even more output formats
  * table output with extra lines between rows (and double lines for header/last line)
  * table output with alternating BG color every 2nd row
  * xml
  * excel

## fixes
* --count causes segfault with aligned outputs
* debug build segfaults in LineReader.zig readLine, release is working

### speed

### cleanup
* add argument check after parsing all the arguments and error if arguments are used together that make no sense
