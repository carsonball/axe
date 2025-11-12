module axe.renderer;

import std.string;
import std.array;
import axe.structs;
import std.exception;
import std.algorithm;

/** 
 * C backend renderer.
 *
 * Params:
 *   ast = Abstract syntax tree to render.
 * Returns: 
 *   Generated C code.
 */
string generateC(ASTNode ast)
{
    string cCode;
    string[] includes = ["#include <stdio.h>"];

    switch (ast.nodeType)
    {
    case "Program":
        foreach (child; ast.children)
        {
            if (child.nodeType == "Function")
            {
                auto funcDecl = child.value.split("(");
                string funcName = funcDecl[0];
                string args = funcDecl.length > 1 ?
                    funcDecl[1].strip(")") : "";
                cCode ~= "void " ~ funcName ~ "(" ~
                    (args.length > 0 ? "int " ~ args.replace(",", ", int ") : "void") ~ ");\n";
            }
        }
        cCode ~= includes.join("\n") ~ "\n\n";
        foreach (child; ast.children)
        {
            cCode ~= generateC(child) ~ "\n";
        }
        break;

    case "Main":
        cCode ~= "int main() {\n";
        foreach (child; ast.children)
        {
            if (child.nodeType == "Println")
            {
                cCode ~= "    printf(\"%s\\n\", \"" ~ child.value ~ "\");\n";
            }
            else if (child.nodeType == "Loop")
            {
                cCode ~= "    while (1) {\n";
                foreach (loopChild; child.children)
                {
                    if (loopChild.nodeType == "Println")
                    {
                        cCode ~= "        printf(\"%s\\n\", \"" ~ loopChild.value ~ "\");\n";
                    }
                    else if (loopChild.nodeType == "Break")
                    {
                        cCode ~= "        break;\n";
                    }
                    else if (loopChild.nodeType == "Assignment")
                    {
                        cCode ~= "        " ~ loopChild.value ~ ";\n";
                    }
                    else if (loopChild.nodeType == "If")
                    {
                        cCode ~= "        if (" ~ loopChild.value ~ ") {\n";
                        foreach (ifChild; loopChild.children)
                        {
                            if (ifChild.nodeType == "Break")
                            {
                                cCode ~= "            break;\n";
                            }
                            else if (ifChild.nodeType == "FunctionCall")
                            {
                                auto parts = ifChild.value.split("(");
                                string funcName = parts[0];
                                string args = parts.length > 1 ? parts[1].strip(")") : "";
                                cCode ~= "            " ~ funcName ~ "(" ~ args ~ ");\n";
                            }
                            else if (ifChild.nodeType == "Assignment")
                            {
                                cCode ~= "            " ~ ifChild.value ~ ";\n";
                            }
                        }
                        cCode ~= "        }\n";
                    }
                    else if (loopChild.nodeType == "FunctionCall")
                    {
                        auto parts = loopChild.value.split("(");
                        string funcName = parts[0];
                        string args = parts.length > 1 ? parts[1].strip(")") : "";
                        cCode ~= "        " ~ funcName ~ "(" ~ args ~ ");\n";
                    }
                }
                cCode ~= "    }\n";
            }
            else if (child.nodeType == "Break")
            {
                cCode ~= "    break;\n";
            }
            else if (child.nodeType == "FunctionCall")
            {
                auto parts = child.value.split("(");
                string funcName = parts[0];
                string args = parts.length > 1 ? parts[1].strip(")") : "";
                cCode ~= "    " ~ funcName ~ "(" ~ args ~ ");\n";
            }
            else if (child.nodeType == "Assignment")
            {
                cCode ~= "    " ~ child.value ~ ";\n";
            }
            else if (child.nodeType == "If")
            {
                cCode ~= "    if (" ~ child.value ~ ") {\n";
                foreach (ifChild; child.children)
                {
                    if (ifChild.nodeType == "Break")
                    {
                        cCode ~= "        break;\n";
                    }
                    else if (ifChild.nodeType == "FunctionCall")
                    {
                        auto parts = ifChild.value.split("(");
                        string funcName = parts[0];
                        string args = parts.length > 1 ? parts[1].strip(")") : "";
                        cCode ~= "        " ~ funcName ~ "(" ~ args ~ ");\n";
                    }
                    else if (ifChild.nodeType == "Assignment")
                    {
                        cCode ~= "        " ~ ifChild.value ~ ";\n";
                    }
                }
                cCode ~= "    }\n";
            }
        }
        cCode ~= "    return 0;\n}";
        break;

    case "Function":
        auto funcDecl = ast.value.split("(");
        string funcName = funcDecl[0];
        string args = funcDecl.length > 1 ?
            funcDecl[1].strip(")") : "";
        cCode ~= "void " ~ funcName ~ "(" ~
            (args.length > 0 ? "int " ~ args.replace(",", ", int ") : "void") ~ ") {\n";
        foreach (child; ast.children)
        {
            final switch (child.nodeType)
            {
            case "Println":
                cCode ~= "    printf(\"%s\\n\", \"" ~ child.value ~ "\");\n";
                cCode ~= "printf(\"%s\\n\", \"" ~ child.value ~ "\");\n";
                break;
            case "FunctionCall":
                auto parts = child.value.split("(");
                auto calledFuncName = parts[0];
                auto calledFuncArgs = parts.length > 1 ? parts[1].strip(")") : "";
                cCode ~= "    " ~ calledFuncName ~ "(" ~ calledFuncArgs ~ ");\n";
                break;
            case "Assignment":
                cCode ~= child.value ~ ";\n";
                break;
            case "If":
                cCode ~= "if (" ~ child.value ~ ") {\n";
                foreach (ifChild; child.children)
                {
                    final switch (ifChild.nodeType)
                    {
                    case "Break":
                        cCode ~= "break;\n";
                        break;
                    }
                }
                cCode ~= "}\n";
                break;
            }
        }
        cCode ~= "}";
        break;

    case "FunctionCall":
        auto parts = ast.value.split("(");
        string funcName = parts[0];
        string args = parts.length > 1 ? parts[1].strip(")") : "";
        cCode ~= funcName ~ "(" ~ args ~ ");\n";
        break;

    case "Assignment":
        cCode ~= ast.value ~ ";\n";
        break;

    case "If":
        cCode ~= "if (" ~ ast.value ~ ") {\n";
        foreach (child; ast.children)
        {
            final switch (child.nodeType)
            {
            case "Break":
                cCode ~= "break;\n";
                break;
            }
        }
        cCode ~= "}\n";
        break;

    default:
        enforce(false, "Unsupported node type for C generation: " ~ ast.nodeType);
    }

    return cCode;
}

import std.conv;

/** 
 * Assembly/NASM backend renderer.
 *
 * Params:
 *   ast = Abstract syntax tree to render.
 * Returns: 
 *   Generated assembly code.
 */
string generateAsm(ASTNode ast)
{
    string asmCode;

    final switch (ast.nodeType)
    {
    case "Program":
        foreach (child; ast.children)
        {
            if (child.nodeType == "Function")
            {
                asmCode ~= generateAsm(child) ~ "\n";
            }
        }
        foreach (child; ast.children)
        {
            if (child.nodeType == "Main")
            {
                asmCode ~= generateAsm(child);
            }
        }
        break;

    case "Main":
        asmCode = `
            section .data
                fmt db "%s", 0
                nl db 10, 0
            section .text
                extern printf
                global main
            main:
                sub rsp, 40
        `;
        int msgCounter = 0;
        foreach (child; ast.children)
        {
            final switch (child.nodeType)
            {
            case "Println":
                asmCode ~= `
                    section .data
                        msg_`
                    ~ msgCounter.to!string ~ ` db '` ~ child.value ~ `', 0
                    section .text
                        mov rcx, msg_`
                    ~ msgCounter.to!string ~ `
                        call printf
                        mov rcx, nl
                        call printf
                `;
                msgCounter++;
                break;

            case "FunctionCall":
                auto callDecl = child.value.split("(");
                string callName = callDecl[0];
                string callArgs = callDecl.length > 1 ? callDecl[1].strip(")") : "";

                if (callArgs.length > 0)
                {
                    auto argList = callArgs.split(",");
                    foreach (i, a; argList)
                    {
                        string param = a.strip();
                        string reg = i == 0 ? "rcx" : 
                                     i == 1 ? "rdx" : 
                                     i == 2 ? "r8" : 
                                     i == 3 ? "r9" : "";
                        
                        if (i < 4) {
                            asmCode ~= "    mov " ~ reg ~ ", " ~ param ~ "\n";
                        } else {
                            asmCode ~= "    mov rcx, " ~ param ~ "\n";
                            asmCode ~= "    push rcx\n";
                        }
                    }
                }

                asmCode ~= "    call " ~ callName ~ "\n";

                // Clean up stack (8 bytes per argument on 64-bit)
                if (callArgs.length > 0 && callArgs.split(",").length > 4)
                {
                    int numStackArgs = cast(int)callArgs.split(",").length - 4;
                    asmCode ~= "    add rsp, " ~ to!string(numStackArgs * 8) ~ "\n";
                }
                break;

            case "Loop":
                int loopId = 0;
                asmCode ~= "loop_" ~ loopId.to!string ~ "_start:\n";
                foreach (loopChild; child.children)
                {
                    final switch (loopChild.nodeType)
                    {
                    case "Println":
                        asmCode ~= `
                            section .data
                                msg_`
                            ~ msgCounter.to!string ~ ` db '` ~ loopChild.value ~ `', 0
                            section .text
                                mov rcx, msg_`
                            ~ msgCounter.to!string ~ `
                                call printf
                                mov rcx, nl
                                call printf
                        `;
                        msgCounter++;
                        break;
                    case "Break":
                        asmCode ~= "    jmp loop_" ~ loopId.to!string ~ "_end\n";
                        break;
                    case "Assignment":
                        auto parts = loopChild.value.split(" = ");
                        if (parts[1].canFind(" - "))
                        {
                            auto exprParts = parts[1].split(" - ");
                            asmCode ~= "    mov eax, " ~ exprParts[0] ~ "\n"
                                ~ "    sub eax, " ~ exprParts[1] ~ "\n"
                                ~ "    mov " ~ parts[0] ~ ", eax\n";
                        }
                        else
                        {
                            asmCode ~= "    mov eax, " ~ parts[1] ~ "\n"
                                ~ "    mov " ~ parts[0] ~ ", eax\n";
                        }
                        break;
                    }
                }
                asmCode ~= "    jmp loop_" ~ loopId.to!string ~ "_start\n";
                asmCode ~= "loop_" ~ loopId.to!string ~ "_end:\n";
                break;

            case "Break":
                asmCode ~= "    jmp loop_0_end\n";
                break;
            case "Assignment":
                auto parts = child.value.split(" = ");
                if (parts[1].canFind(" - "))
                {
                    auto exprParts = parts[1].split(" - ");
                    asmCode ~= "    mov eax, " ~ exprParts[0] ~ "\n"
                        ~ "    sub eax, " ~ exprParts[1] ~ "\n"
                        ~ "    mov " ~ parts[0] ~ ", eax\n";
                }
                else
                {
                    asmCode ~= "    mov eax, " ~ parts[1] ~ "\n"
                        ~ "    mov " ~ parts[0] ~ ", eax\n";
                }
                break;
            }
        }
        asmCode ~= `
            add rsp, 40
            xor eax, eax
            ret
        `;
        break;

    case "Function":
        auto funcDecl = ast.value.split("(");
        string funcName = funcDecl[0].strip();
        string args = funcDecl.length > 1 ?
            funcDecl[1].strip(")").strip() : "";

        asmCode ~= "section .text\n"
            ~ "global " ~ funcName ~ "\n"
            ~ funcName ~ ":\n"
            ~ "    sub rsp, 40\n";

        // Handle function parameters
        if (args.length > 0)
        {
            auto params = args.split(",");
            int paramOffset = 16; // First parameter is at [rsp+16] (after return address and rbp)

            foreach (i, param; params)
            {
                auto parts = param.split(":");
                if (parts.length == 2)
                {
                    string paramName = parts[0].strip();
                    string paramType = parts[1].strip();

                    // Store parameter from register to stack
                    asmCode ~= "    mov " ~ paramName ~ ", " ~
                        (i == 0 ? "rcx" : i == 1 ? "rdx" : i == 2 ? "r8" : "r9") ~ "\n";
                    asmCode ~= "    mov [rsp+" ~ to!string(paramOffset) ~ "], " ~
                        (i == 0 ? "rcx" : i == 1 ? "rdx" : i == 2 ? "r8" : "r9") ~ "\n";

                    paramOffset += 8; // Each parameter is 8 bytes on stack
                }
            }
        }
        int msgCounter = 0;
        foreach (child; ast.children)
        {
            switch (child.nodeType)
            {
            case "Println":
                asmCode ~= `
                    section .data
                        msg_`
                    ~ msgCounter.to!string ~ ` db '` ~ child.value ~ `', 0
                    section .text
                        mov rcx, msg_`
                    ~ msgCounter.to!string ~ `
                        call printf
                        mov rcx, nl
                        call printf
                `;
                msgCounter++;
                break;

            case "FunctionCall":
                auto callDecl = child.value.split("(");
                string callName = callDecl[0];
                string callArgs = callDecl.length > 1 ?
                    callDecl[1].strip(")") : "";

                if (callArgs.length > 0)
                {
                    auto argList = callArgs.split(",");
                    foreach (i, a; argList)
                    {
                        string param = a.strip();
                        string reg = i == 0 ? "rcx" : 
                                     i == 1 ? "rdx" : 
                                     i == 2 ? "r8" : 
                                     i == 3 ? "r9" : "";
                        
                        if (i < 4) {
                            asmCode ~= "    mov " ~ reg ~ ", " ~ param ~ "\n";
                        } else {
                            asmCode ~= "    mov rcx, " ~ param ~ "\n";
                            asmCode ~= "    push rcx\n";
                        }
                    }
                }

                asmCode ~= "    call " ~ callName ~ "\n";
                break;
            case "Assignment":
                auto parts = child.value.split(" = ");
                if (parts[1].canFind(" - "))
                {
                    auto exprParts = parts[1].split(" - ");
                    asmCode ~= "    mov eax, " ~ exprParts[0] ~ "\n"
                        ~ "    sub eax, " ~ exprParts[1] ~ "\n"
                        ~ "    mov " ~ parts[0] ~ ", eax\n";
                }
                else
                {
                    asmCode ~= "    mov eax, " ~ parts[1] ~ "\n"
                        ~ "    mov " ~ parts[0] ~ ", eax\n";
                }
                break;

            case "If":
                auto condition = child.value;
                string endIfLabel = "endif_" ~ to!string(child.children.length);

                if (condition.canFind("=="))
                {
                    auto parts = condition.split("==");
                    asmCode ~= "    mov eax, " ~ parts[0].strip() ~ "\n"
                        ~ "    cmp eax, " ~ parts[1].strip() ~ "\n"
                        ~ "    jne " ~ endIfLabel ~ "\n";
                }

                foreach (ifChild; child.children)
                {
                    if (ifChild.nodeType == "Break")
                    {
                        asmCode ~= "    jmp " ~ endIfLabel ~ "\n";
                    }
                }

                asmCode ~= endIfLabel ~ ":\n";
                break;

            case "Loop":
                string loopStart = "loop_" ~ to!string(msgCounter) ~ "_start";
                string loopEnd = "loop_" ~ to!string(msgCounter) ~ "_end";
                msgCounter++;

                asmCode ~= loopStart ~ ":\n";

                foreach (loopChild; child.children)
                {
                    switch (loopChild.nodeType)
                    {
                    case "Break":
                        asmCode ~= "    jmp " ~ loopEnd ~ "\n";
                        break;
                    case "Println":
                        asmCode ~= `
                            section .data
                                msg_`
                            ~ msgCounter.to!string ~ ` db '` ~ loopChild.value ~ `', 0
                            section .text
                                mov rcx, msg_`
                            ~ msgCounter.to!string ~ `
                                call printf
                                mov rcx, nl
                                call printf
                        `;
                        msgCounter++;
                        break;
                    case "If":
                        auto condition = loopChild.value;
                        string endIfLabel = "loop_if_end_" ~ to!string(msgCounter);
                        msgCounter++;

                        if (condition.canFind("=="))
                        {
                            auto parts = condition.split("==");
                            asmCode ~= "    mov eax, " ~ parts[0].strip() ~ "\n"
                                ~ "    cmp eax, " ~ parts[1].strip() ~ "\n"
                                ~ "    jne " ~ endIfLabel ~ "\n";
                        }

                        foreach (ifChild; loopChild.children)
                        {
                            if (ifChild.nodeType == "Break")
                            {
                                asmCode ~= "    jmp " ~ loopEnd ~ "\n";
                            }
                        }

                        asmCode ~= endIfLabel ~ ":\n";
                        break;

                    default:
                        enforce(false, "Unsupported node type in loop: " ~ loopChild.nodeType);
                    }
                }

                asmCode ~= "    jmp " ~ loopStart ~ "\n";
                asmCode ~= loopEnd ~ ":\n";
                break;
            default:
                enforce(false, "Invalid node type: " ~ child.nodeType);
            }

        }
        asmCode ~= "    add rsp, 40\n"
            ~ "    ret\n";
        break;

    case "FunctionCall":
        auto funcDecl = ast.value.split("(");
        string funcName = funcDecl[0];
        string args = funcDecl.length > 1 ?
            funcDecl[1].strip(")") : "";

        if (args.length > 0)
        {
            auto argList = args.split(",");
            foreach (i, a; argList)
            {
                string param = a.strip();
                string reg = i == 0 ? "rcx" : 
                             i == 1 ? "rdx" : 
                             i == 2 ? "r8" : 
                             i == 3 ? "r9" : "";
                
                if (i < 4) {
                    asmCode ~= "    mov " ~ reg ~ ", " ~ param ~ "\n";
                } else {
                    asmCode ~= "    mov rcx, " ~ param ~ "\n";
                    asmCode ~= "    push rcx\n";
                }
            }
        }

        asmCode ~= "    call " ~ funcName ~ "\n";
        break;

    case "Loop":
        int loopId = 0;
        asmCode ~= "loop_" ~ loopId.to!string ~ "_start:\n";
        foreach (child; ast.children)
        {
            final switch (child.nodeType)
            {
            case "Println":
                asmCode ~= `
                    section .data
                        msg_`
                    ~ loopId.to!string ~ ` db '` ~ child.value ~ `', 0
                    section .text
                        mov rcx, msg_`
                    ~ loopId.to!string ~ `
                        call printf
                        mov rcx, nl
                        call printf
                `;
                break;
            case "Break":
                asmCode ~= "    jmp loop_" ~ loopId.to!string ~ "_end\n";
                break;
            case "Assignment":
                auto parts = child.value.split(" = ");
                if (parts[1].canFind(" - "))
                {
                    auto exprParts = parts[1].split(" - ");
                    asmCode ~= "    mov eax, " ~ exprParts[0] ~ "\n"
                        ~ "    sub eax, " ~ exprParts[1] ~ "\n"
                        ~ "    mov " ~ parts[0] ~ ", eax\n";
                }
                else
                {
                    asmCode ~= "    mov eax, " ~ parts[1] ~ "\n"
                        ~ "    mov " ~ parts[0] ~ ", eax\n";
                }
                break;
            }
        }
        asmCode ~= "    jmp loop_" ~ loopId.to!string ~ "_start\n";
        asmCode ~= "loop_" ~ loopId.to!string ~ "_end:\n";
        break;

    case "Break":
        asmCode ~= "    jmp end\n";
        break;

    case "Assignment":
        auto parts = ast.value.split(" = ");
        if (parts[1].canFind(" - "))
        {
            auto exprParts = parts[1].split(" - ");
            asmCode ~= "    mov eax, " ~ exprParts[0] ~ "\n"
                ~ "    sub eax, " ~ exprParts[1] ~ "\n"
                ~ "    mov " ~ parts[0] ~ ", eax\n";
        }
        else
        {
            asmCode ~= "    mov eax, " ~ parts[1] ~ "\n"
                ~ "    mov " ~ parts[0] ~ ", eax\n";
        }
        break;

    }

    return asmCode;
}

unittest
{
    import axe.parser;
    import axe.lexer;

    {
        auto tokens = lex("main { println \"hello\"; }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("section .data"));
        assert(asma.canFind("msg_0 db 'hello', 0"));
        assert(asma.canFind("call printf"));
    }

    {
        auto tokens = lex("main { foo(); }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("call foo"));
    }

    {
        auto tokens = lex("main { foo(1, 2); }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("mov rcx, 1"));
        assert(asma.canFind("mov rcx, 2"));
        assert(asma.canFind("call foo"));
    }

    {
        auto tokens = lex("main { x = 5; }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("mov eax, 5"));
        assert(asma.canFind("mov x, eax"));
    }

    {
        auto tokens = lex("main { x = 5 - 3; }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("mov eax, 5"));
        assert(asma.canFind("sub eax, 3"));
        assert(asma.canFind("mov x, eax"));
    }

    {
        auto tokens = lex("main { loop { break; } }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("loop_0_start:"));
        assert(asma.canFind("jmp loop_0_end"));
        assert(asma.canFind("loop_0_end:"));
    }

    {
        auto tokens = lex("main { if x == 5 { break; } }");
        auto ast = parse(tokens);
        auto asma = generateAsm(ast);
        assert(asma.canFind("mov eax, x"));
        assert(asma.canFind("cmp eax, 5"));
        assert(asma.canFind("jne endif_1"));
        assert(asma.canFind("jmp endif_1"));
        assert(asma.canFind("endif_1:"));
    }
}
