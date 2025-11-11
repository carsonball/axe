import
    structs,
    strformat,
    strutils,
    sets

proc generateC*(ast: ASTNode): string =
    ## Code generation from abstract syntax tree (AST)
    ## Includes C code generation for main function, loop and break statements, and string handling

    var cCode = ""
    var includes = initHashSet[string]()
    includes.incl("#include <stdio.h>")
    
    case ast.nodeType
    of "Program":
        for i in includes:
            cCode.add(i & "\n")
        cCode.add("\n")
        for child in ast.children:
            cCode.add(generateC(child) & "\n")
    of "Function":
        cCode.add(fmt"void {ast.value}() {{")
        for child in ast.children:
            case child.nodeType
            of "Println":
                cCode.add("    printf(\"%s\\n\", \"" & child.value & "\");")

        cCode.add("}\n")
    of "FunctionCall":
        let valToAdd = ast.value.replace("\n","")
        cCode.add(fmt"    {valToAdd}();")
    of "Main":
        cCode.add("int main() {\n")
        for child in ast.children:
            cCode.add(generateC(child))
        cCode.add("    return 0;\n}\n")
    return cCode

proc generateAsm*(ast: ASTNode): string =
    ## Generate x86 assembly code from AST
    ## Should be able to generate code for main function, loop and break statements, and string handling#
    
    var asmCode = ""
    if ast.nodeType == "Main":
        asmCode.add("""
            section .data
                fmt db "%s", 10, 0
            section .text
                global _start
            _start:
            """)
        for child in ast.children:
            case child.nodeType
            of "Println":
                asmCode.add(fmt"""
                    push {child.value}
                    push fmt
                    call printf
                    add esp, 8
                """)
            of "Loop":
                asmCode.add("loop_start:\n")
                for loopChild in child.children:
                    case loopChild.nodeType
                    of "Println":
                        asmCode.add(fmt"""
                            push {loopChild.value}
                            push fmt
                            call printf
                            add esp, 8
                        """)
                    of "Break":
                        asmCode.add("    jmp loop_end\n")
                asmCode.add("    jmp loop_start\n")
                asmCode.add("loop_end:\n")
        asmCode.add("""
            mov eax, 1
            mov ebx, 0
            int 0x80
        """)
    return asmCode
