from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

KEYWORDS = {"fn", "let", "ret"}
SINGLE = {"(": "LPAREN", ")": "RPAREN", "{": "LBRACE", "}": "RBRACE", ",": "COMMA", "+": "PLUS", "=": "EQUAL"}


@dataclass(frozen=True)
class Token:
    kind: str
    text: str
    line: int
    col: int


class ETLError(Exception):
    pass


class LexerError(ETLError):
    pass


class ParseError(ETLError):
    pass


@dataclass(frozen=True)
class Program:
    functions: list["Function"]


@dataclass(frozen=True)
class Function:
    name: str
    params: list["Param"]
    return_type: str
    body: list["Stmt"]


@dataclass(frozen=True)
class Param:
    name: str
    typ: str


@dataclass(frozen=True)
class Let:
    name: str
    typ: str
    expr: "Expr"


@dataclass(frozen=True)
class Ret:
    expr: "Expr"


Stmt = Let | Ret


@dataclass(frozen=True)
class IntLit:
    value: int


@dataclass(frozen=True)
class Name:
    value: str


@dataclass(frozen=True)
class Call:
    name: str
    args: list["Expr"]


@dataclass(frozen=True)
class Binary:
    op: str
    left: "Expr"
    right: "Expr"


Expr = IntLit | Name | Call | Binary


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
        if ch.isalpha() or ch == "_":
            start = i
            start_col = col
            while i < len(src) and (src[i].isalnum() or src[i] == "_"):
                i += 1
                col += 1
            text = src[start:i]
            kind = text.upper() if text in KEYWORDS else "IDENT"
            tokens.append(Token(kind, text, line, start_col))
            continue
        raise LexerError(f"unexpected character {ch!r} at {line}:{col}")
    tokens.append(Token("EOF", "", line, col))
    return tokens


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
        funcs = []
        while self.peek().kind != "EOF":
            funcs.append(self.parse_function())
        return Program(funcs)

    def parse_function(self) -> Function:
        self.take("FN")
        name = self.take("IDENT").text
        self.take("LPAREN")
        params: list[Param] = []
        if self.peek().kind != "RPAREN":
            while True:
                pname = self.take("IDENT").text
                ptype = self.take("IDENT").text
                params.append(Param(pname, ptype))
                if self.peek().kind != "COMMA":
                    break
                self.take("COMMA")
        self.take("RPAREN")
        return_type = self.take("IDENT").text
        self.take("LBRACE")
        body: list[Stmt] = []
        while self.peek().kind != "RBRACE":
            body.append(self.parse_stmt())
        self.take("RBRACE")
        return Function(name, params, return_type, body)

    def parse_stmt(self) -> Stmt:
        if self.peek().kind == "LET":
            self.take("LET")
            name = self.take("IDENT").text
            typ = self.take("IDENT").text
            self.take("EQUAL")
            return Let(name, typ, self.parse_expr())
        if self.peek().kind == "RET":
            self.take("RET")
            return Ret(self.parse_expr())
        tok = self.peek()
        raise ParseError(f"expected statement at {tok.line}:{tok.col}")

    def parse_expr(self) -> Expr:
        expr = self.parse_primary()
        while self.peek().kind == "PLUS":
            op = self.take("PLUS").text
            expr = Binary(op, expr, self.parse_primary())
        return expr

    def parse_primary(self) -> Expr:
        tok = self.peek()
        if tok.kind == "INT":
            return IntLit(int(self.take("INT").text))
        if tok.kind == "IDENT":
            name = self.take("IDENT").text
            if self.peek().kind == "LPAREN":
                self.take("LPAREN")
                args: list[Expr] = []
                if self.peek().kind != "RPAREN":
                    while True:
                        args.append(self.parse_expr())
                        if self.peek().kind != "COMMA":
                            break
                        self.take("COMMA")
                self.take("RPAREN")
                return Call(name, args)
            return Name(name)
        raise ParseError(f"expected expression at {tok.line}:{tok.col}")


def parse(src: str) -> Program:
    return Parser(lex(src)).parse_program()


def c_type(t: str) -> str:
    if t == "i32":
        return "int32_t"
    raise ETLError(f"unsupported type {t!r}")


def emit_expr(expr: Expr) -> str:
    if isinstance(expr, IntLit):
        return str(expr.value)
    if isinstance(expr, Name):
        return expr.value
    if isinstance(expr, Call):
        return f"{expr.name}(" + ", ".join(emit_expr(a) for a in expr.args) + ")"
    if isinstance(expr, Binary):
        return f"({emit_expr(expr.left)} {expr.op} {emit_expr(expr.right)})"
    raise TypeError(expr)


def emit_c(program: Program) -> str:
    lines = ["#include <stdint.h>", ""]
    for fn in program.functions:
        params = ", ".join(f"{c_type(p.typ)} {p.name}" for p in fn.params) or "void"
        lines.append(f"{c_type(fn.return_type)} {fn.name}({params}) {{")
        for stmt in fn.body:
            if isinstance(stmt, Let):
                lines.append(f"  {c_type(stmt.typ)} {stmt.name} = {emit_expr(stmt.expr)};")
            elif isinstance(stmt, Ret):
                lines.append(f"  return {emit_expr(stmt.expr)};")
            else:
                raise TypeError(stmt)
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def compile_source(src: str) -> str:
    return emit_c(parse(src))
