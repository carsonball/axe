module axe.imports;

import axe.structs;
import axe.lexer;
import axe.parser;
import std.file;
import std.path;
import std.stdio;
import std.algorithm;
import std.string;
import std.array;
import std.exception;

/**
 * Process use statements and merge imported ASTs
 */
ASTNode processImports(ASTNode ast, string baseDir, bool isAxec)
{
    auto programNode = cast(ProgramNode) ast;
    if (programNode is null)
        return ast;
    
    ASTNode[] newChildren;
    string[string] importedFunctions;
    
    foreach (child; programNode.children)
    {
        if (child.nodeType == "Use")
        {
            auto useNode = cast(UseNode) child;
            string modulePath = buildPath(baseDir, useNode.moduleName ~ ".axe");
            
            if (!exists(modulePath))
            {
                throw new Exception("Module not found: " ~ modulePath);
            }
            
            string importSource = readText(modulePath);
            auto importTokens = lex(importSource);
            auto importAst = parse(importTokens, isAxec);
            auto importProgram = cast(ProgramNode) importAst;
            
            foreach (importChild; importProgram.children)
            {
                if (importChild.nodeType == "Function")
                {
                    auto funcNode = cast(FunctionNode) importChild;
                    if (useNode.imports.canFind(funcNode.name))
                    {
                        string prefixedName = useNode.moduleName ~ "_" ~ funcNode.name;
                        importedFunctions[funcNode.name] = prefixedName;
                        auto newFunc = new FunctionNode(prefixedName, funcNode.params);
                        newFunc.returnType = funcNode.returnType;
                        newFunc.children = funcNode.children;
                        newChildren ~= newFunc;
                    }
                }
            }
        }
        else
        {
            renameFunctionCalls(child, importedFunctions);
            newChildren ~= child;
        }
    }
    
    programNode.children = newChildren;
    return programNode;
}

/**
 * Recursively rename function calls to use prefixed names
 */
void renameFunctionCalls(ASTNode node, string[string] nameMap)
{
    if (node.nodeType == "FunctionCall")
    {
        auto callNode = cast(FunctionCallNode) node;
        if (callNode.functionName in nameMap)
        {
            callNode.functionName = nameMap[callNode.functionName];
        }
    }
    else if (node.nodeType == "Println")
    {
        auto printlnNode = cast(PrintlnNode) node;
        if (printlnNode.isExpression)
        {
            // Rename function calls in expression strings
            foreach (oldName, newName; nameMap)
            {
                // Match function name followed by '('
                printlnNode.message = printlnNode.message.replace(oldName ~ "(", newName ~ "(");
            }
        }
    }
    
    foreach (child; node.children)
    {
        renameFunctionCalls(child, nameMap);
    }
}
