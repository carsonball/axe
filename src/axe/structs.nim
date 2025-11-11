type
    TokenType* = enum
        Main,
        Println,
        Loop,
        Break,
        String,
        Semicolon,
        LBrace,
        RBrace,
        Def,
        Identifier,
        Whitespace,
        Newline,
        LParen,
        RParen,
        LBracket,
        RBracket,
        Comma,
        Dot,
        Colon

    Token* = object
        typ*: TokenType
        value*: string

    ASTNode* = object
        nodeType*: string
        children*: seq[ASTNode]
        value*: string
