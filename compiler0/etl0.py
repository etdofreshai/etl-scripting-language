from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

KEYWORDS = {"fn", "let", "if", "else", "while", "ret", "type", "use"}
SINGLE = {
    "(": "LPAREN",
    ")": "RPAREN",
    "{": "LBRACE",
    "}": "RBRACE",
    ",": "COMMA",
    "+": "PLUS",
    "-": "MINUS",
    "=": "EQUAL",
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
class Program:
    functions: list["Function"]


@dataclass(frozen=True)
class Function:
    name: str
    params: list["Param"]
    return_type: str
    body: list["Stmt"]
    loc: SourceLoc


@dataclass(frozen=True)
class Param:
    name: str
    typ: str
    loc: SourceLoc


@dataclass(frozen=True)
class Let:
    name: str
    typ: str
    expr: "Expr"
    loc: SourceLoc


@dataclass(frozen=True)
class Ret:
    expr: "Expr"
    loc: SourceLoc


Stmt = Let | Ret


@dataclass(frozen=True)
class IntLit:
    value: int
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
class Binary:
    op: str
    left: "Expr"
    right: "Expr"
    loc: SourceLoc


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
        if ch == "/" and i + 1 < len(src) and src[i + 1] == "/":
            while i < len(src) and src[i] != "\n":
                i += 1
                col += 1
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
        fn_tok = self.take("FN")
        name = self.take("IDENT").text
        self.take("LPAREN")
        params: list[Param] = []
        if self.peek().kind != "RPAREN":
            while True:
                param_tok = self.take("IDENT")
                pname = param_tok.text
                ptype = self.take("IDENT").text
                params.append(Param(pname, ptype, SourceLoc.from_token(param_tok)))
                if self.peek().kind != "COMMA":
                    break
                self.take("COMMA")
        self.take("RPAREN")
        return_type = self.take("IDENT").text
        self.take("LBRACE")
        body: list[Stmt] = []
        while self.peek().kind != "RBRACE":
            if self.peek().kind == "EOF":
                raise ParseError(f"unterminated function {name!r}; expected RBRACE before EOF at {self.peek().line}:{self.peek().col}")
            body.append(self.parse_stmt())
        self.take("RBRACE")
        return Function(name, params, return_type, body, SourceLoc.from_token(fn_tok))

    def parse_stmt(self) -> Stmt:
        if self.peek().kind == "LET":
            let_tok = self.take("LET")
            name = self.take("IDENT").text
            typ = self.take("IDENT").text
            self.take("EQUAL")
            return Let(name, typ, self.parse_expr(), SourceLoc.from_token(let_tok))
        if self.peek().kind == "RET":
            ret_tok = self.take("RET")
            return Ret(self.parse_expr(), SourceLoc.from_token(ret_tok))
        tok = self.peek()
        raise ParseError(f"expected statement at {tok.line}:{tok.col}")

    def parse_expr(self) -> Expr:
        expr = self.parse_primary()
        while self.peek().kind in {"PLUS", "MINUS"}:
            op_tok = self.peek()
            self.take(op_tok.kind)
            expr = Binary(op_tok.text, expr, self.parse_primary(), SourceLoc.from_token(op_tok))
        return expr

    def parse_primary(self) -> Expr:
        tok = self.peek()
        if tok.kind == "MINUS":
            minus_tok = self.take("MINUS")
            int_tok = self.peek()
            if int_tok.kind != "INT":
                raise ParseError(f"expected integer literal after unary '-' at {minus_tok.line}:{minus_tok.col}")
            return IntLit(-int(self.take("INT").text), SourceLoc.from_token(minus_tok))
        if tok.kind == "INT":
            return IntLit(int(self.take("INT").text), SourceLoc.from_token(tok))
        if tok.kind == "LPAREN":
            self.take("LPAREN")
            expr = self.parse_expr()
            self.take("RPAREN")
            return expr
        if tok.kind == "IDENT":
            ident_tok = self.take("IDENT")
            name = ident_tok.text
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
                return Call(name, args, SourceLoc.from_token(ident_tok))
            return Name(name, SourceLoc.from_token(ident_tok))
        raise ParseError(f"expected expression at {tok.line}:{tok.col}")


def parse(src: str) -> Program:
    return Parser(lex(src)).parse_program()


SUPPORTED_TYPES = {"i32"}
C_RESERVED_IDENTIFIERS = {
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
}
I32_MIN = -(2**31)
I32_MAX = 2**31 - 1


def validate(program: Program) -> None:
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
    if main_fn.return_type != "i32":
        raise SemanticError(f"{main_fn.loc.format()}: function 'main' must return i32")

    for fn in program.functions:
        validate_type(fn.return_type, f"return type for {fn.name}", fn.loc)
        if not fn.body:
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} must end with ret")
        names: set[str] = set()
        for param in fn.params:
            validate_identifier(param.name, "parameter", param.loc)
            validate_type(param.typ, f"parameter {param.name} in {fn.name}", param.loc)
            if param.name in names:
                raise SemanticError(f"{param.loc.format()}: duplicate local name {param.name!r} in {fn.name}")
            names.add(param.name)
        saw_ret = False
        for stmt in fn.body:
            if saw_ret:
                raise SemanticError(f"{stmt.loc.format()}: unreachable statement after ret in {fn.name}")
            if isinstance(stmt, Let):
                validate_identifier(stmt.name, "local", stmt.loc)
                validate_type(stmt.typ, f"local {stmt.name} in {fn.name}", stmt.loc)
                if stmt.name in names:
                    raise SemanticError(f"{stmt.loc.format()}: duplicate local name {stmt.name!r} in {fn.name}")
                validate_expr(stmt.expr, functions, names, fn.name)
                names.add(stmt.name)
            elif isinstance(stmt, Ret):
                validate_expr(stmt.expr, functions, names, fn.name)
                saw_ret = True
            else:
                raise TypeError(stmt)
        if not saw_ret:
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} must end with ret")


def validate_type(typ: str, where: str, loc: SourceLoc) -> None:
    if typ not in SUPPORTED_TYPES:
        raise SemanticError(f"{loc.format()}: unsupported type {typ!r} in {where}")


def validate_identifier(name: str, where: str, loc: SourceLoc) -> None:
    if name in C_RESERVED_IDENTIFIERS:
        raise SemanticError(f"{loc.format()}: {where} name {name!r} is reserved by the C backend")


def validate_expr(expr: Expr, functions: dict[str, Function], names: set[str], current_fn: str) -> None:
    if isinstance(expr, IntLit):
        if not (I32_MIN <= expr.value <= I32_MAX):
            raise SemanticError(
                f"{expr.loc.format()}: integer literal {expr.value} is outside supported i32 range in {current_fn}"
            )
        return
    if isinstance(expr, Name):
        if expr.value not in names:
            raise SemanticError(f"{expr.loc.format()}: unknown name {expr.value!r} in {current_fn}")
        return
    if isinstance(expr, Binary):
        validate_expr(expr.left, functions, names, current_fn)
        validate_expr(expr.right, functions, names, current_fn)
        return
    if isinstance(expr, Call):
        if expr.name not in functions:
            raise SemanticError(f"{expr.loc.format()}: unknown function {expr.name!r} in {current_fn}")
        expected = len(functions[expr.name].params)
        if len(expr.args) != expected:
            raise SemanticError(
                f"{expr.loc.format()}: function {expr.name!r} expects {expected} args, got {len(expr.args)} in {current_fn}"
            )
        for arg in expr.args:
            validate_expr(arg, functions, names, current_fn)
        return
    raise TypeError(expr)


def c_type(t: str) -> str:
    if t == "i32":
        return "int32_t"
    raise SemanticError(f"unsupported type {t!r}")


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


def c_signature(fn: Function) -> str:
    params = ", ".join(f"{c_type(p.typ)} {p.name}" for p in fn.params) or "void"
    return f"{c_type(fn.return_type)} {fn.name}({params})"


def emit_c(program: Program) -> str:
    lines = ["#include <stdint.h>", ""]
    for fn in program.functions:
        lines.append(f"{c_signature(fn)};")
    lines.append("")
    for fn in program.functions:
        lines.append(f"{c_signature(fn)} {{")
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
    program = parse(src)
    validate(program)
    return emit_c(program)


def compile_file(input_path: Path, output_path: Path | None) -> str | None:
    c_source = compile_source(input_path.read_text())
    if output_path is None:
        return c_source
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(c_source)
    return None


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="etl0", description="ETL compiler-0")
    subcommands = parser.add_subparsers(dest="command", required=True)

    compile_parser = subcommands.add_parser("compile", help="compile ETL source to C")
    compile_parser.add_argument("input", type=Path, help="input .etl source path")
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
            c_source = compile_file(args.input, output_path)
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
