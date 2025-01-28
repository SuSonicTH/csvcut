# csvcut todos

## additional features
* add --sum option to sum up numeric columns (i.e. --sum 2,3 would output the unique values of the 1st column and the sums of column 2 and 3)

## fixes
* create outputWriter outside of proccessFile to handle multiple input files correctly (and write header once) -> needs a rework how fieldWidths are done (for multiple files)

### speed

### cleanup

