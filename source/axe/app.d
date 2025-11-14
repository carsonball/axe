module axe.app;

import axe.builds;
import axe.meta;
import std.stdio;
import std.algorithm;

void main(string[] args)
{
    if (args.canFind("--version") || args.canFind("-v"))
    {
        writeln(ver ~ "\n" ~ about);
        return;
    }
    if (args.length < 2)
    {
        writeln("usage: axe input.axe");
        writeln("\t[-e = emit generated code as file | -asm = emit assembly code | -r = run after compile]");
        return;
    }
    if (handleMachineArgs(args)) {
        writeln("Compiled.");
    } else {
        writeln("Compilation failed.");
    }
}
