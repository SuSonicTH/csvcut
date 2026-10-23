Output media/csvcut.gif

Hide
Type "PS1='\[\e[96m\]\\$\[\e[0m\] '"
Enter
Type@1ms "zig build native"
Enter
Type@1ms "cp ./media/people.csv ./zig-out/bin"
Enter
Type@1ms "cd ./zig-out/bin"
Enter

Type@1ms "clear"
Enter
Sleep 1s
Show


Sleep 2s
Type "# select columns by name"
Enter
Sleep 500ms

Type "./csvcut people.csv --include Name,Department --format table"
Sleep 500ms
Enter
Sleep 4s

Type@1ms "clear"
Enter
Type "# or by index and range"
Enter
Sleep 500ms

Type "./csvcut people.csv --include 1,3-4 --format table"
Sleep 500ms
Enter
Sleep 4s

Type@1ms "clear"
Enter
Type "# exclude columns and output markdown"
Enter
Sleep 500ms

Type "./csvcut people.csv --exclude City,Salary --format markdown"
Sleep 500ms
Enter
Sleep 4s

Type@1ms "clear"
Enter
Type "# filter rows by column value"
Enter
Sleep 500ms

Type "./csvcut people.csv --filter 'Department=Engineering' --format table"
Sleep 500ms
Enter
Sleep 4s

Type@1ms "clear"
Enter
Type "# summarize with --count"
Enter
Sleep 500ms

Type "./csvcut people.csv --include Department --count --format table"
Sleep 500ms
Enter
Sleep 4s

Type@1ms "clear"
Enter
Type "# export JSON for other tools"
Enter
Sleep 500ms

Type "./csvcut people.csv --include Name,Salary --format json"
Sleep 500ms
Enter
Sleep 4s


Hide
Type@1ms "rm people.csv"
Enter
