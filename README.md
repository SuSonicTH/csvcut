# csvcut

`csvcut` is a fast, header-aware command-line tool for slicing CSV files, in the spirit of `cut`. Select or remove columns, filter and deduplicate rows, then export the result as a clean table, Markdown, HTML, JSON, Excel XML, or CSV. It is written in Zig and ships as a single binary with no runtime dependencies.

![csvcut demo](media/csvcut.gif)

## Features

- **Column selection** - choose columns by name or 1-based index, use ranges such as `--include Name,3-5`, or drop columns with `--exclude`.
- **Row filtering** - match fields exactly (`Department=Engineering`) or with regular expressions (`Name~^A`) via `--filter`, and exclude matching rows with `--filterOut`.
- **Deduplication and counting** - collapse repeated rows with `--unique` or summarize them with `--count`, which adds a count column.
- **Multiple output formats** - CSV, compact or evenly spaced Markdown, Jira/Confluence tables, console tables, plain HTML, an interactive Handsontable HTML page, JSON as objects or arrays, and Excel XML.
- **Flexible input** - comma, semicolon, pipe, or tab separators; optional single or double quoting; headers from the file, from the command line, or no header at all; fixed-width records via `--lengths`; and skipped lines.
- **Limits and cleanup** - trim surrounding whitespace with `--trim`, skip lines with `--skipLines`, cap input with `--inputLimit`, and cap output with `--outputLimit`.
- **Multiple files** - process several input files independently in one invocation, writing to stdout or to a file with `-o`.
- **Config files** - a `default.config` in the current directory is applied automatically, and named configs can be loaded with `--config`; `$CSVCUT_CONFIG` overrides the config directory.
- **Fast by default** - memory-mapped input, no quote processing unless requested, and a compact native executable.
- **Helpful diagnostics** - `--listHeader`, `--time`, and a documented list of exit codes via `--exitCodes`.

## Usage

```text
csvcut [OPTION]... FILE...
```

Each `FILE` is processed independently. Formats that emit a complete document (JSON, HTML, Excel XML, and their variants) produce one document per input file. Input from stdin is not supported.

Run `csvcut --help` for the full option reference, which is also kept in [src/USAGE.txt](src/USAGE.txt). A quick example:

```shell
csvcut people.csv --include Name,Department --filter Department=Engineering --format table
```

## Installation

Prebuilt binaries for Linux (x86_64 and aarch64) and Windows (x86_64) are available on the [releases page](https://github.com/SuSonicTH/csvcut/releases). Download the binary for your platform and add it to your `PATH`. No installation or runtime dependencies are required.

## Build requirements

Building csvcut only requires the Zig compiler, which can be downloaded from [https://ziglang.org/download/](https://ziglang.org/download/). Currently Zig 0.17.0 is supported; builds may break with newer or older versions.

Running `zig build test` additionally requires `bash` and `python3` for the integration tests.

### Windows Zig setup example for x86_64

Execute the following commands in a Windows Command Prompt (`cmd.exe`):

```cmd
curl https://ziglang.org/download/0.17.0/zig-x86_64-windows-0.17.0.zip --output zig.zip
tar -xf zig.zip
del zig.zip
set PATH=%cd%\zig;%PATH%
```

### Linux Zig setup example for x86_64

Either install Zig 0.17.0 with your package manager or execute the following commands in a shell:

```bash
wget https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz
tar -xf zig-x86_64-linux-0.17.0.tar.xz
rm zig-x86_64-linux-0.17.0.tar.xz
export PATH=$(pwd)/zig-x86_64-linux-0.17.0:$PATH
```

## Build

With Zig installed and on your `PATH`, run:

```shell
zig build
```

The first build takes a while. When it finishes, the executable (`csvcut` or `csvcut.exe`) is in `zig-out/bin/`.

For an optimized release build for just your native platform, use `zig build native`. This saves a compressed executable as `zig-out/bin/csvcut` (`csvcut.exe` on Windows).

To build compressed release binaries for all supported platforms, run:

```shell
zig build release
```

This saves the following files to `zig-out/bin`:

- `csvcut-x86_64-linux`
- `csvcut-aarch64-linux`
- `csvcut-x86_64-windows.exe`

## Tests

Run the built-in unit and integration tests with:

```shell
zig build test
```

## License

csvcut is licensed under the MIT license. See [LICENSE.txt](LICENSE.txt).
