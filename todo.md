# csvcut todos

## additional features
* add --sum option to sum up numeric columns (i.e. --sum 2,3 would output the unique values of the 1st column and the sums of column 2 and 3)
* add --sort col1,col2,col3 to sort by (multiple) by columns
* jsonLine output -> like json but each line is a json object
* anonymize columns (--anonymize Number=x3,Name=3x,Account=3*3)
* negative indices for column selection (i.e. -1 is last column, -2 2nd to last,....)
* fixed lenght output
* json,jsonArray and jsonLine input ????

## fixes
* create outputWriter outside of proccessFile to handle multiple input files correctly (and write header once) -> needs a rework how fieldWidths are done (for multiple files)

### speed

### cleanup

## testing
* test main
* test outputs
