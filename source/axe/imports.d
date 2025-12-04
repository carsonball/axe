/** 
 * Axe Programming Language Compiler.
 * Author: Navid Momtahen (C) 2025
 * License: GPL-3.0
 * 
 * Handles the import process.
 */

module axe.imports;

import axe.structs;
import axe.lexer;
import axe.parser;
import axe.gstate;
import std.file;
import std.path;
import std.stdio;
import std.algorithm;
import std.string;
import std.array;
import std.exception;

private string[string] g_processedModules;
private bool[string] g_addedNodeNames;

/**
 * Reset the processed modules cache before a new compilation
 */
void resetProcessedModules()
{
    g_processedModules.clear();
    g_addedNodeNames.clear();
}

/**
 * Check if a specific stdlib module was imported during compilation
 */
bool hasImportedModule(string moduleName)
{
    foreach (key; g_processedModules.byKey())
    {
        if (key.canFind(moduleName))
            return true;
    }
    return false;
}

/**
 * Process use statements and merge imported ASTs, recursively handling transitive dependencies
 */
ASTNode processImports(ASTNode ast, string baseDir, bool isAxec, string currentFilePath = "",
    bool isTopLevel = true, string moduleName = "")
{
    auto programNode = cast(ProgramNode) ast;
    if (programNode is null)
        return ast;

    if (currentFilePath.length > 0)
    {
        string normalizedPath = currentFilePath.replace("\\", "/");
        if (normalizedPath in g_processedModules)
        {
            debugWriteln("DEBUG: Module already processed, skipping: ", normalizedPath);
            return ast;
        }
        g_processedModules[normalizedPath] = "1";
    }

    auto startsWithLower = (string s) {
        return s.length > 0 && s[0] >= 'a' && s[0] <= 'z';
    };

    if (currentFilePath.length > 0 && !currentFilePath.canFind("std"))
    {
        foreach (child; programNode.children)
        {
            if (child.nodeType == "Model")
            {
                auto modelNode = cast(ModelNode) child;
                // Check if this is a primitive type declaration (lowercase name without prefix)
                // Allow prefixed models like "lexer__Token" (module__Type pattern with double underscore)
                bool isPrefixedModel = false;
                if (modelNode.name.canFind("__"))
                {
                    import std.array : split;

                    auto parts = modelNode.name.split("__");
                    if (parts.length >= 2)
                    {
                        string lastPart = parts[$ - 1];
                        debugWriteln("DEBUG: Checking model '", modelNode.name, "' - parts: ", parts,
                            " - lastPart: '", lastPart, "' - starts with upper: ",
                            (lastPart.length > 0 && lastPart[0] >= 'A' && lastPart[0] <= 'Z'));
                        if (lastPart.length > 0 && lastPart[0] >= 'A' && lastPart[0] <= 'Z')
                        {
                            isPrefixedModel = true;
                        }
                    }
                }

                if (startsWithLower(modelNode.name) && !modelNode.name.startsWith("std__") && !isPrefixedModel)
                {
                    throw new Exception(
                        "Declaring primitive types outside of the standard library is disallowed: " ~
                            modelNode.name);
                }
            }
        }
    }

    ASTNode[] newChildren;
    string[string] importedFunctions;
    string[string] importedModels;

    string currentModulePrefix = "";
    bool isStdModule = currentFilePath.canFind("std");

    if (isTopLevel && moduleName.length > 0)
    {
        import std.string : replace;

        currentModulePrefix = moduleName.replace(".", "__").replace("-", "_");
        g_currentModulePrefix = currentModulePrefix;
        debugWriteln("DEBUG: Set currentModulePrefix='", currentModulePrefix, "' from moduleName='", moduleName, "'");
    }
    else if (isTopLevel && currentFilePath.length > 0 && isAxec)
    {
        import std.path : baseName, stripExtension;

        if (isStdModule)
        {
            auto fileName = baseName(currentFilePath).stripExtension();
            currentModulePrefix = "std_" ~ fileName;
            g_currentModulePrefix = currentModulePrefix;
        }
    }

    string[string] localModels;
    string[string] localFunctions;
    string[string] localEnums;
    bool[string] addedFunctionNames;
    bool[string] addedModelNames;
    bool[string] addedEnumNames;
    bool[string] addedMacroNames;
    bool[string] addedOverloadNames;
    string[string] macros;

    if (currentModulePrefix.length > 0)
    {
        foreach (child; programNode.children)
        {
            if (child.nodeType == "Macro")
            {
                auto macroNode = cast(MacroNode) child;
                foreach (macroChild; macroNode.children)
                {
                    if (macroChild.nodeType == "Model")
                    {
                        auto modelNode = cast(ModelNode) macroChild;
                        if (macroNode.name == "create_map" && macroNode.params.length > 2)
                        {
                            macros[macroNode.name] = macroNode.params[2];
                            debugWriteln("DEBUG: Macro '", macroNode.name,
                                "' generates models using param '", macroNode.params[2], "'");
                        }
                    }
                }
            }
        }
    }

    if (currentModulePrefix.length > 0 && macros.length > 0)
    {
        foreach (child; programNode.children)
        {
            if (child.nodeType == "FunctionCall")
            {
                auto callNode = cast(FunctionCallNode) child;
                if (callNode.functionName in macros)
                {
                    string modelParamName = macros[callNode.functionName];
                    if (callNode.functionName == "create_map")
                    {
                        import std.string : strip;

                        if (callNode.args.length > 2)
                        {
                            string modelName = callNode.args[2].strip();
                            localModels[modelName] = currentModulePrefix ~ "__" ~ modelName;
                            debugWriteln("DEBUG: Macro invocation '", callNode.functionName,
                                "' generates model '", modelName, "' -> '",
                                currentModulePrefix ~ "__" ~ modelName, "'");
                        }
                    }
                }
            }
        }
    }

    if (currentModulePrefix.length > 0)
    {
        foreach (child; programNode.children)
        {
            if (child.nodeType == "Model")
            {
                auto modelNode = cast(ModelNode) child;

                debugWriteln("DEBUG: Found model with name='", modelNode.name, "'");

                if (modelNode.name == "C")
                {
                    debugWriteln("DEBUG: Skipping special 'C' model (used for direct C calls)");
                    continue;
                }

                if (modelNode.name in localModels)
                {
                    debugWriteln("DEBUG: Model '", modelNode.name, "' already registered, mapped to '",
                        localModels[modelNode.name], "'");
                }
                else
                {
                    localModels[modelNode.name] = currentModulePrefix ~ "__" ~ modelNode.name;
                    debugWriteln("DEBUG: Added local model '", modelNode.name, "' -> '", currentModulePrefix ~ "__" ~
                            modelNode.name, "'");
                }

                foreach (method; modelNode.methods)
                {
                    auto methodFunc = cast(FunctionNode) method;
                    if (methodFunc !is null)
                    {
                        string methodName = methodFunc.name[modelNode.name.length + 1 .. $];
                        string originalCallName = modelNode.name ~ "_" ~ methodName;
                        string prefixedCallName = currentModulePrefix ~ "__" ~ modelNode.name ~ "_" ~ methodName;
                        localFunctions[originalCallName] = prefixedCallName;
                        debugWriteln("DEBUG: Added local function '", originalCallName, "' -> '",
                            prefixedCallName, "'");
                    }
                }
            }
            else if (child.nodeType == "Enum")
            {
                auto enumNode = cast(EnumNode) child;
                localEnums[enumNode.name] = currentModulePrefix ~ "__" ~ enumNode.name;
                debugWriteln("DEBUG: Added local enum '", enumNode.name, "' -> '", currentModulePrefix ~ "__" ~
                        enumNode.name, "'");
            }
            else if (child.nodeType == "Function")
            {
                auto funcNode = cast(FunctionNode) child;
                // For .axec files: add ALL functions (public and non-public) to localFunctions
                // so they call each other with prefixes
                // For .axe files: only add non-public functions
                if (funcNode.name != "main")
                {
                    if (currentModulePrefix.length > 0)
                    {
                        localFunctions[funcNode.name] = currentModulePrefix ~ "__" ~ funcNode.name;
                        debugWriteln("DEBUG: Added local function '", funcNode.name, "' -> '",
                            currentModulePrefix ~ "__" ~ funcNode.name, "' (from .axec)");
                    }
                    else if (!funcNode.isPublic)
                    {
                        localFunctions[funcNode.name] = currentModulePrefix ~ "__" ~ funcNode.name;
                        debugWriteln("DEBUG: Added local non-public function '", funcNode.name, "' -> '",
                            currentModulePrefix ~ "__" ~ funcNode.name, "'");
                    }
                }
            }
        }

        g_localFunctionMap = localFunctions.dup;
    }

    bool[string] isTransitiveDependency;

    foreach (child; programNode.children)
    {
        if (child.nodeType == "Use")
        {
            auto useNode = cast(UseNode) child;
            string modulePath;

            if (useNode.moduleName.startsWith("std."))
            {
                string moduleFile = useNode.moduleName[4 .. $].replace(".", dirSeparator);

                if (baseDir.endsWith("std") || baseDir.endsWith("std/"))
                {
                    modulePath = buildPath(baseDir, moduleFile ~ ".axec");
                }
                else
                {
                    modulePath = buildPath(baseDir, "std", moduleFile ~ ".axec");
                }

                if (!exists(modulePath))
                {
                    string homeDir = getUserHomeDir();
                    if (homeDir.length == 0)
                    {
                        throw new Exception("Could not determine user home directory");
                    }

                    modulePath = buildPath(homeDir, ".axe", "std", moduleFile ~ ".axec");

                    if (!exists(modulePath))
                    {
                        throw new Exception(
                            "Standard library module not found: " ~ modulePath ~
                                "\nMake sure the module is installed in ~/.axe/std/ " ~
                                "or in a local std/ directory");
                    }
                }
            }
            else
            {
                string processedModuleName = useNode.moduleName;
                // Handle relative paths (../ and ./) and dot-separated module paths
                // Replace dots with directory separators, but keep ../ and ./
                // This preserves relative path prefixes while converting module.submodule to module/submodule
                if (!processedModuleName.startsWith("../") && !processedModuleName.startsWith("./"))
                {
                    processedModuleName = processedModuleName.replace(".", dirSeparator);
                }

                modulePath = buildPath(baseDir, processedModuleName ~ ".axe");

                if (!exists(modulePath))
                {
                    throw new Exception("Module not found: " ~ modulePath);
                }
            }

            string importSource = readText(modulePath);
            auto importTokens = lex(importSource);
            bool importIsAxec = modulePath.endsWith(".axec");
            auto importAst = parse(importTokens, importIsAxec, false, useNode.moduleName);
            string importBaseDir = dirName(modulePath);
            importAst = processImports(importAst, importBaseDir, importIsAxec, modulePath, false);

            auto importProgram = cast(ProgramNode) importAst;

            if (!modulePath.canFind("std") && importProgram !is null)
            {
                foreach (importChild; importProgram.children)
                {
                    if (importChild.nodeType == "Model")
                    {
                        auto mNode = cast(ModelNode) importChild;
                        // Check if this is a prefixed model like "lexer__Token" (module__Type pattern)
                        bool isPrefixedModel = false;
                        if (mNode.name.canFind("__"))
                        {
                            import std.array : split;

                            auto parts = mNode.name.split("__");
                            if (parts.length >= 2)
                            {
                                string lastPart = parts[$ - 1];
                                if (lastPart.length > 0 && lastPart[0] >= 'A' && lastPart[0] <= 'Z')
                                {
                                    isPrefixedModel = true;
                                }
                            }
                        }

                        if (startsWithLower(mNode.name) && !mNode.name.startsWith("std__") && !isPrefixedModel)
                        {
                            string msg = "Declaring primitive types outside of the standard library is disallowed: "
                                ~ mNode.name;
                            throw new Exception(msg);
                        }
                    }
                }
            }

            string sanitizedModuleName = useNode.moduleName.replace(".", "__").replace("-", "_");
            string[string] moduleFunctionMap;
            string[string] moduleModelMap;
            string[string] moduleMacroMap;

            bool[string] importsSet;
            foreach (imp; useNode.imports)
                importsSet[imp] = true;

            debugWriteln("DEBUG: Processing ", importProgram.children.length, " children from imported module ", useNode
                    .moduleName);
            foreach (importChild; importProgram.children)
            {
                if (importChild.nodeType == "ExternalImport")
                {
                    auto extNode = cast(ExternalImportNode) importChild;
                    string key = "__external_import__" ~ extNode.headerFile;
                    if (key !in g_addedNodeNames)
                    {
                        g_addedNodeNames[key] = true;
                        newChildren ~= importChild;
                    }
                    continue;
                }
                else if (importChild.nodeType == "Platform")
                {
                    auto platformNode = cast(PlatformNode) importChild;

                    PlatformNode platformImports = null;
                    foreach (pChild; platformNode.children)
                    {
                        if (pChild.nodeType == "ExternalImport")
                        {
                            if (platformImports is null)
                            {
                                platformImports = new PlatformNode(platformNode.platform);
                            }
                            platformImports.children ~= pChild;
                        }

                        if (pChild.nodeType == "Function")
                        {
                            auto funcNode = cast(FunctionNode) pChild;
                            if (funcNode.isPublic && (useNode.importAll || (
                                    funcNode.name in importsSet)
                                    || funcNode.name.startsWith("std_")))
                            {
                                string prefixedName = funcNode.name.startsWith("std_") ? funcNode.name
                                    : (sanitizedModuleName ~ "__" ~ funcNode.name);
                                moduleFunctionMap[funcNode.name] = prefixedName;
                            }
                        }
                        else if (pChild.nodeType == "Model")
                        {
                            auto modelNode = cast(ModelNode) pChild;
                            if (modelNode.isPublic && (useNode.importAll || (
                                    modelNode.name in importsSet)
                                    || modelNode.name.startsWith("std_")))
                            {
                                string prefixedName = modelNode.name.startsWith("std_") ? modelNode.name
                                    : (sanitizedModuleName ~ "__" ~ modelNode.name);
                                moduleModelMap[modelNode.name] = prefixedName;

                                foreach (method; modelNode.methods)
                                {
                                    auto methodFunc = cast(FunctionNode) method;
                                    if (methodFunc !is null && methodFunc.isPublic)
                                    {
                                        string prefixedMethodName = methodFunc.name.startsWith("std_") ? methodFunc
                                            .name : (sanitizedModuleName ~ "__" ~ methodFunc.name);
                                        moduleFunctionMap[methodFunc.name] = prefixedMethodName;
                                    }
                                }
                            }
                        }
                        else if (pChild.nodeType == "Enum")
                        {
                            auto enumNode = cast(EnumNode) pChild;
                            if (useNode.importAll || (enumNode.name in importsSet))
                            {
                                string prefixedName = enumNode.name.startsWith("std_") ? enumNode.name
                                    : (sanitizedModuleName ~ "__" ~ enumNode.name);
                                moduleModelMap[enumNode.name] = prefixedName;
                            }
                        }
                        else if (pChild.nodeType == "Macro")
                        {
                            auto macroNode = cast(MacroNode) pChild;
                            if (useNode.importAll || (macroNode.name in importsSet))
                            {
                                moduleMacroMap[macroNode.name] = macroNode.name;
                            }
                        }
                        else if (pChild.nodeType == "Overload")
                        {
                            auto overloadNode = cast(OverloadNode) pChild;
                            if (useNode.importAll || (overloadNode.name in importsSet))
                            {
                                moduleMacroMap[overloadNode.name] = overloadNode.name;
                            }
                        }
                    }

                    if (platformImports !is null)
                    {
                        string headerKey;
                        foreach (pChild; platformImports.children)
                        {
                            auto extChild = cast(ExternalImportNode) pChild;
                            if (headerKey.length > 0)
                                headerKey ~= ",";
                            headerKey ~= extChild.headerFile;
                        }
                        string key = "__platform_external_imports__" ~ platformImports.platform ~ "__" ~ headerKey;
                        if (key !in g_addedNodeNames)
                        {
                            g_addedNodeNames[key] = true;
                            newChildren ~= platformImports;
                        }
                    }
                }

                if (importChild.nodeType == "Use")
                {
                    newChildren ~= importChild;
                }
                else if (importChild.nodeType == "Function")
                {
                    auto funcNode = cast(FunctionNode) importChild;
                    debugWriteln("DEBUG: Checking function '", funcNode.name, "' isPublic=", funcNode
                            .isPublic);

                    // For .axec modules, map ALL functions (public and non-public) so they all get prefixed
                    //
                    // For .axe modules, only map explicitly imported or non-public functions

                    if (importIsAxec && funcNode.name != "main")
                    {
                        string prefixedName = funcNode.name.startsWith("std__") ? funcNode.name
                            : (sanitizedModuleName ~ "__" ~ funcNode.name);
                        moduleFunctionMap[funcNode.name] = prefixedName;

                        if (prefixedName.canFind("__"))
                        {
                            auto lastUnderscore = prefixedName.lastIndexOf("__");
                            if (lastUnderscore >= 0)
                            {
                                string baseName = prefixedName[lastUnderscore + 2 .. $];
                                moduleFunctionMap[baseName] = prefixedName;
                            }
                        }
                    }
                    else if (funcNode.isPublic && (useNode.importAll || (funcNode.name in importsSet)
                            || funcNode.name.startsWith("std__")))
                    {
                        string prefixedName = funcNode.name.startsWith("std_") ? funcNode.name
                            : (sanitizedModuleName ~ "__" ~ funcNode.name);
                        moduleFunctionMap[funcNode.name] = prefixedName;
                        debugWriteln("DEBUG: Mapped public function '", funcNode.name, "' -> '", prefixedName, "'");
                    }
                    else if (!funcNode.isPublic && funcNode.name != "main")
                    {
                        string prefixedName = sanitizedModuleName ~ "__" ~ funcNode.name;
                        moduleFunctionMap[funcNode.name] = prefixedName;
                        debugWriteln("DEBUG: Mapped non-public function '", funcNode.name, "' -> '", prefixedName, "'");
                    }
                }
                else if (importChild.nodeType == "Model")
                {
                    auto modelNode = cast(ModelNode) importChild;
                    if (modelNode.isPublic && (useNode.importAll || (modelNode.name in importsSet)
                            || modelNode.name.startsWith("std_")))
                    {
                        string prefixedName;

                        // If the model name already looks like a fully-prefixed
                        // C type (e.g. "structs__ASTNode" or "foo__Bar"), then
                        // treat that as the canonical C name and avoid layering
                        // another module prefix on top of it. This prevents
                        // double-prefixing like renderer__structs__ASTNode.
                        bool hasDoubleUnderscore = modelNode.name.canFind("__");
                        bool isAlreadyPrefixedModel = false;

                        if (hasDoubleUnderscore)
                        {
                            import std.array : split;

                            auto parts = modelNode.name.split("__");
                            if (parts.length >= 2)
                            {
                                string lastPart = parts[$ - 1];
                                if (lastPart.length > 0 && lastPart[0] >= 'A' && lastPart[0] <= 'Z')
                                {
                                    isAlreadyPrefixedModel = true;
                                }
                            }
                        }

                        if (isAlreadyPrefixedModel)
                        {
                            string canonicalName = modelNode.name;
                            prefixedName = canonicalName;

                            // Map both the full name and the short base name to the
                            // same canonical C type so that any module importing via
                            // an intermediate re-export still instantiates lists and
                            // other templates against the canonical type, rather than
                            // creating per-import variants.
                            moduleModelMap[modelNode.name] = canonicalName;

                            import std.string : lastIndexOf;

                            auto lastUnderscore = canonicalName.lastIndexOf("__");
                            if (lastUnderscore >= 0)
                            {
                                string baseName = canonicalName[lastUnderscore + 2 .. $];
                                moduleModelMap[baseName] = canonicalName;
                            }
                        }
                        else
                        {
                            prefixedName = modelNode.name.startsWith("std_") ? modelNode.name
                                : (sanitizedModuleName ~ "__" ~ modelNode.name);

                            moduleModelMap[modelNode.name] = prefixedName;
                        }

                        foreach (method; modelNode.methods)
                        {
                            auto methodFunc = cast(FunctionNode) method;
                            if (methodFunc !is null && methodFunc.isPublic)
                            {
                                string prefixedMethodName = methodFunc.name.startsWith("std_") ? methodFunc.name
                                    : (sanitizedModuleName ~ "__" ~ methodFunc.name);
                                moduleFunctionMap[methodFunc.name] = prefixedMethodName;
                            }
                        }
                    }
                }
                else if (importChild.nodeType == "Enum")
                {
                    auto enumNode = cast(EnumNode) importChild;
                    if (useNode.importAll || (enumNode.name in importsSet) || enumNode.name.startsWith(
                            "std_"))
                    {
                        string prefixedName = enumNode.name.startsWith("std_") ? enumNode.name
                            : (sanitizedModuleName ~ "__" ~ enumNode.name);
                        moduleModelMap[enumNode.name] = prefixedName;
                    }
                }
                else if (importChild.nodeType == "Declaration" || importChild.nodeType == "ArrayDeclaration")
                {
                    // Any module that is imported may have top-level globals that its
                    // own functions depend on. If we only import the functions but
                    // drop their globals, those functions will fail to compile when
                    // used from another module. 
                    // 
                    // To avoid this, always bring over the module's top-level globals into the merged AST. 
                    // Visibility (isPublic) is still respected later for the :: / gvar__ sugar,
                    // but here we ensure the implementation details are present.

                    string globalName;

                    if (importChild.nodeType == "Declaration")
                    {
                        auto declNode = cast(DeclarationNode) importChild;
                        if (declNode !is null)
                        {
                            globalName = declNode.name;
                        }
                    }
                    else
                    {
                        auto arrayDecl = cast(ArrayDeclarationNode) importChild;
                        if (arrayDecl !is null)
                        {
                            globalName = arrayDecl.name;
                        }
                    }

                    if (globalName.length > 0)
                    {
                        string key = "__global__" ~ useNode.moduleName ~ "__" ~ globalName;
                        if (key !in g_addedNodeNames)
                        {
                            g_addedNodeNames[key] = true;
                            newChildren ~= importChild;
                        }
                    }
                }
                else if (importChild.nodeType == "Extern")
                {
                    // Always propagate extern declarations so that any
                    // imported functions which call C symbols (like
                    // snprintf) have their extern prototypes available in
                    // the merged AST. This also lets later semantic passes
                    // see that these names are intentionally provided by C.
                    auto externNode = cast(ExternNode) importChild;
                    if (externNode !is null)
                    {
                        string key = "__extern__" ~ externNode.functionName;
                        if (key !in g_addedNodeNames)
                        {
                            g_addedNodeNames[key] = true;
                            newChildren ~= externNode;
                        }
                    }
                }
                else if (importChild.nodeType == "Macro")
                {
                    auto macroNode = cast(MacroNode) importChild;
                    if (useNode.importAll || (macroNode.name in importsSet) ||
                        macroNode.name.startsWith("std_"))
                    {
                        moduleMacroMap[macroNode.name] = macroNode.name;
                    }
                }
                else if (importChild.nodeType == "Overload")
                {
                    auto overloadNode = cast(OverloadNode) importChild;
                    if (useNode.importAll || (overloadNode.name in importsSet) ||
                        overloadNode.name.startsWith("std_"))
                    {
                        moduleMacroMap[overloadNode.name] = overloadNode.name;
                    }
                }
            }

            // Build function mappings from the imported module's dependencies
            // Look at Use statements and find corresponding functions in the AST
            foreach (importChild; importProgram.children)
            {
                if (importChild.nodeType == "Use")
                {
                    auto importedUse = cast(UseNode) importChild;
                    string importedModulePrefix = importedUse.moduleName.replace(".", "__");

                    // For each function that the imported module uses,
                    // find the corresponding prefixed function in the AST
                    foreach (importedFuncName; importedUse.imports)
                    {
                        // Skip models (start with uppercase)
                        if (importedFuncName.length > 0 &&
                            (importedFuncName[0] < 'A' || importedFuncName[0] > 'Z'))
                        {
                            string expectedPrefixedName = importedModulePrefix ~ "__" ~ importedFuncName;

                            foreach (funcChild; importProgram.children)
                            {
                                if (funcChild.nodeType == "Function")
                                {
                                    auto funcNode = cast(FunctionNode) funcChild;
                                    if (funcNode.name == expectedPrefixedName)
                                    {
                                        // Add mapping from unprefixed to prefixed name
                                        if (importedFuncName !in moduleFunctionMap)
                                        {
                                            moduleFunctionMap[importedFuncName] = expectedPrefixedName;
                                            if (importedFuncName == "str" ||
                                                importedFuncName == "is_alphanum" ||
                                                importedFuncName == "get_char")
                                            {
                                                debugWriteln("DEBUG: Added transitive mapping: ",
                                                    importedFuncName, " -> ", expectedPrefixedName,
                                                    " (from ", useNode.moduleName, "'s import of ",
                                                    importedUse.moduleName, ")");
                                            }
                                        }
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (useNode.importAll)
            {
                foreach (name; moduleMacroMap.keys)
                {
                    if (name !in importsSet)
                    {
                        useNode.imports ~= name;
                        importsSet[name] = true;
                    }
                }
            }

            bool[string] resolvedImports;

            foreach (importChild; importProgram.children)
            {
                if (importChild.nodeType == "Platform")
                {
                    auto platformNode = cast(PlatformNode) importChild;
                    PlatformNode newPlatform = new PlatformNode(platformNode.platform);

                    foreach (pChild; platformNode.children)
                    {
                        if (pChild.nodeType == "Function")
                        {
                            auto funcNode = cast(FunctionNode) pChild;

                            if (funcNode.name == "main")
                                continue;

                            // NOTE: For platform blocks, include ALL functions (even private ones)
                            // because private functions may be dependencies of public functions
                            // that are imported. For .axec files, always include all platform functions
                            // as they are typically low-level helpers needed by other functions.
                            bool isExplicitImport = useNode.importAll || (funcNode.name in importsSet);

                            // For .axec modules, include all platform functions regardless of explicit imports
                            if (!importIsAxec && !useNode.importAll && (funcNode.name !in importsSet))
                                continue;

                            if (isExplicitImport)
                                resolvedImports[funcNode.name] = true;

                            if (isExplicitImport && funcNode.name in moduleFunctionMap)
                            {
                                string originalName = funcNode.name;
                                string prefixedName = moduleFunctionMap[originalName];

                                funcNode.name = prefixedName;
                                importedFunctions[originalName] = prefixedName;
                                renameFunctionCalls(funcNode, moduleFunctionMap);
                                renameTypeReferences(funcNode, moduleModelMap);
                                newPlatform.children ~= funcNode;
                                g_addedNodeNames[prefixedName] = true;
                            }
                            else
                            {
                                if (funcNode.name !in addedFunctionNames)
                                {
                                    addedFunctionNames[funcNode.name] = true;
                                    renameFunctionCalls(funcNode, moduleFunctionMap);
                                    renameTypeReferences(funcNode, moduleModelMap);
                                    foreach (childNode; funcNode.children)
                                    {
                                        renameFunctionCalls(childNode, moduleFunctionMap);
                                        renameTypeReferences(childNode, moduleModelMap);
                                    }
                                    newPlatform.children ~= funcNode;
                                }
                            }
                        }
                        else if (pChild.nodeType == "Model")
                        {
                            auto modelNode = cast(ModelNode) pChild;
                            import std.stdio : writeln;

                            if (!modelNode.isPublic)
                            {
                                continue;
                            }

                            if (useNode.importAll || (modelNode.name in importsSet))
                            {
                                resolvedImports[modelNode.name] = true;
                            }

                            if (useNode.importAll || (modelNode.name in importsSet))
                            {
                                if (modelNode.name == "C")
                                {
                                    continue;
                                }

                                string prefixedName = moduleModelMap[modelNode.name];
                                importedModels[modelNode.name] = prefixedName;
                                auto newModel = new ModelNode(prefixedName, null);
                                newModel.fields = modelNode.fields.dup;
                                newModel.isPublic = modelNode.isPublic;

                                foreach (ref field; newModel.fields)
                                {
                                    if (field.type in moduleModelMap)
                                        field.type = moduleModelMap[field.type];
                                }

                                foreach (method; modelNode.methods)
                                {
                                    auto methodFunc = cast(FunctionNode) method;
                                    if (methodFunc !is null && methodFunc.isPublic)
                                    {
                                        string prefixedMethodName = moduleFunctionMap[methodFunc
                                            .name];
                                        auto newMethod = new FunctionNode(prefixedMethodName, methodFunc
                                                .params);
                                        newMethod.returnType = methodFunc.returnType;
                                        newMethod.children = methodFunc.children;
                                        newMethod.isPublic = methodFunc.isPublic;

                                        renameFunctionCalls(newMethod, moduleFunctionMap);
                                        renameTypeReferences(newMethod, moduleModelMap);

                                        newModel.methods ~= newMethod;
                                        importedFunctions[methodFunc.name] = prefixedMethodName;
                                    }
                                }

                                newPlatform.children ~= newModel;
                                g_addedNodeNames[prefixedName] = true;
                            }
                            else
                            {
                                if (modelNode.name !in addedModelNames)
                                {
                                    addedModelNames[modelNode.name] = true;
                                    isTransitiveDependency[modelNode.name] = true;

                                    foreach (method; modelNode.methods)
                                    {
                                        auto methodFunc = cast(FunctionNode) method;
                                        if (methodFunc !is null)
                                        {
                                            renameFunctionCalls(methodFunc, moduleFunctionMap);
                                            renameTypeReferences(methodFunc, moduleModelMap);
                                        }
                                    }

                                    newPlatform.children ~= modelNode;
                                }
                            }
                        }
                        else if (pChild.nodeType == "Enum")
                        {
                            auto enumNode = cast(EnumNode) pChild;
                            if (useNode.importAll || (enumNode.name in importsSet))
                            {
                                resolvedImports[enumNode.name] = true;
                                enumNode.name = moduleModelMap[enumNode.name];
                                newPlatform.children ~= enumNode;
                            }
                            else
                            {
                                if (enumNode.name !in addedEnumNames)
                                {
                                    addedEnumNames[enumNode.name] = true;
                                    newPlatform.children ~= enumNode;
                                }
                            }
                        }
                        else if (pChild.nodeType == "Extern")
                        {
                            auto externNode = cast(ExternNode) pChild;
                            if (externNode !is null)
                            {
                                bool alreadyAdded = false;
                                foreach (existingChild; newPlatform.children)
                                {
                                    auto existingExtern = cast(ExternNode) existingChild;
                                    if (existingExtern !is null && existingExtern.functionName ==
                                        externNode.functionName)
                                    {
                                        alreadyAdded = true;
                                        break;
                                    }
                                }

                                if (!alreadyAdded)
                                {
                                    newPlatform.children ~= externNode;
                                }
                            }
                        }
                        else if (pChild.nodeType == "Opaque")
                        {
                            auto opaqueNode = cast(OpaqueNode) pChild;
                            if (opaqueNode !is null)
                            {
                                newPlatform.children ~= opaqueNode;
                            }
                        }
                        else if (pChild.nodeType == "Macro")
                        {
                            auto macroNode = cast(MacroNode) pChild;
                            if (useNode.importAll || (macroNode.name in importsSet))
                            {
                                resolvedImports[macroNode.name] = true;
                                macroNode.name = moduleMacroMap[macroNode.name];
                                newPlatform.children ~= macroNode;
                            }
                            else
                            {
                                if (macroNode.name !in addedMacroNames)
                                {
                                    addedMacroNames[macroNode.name] = true;
                                    newPlatform.children ~= macroNode;
                                }
                            }
                        }
                        else if (pChild.nodeType == "Overload")
                        {
                            auto overloadNode = cast(OverloadNode) pChild;
                            if (useNode.importAll || (overloadNode.name in importsSet))
                            {
                                resolvedImports[overloadNode.name] = true;
                                overloadNode.name = moduleMacroMap[overloadNode.name];
                                newPlatform.children ~= overloadNode;
                            }
                            else
                            {
                                if (overloadNode.name !in addedOverloadNames)
                                {
                                    addedOverloadNames[overloadNode.name] = true;
                                    newPlatform.children ~= overloadNode;
                                }
                            }
                        }
                    }

                    if (newPlatform.children.length > 0)
                    {
                        newChildren ~= newPlatform;
                    }

                    continue;
                }

                if (importChild.nodeType == "Function")
                {
                    auto funcNode = cast(FunctionNode) importChild;

                    if (funcNode.name == "main")
                        continue;

                    // Don't skip non-public functions anymore - they need to be added with prefixing
                    // if (!funcNode.isPublic)
                    //     continue;

                    if (funcNode.isPublic && (useNode.importAll || (funcNode.name in importsSet)))
                        resolvedImports[funcNode.name] = true;

                    if (useNode.importAll || (funcNode.name in importsSet) || (funcNode.isPublic &&
                            importIsAxec))
                    {
                        string originalName = funcNode.name;
                        string prefixedName = moduleFunctionMap[originalName];

                        // Rename the function definition itself so that
                        // generated C has a matching symbol for rewritten
                        // call sites (e.g., std_io_read_int).

                        funcNode.name = prefixedName;

                        // Name map must use the ORIGINAL name as key so that
                        // call sites like read_int() or randomize() get
                        // rewritten to the prefixed symbol.

                        importedFunctions[originalName] = prefixedName;
                        renameFunctionCalls(funcNode, moduleFunctionMap);
                        renameTypeReferences(funcNode, moduleModelMap);
                        newChildren ~= funcNode;
                        g_addedNodeNames[prefixedName] = true;
                    }
                    else if (!funcNode.isPublic && funcNode.name in moduleFunctionMap)
                    {
                        string originalName = funcNode.name;
                        string prefixedName = moduleFunctionMap[originalName];

                        debugWriteln("DEBUG: Non-public function '", originalName, "' - isPublic=", funcNode.isPublic,
                            ", inMap=", (funcNode.name in moduleFunctionMap));

                        if (prefixedName !in addedFunctionNames)
                        {
                            funcNode.name = prefixedName;
                            addedFunctionNames[prefixedName] = true;
                            debugWriteln("DEBUG: Adding non-public function '", originalName,
                                "' as '", prefixedName, "'");
                            debugWriteln("DEBUG: moduleFunctionMap has ", moduleFunctionMap.length,
                                " entries for module: ",
                                useNode.moduleName);
                            foreach (key, value; moduleFunctionMap)
                            {
                                if (key.canFind("str") || key.canFind("alphanum") || key.canFind(
                                        "get_char"))
                                    debugWriteln("DEBUG:   '", key, "' -> '", value, "'");
                            }

                            renameFunctionCalls(funcNode, moduleFunctionMap);
                            renameTypeReferences(funcNode, moduleModelMap);
                            newChildren ~= funcNode;
                            g_addedNodeNames[prefixedName] = true;
                        }
                    }
                    else
                    {
                        string originalName = funcNode.name;
                        string prefixedName = originalName;

                        if (originalName in moduleFunctionMap)
                        {
                            prefixedName = moduleFunctionMap[originalName];
                        }

                        if (prefixedName !in addedFunctionNames)
                        {
                            addedFunctionNames[prefixedName] = true;
                            debugWriteln("DEBUG: Adding transitive function: ", originalName, " -> ", prefixedName);

                            funcNode.name = prefixedName;
                            renameFunctionCalls(funcNode, moduleFunctionMap);
                            renameTypeReferences(funcNode, moduleModelMap);
                            foreach (childNode; funcNode.children)
                            {
                                renameFunctionCalls(childNode, moduleFunctionMap);
                                renameTypeReferences(childNode, moduleModelMap);
                            }
                            newChildren ~= funcNode;
                            g_addedNodeNames[prefixedName] = true;
                        }
                        else
                        {
                            debugWriteln("DEBUG: Skipping duplicate transitive function: ", funcNode
                                    .name);
                        }
                    }
                }
                else if (importChild.nodeType == "Model")
                {
                    auto modelNode = cast(ModelNode) importChild;
                    import std.stdio : writeln;

                    if (!modelNode.isPublic)
                    {
                        continue;
                    }

                    // Extract base model name for checking against import list
                    // E.g., "std__errors__error" -> "error"
                    string baseName = modelNode.name;
                    if (modelNode.name.canFind("__"))
                    {
                        auto lastDoubleUnderscore = modelNode.name.lastIndexOf("__");
                        if (lastDoubleUnderscore >= 0)
                        {
                            baseName = modelNode.name[lastDoubleUnderscore + 2 .. $];
                        }
                    }

                    bool isExplicitlyImported = useNode.importAll || (baseName in importsSet);

                    if (isExplicitlyImported)
                    {
                        resolvedImports[baseName] = true;
                    }

                    if (isExplicitlyImported)
                    {
                        if (baseName == "C" || modelNode.name == "C")
                        {
                            continue;
                        }

                        string prefixedName = moduleModelMap.get(modelNode.name, modelNode.name);
                        importedModels[baseName] = prefixedName;
                        auto newModel = new ModelNode(prefixedName, null);
                        newModel.fields = modelNode.fields.dup;
                        newModel.isPublic = modelNode.isPublic;

                        foreach (ref field; newModel.fields)
                        {
                            if (field.type in moduleModelMap)
                                field.type = moduleModelMap[field.type];
                        }

                        foreach (method; modelNode.methods)
                        {
                            auto methodFunc = cast(FunctionNode) method;
                            if (methodFunc !is null && methodFunc.isPublic)
                            {
                                string prefixedMethodName = moduleFunctionMap.get(methodFunc.name,
                                    methodFunc.name);
                                auto newMethod = new FunctionNode(prefixedMethodName, methodFunc
                                        .params);
                                newMethod.returnType = methodFunc.returnType;
                                newMethod.children = methodFunc.children;
                                newMethod.isPublic = methodFunc.isPublic;

                                renameFunctionCalls(newMethod, moduleFunctionMap);
                                renameTypeReferences(newMethod, moduleModelMap);

                                newModel.methods ~= newMethod;

                                importedFunctions[methodFunc.name] = prefixedMethodName;
                            }
                        }

                        newChildren ~= newModel;
                        g_addedNodeNames[prefixedName] = true;
                    }
                    else
                    {
                        if (modelNode.name !in addedModelNames)
                        {
                            addedModelNames[modelNode.name] = true;
                            isTransitiveDependency[modelNode.name] = true;

                            // For transitive dependencies, just pass through the model as-is.
                            // It should already be prefixed from when it was explicitly imported
                            // in its original module.
                            foreach (method; modelNode.methods)
                            {
                                auto methodFunc = cast(FunctionNode) method;
                                if (methodFunc !is null)
                                {
                                    renameFunctionCalls(methodFunc, moduleFunctionMap);
                                    renameTypeReferences(methodFunc, moduleModelMap);
                                }
                            }

                            newChildren ~= modelNode;
                        }
                    }
                }
                else if (importChild.nodeType == "Enum")
                {
                    auto enumNode = cast(EnumNode) importChild;
                    if (useNode.importAll || (enumNode.name in importsSet))
                    {
                        resolvedImports[enumNode.name] = true;
                        enumNode.name = moduleModelMap[enumNode.name];
                        newChildren ~= enumNode;
                    }
                    else
                    {
                        if (enumNode.name !in addedEnumNames)
                        {
                            addedEnumNames[enumNode.name] = true;
                            string prefixedName = enumNode.name.startsWith("std_") ? enumNode.name
                                : (sanitizedModuleName ~ "__" ~ enumNode.name);
                            enumNode.name = prefixedName;
                            newChildren ~= enumNode;
                        }
                    }
                }
                else if (importChild.nodeType == "Macro")
                {
                    auto macroNode = cast(MacroNode) importChild;
                    if (useNode.importAll || (macroNode.name in importsSet))
                    {
                        resolvedImports[macroNode.name] = true;
                        macroNode.name = moduleMacroMap[macroNode.name];
                        newChildren ~= macroNode;
                    }
                    else
                    {
                        if (macroNode.name !in addedMacroNames)
                        {
                            addedMacroNames[macroNode.name] = true;
                            newChildren ~= macroNode;
                        }
                    }
                }
                else if (importChild.nodeType == "Overload")
                {
                    auto overloadNode = cast(OverloadNode) importChild;
                    if (useNode.importAll || (overloadNode.name in importsSet))
                    {
                        resolvedImports[overloadNode.name] = true;
                        overloadNode.name = moduleMacroMap[overloadNode.name];
                        newChildren ~= overloadNode;
                    }
                    else
                    {
                        if (overloadNode.name !in addedOverloadNames)
                        {
                            addedOverloadNames[overloadNode.name] = true;
                            newChildren ~= overloadNode;
                        }
                    }
                }
            }

            foreach (importName; useNode.imports)
            {
                if (importName !in resolvedImports)
                {
                    throw new Exception(
                        "Import '" ~ importName ~ "' not found in module '" ~
                            useNode.moduleName ~ "'");
                }
            }

            newChildren ~= child;
        }
        else
        {
            debugWriteln("DEBUG imports: Renaming user code with ", importedFunctions.length, " imported functions");
            foreach (key, value; importedFunctions)
            {
                debugWriteln("  DEBUG: importedFunctions['", key, "'] = '", value, "'");
            }

            if (child.nodeType == "Model" && currentModulePrefix.length > 0)
            {
                auto modelNode = cast(ModelNode) child;

                if (modelNode.name in isTransitiveDependency)
                {
                    newChildren ~= child;
                    continue;
                }

                string originalModelName = modelNode.name;
                string prefixedModelName = currentModulePrefix ~ "__" ~ originalModelName;
                string[string] modelTypeMap = importedModels.dup;
                modelTypeMap[originalModelName] = prefixedModelName;
                modelNode.name = prefixedModelName;

                foreach (method; modelNode.methods)
                {
                    auto methodFunc = cast(FunctionNode) method;
                    if (methodFunc !is null)
                    {
                        string methodName = methodFunc.name;
                        if (methodName.startsWith(originalModelName ~ "_"))
                        {
                            methodName = methodName[originalModelName.length + 1 .. $];
                        }
                        methodFunc.name = prefixedModelName ~ "_" ~ methodName;

                        string[string] localTypeMap = importedModels.dup;
                        foreach (modelName, prefixedName; localModels)
                        {
                            localTypeMap[modelName] = prefixedName;
                        }
                        foreach (enumName, prefixedName; localEnums)
                        {
                            localTypeMap[enumName] = prefixedName;
                        }

                        renameFunctionCalls(methodFunc, importedFunctions);
                        renameTypeReferences(methodFunc, localTypeMap);
                    }
                }

                string[string] fieldTypeMap = importedModels.dup;
                foreach (modelName, prefixedName; localModels)
                {
                    fieldTypeMap[modelName] = prefixedName;
                }
                foreach (enumName, prefixedName; localEnums)
                {
                    fieldTypeMap[enumName] = prefixedName;
                }
                foreach (ref field; modelNode.fields)
                {
                    if (field.type in fieldTypeMap)
                        field.type = fieldTypeMap[field.type];
                }
            }
            else if (child.nodeType == "Model")
            {
                auto modelNode = cast(ModelNode) child;

                if (modelNode.name in isTransitiveDependency)
                {
                    newChildren ~= child;
                    continue;
                }

                string[string] localTypeMap = importedModels.dup;
                foreach (modelName, prefixedName; localModels)
                {
                    localTypeMap[modelName] = prefixedName;
                }
                foreach (enumName, prefixedName; localEnums)
                {
                    localTypeMap[enumName] = prefixedName;
                }

                foreach (method; modelNode.methods)
                {
                    renameFunctionCalls(method, importedFunctions);
                    renameTypeReferences(method, localTypeMap);
                }

                foreach (ref field; modelNode.fields)
                {
                    if (field.type in localTypeMap)
                        field.type = localTypeMap[field.type];
                }

                renameFunctionCalls(child, importedFunctions);
                renameTypeReferences(child, importedModels);
            }
            else if (child.nodeType == "Function" && (currentModulePrefix.length > 0 || importedFunctions.length > 0))
            {
                auto funcNode = cast(FunctionNode) child;
                if (funcNode.name in isTransitiveDependency)
                {
                    newChildren ~= child;
                    continue;
                }

                if (currentModulePrefix.length > 0 && funcNode.name != "main")
                {
                    string originalName = funcNode.name;
                    funcNode.name = currentModulePrefix ~ "__" ~ funcNode.name;
                    debugWriteln("DEBUG: Renamed function declaration '", originalName, "' -> '", funcNode.name, "'");
                }

                string[string] localTypeMap = importedModels.dup;
                foreach (modelName, prefixedName; localModels)
                {
                    localTypeMap[modelName] = prefixedName;
                }
                foreach (enumName, prefixedName; localEnums)
                {
                    localTypeMap[enumName] = prefixedName;
                }

                // For .axec modules, apply localFunctions renaming so functions call each other with prefixes
                // For regular .axe files, only use importedFunctions
                string[string] functionMap = importedFunctions.dup;
                if (currentModulePrefix.length > 0)
                {
                    debugWriteln("DEBUG: currentModulePrefix=", currentModulePrefix, " applying localFunctions:");
                    foreach (funcName, prefixedName; localFunctions)
                    {
                        debugWriteln("  ", funcName, " -> ", prefixedName);
                        functionMap[funcName] = prefixedName;
                    }
                }

                renameFunctionCalls(child, functionMap);
                renameTypeReferences(child, localTypeMap);
            }
            else if (child.nodeType == "Enum" && currentModulePrefix.length > 0)
            {
                auto enumNode = cast(EnumNode) child;
                if (enumNode.name !in isTransitiveDependency)
                {
                    string originalEnumName = enumNode.name;
                    string prefixedEnumName = currentModulePrefix ~ "__" ~ originalEnumName;
                    enumNode.name = prefixedEnumName;
                }
            }
            else if (child.nodeType == "Test" && currentModulePrefix.length > 0)
            {
                string[string] localTypeMap = importedModels.dup;
                foreach (modelName, prefixedName; localModels)
                {
                    localTypeMap[modelName] = prefixedName;
                }
                foreach (enumName, prefixedName; localEnums)
                {
                    localTypeMap[enumName] = prefixedName;
                }

                string[string] localNameMap = importedFunctions.dup;
                foreach (funcName, prefixedName; localFunctions)
                {
                    localNameMap[funcName] = prefixedName;
                }

                renameFunctionCalls(child, localNameMap);
                renameTypeReferences(child, localTypeMap);
            }
            else
            {
                renameFunctionCalls(child, importedFunctions);
                renameTypeReferences(child, importedModels);
            }

            newChildren ~= child;
        }
    }

    programNode.children = newChildren;
    return programNode;
}

/**
 * Convert ModelName_methodName to a regex pattern ModelName\s*\.\s*methodName
 * Only replaces the FIRST underscore (between model and method name)
 */
string convertToModelMethodPattern(string modelMethodName)
{
    import std.string : indexOf;

    auto firstUnderscore = modelMethodName.indexOf('_');
    if (firstUnderscore == -1)
        return modelMethodName;

    return modelMethodName[0 .. firstUnderscore] ~ "\\s*\\.\\s*" ~ modelMethodName[firstUnderscore + 1 .. $];
}

string escapeRegexLiteral(string value)
{
    import std.array : appender;

    auto buffer = appender!string();
    foreach (ch; value)
    {
        immutable bool needsEscape = ch == '\\' || ch == '.' || ch == '+' || ch == '*' || ch == '?' || ch == '|' ||
            ch == '{' || ch == '}' || ch == '[' || ch == ']' || ch == '(' || ch == ')' || ch == '^' || ch == '$';
        if (needsEscape)
            buffer.put('\\');
        buffer.put(ch);
    }
    return buffer.data;
}

import std.regex : Regex;

private static Regex!char[string] g_regexCache;
private static Regex!char[string] g_modelMethodExactRegexCache;
private static Regex!char[string] g_modelMethodDotCallRegexCache;
private bool[string] g_stringCheckCache;

private Regex!char getModelMethodExactRegex(string oldName)
{
    import std.regex : regex;

    string cacheKey = "model_exact_" ~ oldName;
    if (cacheKey !in g_modelMethodExactRegexCache)
    {
        string modelMethod = convertToModelMethodPattern(oldName);
        g_modelMethodExactRegexCache[cacheKey] = regex("^" ~ modelMethod ~ "$");
    }
    return g_modelMethodExactRegexCache[cacheKey];
}

private Regex!char getModelMethodDotCallRegex(string oldName)
{
    import std.regex : regex;

    string cacheKey = "model_dot_" ~ oldName;
    if (cacheKey !in g_modelMethodDotCallRegexCache)
    {
        string modelMethod = convertToModelMethodPattern(oldName);
        g_modelMethodDotCallRegexCache[cacheKey] = regex("\\b" ~ modelMethod ~ "\\s*\\(");
    }
    return g_modelMethodDotCallRegexCache[cacheKey];
}

string replaceStandaloneCall(string text, string oldName, string newName)
{
    import std.regex : regex, replaceAll, Regex;

    if (!text.canFind(oldName))
        return text;

    if (newName.canFind("_" ~ oldName) && text.canFind(newName ~ "("))
    {
        return text;
    }

    string cacheKey = "standalone_" ~ oldName;
    if (cacheKey !in g_regexCache)
    {
        auto escaped = escapeRegexLiteral(oldName);
        g_regexCache[cacheKey] = regex("(?<![A-Za-z0-9_])" ~ escaped ~ "(\\s*)\\(");
    }

    return replaceAll(text, g_regexCache[cacheKey], newName ~ "$1(");
}

/**
 * TODO: Fix double-prefixed function names (e.g., stdlib_string_stdlib_string_concat -> stdlib_string_concat)
 * This is a NOOP for the moment.
 */
string fixDoublePrefix(string expr)
{
    import std.regex : regex, replaceAll;

    string fixedExpr = expr;

    return fixedExpr;
}

/**
 * Pre-computed data for name mapping to avoid repeated string operations
 */
private struct NameMapData
{
    string[string] dotCallMap;
    string[] underscoreNames;

    static NameMapData create(string[string] nameMap)
    {
        NameMapData data;
        foreach (oldName, newName; nameMap)
        {
            if (oldName.canFind("_"))
            {
                data.underscoreNames ~= oldName;
                string dotCall = oldName.replace("_", ".") ~ "(";
                data.dotCallMap[dotCall] = newName ~ "(";
            }
        }
        return data;
    }
}

private static NameMapData[size_t] g_nameMapDataCache;

private NameMapData getNameMapData(string[string] nameMap)
{
    size_t key = cast(size_t) nameMap.length;
    if (nameMap.length > 0)
    {
        foreach (k, v; nameMap)
        {
            key ^= hashOf(k) ^ hashOf(v);
            break;
        }
    }

    if (key !in g_nameMapDataCache)
    {
        g_nameMapDataCache[key] = NameMapData.create(nameMap);
    }
    return g_nameMapDataCache[key];
}

/**
 * Recursively rename function calls to use prefixed names
 */
void renameFunctionCalls(ASTNode node, string[string] nameMap)
{
    if (nameMap.length == 0)
        return;

    auto mapData = getNameMapData(nameMap);

    if (node.nodeType == "FunctionCall")
    {
        auto callNode = cast(FunctionCallNode) node;

        if (callNode.functionName.startsWith("C_"))
        {
            // Who cares.
        }
        else if (callNode.functionName in nameMap)
            callNode.functionName = nameMap[callNode.functionName];
        else
        {
            foreach (oldName; mapData.underscoreNames)
            {
                import std.regex : matchFirst;

                auto pattern = getModelMethodExactRegex(oldName);
                if (matchFirst(callNode.functionName, pattern))
                {
                    callNode.functionName = nameMap[oldName];
                    break;
                }
            }
        }

        // Also apply renaming inside FunctionCall arguments. This is
        // important for nested calls like `compare(upper, string.create("X"))`
        // where `string.create` only appears as text in the args.
        foreach (ref arg; callNode.args)
        {
            foreach (oldName, newName; nameMap)
            {
                arg = replaceStandaloneCall(arg, oldName, newName);
            }
            foreach (dotCall, replacement; mapData.dotCallMap)
            {
                if (arg.canFind(dotCall))
                {
                    arg = arg.replace(dotCall, replacement);
                }
            }
        }
    }
    else if (node.nodeType == "Print")
    {
        auto printNode = cast(PrintNode) node;
        for (size_t i = 0; i < printNode.messages.length; i++)
        {
            if (i >= printNode.isExpressions.length || !printNode.isExpressions[i])
                continue;
            {
                foreach (oldName, newName; nameMap)
                {
                    printNode.messages[i] = replaceStandaloneCall(printNode.messages[i], oldName, newName);
                }
                foreach (dotCall, replacement; mapData.dotCallMap)
                {
                    if (printNode.messages[i].canFind(dotCall))
                        printNode.messages[i] = printNode.messages[i].replace(dotCall, replacement);
                }
                printNode.messages[i] = fixDoublePrefix(printNode.messages[i]);
            }
        }
    }
    else if (node.nodeType == "Println")
    {
        auto printlnNode = cast(PrintlnNode) node;
        for (size_t i = 0; i < printlnNode.messages.length; i++)
        {
            if (i >= printlnNode.isExpressions.length || !printlnNode.isExpressions[i])
                continue;
            {
                foreach (oldName, newName; nameMap)
                {
                    printlnNode.messages[i] = replaceStandaloneCall(printlnNode.messages[i], oldName, newName);
                }
                foreach (dotCall, replacement; mapData.dotCallMap)
                {
                    if (printlnNode.messages[i].canFind(dotCall))
                        printlnNode.messages[i] = printlnNode.messages[i].replace(dotCall, replacement);
                }
                printlnNode.messages[i] = fixDoublePrefix(printlnNode.messages[i]);
            }
        }
    }
    else if (node.nodeType == "Return")
    {
        auto returnNode = cast(ReturnNode) node;
        debugWriteln("    DEBUG Return before processing: '", returnNode.expression, "'");
        debugWriteln("    DEBUG Return nameMap: ", nameMap);
        foreach (oldName, newName; nameMap)
        {
            string before = returnNode.expression;
            returnNode.expression = replaceStandaloneCall(returnNode.expression, oldName, newName);
            if (before != returnNode.expression)
                debugWriteln("      DEBUG Return replaced '", oldName, "' -> '", newName, "': '", returnNode
                        .expression, "'");
        }

        foreach (dotCall, replacement; mapData.dotCallMap)
        {
            if (returnNode.expression.canFind(dotCall))
            {
                string before = returnNode.expression;
                returnNode.expression = returnNode.expression.replace(dotCall, replacement);
                debugWriteln("      DEBUG Return replaced dot call '", dotCall, "' -> '", replacement, "': '",
                    returnNode.expression, "'");
            }
        }

        import std.regex : replaceAll;

        if (returnNode.expression.canFind("."))
        {
            foreach (oldName; mapData.underscoreNames)
            {
                if (!(oldName in nameMap))
                    continue;
                auto dotPattern = getModelMethodDotCallRegex(oldName);
                string newExpr = replaceAll(returnNode.expression, dotPattern, nameMap[oldName] ~ "(");
                if (newExpr != returnNode.expression)
                {
                    debugWriteln("      DEBUG Return regex replaced pattern: '", returnNode.expression, "' -> '",
                        newExpr, "'");
                    returnNode.expression = newExpr;
                }
            }
        }

        returnNode.expression = fixDoublePrefix(returnNode.expression);

        debugWriteln("    DEBUG Return after processing: '", returnNode.expression, "'");
    }
    else if (node.nodeType == "Declaration")
    {
        auto declNode = cast(DeclarationNode) node;
        debugWriteln("    DEBUG renameFunctionCalls Declaration: initializer='", declNode.initializer, "'");

        bool hasDirectCCall = declNode.initializer.canFind("C_");

        if (!hasDirectCCall)
        {
            foreach (oldName, newName; nameMap)
            {
                auto newInit = replaceStandaloneCall(declNode.initializer, oldName, newName);
                if (newInit != declNode.initializer)
                {
                    debugWriteln("    DEBUG renameFunctionCalls: Renamed call in declaration: '", oldName,
                        "' -> '", newName, "'");
                    declNode.initializer = newInit;
                }
            }

            foreach (dotCall, replacement; mapData.dotCallMap)
            {
                if (declNode.initializer.canFind(dotCall))
                {
                    debugWriteln("    DEBUG renameFunctionCalls: Renamed dot call in declaration: '",
                        dotCall, "' -> '", replacement);
                    declNode.initializer = declNode.initializer.replace(dotCall, replacement);
                }
            }

            import std.regex : replaceAll;

            if (declNode.initializer.canFind("."))
            {
                foreach (oldName; mapData.underscoreNames)
                {
                    if (!(oldName in nameMap))
                        continue;
                    auto dotPattern = getModelMethodDotCallRegex(oldName);
                    debugWriteln("    DEBUG: Trying cached regex pattern for '", oldName, "' on '",
                        declNode.initializer, "'");
                    string regexInit = replaceAll(declNode.initializer, dotPattern, nameMap[oldName] ~ "(");
                    if (regexInit != declNode.initializer)
                    {
                        debugWriteln("    DEBUG: Regex matched! Replaced '", declNode.initializer,
                            "' -> '", regexInit, "'");
                        declNode.initializer = regexInit;
                    }
                }
            }
        }
        declNode.initializer = fixDoublePrefix(declNode.initializer);
    }
    else if (node.nodeType == "Assignment")
    {
        auto assignNode = cast(AssignmentNode) node;
        foreach (oldName, newName; nameMap)
        {
            assignNode.expression = replaceStandaloneCall(assignNode.expression, oldName, newName);
        }

        foreach (dotCall, replacement; mapData.dotCallMap)
        {
            if (assignNode.expression.canFind(dotCall))
            {
                assignNode.expression = assignNode.expression.replace(dotCall, replacement);
            }
        }

        import std.regex : replaceAll;

        if (assignNode.expression.canFind("."))
        {
            foreach (oldName; mapData.underscoreNames)
            {
                if (!(oldName in nameMap))
                    continue;
                auto dotPattern = getModelMethodDotCallRegex(oldName);
                string newExpr = replaceAll(assignNode.expression, dotPattern, nameMap[oldName] ~ "(");
                if (newExpr != assignNode.expression)
                {
                    assignNode.expression = newExpr;
                }
            }
        }
        assignNode.expression = fixDoublePrefix(assignNode.expression);

        // TODO: Remove.
        if (assignNode.expression.canFind("read_int("))
        {
            assignNode.expression = assignNode.expression.replace("read_int(", "std_io_read_int(");
        }
        if (assignNode.expression.canFind("read_float("))
        {
            assignNode.expression = assignNode.expression.replace("read_float(", "std_io_read_float(");
        }
        if (assignNode.expression.canFind("read_string("))
        {
            assignNode.expression = assignNode.expression.replace("read_string(", "std_io_read_string(");
        }
    }
    else if (node.nodeType == "If")
    {
        auto ifNode = cast(IfNode) node;

        debugWriteln("    DEBUG renameFunctionCalls If: condition='", ifNode.condition, "'");
        foreach (oldName, newName; nameMap)
        {
            auto newCond = replaceStandaloneCall(ifNode.condition, oldName, newName);
            if (newCond != ifNode.condition)
            {
                debugWriteln("    DEBUG renameFunctionCalls: Renamed call in if condition: '", oldName,
                    "' -> '", newName, "'");
                ifNode.condition = newCond;
            }
        }

        foreach (dotCall, replacement; mapData.dotCallMap)
        {
            if (ifNode.condition.canFind(dotCall))
            {
                debugWriteln("    DEBUG renameFunctionCalls: Renamed dot call in if condition: '",
                    dotCall, "' -> '", replacement);
                ifNode.condition = ifNode.condition.replace(dotCall, replacement);
            }
        }

        // Also propagate renaming into elif and else branches, which are
        // stored separately from the main children array.
        foreach (elifBranch; ifNode.elifBranches)
        {
            renameFunctionCalls(elifBranch, nameMap);
        }

        foreach (elseChild; ifNode.elseBody)
        {
            renameFunctionCalls(elseChild, nameMap);
        }

        ifNode.condition = fixDoublePrefix(ifNode.condition);
    }
    else if (node.nodeType == "Assert")
    {
        auto assertNode = cast(AssertNode) node;
        foreach (oldName, newName; nameMap)
        {
            assertNode.condition = replaceStandaloneCall(assertNode.condition, oldName, newName);
        }

        foreach (dotCall, replacement; mapData.dotCallMap)
        {
            if (assertNode.condition.canFind(dotCall))
            {
                assertNode.condition = assertNode.condition.replace(dotCall, replacement);
            }
        }

        import std.regex : replaceAll;

        if (assertNode.condition.canFind("."))
        {
            foreach (oldName; mapData.underscoreNames)
            {
                if (!(oldName in nameMap))
                    continue;
                auto dotPattern = getModelMethodDotCallRegex(oldName);
                string newCond = replaceAll(assertNode.condition, dotPattern, nameMap[oldName] ~ "(");
                if (newCond != assertNode.condition)
                {
                    assertNode.condition = newCond;
                }
            }
        }
        assertNode.condition = fixDoublePrefix(assertNode.condition);
    }

    foreach (child; node.children)
    {
        renameFunctionCalls(child, nameMap);
    }
}

/**
 * Replace a type name in code, but skip replacements inside string literals
 */
string replaceTypeOutsideStrings(string code, string oldType, string newType)
{
    import std.array : appender;
    import std.regex : regex, matchFirst;

    auto result = appender!string();
    size_t pos = 0;
    bool inString = false;
    bool inChar = false;

    while (pos < code.length)
    {
        if (pos > 0 && code[pos - 1] == '\\')
        {
            result ~= code[pos];
            pos++;
            continue;
        }

        if (code[pos] == '"' && !inChar)
        {
            inString = !inString;
            result ~= code[pos];
            pos++;
            continue;
        }

        if (code[pos] == '\'' && !inString)
        {
            inChar = !inChar;
            result ~= code[pos];
            pos++;
            continue;
        }

        if (inString || inChar)
        {
            result ~= code[pos];
            pos++;
            continue;
        }

        import std.algorithm : startsWith;
        import std.uni : isAlphaNum;

        if (pos + oldType.length <= code.length && code[pos .. pos + oldType.length] == oldType)
        {
            bool validPrefix = (pos == 0 || (!isAlphaNum(code[pos - 1]) && code[pos - 1] != '_'));
            bool validSuffix = (pos + oldType.length >= code.length ||
                    (!isAlphaNum(code[pos + oldType.length]) && code[pos + oldType.length] != '_'));

            if (validPrefix && validSuffix)
            {
                result ~= newType;
                pos += oldType.length;
                continue;
            }
        }

        result ~= code[pos];
        pos++;
    }

    return result.data;
}

/**
 * Recursively rename type references to use prefixed model names
 */
void renameTypeReferences(ASTNode node, string[string] typeMap)
{
    if (typeMap.length == 0)
        return;

    import std.algorithm : startsWith;
    import std.array : split, join;

    if (node.nodeType == "Function")
    {
        auto funcNode = cast(FunctionNode) node;

        if (funcNode.returnType in typeMap)
            funcNode.returnType = typeMap[funcNode.returnType];
        else if (funcNode.returnType.startsWith("ref "))
        {
            string baseType = funcNode.returnType[4 .. $].strip();
            if (baseType in typeMap)
            {
                funcNode.returnType = "ref " ~ typeMap[baseType];
            }
        }

        for (size_t i = 0; i < funcNode.params.length; i++)
        {
            string param = funcNode.params[i];
            auto parts = param.split(" ");
            if (parts.length >= 2)
            {
                foreach (oldType, newType; typeMap)
                {
                    if (parts[0] == oldType)
                    {
                        parts[0] = newType;
                    }
                    else if (parts.length >= 3 && parts[0] == "ref" && parts[1] == oldType)
                    {
                        parts[1] = newType;
                    }
                    else if (parts[0].startsWith(oldType ~ "["))
                    {
                        parts[0] = parts[0].replace(oldType ~ "[", newType ~ "[");
                    }
                }
                funcNode.params[i] = parts.join(" ");
            }
        }
    }
    else if (node.nodeType == "Declaration")
    {
        auto declNode = cast(DeclarationNode) node;
        if (declNode.typeName in typeMap)
        {
            declNode.typeName = typeMap[declNode.typeName];
        }
    }
    else if (node.nodeType == "ArrayDeclaration")
    {
        auto arrDeclNode = cast(ArrayDeclarationNode) node;
        if (arrDeclNode.elementType in typeMap)
        {
            arrDeclNode.elementType = typeMap[arrDeclNode.elementType];
        }
    }
    else if (node.nodeType == "ModelInstantiation")
    {
        auto modelInstNode = cast(ModelInstantiationNode) node;
        if (modelInstNode.modelName in typeMap)
        {
            modelInstNode.modelName = typeMap[modelInstNode.modelName];
        }
    }
    else if (node.nodeType == "RawC")
    {
        auto rawNode = cast(RawCNode) node;

        foreach (oldType, newType; typeMap)
        {
            rawNode.code = replaceTypeOutsideStrings(rawNode.code, oldType, newType);
        }
    }
    else if (node.nodeType == "Unsafe")
    {
        auto unsafeNode = cast(UnsafeNode) node;
        // Process children of unsafe blocks to rename type references
        foreach (child; unsafeNode.body)
        {
            renameTypeReferences(child, typeMap);
        }
    }
    else if (node.nodeType == "Assignment")
    {
        auto assignNode = cast(AssignmentNode) node;
        // Replace type names in the assignment expression
        foreach (oldType, newType; typeMap)
        {
            assignNode.expression = replaceTypeOutsideStrings(assignNode.expression, oldType, newType);
        }
    }

    foreach (child; node.children)
    {
        renameTypeReferences(child, typeMap);
    }
}

/**
 * Get the user's home directory
 */
string getUserHomeDir()
{
    import std.process : environment;

    version (Windows)
    {
        return environment.get("USERPROFILE", "");
    }
    else
    {
        return environment.get("HOME", "");
    }
}

unittest
{
    import std.string : indexOf;

    assert(convertToModelMethodPattern("Model_method") == r"Model\s*\.\s*method");
    assert(convertToModelMethodPattern("Arena_create") == r"Arena\s*\.\s*create");
}

unittest
{
    NameMapData data;
    data.underscoreNames ~= "Fake_missing_name";
    data.dotCallMap["Fake.missing("] = "prefix_thing(";
    g_nameMapDataCache[0] = data;
    auto decl = new DeclarationNode("x", false, "Fake.missing(1)", "");
    string[string] nameMap;
    renameFunctionCalls(decl, nameMap);
    assert(decl.initializer == "Fake.missing(1)");
}

unittest
{
    auto pn = new PrintlnNode(["literal", "funcCall(1)"], [false]);

    string[string] nameMap;
    nameMap["funcCall"] = "prefix_funcCall";

    renameFunctionCalls(pn, nameMap);

    assert(pn.messages.length == 2);
    assert(pn.isExpressions.length == 1);
    assert(pn.messages[1].canFind("funcCall"));
}

unittest
{
    import std.string : indexOf;

    string expr1 = "my_func(10)";
    string expr2 = "x + my_func(10)";
    string expr3 = "my_func(10) + x";
    string expr4 = "foo(bar(baz(5)))";

    assert(expr1.indexOf("(") >= 0, "Should find function call");
    assert(expr2.indexOf("my_func") >= 0, "Should find function call in expression");
    assert(expr3.indexOf("my_func") >= 0, "Should find function call in expression");
    assert(expr4.indexOf("(") >= 0, "Should find nested function calls");
}

unittest
{
    assert(convertToModelMethodPattern("List_push") == r"List\s*\.\s*push");
    assert(convertToModelMethodPattern("Arena_alloc") == r"Arena\s*\.\s*alloc");

    import std.regex : regex, matchFirst;

    auto pattern = regex("^" ~ convertToModelMethodPattern("List_push") ~ "$");
    assert(matchFirst("List.push", pattern), "Should match List.push");
    assert(matchFirst("List . push", pattern), "Should match List . push");
}
