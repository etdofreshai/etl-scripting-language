from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

KEYWORDS = {"fn", "let", "if", "else", "while", "ret", "type", "use", "end", "true", "false", "and", "or", "not"}
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


@dataclass(frozen=True)
class If:
    cond: "Expr"
    then_body: list["Stmt"]
    else_body: list["Stmt"] | None
    loc: SourceLoc


Stmt = Let | Ret | If


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


Expr = IntLit | BoolLit | Name | Call | Binary | Unary


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
                if self.peek().kind == "COMMA":
                    self.take("COMMA")
                    continue
                if self.peek().kind != "RPAREN":
                    tok = self.peek()
                    raise ParseError(f"expected COMMA or RPAREN after parameter, got {tok.kind} at {tok.line}:{tok.col}")
                break
        self.take("RPAREN")
        return_type = self.take("IDENT").text
        body = self.parse_block({"END"}, f"function {name!r}")
        self.take("END")
        return Function(name, params, return_type, body, SourceLoc.from_token(fn_tok))

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
            typ = self.take("IDENT").text
            self.take("EQUAL")
            return Let(name, typ, self.parse_expr(), SourceLoc.from_token(let_tok))
        if self.peek().kind == "RET":
            ret_tok = self.take("RET")
            return Ret(self.parse_expr(), SourceLoc.from_token(ret_tok))
        if self.peek().kind == "IF":
            if_tok = self.take("IF")
            cond = self.parse_expr()
            then_body = self.parse_block({"ELSE", "END"}, "if statement")
            else_body = None
            if self.peek().kind == "ELSE":
                self.take("ELSE")
                else_body = self.parse_block({"END"}, "else block")
            self.take("END")
            return If(cond, then_body, else_body, SourceLoc.from_token(if_tok))
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
            ident_tok = self.take("IDENT")
            name = ident_tok.text
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
                return Call(name, args, SourceLoc.from_token(ident_tok))
            return Name(name, SourceLoc.from_token(ident_tok))
        raise ParseError(f"expected expression at {tok.line}:{tok.col}")


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
        names: dict[str, str] = {}
        for param in fn.params:
            validate_identifier(param.name, "parameter", param.loc)
            validate_type(param.typ, f"parameter {param.name} in {fn.name}", param.loc)
            if param.name in functions:
                raise SemanticError(
                    f"{param.loc.format()}: parameter name {param.name!r} conflicts with function name in {fn.name}"
                )
            if param.name in names:
                raise SemanticError(f"{param.loc.format()}: duplicate local name {param.name!r} in {fn.name}")
            names[param.name] = param.typ
        validate_stmts(fn.body, functions, names, fn)
        if not body_returns(fn.body):
            raise SemanticError(f"{fn.loc.format()}: function {fn.name!r} must end with ret")


def validate_stmts(
    stmts: list[Stmt],
    functions: dict[str, Function],
    names: dict[str, str],
    fn: Function,
) -> bool:
    saw_return = False
    for stmt in stmts:
        if saw_return:
            raise SemanticError(f"{stmt.loc.format()}: unreachable statement after ret in {fn.name}")
        if isinstance(stmt, Let):
            validate_identifier(stmt.name, "local", stmt.loc)
            validate_type(stmt.typ, f"local {stmt.name} in {fn.name}", stmt.loc)
            if stmt.name in functions:
                raise SemanticError(
                    f"{stmt.loc.format()}: local name {stmt.name!r} conflicts with function name in {fn.name}"
                )
            if stmt.name in names:
                raise SemanticError(f"{stmt.loc.format()}: duplicate local name {stmt.name!r} in {fn.name}")
            validate_expr(stmt.expr, functions, names, fn.name)
            names[stmt.name] = stmt.typ
        elif isinstance(stmt, Ret):
            validate_expr(stmt.expr, functions, names, fn.name)
            saw_return = True
        elif isinstance(stmt, If):
            cond_type = validate_expr(stmt.cond, functions, names, fn.name)
            if cond_type != "bool":
                raise SemanticError(
                    f"{stmt.cond.loc.format()}: if condition expected bool, got {cond_type!r} in {fn.name}"
                )
            then_returns = validate_stmts(stmt.then_body, functions, names.copy(), fn)
            else_returns = False
            if stmt.else_body is not None:
                else_returns = validate_stmts(stmt.else_body, functions, names.copy(), fn)
            saw_return = then_returns and else_returns
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
        return body_returns(last.then_body) and body_returns(last.else_body)
    return False


def validate_type(typ: str, where: str, loc: SourceLoc) -> None:
    if typ not in SUPPORTED_TYPES:
        raise SemanticError(f"{loc.format()}: unsupported type {typ!r} in {where}")


def validate_identifier(name: str, where: str, loc: SourceLoc) -> None:
    if name in C_RESERVED_IDENTIFIERS or is_c_reserved_underscore_identifier(name):
        raise SemanticError(f"{loc.format()}: {where} name {name!r} is reserved by the C backend")


def is_c_reserved_underscore_identifier(name: str) -> bool:
    return name.startswith("__") or (len(name) > 1 and name[0] == "_" and name[1].isupper())


def validate_expr(expr: Expr, functions: dict[str, Function], names: dict[str, str], current_fn: str) -> str:
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
        return names[expr.value]
    if isinstance(expr, Binary):
        left_type = validate_expr(expr.left, functions, names, current_fn)
        right_type = validate_expr(expr.right, functions, names, current_fn)
        if expr.op in {"*", "/", "%"} and (left_type != "i32" or right_type != "i32"):
            raise SemanticError(
                f"{expr.loc.format()}: operator {expr.op!r} requires i32 operands, got {left_type!r} and {right_type!r} in {current_fn}"
            )
        if expr.op in {"+", "-"} and (left_type != "i32" or right_type != "i32"):
            raise SemanticError(
                f"{expr.loc.format()}: operator {expr.op!r} requires i32 operands, got {left_type!r} and {right_type!r} in {current_fn}"
            )
        if expr.op in {"and", "or"} and (left_type != "bool" or right_type != "bool"):
            raise SemanticError(
                f"{expr.loc.format()}: operator {expr.op!r} requires bool operands, got {left_type!r} and {right_type!r} in {current_fn}"
            )
        if expr.op in {"==", "!="}:
            if left_type != right_type:
                raise SemanticError(
                    f"{expr.loc.format()}: operator {expr.op!r} requires matching types, got {left_type!r} and {right_type!r} in {current_fn}"
                )
        if expr.op in {"<", "<=", ">", ">="}:
            if left_type != "i32" or right_type != "i32":
                raise SemanticError(
                    f"{expr.loc.format()}: operator {expr.op!r} requires i32 operands, got {left_type!r} and {right_type!r} in {current_fn}"
                )
        if expr.op in {"==", "!=", "<", "<=", ">", ">=", "and", "or"}:
            return "bool"
        return "i32"
    if isinstance(expr, Unary):
        operand_type = validate_expr(expr.operand, functions, names, current_fn)
        if expr.op == "not" and operand_type != "bool":
            raise SemanticError(
                f"{expr.loc.format()}: operator 'not' requires bool operand, got {operand_type!r} in {current_fn}"
            )
        if expr.op == "-" and operand_type != "i32":
            raise SemanticError(
                f"{expr.loc.format()}: unary '-' requires i32 operand, got {operand_type!r} in {current_fn}"
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
        for arg in expr.args:
            validate_expr(arg, functions, names, current_fn)
        return functions[expr.name].return_type
    raise TypeError(expr)


def c_type(t: str) -> str:
    if t == "i32":
        return "int32_t"
    if t == "bool":
        return "bool"
    raise SemanticError(f"unsupported type {t!r}")


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
        lines.append(f"{pad}{c_type(stmt.typ)} {stmt.name} = {emit_expr(stmt.expr)};")
    elif isinstance(stmt, Ret):
        lines.append(f"{pad}return {emit_expr(stmt.expr)};")
    elif isinstance(stmt, If):
        lines.append(f"{pad}if ({emit_expr(stmt.cond)}) {{")
        for child in stmt.then_body:
            emit_stmt(child, lines, indent + 2)
        if stmt.else_body is None:
            lines.append(f"{pad}}}")
        else:
            lines.append(f"{pad}}} else {{")
            for child in stmt.else_body:
                emit_stmt(child, lines, indent + 2)
            lines.append(f"{pad}}}")
    else:
        raise TypeError(stmt)


def emit_c(program: Program) -> str:
    lines = ["#include <stdbool.h>", "#include <stdint.h>", ""]
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
