import
    os,
    osproc,
    strutils,
    axe/[lexer, parser, renderer]

when defined(windows):
    const extension = ".exe"
else:
    const extension = ""

when isMainModule:
    if paramCount() < 1:
        echo "usage: axe input.axe\n\t[-e = emit generated code as file | -asm = emit assembly code]"
    else:
        try:
            var name = paramStr(1)
            if ".axe" notin name:
                name = name & ".axe"
            let
                source = readFile(name)
                tokens = lex(source)
                ast = parse(tokens)
                
            if "-asm" in commandLineParams():
                let asmCode = generateAsm(ast)
                writeFile(name.replace(".axe", ".asm"), asmCode)
                discard execProcess(
                    command = "nasm",
                    args = ["-f", "elf32", name.replace(".axe", ".asm"), "-o", name.replace(".axe", ".o")],
                    options = {poStdErrToStdOut}
                )
                discard execProcess(
                    command = "gcc",
                    args = ["-m32", name.replace(".axe", ".o"), "-o", name.replace(".axe", extension)],
                    options = {poStdErrToStdOut}
                )
                if "-e" notin commandLineParams():
                    removeFile(name.replace(".axe", ".asm"))
                    removeFile(name.replace(".axe", ".o"))
            else:
                let cCode = generateC(ast)
                writeFile(name.replace(".axe", ".c"), cCode)
                discard execProcess(
                    command = "gcc",
                    args = [name.replace(".axe", ".c"), "-o", name.replace(".axe", extension)],
                    options = {poStdErrToStdOut}
                )
                if "-e" notin commandLineParams():
                    removeFile(name.replace(".axe", ".c"))

        except ValueError as e:
            echo "Compilation error: ", e.msg
        except OSError as e:
            echo "Linker error (maybe no C/NASM toolchain is installed?): ", e.msg.replace("OS error:", "")
        except Exception as e:
            echo "Error: ", e.msg
