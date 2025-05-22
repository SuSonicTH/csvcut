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

### Windows zig setup example for x86_64
execute following commands in a windows Command Prompt (cmd.exe)
```cmd
curl https://ziglang.org/download/0.14.0/zig-windows-x86_64-0.14.0.zip --output zig.zip
tar -xf zig.zip
del zig.zip
set PATH=%cd%\zig-windows-aarch64-0.14.0;%PATH%
```

### Linux zig setup example for x86_64
either install zig 0.14.0 with your package manager or
execute following commands in a shell
```bash
wget https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz
tar -xf zig-linux-x86_64-0.14.0.tar.xz
rm zig-linux-x86_64-0.14.0.tar.xz
export PATH=$(pwd)/zig-linux-x86_64-0.14.0.tar.xz:$PATH
```

## Build
If you have zig installed and on your `PATH` just cd into the directory and execute `zig build`
The first build takes a while and when it's finished you'll find the executeable (csvdiff or csvdiff.exe) in zig-out/bin/
You can run the built-in unit tests with `zig build test` If everything is ok you will see no output.
Use `zig build -Doption=ReleaseFast` to build a release version optimized for speed.
