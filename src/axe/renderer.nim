import
    structs,
    strformat,
    strutils,
    sets

proc generateC*(ast: ASTNode): string =
    ## Code generation from abstract syntax tree (AST)
    ## Indentation does not matter in the generated code. It is not supposed to be readable.

    var cCode = ""
    var includes = initHashSet[string]()
    
    includes.incl("#include <stdio.h>")
    
    case ast.nodeType
    of "Program":
        for child in ast.children:
            if child.nodeType == "Function":
                let funcDecl = child.value.split('(')
                let funcName = funcDecl[0]
                let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
                cCode.add("void " & funcName & "(" & 
                    (if args.len > 0: "int " & args.replace(",", ", int ") else: "void") & ");\n")
        for i in includes:
            cCode.add(i & "\n")
        cCode.add("\n")
        for child in ast.children:
            cCode.add(generateC(child) & "\n")
    of "Main":
        cCode.add("int main() {\n")
        for child in ast.children:
            case child.nodeType
            of "Println":
                cCode.add("printf(\"%s\\n\", \"" & child.value & "\");\n")
            of "Loop":
                cCode.add("while (1) {\n")
                for loopChild in child.children:
                    case loopChild.nodeType
                    of "Println":
                        cCode.add("printf(\"%s\\n\", \"" & loopChild.value & "\");\n")
                    of "Break":
                        cCode.add("break;\n")
                cCode.add("}\n")
            of "Break":
                cCode.add("break;\n")
            of "FunctionCall":
                let funcDecl = ast.value.split('(')
                let funcName = funcDecl[0]
                let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
                cCode.add(funcName & "(" & args & ");\n")
            of "Function":
                let funcDecl = ast.value.split('(')
                let funcName = funcDecl[0]
                let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
                cCode.add("void " & funcName & "(" & 
                    (if args.len > 0: "int " & args.replace(",", ", int ") else: "void") & ") {\n")
                for child in ast.children:
                    cCode.add(generateC(child))
                cCode.add("}\n")
        cCode.add("return 0;\n}")
    of "Function":
        let funcDecl = ast.value.split('(')
        let funcName = funcDecl[0]
        let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
        cCode.add("void " & funcName & "(" & 
            (if args.len > 0: "int " & args.replace(",", ", int ") else: "void") & ") {\n")
        for child in ast.children:
            case child.nodeType
            of "Println":
                cCode.add("printf(\"%s\\n\", \"" & child.value & "\");\n")
            of "FunctionCall":
                let funcDecl = ast.value.split('(')
                let funcName = funcDecl[0]
                let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
                cCode.add(funcName & "(" & args & ");\n")
        cCode.add("}")
    of "FunctionCall":
        let funcDecl = ast.value.split('(')
        let funcName = funcDecl[0]
        let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
        cCode.add(funcName & "(" & args & ");\n")
    else:
        raise newException(ValueError, "Unsupported node type for C generation: " & ast.nodeType)
    
    return cCode

proc generateAsm*(ast: ASTNode): string =
    ## Generate x64 assembly code from AST
    ## Includes assembly code generation for main function, loop and break statements, and string handling

    var asmCode = ""
    
    case ast.nodeType
    of "Program":
        if ast.children.len > 0 and ast.children[0].nodeType == "Main":
            asmCode = generateAsm(ast.children[0])
    of "Main":
        asmCode = """
            section .data
                fmt db "%s", 10, 0
                hello db "hello", 0
            section .text
                extern printf
                global main
            main:
        """
        var loopCounter = 0
        for child in ast.children:
            case child.nodeType
            of "Println":
                asmCode.add """
                    mov rdi, fmt
                    mov rsi, hello
                    xor rax, rax
                    call printf
                """
            of "Loop":
                let loopId = loopCounter
                loopCounter += 1
                asmCode.add "loop_" & $loopId & "_start:"
                for loopChild in child.children:
                    case loopChild.nodeType
                    of "Println":
                        asmCode.add """
                            mov rdi, fmt
                            mov rsi, hello
                            xor rax, rax
                            call printf
                        """
                    of "Break":
                        asmCode.add "    jmp loop_" & $loopId & "_end"
                        asmCode.add("\n")
                asmCode.add "    jmp loop_" & $loopId & "_start"
                asmCode.add("\n")
                asmCode.add "loop_" & $loopId & "_end:"
                asmCode.add("\n")
            of "FunctionCall":
                let funcDecl = ast.value.split('(')
                let funcName = funcDecl[0]
                let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
                asmCode.add(funcName & "(" & args & ");\n")
            of "Function":
                let funcDecl = ast.value.split('(')
                let funcName = funcDecl[0]
                let args = if funcDecl.len > 1: funcDecl[1].strip(chars={')'}) else: ""
                asmCode.add("void " & funcName & "(" & 
                    (if args.len > 0: "int " & args.replace(",", ", int ") else: "void") & ") {\n")
                for child in ast.children:
                    asmCode.add(generateC(child))
                asmCode.add("}\n")
        asmCode.add """
            mov rax, 60
            xor rdi, rdi
            syscall
        """
    of "Function":
        let funcParts = ast.value.split('(')
        let funcName = funcParts[0]
        
        asmCode = """
            global """ & funcName & """
            """ & funcName & """:
                push ebp
                mov ebp, esp
            """
        
        for child in ast.children:
            case child.nodeType
            of "Println":
                asmCode.add """
                    push hello
                    push fmt
                    call printf
                    add esp, 8
                """
            of "FunctionCall":
                let callParts = child.value.split('(')
                let callName = callParts[0]
                let callArgs = if callParts.len > 1: callParts[1].strip(chars={')'}) else: ""
                if callArgs.len > 0:
                    for arg in callArgs.split(','):
                        asmCode.add("    push " & arg.strip() & "\n")
                asmCode.add("    call " & callName & "\n")
                if callArgs.len > 0:
                    asmCode.add("    add esp, " & $(callArgs.split(',').len * 4) & "\n")
    
        asmCode.add """
                pop ebp
                ret
            """
    of "FunctionCall":
        let funcParts = ast.value.split('(')
        let funcName = funcParts[0]
        let args = if funcParts.len > 1: funcParts[1].strip(chars={')'}) else: ""
        
        asmCode = ""
        if args.len > 0:
            for arg in args.split(','):
                asmCode.add("    push " & arg.strip() & "\n")
        asmCode.add("    call " & funcName & "\n")
        if args.len > 0:
            asmCode.add("    add esp, " & $(args.split(',').len * 4) & "\n")

    of "FunctionDecl":
        let funcParts = ast.value.split('(')
        let funcName = funcParts[0]
        let args = if funcParts.len > 1: funcParts[1].strip(chars={')'}) else: ""
        
        asmCode = """
            global """ & funcName & """
            """ & funcName & """:
                push ebp
                mov ebp, esp
                """

        for child in ast.children:
            asmCode.add(generateAsm(child))
        
        asmCode.add """
                pop ebp
                ret
            """
    else:
        raise newException(ValueError, "Unsupported node type for ASM generation: " & ast.nodeType)
    
    return asmCode
