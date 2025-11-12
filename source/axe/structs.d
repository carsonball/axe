module axe.structs;

/** 
 * Token types for the Axe language.
 */
enum TokenType
{
    MAIN,
    PRINTLN,
    LOOP,
    BREAK,
    STR,
    SEMICOLON,
    LBRACE,
    RBRACE,
    DEF,
    IDENTIFIER,
    WHITESPACE,
    NEWLINE,
    LPAREN,
    RPAREN,
    LBRACKET,
    RBRACKET,
    COMMA,
    DOT,
    COLON,
    OPERATOR,
    IF
}

/** 
 * Token struct for the Axe language.
 */
struct Token
{
    TokenType type;
    string value;
}

/** 
 * Abstract syntax tree node for the Axe language.
 */
struct ASTNode
{
    string nodeType;
    ASTNode[] children;
    string value;
}
