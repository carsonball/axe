This directory contains the self-hosted version of the Axe compiler, written in Axe itself.

## Status: WIP

### TODO

#### Bugfixes

- [x] Fix `[]` syntax with non-primitive types

#### Overarching

- [x] **lexer.axe** - Lexical Analysis and Tokenization
- [-] **parser.axe** - Parse tokens into an AST
- [ ] **ast.axe** - Abstract syntax tree node definitions
- [ ] **validator.axe** - Semantic analysis and type checking
- [ ] **codegen.axe** - Code generation to C
- [ ] **imports.axe** - Module import resolution
- [ ] **optimizer.axe** - AST optimization passes
