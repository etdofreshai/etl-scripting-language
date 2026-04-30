from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

KEYWORDS = {"fn", "let", "if", "elif", "else", "while", "ret", "type", "use", "end", "true", "false", "and", "or", "not"}
SINGLE = {
    "(": "LPAREN",
    ")": "RPAREN",
    ",": "COMMA",
    "+": "PLUS",
    "-": "MINUS",
    "*": "STAR",
    "/": "SLASH",
    "%": "PERCENT",
    "=": "EQUAL",
    "<": "LT",
    ">": "GT",
    "[": "LBRACKET",
    "]": "RBRACKET",
    ".": "DOT",
}
DOUBLE = {
    "==": "EQEQ",
    "!=": "NEQ",
    "<=": "LTE",
    ">=": "GTE",
}


@dataclass(frozen=True)
class Token:
    kind: str
    text: str
    line: int
    col: int


@dataclass(frozen=True)
class SourceLoc:
    line: int
    col: int

    @classmethod
    def from_token(cls, token: Token) -> "SourceLoc":
        return cls(token.line, token.col)

    def format(self) -> str:
        return f"{self.line}:{self.col}"


class ETLError(Exception):
    pass


class LexerError(ETLError):
    pass


class ParseError(ETLError):
    pass


class SemanticError(ETLError):
    pass


@dataclass(frozen=True)
class ArrayType:
    element_type: str
    size: int
    loc: SourceLoc

    def format(self) -> str:
        return f"{self.element_type}[{self.size}]"


TypeRef = str | ArrayType


@dataclass(frozen=True)
class Program:
    structs: list["StructDecl"]
    functions: list["Function"]


@dataclass(frozen=True)
class StructDecl:
    name: str
    fields: list["Field"]
    loc: SourceLoc


@dataclass(frozen=True)
class Field:
    name: str
    typ: TypeRef
    loc: SourceLoc


@dataclass(frozen=True)
class Function:
    name: str
    params: list["Param"]
    return_type: TypeRef
    body: list["Stmt"]
    loc: SourceLoc


@dataclass(frozen=True)
class Param:
    name: str
    typ: TypeRef
    loc: SourceLoc


@dataclass(frozen=True)
class Let:
    name: str
    typ: TypeRef
    expr: "Expr | None"
    loc: SourceLoc


@dataclass(frozen=True)
class Ret:
    expr: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class Assign:
    name: str
    expr: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class IndexAssign:
    array: str
    index: "Expr"
    expr: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class ExprAssign:
    target: "Expr"
    expr: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class ElifBranch:
    cond: "Expr"
    body: list["Stmt"]
    loc: SourceLoc


@dataclass(frozen=True)
class If:
    cond: "Expr"
    then_body: list["Stmt"]
    elifs: list[ElifBranch]
    else_body: list["Stmt"] | None
    loc: SourceLoc


@dataclass(frozen=True)
class While:
    cond: "Expr"
    body: list["Stmt"]
    loc: SourceLoc


Stmt = Let | Ret | Assign | IndexAssign | ExprAssign | If | While


@dataclass(frozen=True)
class IntLit:
    value: int
    loc: SourceLoc


@dataclass(frozen=True)
class BoolLit:
    value: bool
    loc: SourceLoc


@dataclass(frozen=True)
class Name:
    value: str
    loc: SourceLoc


@dataclass(frozen=True)
class Call:
    name: str
    args: list["Expr"]
    loc: SourceLoc


@dataclass(frozen=True)
class Index:
    array: "Expr"
    index: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class FieldAccess:
    base: "Expr"
    field: str
    loc: SourceLoc


@dataclass(frozen=True)
class Binary:
    op: str
    left: "Expr"
    right: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class Unary:
    op: str
    operand: "Expr"
    loc: SourceLoc


Expr = IntLit | BoolLit | Name | Call | Index | FieldAccess | Binary | Unary


def lex(src: str) -> list[Token]:
    tokens: list[Token] = []
    i = 0
    line = 1
    col = 1
    while i < len(src):
        ch = src[i]
        if ch in " \t\r":
            i += 1
            col += 1
            continue
        if ch == "\n":
            i += 1
            line += 1
            col = 1
            continue
        if ch == "/" and i + 1 < len(src) and src[i + 1] == "/":
            while i < len(src) and src[i] != "\n":
                i += 1
                col += 1
            continue
        if ch in "{}":
            raise LexerError(f"unexpected character {ch!r} at {line}:{col}; ETL no longer uses braces for blocks, use 'end'")
        if ch == "!" and i + 1 < len(src) and src[i + 1] == "=":
            tokens.append(Token("NEQ", "!=", line, col))
            i += 2
            col += 2
            continue
        if ch == "!" :
            raise LexerError(f"unexpected character '!' at {line}:{col}")
        # Check for two-character operators first
        if i + 1 < len(src) and src[i:i+2] in DOUBLE:
            text = src[i:i+2]
            tokens.append(Token(DOUBLE[text], text, line, col))
            i += 2
            col += 2
            continue
        if ch in SINGLE:
            tokens.append(Token(SINGLE[ch], ch, line, col))
            i += 1
            col += 1
            continue
        if ch.isdigit():
            start = i
            start_col = col
            while i < len(src) and src[i].isdigit():
                i += 1
                col += 1
            tokens.append(Token("INT", src[start:i], line, start_col))
            continue
        if is_ident_start(ch):
            start = i
            start_col = col
            while i < len(src) and is_ident_continue(src[i]):
                i += 1
                col += 1
            text = src[start:i]
            kind = text.upper() if text in KEYWORDS else "IDENT"
            tokens.append(Token(kind, text, line, start_col))
            continue
        raise LexerError(f"unexpected character {ch!r} at {line}:{col}")
    tokens.append(Token("EOF", "", line, col))
    return tokens


def is_ident_start(ch: str) -> bool:
    return ch == "_" or "A" <= ch <= "Z" or "a" <= ch <= "z"


def is_ident_continue(ch: str) -> bool:
    return is_ident_start(ch) or "0" <= ch <= "9"


class Parser:
    def __init__(self, tokens: list[Token]):
        self.tokens = tokens
        self.pos = 0

    def peek(self) -> Token:
        return self.tokens[self.pos]

    def take(self, kind: str) -> Token:
        tok = self.peek()
        if tok.kind != kind:
            raise ParseError(f"expected {kind}, got {tok.kind} at {tok.line}:{tok.col}")
        self.pos += 1
        return tok

    def parse_program(self) -> Program:
        structs = []
        funcs = []
        while self.peek().kind != "EOF":
            if self.peek().kind == "TYPE":
                structs.append(self.parse_struct_decl())
            else:
                funcs.append(self.parse_function())
        return Program(structs, funcs)

    def parse_struct_decl(self) -> StructDecl:
        type_tok = self.take("TYPE")
        name = self.take("IDENT").text
        struct_tok = self.take("IDENT")
        if struct_tok.text != "struct":
            raise ParseError(f"expected struct, got {struct_tok.text!r} at {struct_tok.line}:{struct_tok.col}")
        fields: list[Field] = []
        while self.peek().kind != "END":
            if self.peek().kind == "EOF":
                raise ParseError(f"expected 'end' before EOF in struct {name!r} at {self.peek().line}:{self.peek().col}")
            field_tok = self.take("IDENT")
            fields.append(Field(field_tok.text, self.parse_type(), SourceLoc.from_token(field_tok)))
        self.take("END")
        return StructDecl(name, fields, SourceLoc.from_token(type_tok))

    def parse_function(self) -> Function:
        fn_tok = self.take("FN")
        name = self.take("IDENT").text
        self.take("LPAREN")
        params: list[Param] = []
        if self.peek().kind != "RPAREN":
            while True:
                param_tok = self.take("IDENT")
                pname = param_tok.text
                ptype = self.parse_type()
                params.append(Param(pname, ptype, SourceLoc.from_token(param_tok)))
                if self.peek().kind == "COMMA":
                    self.take("COMMA")
                    continue
                if self.peek().kind != "RPAREN":
                    tok = self.peek()
                    raise ParseError(f"expected COMMA or RPAREN after parameter, got {tok.kind} at {tok.line}:{tok.col}")
                break
        self.take("RPAREN")
        return_type = self.parse_type()
        body = self.parse_block({"END"}, f"function {name!r}")
        self.take("END")
        return Function(name, params, return_type, body, SourceLoc.from_token(fn_tok))

    def parse_type(self) -> TypeRef:
        type_tok = self.take("IDENT")
        base = type_tok.text
        if self.peek().kind != "LBRACKET":
            return base
        self.take("LBRACKET")
        if self.peek().kind == "MINUS":
            minus_tok = self.take("MINUS")
            if self.peek().kind != "INT":
                raise ParseError(f"expected array size literal after '-' at {minus_tok.line}:{minus_tok.col}")
            size = -int(self.take("INT").text)
            loc = SourceLoc.from_token(minus_tok)
        elif self.peek().kind == "INT":
            size_tok = self.take("INT")
            size = int(size_tok.text)
            loc = SourceLoc.from_token(size_tok)
        else:
            tok = self.peek()
            raise ParseError(f"expected integer literal array size at {tok.line}:{tok.col}")
        self.take("RBRACKET")
        if size <= 0:
            raise ParseError(f"array size must be a positive integer literal at {loc.format()}")
        return ArrayType(base, size, loc)

    def parse_block(self, terminators: set[str], context: str) -> list[Stmt]:
        body: list[Stmt] = []
        while self.peek().kind not in terminators:
            if self.peek().kind == "EOF":
                raise ParseError(f"expected 'end' before EOF in {context} at {self.peek().line}:{self.peek().col}")
            body.append(self.parse_stmt())
        return body

    def parse_stmt(self) -> Stmt:
        if self.peek().kind == "LET":
            let_tok = self.take("LET")
            name = self.take("IDENT").text
            typ = self.parse_type()
            expr = None
            if self.peek().kind == "EQUAL":
                self.take("EQUAL")
                expr = self.parse_expr()
            return Let(name, typ, expr, SourceLoc.from_token(let_tok))
        if self.peek().kind == "RET":
            ret_tok = self.take("RET")
            return Ret(self.parse_expr(), SourceLoc.from_token(ret_tok))
        if self.peek().kind == "IF":
            if_tok = self.take("IF")
            cond = self.parse_expr()
            then_body = self.parse_block({"ELIF", "ELSE", "END"}, "if statement")
            elifs: list[ElifBranch] = []
            while self.peek().kind == "ELIF":
                elif_tok = self.take("ELIF")
                elif_cond = self.parse_expr()
                elif_body = self.parse_block({"ELIF", "ELSE", "END"}, "elif block")
                elifs.append(ElifBranch(elif_cond, elif_body, SourceLoc.from_token(elif_tok)))
            else_body = None
            if self.peek().kind == "ELSE":
                self.take("ELSE")
                else_body = self.parse_block({"END"}, "else block")
            self.take("END")
            return If(cond, then_body, elifs, else_body, SourceLoc.from_token(if_tok))
        if self.peek().kind == "WHILE":
            while_tok = self.take("WHILE")
            cond = self.parse_expr()
            body = self.parse_block({"END"}, "while statement")
            self.take("END")
            return While(cond, body, SourceLoc.from_token(while_tok))
        if self.peek().kind == "IDENT":
            start = self.pos
            target = self.parse_postfix_name()
            if self.peek().kind == "EQUAL":
                self.take("EQUAL")
                loc = target.loc
                expr = self.parse_expr()
                if isinstance(target, Name):
                    return Assign(target.value, expr, loc)
                if isinstance(target, Index) and isinstance(target.array, Name):
                    return IndexAssign(target.array.value, target.index, expr, loc)
                return ExprAssign(target, expr, loc)
            self.pos = start
        tok = self.peek()
        raise ParseError(f"expected statement at {tok.line}:{tok.col}")

    def parse_expr(self) -> Expr:
        return self.parse_or()

    def parse_or(self) -> Expr:
        expr = self.parse_and()
        while self.peek().kind == "OR":
            op_tok = self.peek()
            self.take("OR")
            expr = Binary("or", expr, self.parse_and(), SourceLoc.from_token(op_tok))
        return expr

    def parse_and(self) -> Expr:
        expr = self.parse_not()
        while self.peek().kind == "AND":
            op_tok = self.peek()
            self.take("AND")
            expr = Binary("and", expr, self.parse_not(), SourceLoc.from_token(op_tok))
        return expr

    def parse_not(self) -> Expr:
        if self.peek().kind == "NOT":
            op_tok = self.take("NOT")
            operand = self.parse_not()
            return Unary("not", operand, SourceLoc.from_token(op_tok))
        return self.parse_comparison()

    def parse_comparison(self) -> Expr:
        expr = self.parse_additive()
        while self.peek().kind in {"EQEQ", "NEQ", "LT", "LTE", "GT", "GTE"}:
            op_tok = self.peek()
            self.take(op_tok.kind)
            expr = Binary(op_tok.text, expr, self.parse_additive(), SourceLoc.from_token(op_tok))
        return expr

    def parse_additive(self) -> Expr:
        expr = self.parse_term()
        while self.peek().kind in {"PLUS", "MINUS"}:
            op_tok = self.peek()
            self.take(op_tok.kind)
            expr = Binary(op_tok.text, expr, self.parse_term(), SourceLoc.from_token(op_tok))
        return expr

    def parse_term(self) -> Expr:
        expr = self.parse_unary()
        while self.peek().kind in {"STAR", "SLASH", "PERCENT"}:
            op_tok = self.peek()
            self.take(op_tok.kind)
            expr = Binary(op_tok.text, expr, self.parse_unary(), SourceLoc.from_token(op_tok))
        return expr

    def parse_unary(self) -> Expr:
        if self.peek().kind == "MINUS":
            minus_tok = self.take("MINUS")
            # Check if this is a negative integer literal: '-' followed immediately by INT
            if self.peek().kind == "INT":
                return IntLit(-int(self.take("INT").text), SourceLoc.from_token(minus_tok))
            # General unary minus on expression
            operand = self.parse_unary()
            return Unary("-", operand, SourceLoc.from_token(minus_tok))
        return self.parse_primary()

    def parse_primary(self) -> Expr:
        tok = self.peek()
        if tok.kind == "TRUE":
            self.take("TRUE")
            return BoolLit(True, SourceLoc.from_token(tok))
        if tok.kind == "FALSE":
            self.take("FALSE")
            return BoolLit(False, SourceLoc.from_token(tok))
        if tok.kind == "INT":
            return IntLit(int(self.take("INT").text), SourceLoc.from_token(tok))
        if tok.kind == "LPAREN":
            self.take("LPAREN")
            expr = self.parse_expr()
            self.take("RPAREN")
            return expr
        if tok.kind == "IDENT":
            return self.parse_postfix_name()
        raise ParseError(f"expected expression at {tok.line}:{tok.col}")

    def parse_postfix_name(self) -> Expr:
        ident_tok = self.take("IDENT")
        name = ident_tok.text
        expr: Expr
        if self.peek().kind == "LPAREN":
            self.take("LPAREN")
            args: list[Expr] = []
            if self.peek().kind != "RPAREN":
                while True:
                    args.append(self.parse_expr())
                    if self.peek().kind == "COMMA":
                        self.take("COMMA")
                        continue
                    if self.peek().kind != "RPAREN":
                        tok = self.peek()
                        raise ParseError(f"expected COMMA or RPAREN after argument, got {tok.kind} at {tok.line}:{tok.col}")
                    break
            self.take("RPAREN")
            expr = Call(name, args, SourceLoc.from_token(ident_tok))
        else:
            expr = Name(name, SourceLoc.from_token(ident_tok))
        while self.peek().kind in {"LBRACKET", "DOT"}:
            if self.peek().kind == "LBRACKET":
                bracket_tok = self.take("LBRACKET")
                index = self.parse_expr()
                self.take("RBRACKET")
                expr = Index(expr, index, SourceLoc.from_token(bracket_tok))
            else:
                dot_tok = self.take("DOT")
                field = self.take("IDENT").text
                expr = FieldAccess(expr, field, SourceLoc.from_token(dot_tok))
        return expr


def parse(src: str) -> Program:
    return Parser(lex(src)).parse_program()


SUPPORTED_TYPES = {"i32", "bool"}
C_RESERVED_IDENTIFIERS = {
    # C keywords and backend-provided typedef names share the ordinary
    # identifier namespace with ETL function/local names in emitted C.
    "auto",
    "break",
    "case",
    "char",
    "const",
    "continue",
    "default",
    "do",
    "double",
    "else",
    "enum",
    "extern",
    "float",
    "for",
    "goto",
    "if",
    "inline",
    "int",
    "long",
    "register",
    "restrict",
    "return",
    "short",
    "signed",
    "sizeof",
    "static",
    "struct",
    "switch",
    "typedef",
    "union",
    "unsigned",
    "void",
    "volatile",
    "while",
    "int8_t",
    "int16_t",
    "int32_t",
    "int64_t",
    "uint8_t",
    "uint16_t",
    "uint32_t",
    "uint64_t",
    "intptr_t",
    "uintptr_t",
}
I32_MIN = -(2**31)
I32_MAX = 2**31 - 1


def validate(program: Program) -> None:
    structs: dict[str, StructDecl] = {}
    for struct in program.structs:
        validate_identifier(struct.name, "type", struct.loc)
        if struct.name in SUPPORTED_TYPES:
            raise SemanticError(f"{struct.loc.format()}: duplicate struct type {struct.name!r}")
        if struct.name in structs:
            raise SemanticError(f"{struct.loc.format()}: duplicate struct type {struct.name!r}")
        if not struct.fields:
            raise SemanticError(f"{struct.loc.format()}: struct {struct.name!r} must have at least one field in v0")
        field_names: set[str] = set()
        for field in struct.fields:
            validate_identifier(field.name, "field", field.loc)
            if field.name in field_names:
                raise SemanticError(f"{field.loc.format()}: duplicate field {field.name!r} in struct {struct.name!r}")
            validate_field_type(field.typ, f"field {field.name} in struct {struct.name}", field.loc, structs)
            field_names.add(field.name)
        structs[struct.name] = struct

    functions: dict[str, Function] = {}
    for fn in program.functions:
        validate_identifier(fn.name, "function", fn.loc)
        if fn.name in functions:
            raise SemanticError(f"{fn.loc.format()}: duplicate function {fn.name!r}")
        functions[fn.name] = fn

    if "main" not in functions:
        raise SemanticError("program must define function 'main'")

    main_fn = functions["main"]
    if main_fn.params:
        raise SemanticError(f"{main_fn.loc.format()}: function 'main' must not take parameters")
    if not same_type(main_fn.return_type, "i32"):
        raise SemanticError(f"{main_fn.loc.format()}: function 'main' must return i32")

    for fn in program.functions:
        validate_type(fn.return_type, f"return type for {fn.name}", fn.loc, structs)
        if is_array_type(fn.return_type):
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} cannot return array type {format_type(fn.return_type)!r} in v0")
        if is_struct_type(fn.return_type, structs):
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} cannot return struct type {format_type(fn.return_type)!r} in v0")
        if not fn.body:
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} must end with ret")
        names: dict[str, TypeRef] = {}
        for param in fn.params:
            validate_identifier(param.name, "parameter", param.loc)
            validate_type(param.typ, f"parameter {param.name} in {fn.name}", param.loc, structs)
            if is_array_type(param.typ):
                raise SemanticError(f"{param.loc.format()}: parameter {param.name!r} cannot have array type {format_type(param.typ)!r} in v0")
            if is_struct_type(param.typ, structs):
                raise SemanticError(f"{param.loc.format()}: parameter {param.name!r} cannot have struct type {format_type(param.typ)!r} in v0")
            if param.name in functions:
                raise SemanticError(
                    f"{param.loc.format()}: parameter name {param.name!r} conflicts with function name in {fn.name}"
                )
            if param.name in names:
                raise SemanticError(f"{param.loc.format()}: duplicate local name {param.name!r} in {fn.name}")
            names[param.name] = param.typ
        validate_stmts(fn.body, functions, structs, names, fn)
        if not body_returns(fn.body):
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} must end with ret")


def validate_stmts(
    stmts: list[Stmt],
    functions: dict[str, Function],
    structs: dict[str, StructDecl],
    names: dict[str, TypeRef],
    fn: Function,
) -> bool:
    saw_return = False
    for stmt in stmts:
        if saw_return:
            raise SemanticError(f"{stmt.loc.format()}: unreachable statement after ret in {fn.name}")
        if isinstance(stmt, Let):
            validate_identifier(stmt.name, "local", stmt.loc)
            validate_type(stmt.typ, f"local {stmt.name} in {fn.name}", stmt.loc, structs)
            if stmt.name in functions:
                raise SemanticError(
                    f"{stmt.loc.format()}: local name {stmt.name!r} conflicts with function name in {fn.name}"
                )
            if stmt.name in names:
                raise SemanticError(f"{stmt.loc.format()}: duplicate local name {stmt.name!r} in {fn.name}")
            if is_array_type(stmt.typ):
                if stmt.expr is not None:
                    raise SemanticError(f"{stmt.loc.format()}: array local {stmt.name!r} cannot have an initializer in v0")
            elif is_struct_type(stmt.typ, structs):
                if stmt.expr is not None:
                    raise SemanticError(f"{stmt.loc.format()}: struct local {stmt.name!r} cannot have an initializer in v0")
            else:
                if stmt.expr is None:
                    raise SemanticError(f"{stmt.loc.format()}: scalar local {stmt.name!r} requires an initializer in {fn.name}")
                expr_type = validate_expr(stmt.expr, functions, structs, names, fn.name)
                if not same_type(expr_type, stmt.typ):
                    raise SemanticError(
                        f"{stmt.loc.format()}: let {stmt.name!r} expected {format_type(stmt.typ)!r}, got {format_type(expr_type)!r} in {fn.name}"
                    )
            names[stmt.name] = stmt.typ
        elif isinstance(stmt, Ret):
            expr_type = validate_expr(stmt.expr, functions, structs, names, fn.name)
            if not same_type(expr_type, fn.return_type):
                raise SemanticError(
                    f"{stmt.loc.format()}: return expected {format_type(fn.return_type)!r}, got {format_type(expr_type)!r} in {fn.name}"
                )
            saw_return = True
        elif isinstance(stmt, Assign):
            if stmt.name not in names:
                raise SemanticError(f"{stmt.loc.format()}: assignment to undeclared local {stmt.name!r} in {fn.name}")
            expr_type = validate_expr(stmt.expr, functions, structs, names, fn.name)
            expected_type = names[stmt.name]
            if is_array_type(expected_type):
                raise SemanticError(f"{stmt.loc.format()}: cannot assign whole array {stmt.name!r} in v0")
            if is_struct_type(expected_type, structs):
                raise SemanticError(f"{stmt.loc.format()}: cannot assign whole struct {stmt.name!r} in v0")
            if not same_type(expr_type, expected_type):
                raise SemanticError(
                    f"{stmt.loc.format()}: assignment to {stmt.name!r} expected {format_type(expected_type)!r}, got {format_type(expr_type)!r} in {fn.name}"
                )
        elif isinstance(stmt, IndexAssign):
            if stmt.array not in names:
                raise SemanticError(f"{stmt.loc.format()}: assignment to undeclared local {stmt.array!r} in {fn.name}")
            array_type = names[stmt.array]
            if not isinstance(array_type, ArrayType):
                raise SemanticError(f"{stmt.loc.format()}: indexed assignment target {stmt.array!r} is not an array in {fn.name}")
            index_type = validate_expr(stmt.index, functions, structs, names, fn.name)
            if not same_type(index_type, "i32"):
                raise SemanticError(
                    f"{stmt.index.loc.format()}: array index expected 'i32', got {format_type(index_type)!r} in {fn.name}"
                )
            expr_type = validate_expr(stmt.expr, functions, structs, names, fn.name)
            if is_struct_type(array_type.element_type, structs):
                raise SemanticError(f"{stmt.loc.format()}: cannot assign whole struct array element {stmt.array!r} in v0")
            if not same_type(expr_type, array_type.element_type):
                raise SemanticError(
                    f"{stmt.loc.format()}: indexed assignment to {stmt.array!r} expected {array_type.element_type!r}, got {format_type(expr_type)!r} in {fn.name}"
                )
        elif isinstance(stmt, ExprAssign):
            expected_type = validate_lvalue(stmt.target, functions, structs, names, fn.name)
            if is_array_type(expected_type):
                raise SemanticError(f"{stmt.loc.format()}: cannot assign whole array field in v0")
            if is_struct_type(expected_type, structs):
                raise SemanticError(f"{stmt.loc.format()}: cannot assign whole struct field in v0")
            expr_type = validate_expr(stmt.expr, functions, structs, names, fn.name)
            if not same_type(expr_type, expected_type):
                raise SemanticError(
                    f"{stmt.loc.format()}: assignment expected {format_type(expected_type)!r}, got {format_type(expr_type)!r} in {fn.name}"
                )
        elif isinstance(stmt, If):
            cond_type = validate_expr(stmt.cond, functions, structs, names, fn.name)
            if cond_type != "bool":
                raise SemanticError(
                    f"{stmt.cond.loc.format()}: if condition expected bool, got {cond_type!r} in {fn.name}"
                )
            then_returns = validate_stmts(stmt.then_body, functions, structs, names.copy(), fn)
            elif_returns = []
            for branch in stmt.elifs:
                elif_cond_type = validate_expr(branch.cond, functions, structs, names, fn.name)
                if elif_cond_type != "bool":
                    raise SemanticError(
                        f"{branch.cond.loc.format()}: elif condition expected bool, got {elif_cond_type!r} in {fn.name}"
                    )
                elif_returns.append(validate_stmts(branch.body, functions, structs, names.copy(), fn))
            else_returns = False
            if stmt.else_body is not None:
                else_returns = validate_stmts(stmt.else_body, functions, structs, names.copy(), fn)
            saw_return = then_returns and all(elif_returns) and else_returns
        elif isinstance(stmt, While):
            cond_type = validate_expr(stmt.cond, functions, structs, names, fn.name)
            if cond_type != "bool":
                raise SemanticError(
                    f"{stmt.cond.loc.format()}: while condition expected bool, got {cond_type!r} in {fn.name}"
                )
            validate_stmts(stmt.body, functions, structs, names.copy(), fn)
        else:
            raise TypeError(stmt)
    return saw_return


def body_returns(stmts: list[Stmt]) -> bool:
    if not stmts:
        return False
    last = stmts[-1]
    if isinstance(last, Ret):
        return True
    if isinstance(last, If) and last.else_body is not None:
        return (
            body_returns(last.then_body)
            and all(body_returns(branch.body) for branch in last.elifs)
            and body_returns(last.else_body)
        )
    return False


def validate_type(typ: TypeRef, where: str, loc: SourceLoc, structs: dict[str, StructDecl] | None = None) -> None:
    structs = structs or {}
    if isinstance(typ, ArrayType):
        if typ.element_type not in SUPPORTED_TYPES and typ.element_type not in structs:
            raise SemanticError(f"{typ.loc.format()}: unsupported array element type {typ.element_type!r} in {where}")
        if typ.size <= 0:
            raise SemanticError(f"{typ.loc.format()}: array size must be a positive integer literal in {where}")
        return
    if typ not in SUPPORTED_TYPES and typ not in structs:
        raise SemanticError(f"{loc.format()}: unsupported type {typ!r} in {where}")


def validate_field_type(typ: TypeRef, where: str, loc: SourceLoc, structs: dict[str, StructDecl]) -> None:
    if isinstance(typ, ArrayType):
        if typ.element_type not in SUPPORTED_TYPES:
            raise SemanticError(f"{typ.loc.format()}: unsupported array field element type {typ.element_type!r} in {where}")
        if typ.size <= 0:
            raise SemanticError(f"{typ.loc.format()}: array size must be a positive integer literal in {where}")
        return
    validate_type(typ, where, loc, structs)


def is_array_type(typ: TypeRef) -> bool:
    return isinstance(typ, ArrayType)


def is_struct_type(typ: TypeRef, structs: dict[str, StructDecl]) -> bool:
    return isinstance(typ, str) and typ in structs


def struct_field(struct_name: str, field_name: str, structs: dict[str, StructDecl], loc: SourceLoc) -> Field:
    for field in structs[struct_name].fields:
        if field.name == field_name:
            return field
    raise SemanticError(f"{loc.format()}: unknown field {field_name!r} on struct {struct_name!r}")


def same_type(left: TypeRef, right: TypeRef) -> bool:
    if isinstance(left, ArrayType) and isinstance(right, ArrayType):
        return left.element_type == right.element_type and left.size == right.size
    return isinstance(left, str) and isinstance(right, str) and left == right


def format_type(typ: TypeRef) -> str:
    if isinstance(typ, ArrayType):
        return typ.format()
    return typ


def validate_identifier(name: str, where: str, loc: SourceLoc) -> None:
    if name in C_RESERVED_IDENTIFIERS or is_c_reserved_underscore_identifier(name):
        raise SemanticError(f"{loc.format()}: {where} name {name!r} is reserved by the C backend")


def is_c_reserved_underscore_identifier(name: str) -> bool:
    return name.startswith("__") or (len(name) > 1 and name[0] == "_" and name[1].isupper())


def validate_expr(expr: Expr, functions: dict[str, Function], structs: dict[str, StructDecl], names: dict[str, TypeRef], current_fn: str) -> TypeRef:
    if isinstance(expr, IntLit):
        if not (I32_MIN <= expr.value <= I32_MAX):
            raise SemanticError(
                f"{expr.loc.format()}: integer literal {expr.value} is outside supported i32 range in {current_fn}"
            )
        return "i32"
    if isinstance(expr, BoolLit):
        return "bool"
    if isinstance(expr, Name):
        if expr.value not in names:
            raise SemanticError(f"{expr.loc.format()}: unknown name {expr.value!r} in {current_fn}")
        typ = names[expr.value]
        if isinstance(typ, ArrayType):
            raise SemanticError(f"{expr.loc.format()}: array {expr.value!r} cannot be used as a whole value in v0")
        return typ
    if isinstance(expr, Index):
        if isinstance(expr.array, Name):
            if expr.array.value not in names:
                raise SemanticError(f"{expr.array.loc.format()}: unknown name {expr.array.value!r} in {current_fn}")
            array_type = names[expr.array.value]
        else:
            array_type = validate_expr(expr.array, functions, structs, names, current_fn)
        if not isinstance(array_type, ArrayType):
            raise SemanticError(f"{expr.loc.format()}: indexed read target is not an array in {current_fn}")
        index_type = validate_expr(expr.index, functions, structs, names, current_fn)
        if not same_type(index_type, "i32"):
            raise SemanticError(
                f"{expr.index.loc.format()}: array index expected 'i32', got {format_type(index_type)!r} in {current_fn}"
            )
        return array_type.element_type
    if isinstance(expr, FieldAccess):
        base_type = validate_expr(expr.base, functions, structs, names, current_fn)
        if not is_struct_type(base_type, structs):
            raise SemanticError(f"{expr.loc.format()}: field access on non-struct type {format_type(base_type)!r} in {current_fn}")
        return struct_field(base_type, expr.field, structs, expr.loc).typ
    if isinstance(expr, Binary):
        left_type = validate_expr(expr.left, functions, structs, names, current_fn)
        right_type = validate_expr(expr.right, functions, structs, names, current_fn)
        if expr.op in {"*", "/", "%"} and (left_type != "i32" or right_type != "i32"):
            raise SemanticError(
                f"{expr.loc.format()}: operator {expr.op!r} requires i32 operands, got {format_type(left_type)!r} and {format_type(right_type)!r} in {current_fn}"
            )
        if expr.op in {"+", "-"} and (left_type != "i32" or right_type != "i32"):
            raise SemanticError(
                f"{expr.loc.format()}: operator {expr.op!r} requires i32 operands, got {format_type(left_type)!r} and {format_type(right_type)!r} in {current_fn}"
            )
        if expr.op in {"and", "or"} and (left_type != "bool" or right_type != "bool"):
            raise SemanticError(
                f"{expr.loc.format()}: operator {expr.op!r} requires bool operands, got {format_type(left_type)!r} and {format_type(right_type)!r} in {current_fn}"
            )
        if expr.op in {"==", "!="}:
            if not same_type(left_type, right_type):
                raise SemanticError(
                    f"{expr.loc.format()}: operator {expr.op!r} requires matching types, got {format_type(left_type)!r} and {format_type(right_type)!r} in {current_fn}"
                )
            if is_struct_type(left_type, structs):
                raise SemanticError(f"{expr.loc.format()}: cannot compare struct type {format_type(left_type)!r} in {current_fn}")
        if expr.op in {"<", "<=", ">", ">="}:
            if left_type != "i32" or right_type != "i32":
                raise SemanticError(
                    f"{expr.loc.format()}: operator {expr.op!r} requires i32 operands, got {format_type(left_type)!r} and {format_type(right_type)!r} in {current_fn}"
                )
        if expr.op in {"==", "!=", "<", "<=", ">", ">=", "and", "or"}:
            return "bool"
        return "i32"
    if isinstance(expr, Unary):
        operand_type = validate_expr(expr.operand, functions, structs, names, current_fn)
        if expr.op == "not" and operand_type != "bool":
            raise SemanticError(
                f"{expr.loc.format()}: operator 'not' requires bool operand, got {format_type(operand_type)!r} in {current_fn}"
            )
        if expr.op == "-" and operand_type != "i32":
            raise SemanticError(
                f"{expr.loc.format()}: unary '-' requires i32 operand, got {format_type(operand_type)!r} in {current_fn}"
            )
        return operand_type
    if isinstance(expr, Call):
        if expr.name not in functions:
            raise SemanticError(f"{expr.loc.format()}: unknown function {expr.name!r} in {current_fn}")
        expected = len(functions[expr.name].params)
        if len(expr.args) != expected:
            raise SemanticError(
                f"{expr.loc.format()}: function {expr.name!r} expects {expected} args, got {len(expr.args)} in {current_fn}"
            )
        for arg, param in zip(expr.args, functions[expr.name].params):
            arg_type = validate_expr(arg, functions, structs, names, current_fn)
            if not same_type(arg_type, param.typ):
                raise SemanticError(
                    f"{arg.loc.format()}: function {expr.name!r} argument {param.name!r} expected {format_type(param.typ)!r}, got {format_type(arg_type)!r} in {current_fn}"
                )
        return functions[expr.name].return_type
    raise TypeError(expr)


def validate_lvalue(expr: Expr, functions: dict[str, Function], structs: dict[str, StructDecl], names: dict[str, TypeRef], current_fn: str) -> TypeRef:
    if isinstance(expr, FieldAccess):
        return validate_expr(expr, functions, structs, names, current_fn)
    if isinstance(expr, Index):
        return validate_expr(expr, functions, structs, names, current_fn)
    raise SemanticError(f"{expr.loc.format()}: assignment target is not assignable in {current_fn}")


def c_type(t: TypeRef) -> str:
    if isinstance(t, ArrayType):
        raise SemanticError(f"array type {t.format()!r} is not a scalar C type")
    if t == "i32":
        return "int32_t"
    if t == "bool":
        return "bool"
    return t


def c_decl_type(t: TypeRef) -> str:
    if isinstance(t, ArrayType):
        return c_type(t.element_type)
    return c_type(t)


def emit_expr(expr: Expr) -> str:
    if isinstance(expr, IntLit):
        if expr.value == I32_MIN:
            return "(-2147483647 - 1)"
        return str(expr.value)
    if isinstance(expr, BoolLit):
        return "true" if expr.value else "false"
    if isinstance(expr, Name):
        return expr.value
    if isinstance(expr, Call):
        return f"{expr.name}(" + ", ".join(emit_expr(a) for a in expr.args) + ")"
    if isinstance(expr, Index):
        return f"{emit_expr(expr.array)}[{emit_expr(expr.index)}]"
    if isinstance(expr, FieldAccess):
        return f"{emit_expr(expr.base)}.{expr.field}"
    if isinstance(expr, Binary):
        c_op = expr.op
        if expr.op == "and":
            c_op = "&&"
        elif expr.op == "or":
            c_op = "||"
        return f"({emit_expr(expr.left)} {c_op} {emit_expr(expr.right)})"
    if isinstance(expr, Unary):
        if expr.op == "not":
            return f"(!({emit_expr(expr.operand)}))"
        if expr.op == "-":
            return f"(-{emit_expr(expr.operand)})"
    raise TypeError(expr)


def c_signature(fn: Function) -> str:
    params = ", ".join(f"{c_type(p.typ)} {p.name}" for p in fn.params) or "void"
    return f"{c_type(fn.return_type)} {fn.name}({params})"


def emit_stmt(stmt: Stmt, lines: list[str], indent: int) -> None:
    pad = " " * indent
    if isinstance(stmt, Let):
        if isinstance(stmt.typ, ArrayType):
            lines.append(f"{pad}{c_type(stmt.typ.element_type)} {stmt.name}[{stmt.typ.size}] = {{0}};")
        elif stmt.expr is None:
            lines.append(f"{pad}{c_type(stmt.typ)} {stmt.name} = {{0}};")
        else:
            lines.append(f"{pad}{c_type(stmt.typ)} {stmt.name} = {emit_expr(stmt.expr)};")
    elif isinstance(stmt, Ret):
        lines.append(f"{pad}return {emit_expr(stmt.expr)};")
    elif isinstance(stmt, Assign):
        lines.append(f"{pad}{stmt.name} = {emit_expr(stmt.expr)};")
    elif isinstance(stmt, IndexAssign):
        lines.append(f"{pad}{stmt.array}[{emit_expr(stmt.index)}] = {emit_expr(stmt.expr)};")
    elif isinstance(stmt, ExprAssign):
        lines.append(f"{pad}{emit_expr(stmt.target)} = {emit_expr(stmt.expr)};")
    elif isinstance(stmt, If):
        lines.append(f"{pad}if ({emit_expr(stmt.cond)}) {{")
        for child in stmt.then_body:
            emit_stmt(child, lines, indent + 2)
        for branch in stmt.elifs:
            lines.append(f"{pad}}} else if ({emit_expr(branch.cond)}) {{")
            for child in branch.body:
                emit_stmt(child, lines, indent + 2)
        if stmt.else_body is not None:
            lines.append(f"{pad}}} else {{")
            for child in stmt.else_body:
                emit_stmt(child, lines, indent + 2)
        lines.append(f"{pad}}}")
    elif isinstance(stmt, While):
        lines.append(f"{pad}while ({emit_expr(stmt.cond)}) {{")
        for child in stmt.body:
            emit_stmt(child, lines, indent + 2)
        lines.append(f"{pad}}}")
    else:
        raise TypeError(stmt)


def emit_c(program: Program) -> str:
    lines = ["#include <stdbool.h>", "#include <stdint.h>", ""]
    for struct in program.structs:
        lines.append("typedef struct {")
        for field in struct.fields:
            if isinstance(field.typ, ArrayType):
                lines.append(f"  {c_type(field.typ.element_type)} {field.name}[{field.typ.size}];")
            else:
                lines.append(f"  {c_type(field.typ)} {field.name};")
        lines.append(f"}} {struct.name};")
        lines.append("")
    for fn in program.functions:
        lines.append(f"{c_signature(fn)};")
    lines.append("")
    for fn in program.functions:
        lines.append(f"{c_signature(fn)} {{")
        for stmt in fn.body:
            emit_stmt(stmt, lines, 2)
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def compile_source(src: str) -> str:
    program = parse(src)
    validate(program)
    return emit_c(program)


def compile_text(src: str, output_path: Path | None) -> str | None:
    c_source = compile_source(src)
    if output_path is None:
        return c_source
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(c_source)
    return None


def compile_file(input_path: Path, output_path: Path | None) -> str | None:
    return compile_text(input_path.read_text(), output_path)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="etl0", description="ETL compiler-0")
    subcommands = parser.add_subparsers(dest="command", required=True)

    compile_parser = subcommands.add_parser("compile", help="compile ETL source to C")
    compile_parser.add_argument("input", type=str, help="input .etl source path, or '-' to read from stdin")
    compile_parser.add_argument(
        "-o",
        "--output",
        type=str,
        required=True,
        help="output .c path, or '-' to write generated C to stdout",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    try:
        if args.command == "compile":
            output_path = None if args.output == "-" else Path(args.output)
            source_label = "<stdin>" if args.input == "-" else args.input
            try:
                if args.input == "-":
                    source_text = sys.stdin.read()
                else:
                    source_text = Path(args.input).read_text()
            except OSError as exc:
                print(f"etl0: error: {source_label}: {exc}", file=sys.stderr)
                return 1
            try:
                c_source = compile_text(source_text, output_path)
            except ETLError as exc:
                print(f"etl0: error: {source_label}: {exc}", file=sys.stderr)
                return 1
            if c_source is not None:
                print(c_source, end="")
            return 0
        raise AssertionError(args.command)
    except ETLError as exc:
        print(f"etl0: error: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"etl0: error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
