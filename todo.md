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
* figure out why stdin processing is much slower then file processing in gitbash (ok in cmd, faster in WSL on ext4)
* --count causes segfault with aligned outputs

### speed

### cleanup
