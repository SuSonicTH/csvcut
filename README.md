# csvcut

As a learning exercise to get to know zig I build a small command line tool that works like the *cut* utility but uses the header to identify columns additionaly to indices and has some extra functionality build in.

Feedback from more experienced zig developers is very welcome.
If you find any bug or you see some non-idiomatic costructs please let me know.

## Usage
see [src/USAGE.txt](src/USAGE.txt)

## Licence
csvcut is licensed under the MIT license

see [LICENSE.txt](LICENSE.txt)

## Build requirements
To build csvcut you just need the zig compiler, which can be downloaded from [https://ziglang.org/download/](https://ziglang.org/download/) 
Currently zig master (0.14.0) is supported, builds might break in never and older versions.
There is no installation needed, just download the package for your operating system an extract the archive and add it to your `PATH`

### Windows example
execute following commands in a windows Command Prompt (cmd.exe)
```cmd
curl https://ziglang.org/builds/zig-windows-x86_64-0.14.0-dev.2851+b074fb7dd.zip --output zig.zip
tar -xf zig.zip
del zig.zip
move zig-windows-x86_64-0.14.0-dev* zig
set PATH=%cd%\zig;%PATH%
```

### Linux example
execute following commands in a shell
```bash
curl zig-linux-x86_64-0.14.0-dev.2851+b074fb7dd.tar.xz --output zig.tar.xz
tar -xf zig.tar.xz
rm zig.tar.xz
mv zig-linux-x86_64-0.14.0-dev* zig
export PATH=$(pwd)/zig:$PATH
```

## Build
If you have zig installed and on your `PATH` just cd into the directory and execute `zig build`
The first build takes a while and when it's finished you'll find the executeable (csvcut or csvcut.exe) in zig-out/bin/
You can run the built-in uinit tests with `zig build test` If everything is ok you will see no output.
Use `zig build -Doption=ReleaseFast` to build a release version optimized for speed.
