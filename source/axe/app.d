module axe.app;

import axe.builds;
import std.stdio;

void main(string[] args)
{
    if (args.length < 2)
    {
        writeln("usage: axe input.axe");
        writeln("\t[-e = emit generated code as file | -asm = emit assembly code]");
        return;
    }
    handleMachineArgs(args);
}
