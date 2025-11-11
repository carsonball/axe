import 
    structs, 
    strformat, 
    strutils

proc lex*(source: string): seq[Token] =
    ## Lexical analysis and tokenization
    ## Includes whitespace skipping, basic tokenization, and string handling

    var tokens: seq[Token]
    var pos = 0

    while pos < source.len:
        case source[pos]
        of ' ', '\n', '\t', '\r':
            inc(pos)
        of '{':
            tokens.add(Token(typ: LBrace, value: "{"))
            inc(pos)
        of '}':
            tokens.add(Token(typ: RBrace, value: "}"))
            inc(pos)
        of ';':
            tokens.add(Token(typ: Semicolon, value: ";"))
            inc(pos)
        of '"':
            let ending = source.find('"', pos + 1)
            if ending == -1:
                raise newException(ValueError, "Unterminated string")
            tokens.add(Token(typ: String, value: source[(pos+1)..(ending-1)]))
            pos = ending + 1
        else:
            if pos + 4 <= source.len and source[pos ..< pos+4] == "main":
                tokens.add(Token(typ: Main, value: "main"))
                pos += 4
            elif pos + 7 <= source.len and source[pos ..< pos+7] == "println":
                tokens.add(Token(typ: Println, value: "println"))
                pos += 7
            elif pos + 4 <= source.len and source[pos ..< pos+4] == "loop":
                tokens.add(Token(typ: Loop, value: "loop"))
                pos += 4
            elif pos + 5 <= source.len and source[pos ..< pos+5] == "break":
                tokens.add(Token(typ: Break, value: "break"))
                pos += 5
            elif pos + 3 <= source.len and source[pos ..< pos+3] == "def":
                tokens.add(Token(typ: Def, value: "def"))
                pos += 3
            elif source[pos].isAlphaAscii():
                let start = pos
                while pos < source.len:
                    inc(pos)
                tokens.add(Token(typ: Identifier, value: source[start..<pos]))
            else:
                let charAtPos = if pos < source.len: source[pos] else: '.'
                echo "Charatpos: " & charAtPos
                echo "Pos: " & $pos
                echo "Char code: " & $ord(charAtPos)
                raise newException(ValueError,
                        &"Unexpected character at position {pos}: '{charAtPos}'")
    return tokens