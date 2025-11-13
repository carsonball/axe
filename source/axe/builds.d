module axe.builds;

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

/**
 * Compiles and runs the generated assembly code.
 *
 * Returns NASM errors if any.
 */
string compileAndRunAsm(string asmCode)
{
    string asmFile = buildPath(tempDir(), "temp.asm");
    string objFile = buildPath(tempDir(), "temp.o");
    string exeFile = buildPath(tempDir(), "temp.exe");

    std.file.write(asmFile, asmCode);

    auto nasmResult = execute(["nasm", "-f", "win64", "-o", objFile, asmFile]);

    if (nasmResult.status != 0)
        return "NASM Error: " ~ nasmResult.output;

    auto linkResult = execute(["clang", "-o", exeFile, objFile, "-lmsvcrt"]);

    if (linkResult.status != 0)
        return "Linker Error: " ~ linkResult.output;

    auto runResult = execute([exeFile]);
    return runResult.output;
}

void handleMachineArgs(string[] args)
{
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
                "clang", replace(name, ext, ".c"), "-Wno-everything", "-Os", "-o",
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
                "You do not have the clang toolchain installed. Install it. (https://clang.llvm.org/)."
            );
        }
        else
        {
            stderr.writeln("Compilation error: ", e.msg);
        }
    }
}
