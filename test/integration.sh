#!/usr/bin/env bash
#
# Integration tests for the csvcut command line tool.
# Run with: ./test/integration.sh [path-to-csvcut]
#
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/zig-out/bin/csvcut}"
if [ "${BIN#/}" = "$BIN" ]; then
    BIN="$(cd "$(dirname "$BIN")" 2>/dev/null && pwd)/$(basename "$BIN")"
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -x "$BIN" ]; then
    echo "integration: binary not found or not executable: $BIN" >&2
    exit 1
fi

cd "$WORK" || exit 1
export LC_ALL=C

pass=0
fail=0

fail_test() {
    echo "FAIL $1: $2"
    fail=$((fail + 1))
}

check() {
    local name="$1" expected_status="$2" expected="$3"
    shift 3
    local output status
    output="$("$BIN" "$@" 2>"$WORK/stderr")"
    status=$?

    if [ "$status" -ne "$expected_status" ]; then
        fail_test "$name" "exit code $status, expected $expected_status"
        sed 's/^/  stderr: /' "$WORK/stderr" | head -3
        return
    fi
    if [ "$output" != "$expected" ]; then
        fail_test "$name" "unexpected output"
        diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$output") | sed 's/^/  /'
        return
    fi
    pass=$((pass + 1))
}

check_error() {
    local name="$1" needle="$2"
    shift 2
    local status
    "$BIN" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
    status=$?

    if [ "$status" -eq 0 ]; then
        fail_test "$name" "expected a non-zero exit code"
        return
    fi
    if ! grep -qF -- "$needle" "$WORK/stderr"; then
        fail_test "$name" "stderr does not contain '$needle'"
        sed 's/^/  stderr: /' "$WORK/stderr" | head -3
        return
    fi
    pass=$((pass + 1))
}

check_contains() {
    local name="$1" needle="$2"
    shift 2
    local output status
    output="$("$BIN" "$@" 2>"$WORK/stderr")"
    status=$?

    if [ "$status" -ne 0 ]; then
        fail_test "$name" "exit code $status"
        return
    fi
    if ! printf '%s' "$output" | grep -qF -- "$needle"; then
        fail_test "$name" "output does not contain '$needle'"
        return
    fi
    pass=$((pass + 1))
}

check_ok() {
    local name="$1"
    shift
    local status
    "$BIN" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
    status=$?

    if [ "$status" -ne 0 ]; then
        fail_test "$name" "exit code $status"
        sed 's/^/  stderr: /' "$WORK/stderr" | head -3
        return
    fi
    pass=$((pass + 1))
}

check_json() {
    local name="$1"
    shift
    local output status
    output="$("$BIN" "$@" 2>"$WORK/stderr")"
    status=$?

    if [ "$status" -ne 0 ]; then
        fail_test "$name" "exit code $status"
        return
    fi
    if ! printf '%s' "$output" | python3 -m json.tool >/dev/null 2>&1; then
        fail_test "$name" "output is not valid JSON"
        return
    fi
    pass=$((pass + 1))
}

check_xml() {
    local name="$1"
    shift
    local status
    "$BIN" -o "$WORK/out.xls" "$@" >/dev/null 2>"$WORK/stderr"
    status=$?

    if [ "$status" -ne 0 ]; then
        fail_test "$name" "exit code $status"
        return
    fi
    if ! python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$WORK/out.xls" 2>/dev/null; then
        fail_test "$name" "output is not valid XML"
        return
    fi
    pass=$((pass + 1))
}

# Fixtures
printf 'ONE,TWO,THREE\nA,1,x\nB,2,y\nA,1,x\n' > data.csv
printf 'a,b\n1,2\n' > small.csv
printf 'a,b\n1,2\n1,2\n' > duplicate.csv
printf 'a,b\n1,2,3,4\n' > ragged.csv
printf '1,2\n3,4\n' > noheader.csv
printf 'a,b\n"x,y",z\n"say ""hi""",w\n' > quoted.csv
printf 'a,b\nva"l,<script>alert(1)</script>\n' > json.csv
printf 'a,b\nx=y,1\nz,2\n' > equals.csv
printf 'a\n<script>alert(1)</script>\n' > html.csv
printf 'a,b\n"1,234,567",y\n' > grouped.csv
printf 'a,b\n' > headeronly.csv
: > empty.csv
printf 'a,b\n1,2\n' > first.csv
printf 'c,d\n3,4\n' > second.csv
printf 'A B   C     D         1 2' > fixed.dat
printf 'AABBCCDDEE\n1122\n' > fixed-eol.dat
printf '"h""H",b\n"zz""Z",y\n' > quoted-header.csv
printf 'h\nA\nB\nC\nD\n' > skip.csv
printf 'h\na\nlongvalue\n' > limit.csv
printf 'a,b\n"unterminated\n' > bad-quote.csv
printf 'a,b\n\xff\xfe,ok\n' > non-utf8.csv
printf 'a,b\nx\xef\xbf\xbe y,ok\n' > noncharacter.csv
printf '1\n2\n3\n4\n' > noheader-skip.csv
: > empty.config
printf -- '--config self.config\n' > self.config
mkdir -p adir
cp small.csv same.csv
python3 -c "print('h'); print('x*' * 6000)" > long.csv

check "empty input" 0 "" empty.csv
check "select by index" 0 \
'ONE,THREE
A,x
B,y
A,x' -I 1,3 data.csv
check "exclude by index" 0 \
'ONE,THREE
A,x
B,y
A,x' -E 2 data.csv
check "select by name" 0 \
'ONE,TWO
A,1
B,2
A,1' -I ONE,TWO data.csv
check "unique" 0 \
'ONE,TWO
A,1
B,2' --unique -I 1,2 data.csv
check "count keeps first seen order" 0 \
'ONE,Count
A,2
B,1' --count -I 1 data.csv
check "list header" 0 \
'ONE
TWO
THREE' -l data.csv
check "list supplied header" 0 \
'one
two' -l -h one,two

check "ragged rows are trimmed to the header width" 0 \
'[
{"a": "1", "b": "2"}
]' --format json ragged.csv
check "short raw output" 0 \
'a,b' --inputLimit 1 -I 1,2 small.csv
check "skipLines csv" 0 \
'h
B
C
D' --skipLines 1 skip.csv
check "skipLines table matches csv" 0 \
'┌─┐
│h│
├─┤
│B│
│C│
│D│
└─┘' --format table --skipLines 1 skip.csv
check "inputLimit csv" 0 \
'h
a' --inputLimit 2 limit.csv
check "inputLimit table matches csv" 0 \
'┌─┐
│h│
├─┤
│a│
└─┘' --format table --inputLimit 2 limit.csv
check "skipLines respects inputLimit" 0 \
'h' --skipLines 1 --inputLimit 2 skip.csv
check "headerless skipLines respects inputLimit" 0 \
'1' -n --skipLines 1 --inputLimit 2 noheader-skip.csv

check "markdown with one character columns" 0 \
'| a | b |
| --- | --- |
| 1 | 2 |' --format markdown small.csv
check "table without output header" 0 \
'┌─┬─┐
│1│2│
└─┴─┘' --format table -N small.csv
check "json without output header" 0 \
'[
{"ONE": "A", "TWO": "1", "THREE": "x"},
{"ONE": "B", "TWO": "2", "THREE": "y"},
{"ONE": "A", "TWO": "1", "THREE": "x"}
]' --format json -N data.csv
check "json without input header" 0 \
'[
{"1": "1", "2": "2"},
{"1": "3", "2": "4"}
]' --format json -n noheader.csv
check "json escapes values" 0 \
'[
{"a": "va\"l", "b": "\u003cscript\u003ealert(1)\u003c/script\u003e"}
]' --format json json.csv
check "json unique" 0 \
'[
{"a": "1", "b": "2"}
]' --format json --unique duplicate.csv
check "escaped header survives data parsing" 0 \
'[
{"h\"H": "zz\"Z", "b": "y"}
]' -q double --format json quoted-header.csv
check "count keeps escaped header" 0 \
'"h""H",b,Count
"zz""Z",y,1' -q double --count quoted-header.csv
check_json "json with invalid utf8 is still valid json" --format json non-utf8.csv
check "filter regex containing equals" 0 \
'a,b
x=y,1' --filter '1~=' equals.csv

check "csv quoting on input and output" 0 \
'a,b
"x,y",z
"say ""hi""",w' -q double quoted.csv
check "csv forcing quotes" 0 \
'"a","b"
"x,y","z"
"say ""hi""","w"' -q double -Q double quoted.csv
check "long quote option" 0 \
'a,b
"x,y",z
"say ""hi""",w' --quote double quoted.csv
check "long output quote option" 0 \
'"a","b"
"x,y","z"
"say ""hi""","w"' --quote double --outputQuote double quoted.csv
check_error "removed quote spelling is rejected" "unknown" --quoute double quoted.csv

check_contains "html escapes html" '<td>&lt;script&gt;alert(1)&lt;/script&gt;</td>' --format html html.csv
check_contains "handson escapes js" '\u003cscript\u003e' --format htmlHandson html.csv
check_contains "handson disables headers" 'colHeaders: false' --format htmlHandson -N html.csv
check_contains "excelxml grouped number" '<Data ss:Type="Number">1234567</Data>' -q double --format excelXml grouped.csv
check_xml "excelxml sanitizes xml noncharacters" --format excelXml noncharacter.csv

check "multiple input files" 0 \
'a,b
1,2
c,d
3,4' first.csv second.csv
check_ok "fixed length with partial last record" --lengths 2,4,6,10 fixed.dat
check "fixed length partial record ignores trailing eol" 0 \
'AA,BB,CC,DD,EE
11,22,,,' --lengths 2,2,2,2,2 --extraLF --trim fixed-eol.dat
check_ok "huge record length does not crash" --lengths 18446744073709551615 small.csv
check_ok "long markdown field does not crash" --format markdown long.csv
check "header only table" 0 \
'┌─┬─┐
│a│b│
├─┼─┤
└─┴─┘' --format table headeronly.csv

check_error "empty argument" "empty argument" ""
check_error "zero field index" "indices start at 1" -I 0 data.csv
check_error "out of range field index" "out of range" -I 9 data.csv
check_error "unknown header field" "was not found" -I nope data.csv
check_error "empty selection field" "empty field" -I , data.csv
check_error "empty include list" "empty field" -I "" data.csv
check_error "empty exclude list" "empty field" -E "" data.csv
check_error "empty filter list" "empty field" --filter "" data.csv
check_error "all columns excluded" "no columns selected" -E 1-3 data.csv
check_error "excluded index out of range" "out of range" -E 9 data.csv
check_error "trailing range" "invalid field range" -I 1- data.csv
check_error "directory input" "could not read input file" adir
check_error "output equals input" "also an input file" -o same.csv same.csv
check_error "unterminated quoted field" "unterminated quoted field" -q double bad-quote.csv
check_error "config recursion" "nested too deeply" --config self.config small.csv
check_error "zero length" "greater than 0" --lengths 0 data.csv
check_error "invalid number" "not a valid number" --skipLines x data.csv
check_error "invalid filter" "invalid filter" --filter nope data.csv
check_error "zero filter index" "indices start at 1" --filter 0=A data.csv
check_error "out of range filter index" "out of range" --filter 9=A data.csv
check_error "filter ranges are rejected" "invalid field range" --filter 1-2=A data.csv
check_error "missing input" "no input file" -l
check_error "empty config name" "empty argument" --config "" data.csv
check "empty config is a no-op" 0 \
'a,b
1,2' --config empty.config small.csv
: > default.config
check "empty default.config is a no-op" 0 \
'a,b
1,2' small.csv
rm -f default.config
check "list header ignores output" 0 \
'a
b' -l -o same.csv same.csv
check_error "output alias equals input" "also an input file" -o ./same.csv same.csv
check_error "headerless all columns excluded" "no columns selected" -n -E 1,2 noheader.csv
if [ -w /dev/full ]; then
    check_error "write failure" "could not write output" -o /dev/full small.csv
fi
check_error "no header for name filter" "requires a header" -n --filter a=1 data.csv

echo "integration: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
