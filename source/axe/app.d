module axe.app;

import axe.lexer;
import axe.parser;
import axe.renderer;
import axe.imports;
import axe.structs;
import std.file;
import std.process;
import std.array;
import std.stdio;
import std.algorithm;
import std.string : replace;
import std.path : dirName, buildPath;

void main(string[] args)
{
    if (args.length < 2)
    {
        writeln("usage: axe input.axe");
        writeln("       [-e = emit generated code as file | -asm = emit assembly code]");
        return;
    }

    try
    {
        string name = args[1];
        bool isAxec = name.endsWith(".axec");

        if (!name.endsWith(".axe") && !isAxec)
            name ~= ".axe";

        string source = readText(name);
        auto tokens = lex(source);

        if (args.canFind("-tokens"))
            writeln(tokens);

        auto ast = parse(tokens, isAxec);
        
        ast = processImports(ast, dirName(name), isAxec);

        if (args.canFind("-ast"))
            writeln(ast);

        if (args.canFind("-asm"))
        {
            string asmCode = generateAsm(ast);
            string result = compileAndRunAsm(asmCode);

            if (result.canFind("Error:"))
            {
                stderr.writeln(result);
                return;
            }

            stdout.writeln(result);
        }
        else
        {
            string cCode = generateC(ast);
            string ext = isAxec ? ".axec" : ".axe";
            std.file.write(replace(name, ext, ".c"), cCode);
            auto e = execute([
                "gcc", replace(name, ext, ".c"), "-Wno-everything", "-o",
                replace(name, ext, ".exe")
            ]);
            if (e[0] != 0)
            {
                stderr.writeln(
                    "Fallthrough error, report the bug at https://github.com/navid-m/axe/issues:\nTrace:\n",
                    e[1]
                );
                return;
            }
            if (!args.canFind("-e"))
            {
                remove(replace(name, ext, ".c"));
            }
        }
    }
    catch (Exception e)
    {
        if (e.message.canFind("Failed to spawn process"))
        {
            stderr.writeln(
                "You do not have a C toolchain installed. Install it."
            );
        }
        else
        {
            stderr.writeln("Compilation error: ", e.msg);
        }
    }
}
