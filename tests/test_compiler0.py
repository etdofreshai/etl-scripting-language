import contextlib
import io
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from compiler0.etl0 import (
    Assign,
    ArrayType,
    Binary,
    BoolLit,
    Call,
    ExprAssign,
    FieldAccess,
    If,
    Index,
    IndexAssign,
    IntLit,
    Let,
    LexerError,
    Name,
    ParseError,
    Ret,
    SemanticError,
    SizeOf,
    SourceLoc,
    StringLit,
    Unary,
    While,
    compile_source,
    lex,
    main,
    parse,
    validate_expr,
)

SAMPLE = """fn add(a i32, b i32) i32
  ret a + b
end

fn main() i32
  let x i32 = add(2, 3)
  ret x
end
"""


class Compiler0Tests(unittest.TestCase):
    def test_lex_sample(self):
        kinds = [t.kind for t in lex(SAMPLE)]
        self.assertEqual(kinds[:5], ["FN", "IDENT", "LPAREN", "IDENT", "IDENT"])
        self.assertEqual(kinds[-1], "EOF")
        self.assertIn("RET", kinds)

    def test_lex_skips_line_comments(self):
        kinds = [t.kind for t in lex("// comment before code\nfn main() i32\n  ret 0\nend // trailing comment\n")]
        self.assertEqual(kinds[:4], ["FN", "IDENT", "LPAREN", "RPAREN"])
        self.assertNotIn("SLASH", kinds)
        self.assertEqual(kinds[-1], "EOF")

    def test_lex_recognizes_all_draft_keywords(self):
        kinds = [t.kind for t in lex("fn let if elif else while ret type use end")]
        self.assertEqual(kinds, ["FN", "LET", "IF", "ELIF", "ELSE", "WHILE", "RET", "TYPE", "USE", "END", "EOF"])

    def test_lex_rejects_non_ascii_identifier_start_for_c_backend(self):
        with self.assertRaisesRegex(LexerError, "unexpected character 'é' at 1:4"):
            lex("fn émain() i32\n  ret 0\nend")

    def test_lex_rejects_non_ascii_identifier_continue_for_c_backend(self):
        with self.assertRaisesRegex(LexerError, "unexpected character 'é' at 1:8"):
            lex("fn cafeé() i32\n  ret 0\nend")

    def test_rejects_keyword_function_name(self):
        with self.assertRaisesRegex(ParseError, "expected IDENT, got IF at 1:4"):
            parse("fn if() i32\n  ret 0\nend")

    def test_compile_sample_with_comments(self):
        c_source = compile_source("""// file comment
fn main() i32
  // body comment
  ret 0 // trailing comment
end
""")
        self.assertIn("int32_t main(void)", c_source)
        self.assertIn("return 0;", c_source)

    def test_parse_sample(self):
        program = parse(SAMPLE)
        self.assertEqual([f.name for f in program.functions], ["add", "main"])
        self.assertIsInstance(program.functions[0].body[0], Ret)
        self.assertIsInstance(program.functions[0].body[0].expr, Binary)
        self.assertIsInstance(program.functions[1].body[0], Let)
        self.assertIsInstance(program.functions[1].body[0].expr, Call)

    def test_parse_parenthesized_expression(self):
        program = parse("fn main() i32\n  ret (1 + 2) + 3\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertIsInstance(expr.left, Binary)

    def test_compile_and_run_parenthesized_expression(self):
        c_source = compile_source("fn main() i32\n  ret (1 + 2) + 3\nend")
        self.assertIn("return ((1 + 2) + 3);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 6)

    def test_compile_and_run_compact_multiple_let_statements(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 2 let y i32 = 3 ret x + y\nend")
        self.assertIn("int32_t x = 2;", c_source)
        self.assertIn("int32_t y = 3;", c_source)
        self.assertIn("return (x + y);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_compile_and_run_subtraction_and_negative_literal(self):
        c_source = compile_source("fn main() i32\n  ret 10 - 3 + -2\nend")
        self.assertIn("return ((10 - 3) + -2);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_unary_minus_on_name_now_compiles(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 5\n  ret -x\nend")
        self.assertIn("return (-x);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 256 - 5)  # -5 mod 256 = 251

    def test_parse_multiplication_binds_tighter_than_addition(self):
        program = parse("fn main() i32\n  ret 1 + 2 * 3\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "+")
        self.assertIsInstance(expr.right, Binary)
        self.assertEqual(expr.right.op, "*")

    def test_parse_subtraction_is_left_associative(self):
        program = parse("fn main() i32\n  ret 10 - 4 - 2\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "-")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "-")
        self.assertEqual(expr.right.value, 2)

    def test_parse_division_is_left_associative(self):
        program = parse("fn main() i32\n  ret 12 / 2 / 3\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "/")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "/")
        self.assertEqual(expr.right.value, 3)

    def test_parse_parentheses_override_multiplicative_precedence(self):
        program = parse("fn main() i32\n  ret (1 + 2) * 3\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "*")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "+")

    def test_lexer_distinguishes_division_from_line_comments(self):
        kinds = [t.kind for t in lex("fn main() i32\n  ret 6 / 3\nend // comment")]
        self.assertIn("SLASH", kinds)
        self.assertEqual(kinds[-1], "EOF")

    def test_lexer_error_reports_line_and_column(self):
        with self.assertRaisesRegex(LexerError, "unexpected character '@' at 2:3"):
            lex("fn main() i32\n  @\nend")

    def test_lexer_rejects_brace_blocks_with_migration_hint(self):
        with self.assertRaisesRegex(LexerError, r"unexpected character '\{' at 1:15; ETL no longer uses braces for blocks, use 'end'"):
            lex("fn main() i32 { ret 0 }")

    def test_parse_error_reports_line_and_column(self):
        with self.assertRaisesRegex(ParseError, "expected statement at 2:3"):
            parse("fn main() i32\n  123\nend")

    def test_parse_error_reports_missing_parameter_comma(self):
        with self.assertRaisesRegex(ParseError, "expected COMMA or RPAREN after parameter, got IDENT at 1:15"):
            parse("fn main(a i32 b i32) i32\n  ret a\nend")

    def test_parse_error_reports_missing_call_argument_comma(self):
        with self.assertRaisesRegex(ParseError, "expected COMMA or RPAREN after argument, got INT at 5:13"):
            parse("fn add(a i32, b i32) i32\n  ret a\nend\nfn main() i32\n  ret add(1 2)\nend")

    def test_parse_error_reports_unterminated_function(self):
        with self.assertRaisesRegex(ParseError, "expected 'end' before EOF in function 'main' at 2:8"):
            parse("fn main() i32\n  ret 0")

    def test_compile_sample_matches_golden_c_fixture(self):
        c_source = compile_source(SAMPLE)
        golden = Path("tests/fixtures/add_main.c").read_text()
        self.assertEqual(c_source, golden)

    def test_compile_and_run_sample(self):
        c_source = compile_source(SAMPLE)
        self.assertIn("int32_t add(int32_t a, int32_t b);", c_source)
        self.assertIn("int32_t main(void);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_compile_and_run_zero_arg_helper_call(self):
        c_source = compile_source("""fn forty_two() i32
  ret 42
end

fn main() i32
  ret forty_two()
end
""")
        self.assertIn("int32_t forty_two(void);", c_source)
        self.assertIn("return forty_two();", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 42)

    def test_compile_and_run_call_inside_binary_expression(self):
        c_source = compile_source("""fn one() i32
  ret 1
end
fn main() i32
  ret one() + 4
end
""")
        self.assertIn("return (one() + 4);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_emits_multiplication_expression(self):
        c_source = compile_source("fn main() i32\n  ret 2 * 3\nend")
        self.assertIn("return (2 * 3);", c_source)

    def test_emits_division_expression(self):
        c_source = compile_source("fn main() i32\n  ret 6 / 3\nend")
        self.assertIn("return (6 / 3);", c_source)

    def test_emits_remainder_expression(self):
        c_source = compile_source("fn main() i32\n  ret 7 % 4\nend")
        self.assertIn("return (7 % 4);", c_source)

    def test_emits_mixed_multiplicative_and_additive_expression(self):
        c_source = compile_source("""fn main() i32
  let a i32 = 1
  let b i32 = 2
  let c i32 = 3
  let d i32 = 8
  let e i32 = 4
  let f i32 = 3
  ret (a + b) * c - d / e % f
end
""")
        self.assertIn("return (((a + b) * c) - ((d / e) % f));", c_source)

    def test_forward_function_call_compiles_cleanly(self):
        c_source = compile_source("""fn main() i32
  ret add(2, 3)
end

fn add(a i32, b i32) i32
  ret a + b
end
""")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_compile_and_run_nested_call_arguments_and_left_associative_subtraction(self):
        c_source = compile_source("""fn dec(x i32) i32
  ret x - 1
end

fn sub(a i32, b i32) i32
  ret a - b
end

fn main() i32
  ret sub(dec(10), dec(3)) - 1
end
""")
        self.assertIn("return (sub(dec(10), dec(3)) - 1);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 6)

    def test_cli_compile_and_run_sample(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "sample.etl"
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            input_path.write_text(SAMPLE)
            self.assertEqual(main(["compile", str(input_path), "-o", str(c_path)]), 0)
            self.assertIn("int32_t main(void)", c_path.read_text())
            subprocess.run(["cc", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_python_module_entrypoint_compiles_sample(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "sample.etl"
            c_path = Path(td) / "out.c"
            input_path.write_text(SAMPLE)
            subprocess.run(
                ["python3", "-m", "compiler0", "compile", str(input_path), "-o", str(c_path)],
                check=True,
            )
            self.assertIn("int32_t main(void)", c_path.read_text())

    def test_cli_creates_output_parent_directories(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "sample.etl"
            c_path = Path(td) / "nested" / "generated" / "out.c"
            input_path.write_text(SAMPLE)
            self.assertEqual(main(["compile", str(input_path), "-o", str(c_path)]), 0)
            self.assertIn("int32_t main(void)", c_path.read_text())

    def test_cli_writes_to_stdout_with_dash_output(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "sample.etl"
            input_path.write_text(SAMPLE)
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["compile", str(input_path), "-o", "-"]), 0)
            c_source = stdout.getvalue()
            self.assertIn("#include <stdint.h>", c_source)
            self.assertIn("int32_t main(void)", c_source)
            self.assertIn("return x;", c_source)

    def test_cli_reads_from_stdin_with_dash_input(self):
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            stdin = io.StringIO(SAMPLE)
            with patch.object(sys, "stdin", stdin):
                self.assertEqual(main(["compile", "-", "-o", str(c_path)]), 0)
            self.assertIn("int32_t main(void)", c_path.read_text())

    def test_cli_reads_from_stdin_and_writes_to_stdout(self):
        stdin = io.StringIO("fn main() i32\n  ret 0\nend")
        stdout = io.StringIO()
        with patch.object(sys, "stdin", stdin), contextlib.redirect_stdout(stdout):
            self.assertEqual(main(["compile", "-", "-o", "-"]), 0)
        self.assertIn("return 0;", stdout.getvalue())

    # --- Phase 1b: bool type and comparison operator tests ---

    def test_lex_true_and_false_keywords(self):
        kinds = [t.kind for t in lex("fn main() i32\n  let x bool = true\n  let y bool = false\n  ret 0\nend")]
        self.assertIn("TRUE", kinds)
        self.assertIn("FALSE", kinds)

    def test_lex_comparison_operators(self):
        kinds = [t.kind for t in lex("== != < <= > >=")]
        self.assertEqual(kinds, ["EQEQ", "NEQ", "LT", "LTE", "GT", "GTE", "EOF"])

    def test_lex_standalone_exclamation_is_error(self):
        with self.assertRaisesRegex(LexerError, "unexpected character '!' at 1:1"):
            lex("! x")

    def test_parse_bool_literal_true(self):
        program = parse("fn main() i32\n  let x bool = true\n  ret 0\nend")
        let_stmt = program.functions[0].body[0]
        self.assertIsInstance(let_stmt.expr, BoolLit)
        self.assertTrue(let_stmt.expr.value)

    def test_parse_bool_literal_false(self):
        program = parse("fn main() i32\n  let x bool = false\n  ret 0\nend")
        let_stmt = program.functions[0].body[0]
        self.assertIsInstance(let_stmt.expr, BoolLit)
        self.assertFalse(let_stmt.expr.value)

    def test_parse_less_than_precedence_below_additive(self):
        program = parse("fn main() i32\n  let p bool = 1 + 2 < 3 + 4\n  ret 0\nend")
        let_stmt = program.functions[0].body[0]
        expr = let_stmt.expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "<")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "+")
        self.assertIsInstance(expr.right, Binary)
        self.assertEqual(expr.right.op, "+")

    def test_parse_greater_than_precedence_below_additive(self):
        program = parse("fn main() i32\n  let p bool = a + b > c + d\n  ret 0\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, ">")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "+")
        self.assertIsInstance(expr.right, Binary)
        self.assertEqual(expr.right.op, "+")

    def test_parse_eq_precedence_below_additive(self):
        program = parse("fn main() i32\n  let p bool = 1 + 2 == 3\n  ret 0\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "==")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "+")

    def test_parse_neq_precedence_below_additive(self):
        program = parse("fn main() i32\n  let p bool = a != b + c\n  ret 0\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "!=")
        self.assertIsInstance(expr.right, Binary)
        self.assertEqual(expr.right.op, "+")

    def test_parse_lte_precedence_below_additive(self):
        program = parse("fn main() i32\n  let p bool = x <= y\n  ret 0\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "<=")

    def test_parse_gte_precedence_below_additive(self):
        program = parse("fn main() i32\n  let p bool = x >= y\n  ret 0\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, ">=")

    def test_parse_comparison_left_associative(self):
        program = parse("fn main() i32\n  let p bool = 1 < 2 < 3\n  ret 0\nend")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "<")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "<")

    def test_emit_bool_type_uses_stdbool(self):
        c_source = compile_source("fn main() i32\n  let x bool = true\n  ret 0\nend")
        self.assertIn("#include <stdbool.h>", c_source)
        self.assertIn("bool x = true;", c_source)

    def test_emit_false_literal(self):
        c_source = compile_source("fn main() i32\n  let x bool = false\n  ret 0\nend")
        self.assertIn("bool x = false;", c_source)

    def test_emit_comparison_operators(self):
        c_source = compile_source("fn main() i32\n  let a bool = 1 < 2\n  let b bool = 1 > 2\n  let c bool = 1 <= 2\n  let d bool = 1 >= 2\n  let e bool = 1 == 2\n  let f bool = 1 != 2\n  ret 0\nend")
        self.assertIn("bool a = (1 < 2);", c_source)
        self.assertIn("bool b = (1 > 2);", c_source)
        self.assertIn("bool c = (1 <= 2);", c_source)
        self.assertIn("bool d = (1 >= 2);", c_source)
        self.assertIn("bool e = (1 == 2);", c_source)
        self.assertIn("bool f = (1 != 2);", c_source)

    def test_emit_bool_function_return(self):
        c_source = compile_source("fn is_true() bool\n  ret true\nend\nfn main() i32\n  ret 0\nend")
        self.assertIn("bool is_true(void);", c_source)
        self.assertIn("return true;", c_source)

    def test_emit_bool_parameter(self):
        c_source = compile_source("fn id(x bool) bool\n  ret x\nend\nfn main() i32\n  ret 0\nend")
        self.assertIn("bool id(bool x);", c_source)

    def test_compile_and_run_comparison_smoke(self):
        c_source = compile_source("fn main() i32\n  let p bool = 5 > 3\n  ret 0\nend")
        self.assertIn("bool p = (5 > 3);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)

    def test_compile_and_run_comparison_returns_correct_bool(self):
        c_source = compile_source("fn is_gt(a i32, b i32) bool\n  ret a > b\nend\nfn main() i32\n  let x bool = is_gt(5, 3)\n  ret 0\nend")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)

    # --- Phase 2a: if/else parser and emitter tests ---

    def test_parse_if_without_else(self):
        program = parse("fn main() i32\n  if true\n    ret 1\n  end\n  ret 0\nend")
        stmt = program.functions[0].body[0]
        self.assertIsInstance(stmt, If)
        self.assertIsInstance(stmt.cond, BoolLit)
        self.assertEqual(len(stmt.then_body), 1)
        self.assertIsNone(stmt.else_body)

    def test_parse_if_with_else(self):
        program = parse("fn main() i32\n  if true\n    ret 1\n  else\n    ret 0\n  end\nend")
        stmt = program.functions[0].body[0]
        self.assertIsInstance(stmt, If)
        self.assertEqual(len(stmt.then_body), 1)
        self.assertEqual(len(stmt.else_body), 1)

    def test_parse_nested_if_else(self):
        program = parse("""fn main() i32
  if true
    if false
      ret 1
    else
      ret 2
    end
  else
    ret 3
  end
end
""")
        outer = program.functions[0].body[0]
        self.assertIsInstance(outer, If)
        inner = outer.then_body[0]
        self.assertIsInstance(inner, If)
        self.assertEqual(len(inner.else_body), 1)

    def test_parse_if_missing_end_reports_clean_error(self):
        with self.assertRaisesRegex(ParseError, "expected 'end' before EOF in if statement"):
            parse("fn main() i32\n  if true\n    ret 1\n")

    def test_parse_else_without_if_reports_clean_error(self):
        with self.assertRaisesRegex(ParseError, "expected statement at 2:3"):
            parse("fn main() i32\n  else\n    ret 1\n  end\nend")

    def test_emit_simple_if(self):
        c_source = compile_source("fn main() i32\n  if true\n    ret 1\n  end\n  ret 0\nend")
        self.assertIn("if (true) {\n    return 1;\n  }\n  return 0;", c_source)
        self.assertNotIn("else {", c_source)

    def test_emit_if_else(self):
        c_source = compile_source("fn main() i32\n  if 2 > 1\n    ret 7\n  else\n    ret 3\n  end\nend")
        self.assertIn("if ((2 > 1)) {\n    return 7;\n  } else {\n    return 3;\n  }", c_source)

    # --- Phase 2b: elif, while, and assignment parser/emitter tests ---

    def test_parse_if_with_one_elif(self):
        program = parse("fn main() i32\n  if false\n    ret 1\n  elif true\n    ret 2\n  else\n    ret 3\n  end\nend")
        stmt = program.functions[0].body[0]
        self.assertIsInstance(stmt, If)
        self.assertEqual(len(stmt.elifs), 1)
        self.assertIsInstance(stmt.elifs[0].cond, BoolLit)

    def test_parse_if_with_two_elifs(self):
        program = parse("fn main() i32\n  if false\n    ret 1\n  elif false\n    ret 2\n  elif true\n    ret 3\n  else\n    ret 4\n  end\nend")
        self.assertEqual(len(program.functions[0].body[0].elifs), 2)

    def test_parse_if_with_three_elifs(self):
        program = parse("fn main() i32\n  if false\n    ret 1\n  elif false\n    ret 2\n  elif false\n    ret 3\n  elif true\n    ret 4\n  else\n    ret 5\n  end\nend")
        self.assertEqual(len(program.functions[0].body[0].elifs), 3)

    def test_parse_elif_after_else_is_error(self):
        with self.assertRaisesRegex(ParseError, "expected statement at 6:3"):
            parse("fn main() i32\n  if true\n    ret 1\n  else\n    ret 2\n  elif false\n    ret 3\n  end\nend")

    def test_parse_while_with_end(self):
        program = parse("fn main() i32\n  let i i32 = 0\n  while i < 3\n    i = i + 1\n  end\n  ret i\nend")
        stmt = program.functions[0].body[1]
        self.assertIsInstance(stmt, While)
        self.assertIsInstance(stmt.body[0], Assign)

    def test_parse_while_missing_end_reports_clean_error(self):
        with self.assertRaisesRegex(ParseError, "expected 'end' before EOF in while statement"):
            parse("fn main() i32\n  while true\n    ret 1\n")

    def test_parse_assignment_to_local(self):
        program = parse("fn main() i32\n  let x i32 = 1\n  x = x + 1\n  ret x\nend")
        stmt = program.functions[0].body[1]
        self.assertIsInstance(stmt, Assign)
        self.assertEqual(stmt.name, "x")

    def test_emit_if_elif_elif_else(self):
        c_source = compile_source("fn main() i32\n  if false\n    ret 1\n  elif 1 < 0\n    ret 2\n  elif true\n    ret 3\n  else\n    ret 4\n  end\nend")
        self.assertIn("if (false) {\n    return 1;\n  } else if ((1 < 0)) {\n    return 2;\n  } else if (true) {\n    return 3;\n  } else {\n    return 4;\n  }", c_source)

    def test_emit_while_body(self):
        c_source = compile_source("fn main() i32\n  let i i32 = 0\n  while i < 3\n    i = i + 1\n  end\n  ret i\nend")
        self.assertIn("while ((i < 3)) {\n    i = (i + 1);\n  }", c_source)

    def test_emit_assignment(self):
        c_source = compile_source("fn bump(x i32) i32\n  x = x + 1\n  ret x\nend\nfn main() i32\n  ret bump(4)\nend")
        self.assertIn("x = (x + 1);", c_source)

    # --- Phase 3a: fixed-size arrays and indexing tests ---

    def test_parse_i32_array_let_without_initializer(self):
        program = parse("fn main() i32\n  let buf i32[16]\n  ret 0\nend")
        stmt = program.functions[0].body[0]
        self.assertIsInstance(stmt, Let)
        self.assertIsInstance(stmt.typ, ArrayType)
        self.assertEqual(stmt.typ.element_type, "i32")
        self.assertEqual(stmt.typ.size, 16)
        self.assertIsNone(stmt.expr)

    def test_parse_bool_array_let_without_initializer(self):
        program = parse("fn main() i32\n  let flags bool[8]\n  ret 0\nend")
        stmt = program.functions[0].body[0]
        self.assertIsInstance(stmt.typ, ArrayType)
        self.assertEqual(stmt.typ.element_type, "bool")
        self.assertEqual(stmt.typ.size, 8)

    def test_parse_rejects_zero_array_size(self):
        with self.assertRaisesRegex(ParseError, "array size must be a positive integer literal"):
            parse("fn main() i32\n  let buf i32[0]\n  ret 0\nend")

    def test_parse_rejects_negative_array_size(self):
        with self.assertRaisesRegex(ParseError, "array size must be a positive integer literal"):
            parse("fn main() i32\n  let buf i32[-1]\n  ret 0\nend")

    def test_parse_rejects_non_literal_array_size(self):
        with self.assertRaisesRegex(ParseError, "expected integer literal array size"):
            parse("fn main() i32\n  let n i32 = 4\n  let buf i32[n]\n  ret 0\nend")

    def test_parse_indexed_read(self):
        program = parse("fn main() i32\n  let buf i32[4]\n  let i i32 = 0\n  ret buf[i]\nend")
        ret = program.functions[0].body[2]
        self.assertIsInstance(ret.expr, Index)

    def test_parse_indexed_write(self):
        program = parse("fn main() i32\n  let buf i32[4]\n  buf[0] = 3\n  ret buf[0]\nend")
        stmt = program.functions[0].body[1]
        self.assertIsInstance(stmt, IndexAssign)
        self.assertEqual(stmt.array, "buf")

    def test_type_allows_i32_index_expression(self):
        c_source = compile_source("fn main() i32\n  let buf i32[4]\n  let i i32 = 0\n  ret buf[i]\nend")
        self.assertIn("return buf[i];", c_source)

    def test_type_rejects_bool_index_expression(self):
        with self.assertRaisesRegex(SemanticError, "array index expected 'i32', got 'bool'"):
            compile_source("fn main() i32\n  let buf i32[4]\n  let b bool = true\n  ret buf[b]\nend")

    def test_type_rejects_wrong_element_assignment_type(self):
        with self.assertRaisesRegex(SemanticError, "indexed assignment.*expected 'i32', got 'bool'"):
            compile_source("fn main() i32\n  let buf i32[4]\n  buf[0] = true\n  ret 0\nend")

    def test_type_rejects_array_as_whole_value(self):
        with self.assertRaisesRegex(SemanticError, "array 'buf' cannot be used as a whole value"):
            compile_source("fn main() i32\n  let buf i32[4]\n  ret buf\nend")

    def test_type_rejects_whole_array_assignment(self):
        with self.assertRaisesRegex(SemanticError, "cannot assign whole array"):
            compile_source("fn main() i32\n  let buf i32[4]\n  buf = 1\n  ret 0\nend")

    def test_type_rejects_array_parameter(self):
        with self.assertRaisesRegex(SemanticError, "parameter 'buf' cannot have array type"):
            compile_source("fn id(buf i32[4]) i32\n  ret 0\nend\nfn main() i32\n  ret id(0)\nend")

    def test_type_rejects_array_return(self):
        with self.assertRaisesRegex(SemanticError, "cannot return array type"):
            compile_source("fn bad() i32[4]\n  ret 0\nend\nfn main() i32\n  ret 0\nend")

    def test_emit_array_declarations_and_indexing(self):
        c_source = compile_source("""fn main() i32
  let buf i32[4]
  let flags bool[2]
  buf[0] = 3
  flags[1] = true
  ret buf[0]
end
""")
        self.assertIn("int32_t buf[4] = {0};", c_source)
        self.assertIn("bool flags[2] = {0};", c_source)
        self.assertIn("buf[0] = 3;", c_source)
        self.assertIn("flags[1] = true;", c_source)
        self.assertIn("return buf[0];", c_source)

    # --- Phase 3b: structs and field access tests ---

    def test_parse_simple_struct_decl(self):
        program = parse("type Token struct\n  kind i32\n  value i32\nend\nfn main() i32\n  ret 0\nend")
        self.assertEqual(program.structs[0].name, "Token")
        self.assertEqual([f.name for f in program.structs[0].fields], ["kind", "value"])

    def test_parse_struct_with_array_field(self):
        program = parse("type Row struct\n  cells i32[4]\nend\nfn main() i32\n  ret 0\nend")
        self.assertIsInstance(program.structs[0].fields[0].typ, ArrayType)

    def test_parse_struct_with_nested_struct_field(self):
        program = parse("type Point struct\n  x i32\nend\ntype Box struct\n  p Point\nend\nfn main() i32\n  ret 0\nend")
        self.assertEqual(program.structs[1].fields[0].typ, "Point")

    def test_parse_rejects_struct_without_end(self):
        with self.assertRaisesRegex(ParseError, "expected 'end' before EOF in struct 'Point'"):
            parse("type Point struct\n  x i32\n")

    def test_parse_field_access_and_assignment(self):
        program = parse("type Point struct\n  x i32\nend\nfn main() i32\n  let p Point\n  p.x = 3\n  ret p.x\nend")
        self.assertIsInstance(program.functions[0].body[1], ExprAssign)
        self.assertIsInstance(program.functions[0].body[2].expr, FieldAccess)

    def test_type_allows_struct_local_field_read_write(self):
        c_source = compile_source("type Point struct\n  x i32\n  y bool\nend\nfn main() i32\n  let p Point\n  p.x = 3\n  p.y = true\n  ret p.x\nend")
        self.assertIn("Point p = {0};", c_source)
        self.assertIn("p.x = 3;", c_source)
        self.assertIn("p.y = true;", c_source)
        self.assertIn("return p.x;", c_source)

    def test_type_allows_array_field_indexing(self):
        c_source = compile_source("type Row struct\n  cells i32[3]\nend\nfn main() i32\n  let r Row\n  r.cells[1] = 7\n  ret r.cells[1]\nend")
        self.assertIn("r.cells[1] = 7;", c_source)
        self.assertIn("return r.cells[1];", c_source)

    def test_type_allows_array_of_struct_field_indexing(self):
        c_source = compile_source("type Point struct\n  x i32\nend\nfn main() i32\n  let pts Point[2]\n  pts[1].x = 9\n  ret pts[1].x\nend")
        self.assertIn("Point pts[2] = {0};", c_source)
        self.assertIn("pts[1].x = 9;", c_source)
        self.assertIn("return pts[1].x;", c_source)

    def test_type_rejects_empty_struct(self):
        with self.assertRaisesRegex(SemanticError, "must have at least one field"):
            compile_source("type Empty struct\nend\nfn main() i32\n  ret 0\nend")

    def test_type_rejects_duplicate_fields(self):
        with self.assertRaisesRegex(SemanticError, "duplicate field 'x'"):
            compile_source("type Point struct\n  x i32\n  x bool\nend\nfn main() i32\n  ret 0\nend")

    def test_type_rejects_duplicate_struct_names(self):
        with self.assertRaisesRegex(SemanticError, "duplicate struct type 'Point'"):
            compile_source("type Point struct\n  x i32\nend\ntype Point struct\n  y i32\nend\nfn main() i32\n  ret 0\nend")

    def test_type_rejects_forward_struct_reference(self):
        with self.assertRaisesRegex(SemanticError, "unsupported type 'Point'"):
            compile_source("type Box struct\n  p Point\nend\ntype Point struct\n  x i32\nend\nfn main() i32\n  ret 0\nend")

    def test_type_rejects_wrong_field_write_type(self):
        with self.assertRaisesRegex(SemanticError, "assignment expected 'i32', got 'bool'"):
            compile_source("type Point struct\n  x i32\nend\nfn main() i32\n  let p Point\n  p.x = true\n  ret 0\nend")

    def test_type_rejects_wrong_field_read_type(self):
        with self.assertRaisesRegex(SemanticError, "let 'x' expected 'bool', got 'i32'"):
            compile_source("type Point struct\n  x i32\nend\nfn main() i32\n  let p Point\n  let x bool = p.x\n  ret 0\nend")

    def test_type_rejects_unknown_field(self):
        with self.assertRaisesRegex(SemanticError, "unknown field 'z' on struct 'Point'"):
            compile_source("type Point struct\n  x i32\nend\nfn main() i32\n  let p Point\n  ret p.z\nend")

    def test_type_rejects_field_access_on_non_struct(self):
        with self.assertRaisesRegex(SemanticError, "field access on non-struct type 'i32'"):
            compile_source("fn main() i32\n  let x i32 = 1\n  ret x.y\nend")

    def test_type_rejects_whole_struct_assignment(self):
        with self.assertRaisesRegex(SemanticError, "cannot assign whole struct"):
            compile_source("type Point struct\n  x i32\nend\nfn main() i32\n  let a Point\n  let b Point\n  a = b\n  ret 0\nend")

    def test_type_rejects_struct_equality(self):
        with self.assertRaisesRegex(SemanticError, "cannot compare struct type 'Point'"):
            compile_source("type Point struct\n  x i32\nend\nfn main() i32\n  let a Point\n  let b Point\n  let same bool = a == b\n  ret 0\nend")

    def test_type_rejects_struct_parameter(self):
        with self.assertRaisesRegex(SemanticError, "parameter 'p' cannot have struct type 'Point'"):
            compile_source("type Point struct\n  x i32\nend\nfn id(p Point) i32\n  ret 0\nend\nfn main() i32\n  ret 0\nend")

    def test_type_rejects_struct_return(self):
        with self.assertRaisesRegex(SemanticError, "function 'make' cannot return struct type 'Point'"):
            compile_source("type Point struct\n  x i32\nend\nfn make() Point\n  ret 0\nend\nfn main() i32\n  ret 0\nend")

    def test_emit_struct_typedef_order_and_fields(self):
        c_source = compile_source("type Point struct\n  x i32\n  flags bool[2]\nend\ntype Box struct\n  p Point\nend\nfn main() i32\n  let b Box\n  ret 0\nend")
        self.assertLess(c_source.index("} Point;"), c_source.index("} Box;"))
        self.assertIn("typedef struct {\n  int32_t x;\n  bool flags[2];\n} Point;", c_source)
        self.assertIn("typedef struct {\n  Point p;\n} Box;", c_source)
        self.assertIn("Box b = {0};", c_source)


class SemanticValidationTests(unittest.TestCase):
    def assert_compile_error(self, source, text):
        from compiler0.etl0 import SemanticError
        with self.assertRaisesRegex(SemanticError, text):
            compile_source(source)

    def test_rejects_duplicate_functions(self):
        self.assert_compile_error("""
fn main() i32
  ret 0
end
fn main() i32
  ret 1
end
""", "duplicate function")

    def test_rejects_main_returning_non_i32(self):
        self.assert_compile_error("fn main() u32\n  ret 0\nend", "function 'main' must return i32")

    def test_rejects_missing_main(self):
        self.assert_compile_error("fn helper() i32\n  ret 0\nend", "program must define function 'main'")

    def test_rejects_main_with_parameters(self):
        self.assert_compile_error("fn main(argc i32) i32\n  ret argc\nend", "function 'main' must not take parameters")

    def test_non_main_unsupported_return_type_still_reports_type(self):
        self.assert_compile_error("fn helper() u32\n  ret 0\nend\nfn main() i32\n  ret 0\nend", "unsupported type")

    def test_rejects_call_arity(self):
        self.assert_compile_error("""
fn add(a i32, b i32) i32
  ret a + b
end
fn main() i32
  ret add(1)
end
""", "expects 2 args")

    def test_rejects_unknown_name(self):
        self.assert_compile_error("fn main() i32\n  ret nope\nend", "unknown name")

    def test_rejects_missing_return(self):
        self.assert_compile_error("fn main() i32\n  let x i32 = 1\nend", "must end with ret")

    def test_rejects_empty_function_body(self):
        self.assert_compile_error("fn main() i32\nend", "must end with ret")

    def test_rejects_let_after_return(self):
        self.assert_compile_error("fn main() i32\n  ret 0\n  let x i32 = 1\nend", "3:3: unreachable statement after ret")

    def test_rejects_second_return(self):
        self.assert_compile_error("fn main() i32\n  ret 0\n  ret 1\nend", "3:3: unreachable statement after ret")

    def test_cli_returns_error_for_bad_source(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "bad.etl"
            c_path = Path(td) / "out.c"
            input_path.write_text("fn main() u32\n  ret 0\nend")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                self.assertEqual(main(["compile", str(input_path), "-o", str(c_path)]), 1)
            self.assertIn(f"etl0: error: {input_path}: 1:1: function 'main' must return i32", stderr.getvalue())
            self.assertFalse(c_path.exists())

    def test_cli_stdin_error_reports_stdin_label(self):
        stdin = io.StringIO("fn main() u32\n  ret 0\nend")
        stderr = io.StringIO()
        with patch.object(sys, "stdin", stdin), contextlib.redirect_stderr(stderr):
            self.assertEqual(main(["compile", "-", "-o", "-"]), 1)
        self.assertIn("etl0: error: <stdin>: 1:1: function 'main' must return i32", stderr.getvalue())

    def test_cli_missing_input_reports_input_label(self):
        missing_path = Path("/tmp/etl0-definitely-missing-input.etl")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(main(["compile", str(missing_path), "-o", "-"]), 1)
        self.assertIn(f"etl0: error: {missing_path}:", stderr.getvalue())
        self.assertIn("No such file", stderr.getvalue())

    def test_cli_failure_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "bad.etl"
            c_path = Path(td) / "out.c"
            input_path.write_text("fn main() u32\n  ret 0\nend")
            c_path.write_text("previous generated C")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                self.assertEqual(main(["compile", str(input_path), "-o", str(c_path)]), 1)
            self.assertEqual(c_path.read_text(), "previous generated C")

    def test_semantic_error_reports_unknown_name_location(self):
        self.assert_compile_error("fn main() i32\n  ret nope\nend", "2:7: unknown name")

    def test_semantic_error_reports_call_location(self):
        self.assert_compile_error("""
fn add(a i32, b i32) i32
  ret a + b
end
fn main() i32
  ret add(1)
end
""", "6:7: function 'add' expects 2 args")

    def test_semantic_error_reports_local_type_location(self):
        self.assert_compile_error("fn main() i32\n  let x u32 = 1\n  ret x\nend", "2:3: unsupported type 'u32'")

    def test_rejects_integer_literals_outside_i32_range(self):
        self.assert_compile_error("fn main() i32\n  ret 2147483648\nend", "2:7: integer literal 2147483648 is outside supported i32 range")

    def test_rejects_multiplicative_operator_with_non_i32_operands(self):
        loc = SourceLoc(1, 1)
        for operator in ("*", "/", "%"):
            expr = Binary(operator, Name("left", loc), IntLit(2, loc), loc)
            with self.subTest(operator=operator):
                with self.assertRaisesRegex(
                    SemanticError,
                    re.escape(f"1:1: operator {operator!r} requires i32 operands, got 'u32' and 'i32'"),
                ):
                    validate_expr(expr, {}, {}, {"left": "u32"}, "main")

    def test_rejects_c_reserved_function_name(self):
        self.assert_compile_error("fn int() i32\n  ret 0\nend", "1:1: function name 'int' is reserved by the C backend")

    def test_rejects_c_reserved_parameter_name(self):
        self.assert_compile_error(
            "fn helper(void i32) i32\n  ret void\nend\nfn main() i32\n  ret 0\nend",
            "1:11: parameter name 'void' is reserved by the C backend",
        )

    def test_rejects_c_reserved_local_name(self):
        self.assert_compile_error("fn main() i32\n  let return i32 = 1\n  ret return\nend", "2:3: local name 'return' is reserved by the C backend")

    def test_rejects_c_reserved_double_underscore_name(self):
        self.assert_compile_error(
            "fn __helper() i32\n  ret 0\nend\nfn main() i32\n  ret 0\nend",
            "1:1: function name '__helper' is reserved by the C backend",
        )

    def test_rejects_c_reserved_underscore_uppercase_name(self):
        self.assert_compile_error(
            "fn main() i32\n  let _Tmp i32 = 1\n  ret _Tmp\nend",
            "2:3: local name '_Tmp' is reserved by the C backend",
        )

    def test_rejects_backend_typedef_function_name(self):
        self.assert_compile_error(
            "fn int32_t() i32\n  ret 0\nend\nfn main() i32\n  ret 0\nend",
            "1:1: function name 'int32_t' is reserved by the C backend",
        )

    def test_rejects_backend_typedef_local_name(self):
        self.assert_compile_error(
            "fn main() i32\n  let uint64_t i32 = 1\n  ret uint64_t\nend",
            "2:3: local name 'uint64_t' is reserved by the C backend",
        )

    def test_accepts_nonreserved_underscore_name(self):
        c_source = compile_source("fn main() i32\n  let _tmp i32 = 1\n  ret _tmp\nend")
        self.assertIn("int32_t _tmp = 1;", c_source)

    def test_rejects_parameter_name_that_conflicts_with_function_name(self):
        self.assert_compile_error(
            "fn helper(helper i32) i32\n  ret helper\nend\nfn main() i32\n  ret helper(1)\nend",
            "1:11: parameter name 'helper' conflicts with function name in helper",
        )

    def test_rejects_local_name_that_conflicts_with_function_name(self):
        self.assert_compile_error(
            "fn helper() i32\n  ret 1\nend\nfn main() i32\n  let helper i32 = 1\n  ret helper\nend",
            "5:3: local name 'helper' conflicts with function name in main",
        )

    def test_accepts_max_i32_literal(self):
        c_source = compile_source("fn main() i32\n  ret 2147483647\nend")
        self.assertIn("return 2147483647;", c_source)

    def test_accepts_min_i32_literal(self):
        c_source = compile_source("fn main() i32\n  ret -2147483648\nend")
        self.assertIn("return (-2147483647 - 1);", c_source)

    def test_compile_and_run_min_i32_literal(self):
        c_source = compile_source("fn main() i32\n  let x i32 = -2147483648 ret x + 2147483647\nend")
        self.assertIn("int32_t x = (-2147483647 - 1);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 255)

    # --- Phase 1b: comparison type-mismatch diagnostic tests ---

    def test_rejects_eq_with_mismatched_types(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  let y bool = true\n  let p bool = x == y\n  ret 0\nend",
            "requires matching types.*'i32' and 'bool'",
        )

    def test_rejects_neq_with_mismatched_types(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  let y bool = true\n  let p bool = x != y\n  ret 0\nend",
            "requires matching types.*'i32' and 'bool'",
        )

    def test_rejects_lt_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let x bool = true\n  let p bool = x < 1\n  ret 0\nend",
            "operator '<' requires i32 or i8 operands.*'bool' and 'i32'",
        )

    def test_rejects_gt_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let x bool = true\n  let p bool = 1 > x\n  ret 0\nend",
            "operator '>' requires i32 or i8 operands.*'i32' and 'bool'",
        )

    def test_rejects_lte_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let p bool = true <= false\n  ret 0\nend",
            "operator '<=' requires i32 or i8 operands.*'bool' and 'bool'",
        )

    def test_rejects_gte_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let p bool = true >= false\n  ret 0\nend",
            "operator '>=' requires i32 or i8 operands.*'bool' and 'bool'",
        )

    def test_accepts_bool_eq_bool(self):
        c_source = compile_source("fn main() i32\n  let a bool = true\n  let b bool = false\n  let p bool = a == b\n  ret 0\nend")
        self.assertIn("bool p = (a == b);", c_source)

    def test_accepts_bool_neq_bool(self):
        c_source = compile_source("fn main() i32\n  let a bool = true\n  let b bool = false\n  let p bool = a != b\n  ret 0\nend")
        self.assertIn("bool p = (a != b);", c_source)

    def test_rejects_additive_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let x bool = true\n  let y i32 = x + 1\n  ret y\nend",
            "operator '\\+' requires i32 operands",
        )

    # --- Phase 1c: logical operators and unary minus tests ---

    def test_lex_and_or_not_keywords(self):
        kinds = [t.kind for t in lex("and or not")]
        self.assertEqual(kinds, ["AND", "OR", "NOT", "EOF"])

    def test_and_or_not_cannot_be_used_as_identifiers(self):
        with self.assertRaisesRegex(ParseError, "expected IDENT, got AND"):
            parse("fn and() i32\n  ret 0\nend")

    def test_or_cannot_be_used_as_identifiers(self):
        with self.assertRaisesRegex(ParseError, "expected IDENT, got OR"):
            parse("fn or() i32\n  ret 0\nend")

    def test_not_cannot_be_used_as_identifiers(self):
        with self.assertRaisesRegex(ParseError, "expected IDENT, got NOT"):
            parse("fn not() i32\n  ret 0\nend")

    # --- Phase 1c: parser precedence tests ---

    def test_parse_or_lower_precedence_than_and(self):
        """a or b and c parses as a or (b and c)"""
        program = parse("fn main() i32\n  let a bool = true\n  let b bool = true\n  let c bool = false\n  let p bool = a or b and c\n  ret 0\nend")
        expr = program.functions[0].body[3].expr  # let p (4th statement: a, b, c, p)
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "or")
        self.assertIsInstance(expr.right, Binary)
        self.assertEqual(expr.right.op, "and")

    def test_parse_and_lower_precedence_than_not(self):
        """not a and b parses as (not a) and b"""
        program = parse("fn main() i32\n  let a bool = true\n  let b bool = false\n  let p bool = not a and b\n  ret 0\nend")
        expr = program.functions[0].body[2].expr  # let p
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "and")
        self.assertIsInstance(expr.left, Unary)
        self.assertEqual(expr.left.op, "not")

    def test_parse_not_lower_precedence_than_comparison(self):
        """not a == b parses as not (a == b), since not has lower precedence than comparisons"""
        program = parse("fn main() i32\n  let a bool = true\n  let b bool = false\n  let p bool = not a == b\n  ret 0\nend")
        expr = program.functions[0].body[2].expr  # let p
        self.assertIsInstance(expr, Unary)
        self.assertEqual(expr.op, "not")
        self.assertIsInstance(expr.operand, Binary)
        self.assertEqual(expr.operand.op, "==")

    def test_parse_unary_minus_binds_tighter_than_multiply(self):
        """-a * b parses as (-a) * b"""
        program = parse("fn main() i32\n  let a i32 = 3\n  let b i32 = 4\n  ret -a * b\nend")
        expr = program.functions[0].body[2].expr  # ret
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "*")
        self.assertIsInstance(expr.left, Unary)
        self.assertEqual(expr.left.op, "-")

    def test_parse_not_right_binding(self):
        """not not x parses as not (not x)"""
        program = parse("fn main() i32\n  let x bool = true\n  let p bool = not not x\n  ret 0\nend")
        expr = program.functions[0].body[1].expr  # let p
        self.assertIsInstance(expr, Unary)
        self.assertEqual(expr.op, "not")
        self.assertIsInstance(expr.operand, Unary)
        self.assertEqual(expr.operand.op, "not")

    def test_parse_or_left_associative(self):
        """a or b or c parses as (a or b) or c"""
        program = parse("fn main() i32\n  let a bool = true\n  let b bool = false\n  let c bool = true\n  let p bool = a or b or c\n  ret 0\nend")
        expr = program.functions[0].body[3].expr  # let p
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "or")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "or")

    def test_parse_and_left_associative(self):
        """a and b and c parses as (a and b) and c"""
        program = parse("fn main() i32\n  let a bool = true\n  let b bool = false\n  let c bool = true\n  let p bool = a and b and c\n  ret 0\nend")
        expr = program.functions[0].body[3].expr  # let p
        self.assertIsInstance(expr, Binary)
        self.assertEqual(expr.op, "and")
        self.assertIsInstance(expr.left, Binary)
        self.assertEqual(expr.left.op, "and")

    # --- Phase 1c: emitter tests ---

    def test_emit_and_operator(self):
        c_source = compile_source("fn main() i32\n  let p bool = true and false\n  ret 0\nend")
        self.assertIn("bool p = (true && false);", c_source)

    def test_emit_or_operator(self):
        c_source = compile_source("fn main() i32\n  let p bool = true or false\n  ret 0\nend")
        self.assertIn("bool p = (true || false);", c_source)

    def test_emit_not_operator(self):
        c_source = compile_source("fn main() i32\n  let p bool = not true\n  ret 0\nend")
        self.assertIn("bool p = (!(true));", c_source)

    def test_emit_unary_minus_on_name(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 5\n  ret -x\nend")
        self.assertIn("return (-x);", c_source)

    def test_emit_unary_minus_on_call(self):
        c_source = compile_source("fn neg(x i32) i32\n  ret x\nend\nfn main() i32\n  ret -neg(3)\nend")
        self.assertIn("return (-neg(3));", c_source)

    def test_emit_unary_minus_on_parenthesized(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 5\n  ret -(x + 1)\nend")
        self.assertIn("return (-(x + 1));", c_source)

    # --- Phase 1c: compile-and-run smoke tests ---

    def test_compile_and_run_and_operator(self):
        c_source = compile_source("fn main() i32\n  let a bool = true\n  let b bool = true\n  let p bool = a and b\n  ret 0\nend")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)

    def test_compile_and_run_or_operator(self):
        c_source = compile_source("fn main() i32\n  let a bool = false\n  let b bool = true\n  let p bool = a or b\n  ret 0\nend")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)

    def test_compile_and_run_not_operator(self):
        c_source = compile_source("fn main() i32\n  let a bool = true\n  let p bool = not a\n  ret 0\nend")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)

    def test_compile_and_run_unary_minus_expression(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 3\n  ret -x\nend")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 256 - 3)  # -3 mod 256 = 253

    def test_compile_and_run_combined_logical(self):
        c_source = compile_source("fn main() i32\n  let a bool = true\n  let b bool = false\n  let c bool = not a or b and a\n  ret 0\nend")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)

    # --- Phase 1c: diagnostic tests ---

    def test_rejects_and_with_i32_operands(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  let y i32 = 2\n  let p bool = x and y\n  ret 0\nend",
            "operator 'and' requires bool operands.*'i32' and 'i32'",
        )

    def test_rejects_or_with_i32_operands(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  let y i32 = 2\n  let p bool = x or y\n  ret 0\nend",
            "operator 'or' requires bool operands.*'i32' and 'i32'",
        )

    def test_rejects_not_on_i32(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  let p bool = not x\n  ret 0\nend",
            "operator 'not' requires bool operand, got 'i32'",
        )

    def test_rejects_unary_minus_on_bool(self):
        self.assert_compile_error(
            "fn main() i32\n  let x bool = true\n  ret -x\nend",
            "unary '-' requires i32 operand, got 'bool'",
        )

    def test_rejects_and_with_mixed_types(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  let p bool = x and true\n  ret 0\nend",
            "operator 'and' requires bool operands.*'i32' and 'bool'",
        )

    def test_negative_literal_still_works(self):
        """Negative integer literals continue to parse as literals."""
        c_source = compile_source("fn main() i32\n  ret -2\nend")
        self.assertIn("return -2;", c_source)

    def test_i32_min_literal_still_works(self):
        """I32_MIN handling does not regress."""
        c_source = compile_source("fn main() i32\n  ret -2147483648\nend")
        self.assertIn("return (-2147483647 - 1);", c_source)

    # --- Phase 2a: if/else semantic tests ---

    def test_rejects_if_condition_i32(self):
        self.assert_compile_error(
            "fn main() i32\n  if 1\n    ret 1\n  end\n  ret 0\nend",
            "if condition expected bool, got 'i32'",
        )

    def test_accepts_if_else_when_both_branches_return(self):
        c_source = compile_source("""fn main() i32
  if true
    ret 1
  else
    ret 0
  end
end
""")
        self.assertIn("return 1;", c_source)
        self.assertIn("return 0;", c_source)

    def test_rejects_final_if_else_when_one_branch_missing_ret(self):
        self.assert_compile_error(
            """fn main() i32
  if true
    ret 1
  else
    let x i32 = 0
  end
end
""",
            "function 'main' must end with ret",
        )

    # --- Phase 2b: elif, while, and assignment semantic tests ---

    def test_rejects_elif_non_bool_condition(self):
        self.assert_compile_error(
            "fn main() i32\n  if true\n    ret 1\n  elif 1\n    ret 2\n  else\n    ret 3\n  end\nend",
            "elif condition expected bool, got 'i32'",
        )

    def test_accepts_while_bool_condition(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 0\n  while x < 1\n    x = x + 1\n  end\n  ret x\nend")
        self.assertIn("while ((x < 1))", c_source)

    def test_rejects_while_non_bool_condition(self):
        self.assert_compile_error(
            "fn main() i32\n  while 1\n    ret 1\n  end\n  ret 0\nend",
            "while condition expected bool, got 'i32'",
        )

    def test_accepts_assignment_to_declared_local(self):
        c_source = compile_source("fn main() i32\n  let x i32 = 1\n  x = 2\n  ret x\nend")
        self.assertIn("x = 2;", c_source)

    def test_accepts_assignment_to_parameter(self):
        c_source = compile_source("fn bump(x i32) i32\n  x = x + 1\n  ret x\nend\nfn main() i32\n  ret bump(1)\nend")
        self.assertIn("x = (x + 1);", c_source)

    def test_rejects_assignment_to_undeclared_local(self):
        self.assert_compile_error(
            "fn main() i32\n  x = 1\n  ret x\nend",
            "assignment to undeclared local 'x'",
        )

    def test_rejects_assignment_type_mismatch(self):
        self.assert_compile_error(
            "fn main() i32\n  let x i32 = 1\n  x = true\n  ret x\nend",
            "assignment to 'x' expected 'i32', got 'bool'",
        )

    def test_if_elif_else_all_branches_return_passes(self):
        c_source = compile_source("fn main() i32\n  if false\n    ret 1\n  elif true\n    ret 2\n  else\n    ret 3\n  end\nend")
        self.assertIn("else if (true)", c_source)

    def test_if_elif_without_else_fails_return_check(self):
        self.assert_compile_error(
            "fn main() i32\n  if false\n    ret 1\n  elif true\n    ret 2\n  end\nend",
            "must end with ret",
        )

    def test_if_elif_without_else_passes_with_trailing_return(self):
        c_source = compile_source("fn main() i32\n  if false\n    ret 1\n  elif true\n    ret 2\n  end\n  ret 3\nend")
        self.assertIn("return 3;", c_source)

    def test_while_never_satisfies_return_check(self):
        self.assert_compile_error(
            "fn main() i32\n  while true\n    ret 1\n  end\nend",
            "must end with ret",
        )


# --- Phase 3c: string literals, i8 primitive, and sizeof ---


class StringLiteralLexerTests(unittest.TestCase):
    def test_lex_simple_string_literal(self):
        toks = lex('"hello"')
        self.assertEqual([t.kind for t in toks], ["STRING", "EOF"])
        self.assertEqual(toks[0].text, "hello")
        self.assertEqual(toks[0].line, 1)
        self.assertEqual(toks[0].col, 1)

    def test_lex_empty_string_literal(self):
        toks = lex('""')
        self.assertEqual(toks[0].kind, "STRING")
        self.assertEqual(toks[0].text, "")

    def test_lex_supported_escape_sequences(self):
        toks = lex(r'"a\nb\tc\\d\"e\0f"')
        self.assertEqual(toks[0].kind, "STRING")
        self.assertEqual(toks[0].text, "a\nb\tc\\d\"e\0f")

    def test_lex_rejects_unrecognized_escape(self):
        with self.assertRaisesRegex(LexerError, r"unrecognized escape sequence '\\q' in string literal at 1:2"):
            lex(r'"\q"')

    def test_lex_rejects_unterminated_string_literal(self):
        with self.assertRaisesRegex(LexerError, "unterminated string literal at 1:1"):
            lex('"hello')

    def test_lex_rejects_raw_newline_in_string_literal(self):
        with self.assertRaisesRegex(LexerError, "unterminated string literal at 1:1"):
            lex('"hi\nthere"')

    def test_lex_string_with_escaped_newline_is_one_line(self):
        toks = lex(r'"line1\nline2"')
        self.assertEqual(toks[0].kind, "STRING")
        self.assertEqual(toks[0].text, "line1\nline2")

    def test_lex_rejects_bare_backslash_at_eol(self):
        with self.assertRaisesRegex(LexerError, "bare backslash at end of line in string literal"):
            lex('"hi\\\nthere"')

    def test_lex_rejects_non_ascii_in_string_literal(self):
        with self.assertRaisesRegex(LexerError, "unsupported character 'é' in string literal"):
            lex('"café"')

    def test_lex_string_among_other_tokens(self):
        kinds = [t.kind for t in lex('let s i8[6] = "hello"')]
        self.assertEqual(kinds, ["LET", "IDENT", "IDENT", "LBRACKET", "INT", "RBRACKET", "EQUAL", "STRING", "EOF"])


class StringLiteralParserTests(unittest.TestCase):
    def test_parse_string_literal_in_let(self):
        program = parse('fn main() i32\n  let s i8[6] = "hello"\n  ret 0\nend')
        let_stmt = program.functions[0].body[0]
        self.assertIsInstance(let_stmt, Let)
        self.assertIsInstance(let_stmt.typ, ArrayType)
        self.assertEqual(let_stmt.typ.element_type, "i8")
        self.assertEqual(let_stmt.typ.size, 6)
        self.assertIsInstance(let_stmt.expr, StringLit)
        self.assertEqual(let_stmt.expr.value, "hello")


class StringLiteralSemanticTests(unittest.TestCase):
    def assert_compile_error(self, source, text):
        with self.assertRaisesRegex(SemanticError, text):
            compile_source(source)

    def test_accepts_matching_length_string_literal(self):
        c_source = compile_source('fn main() i32\n  let s i8[6] = "hello"\n  ret 0\nend')
        self.assertIn('int8_t s[6] = "hello";', c_source)

    def test_accepts_empty_string_literal(self):
        c_source = compile_source('fn main() i32\n  let s i8[1] = ""\n  ret 0\nend')
        self.assertIn('int8_t s[1] = "";', c_source)

    def test_rejects_string_literal_length_mismatch_too_small(self):
        self.assert_compile_error(
            'fn main() i32\n  let s i8[3] = "hello"\n  ret 0\nend',
            "string literal of length 5 requires array size 6, but local 's' declares size 3",
        )

    def test_rejects_string_literal_length_mismatch_too_large(self):
        self.assert_compile_error(
            'fn main() i32\n  let s i8[10] = "hi"\n  ret 0\nend',
            "string literal of length 2 requires array size 3, but local 's' declares size 10",
        )

    def test_rejects_string_literal_to_non_i8_array(self):
        self.assert_compile_error(
            'fn main() i32\n  let s i32[6] = "hello"\n  ret 0\nend',
            "string literal can only initialize i8\\[N\\] arrays",
        )

    def test_rejects_string_literal_in_return(self):
        self.assert_compile_error(
            'fn main() i32\n  ret "hi"\nend',
            "string literal can only initialize an i8\\[N\\] local",
        )

    def test_rejects_string_literal_in_arithmetic(self):
        self.assert_compile_error(
            'fn main() i32\n  let n i32 = "hi" + 1\n  ret 0\nend',
            "string literal can only initialize an i8\\[N\\] local",
        )

    def test_emits_string_literal_with_escapes(self):
        c_source = compile_source('fn main() i32\n  let s i8[5] = "a\\nb\\t"\n  ret 0\nend')
        self.assertIn('int8_t s[5] = "a\\nb\\t";', c_source)

    def test_compile_and_run_string_literal_smoke(self):
        c_source = compile_source('fn main() i32\n  let s i8[6] = "hello"\n  ret 0\nend')
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", "-Wno-unused-variable", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 0)


class I8PrimitiveTests(unittest.TestCase):
    def assert_compile_error(self, source, text):
        with self.assertRaisesRegex(SemanticError, text):
            compile_source(source)

    def test_i8_array_local_zero_initialized(self):
        c_source = compile_source('fn main() i32\n  let buf i8[4]\n  ret 0\nend')
        self.assertIn("int8_t buf[4] = {0};", c_source)

    def test_i8_arithmetic_addition_is_deferred(self):
        self.assert_compile_error(
            'fn main() i32\n  let a i8[1]\n  let b i8[1]\n  let c i8[1]\n  c[0] = a[0] + b[0]\n  ret 0\nend',
            "arithmetic operator '\\+' on i8 is deferred in v0",
        )

    def test_i8_arithmetic_multiplication_is_deferred(self):
        self.assert_compile_error(
            'fn main() i32\n  let a i8[1]\n  let b i8[1]\n  let c i8[1]\n  c[0] = a[0] * b[0]\n  ret 0\nend',
            "arithmetic operator '\\*' on i8 is deferred in v0",
        )

    def test_i8_equality_produces_bool(self):
        c_source = compile_source(
            'fn main() i32\n  let a i8[1]\n  let b i8[1]\n  let p bool = a[0] == b[0]\n  ret 0\nend'
        )
        self.assertIn("bool p = (a[0] == b[0]);", c_source)

    def test_i8_inequality_produces_bool(self):
        c_source = compile_source(
            'fn main() i32\n  let a i8[1]\n  let b i8[1]\n  let p bool = a[0] != b[0]\n  ret 0\nend'
        )
        self.assertIn("bool p = (a[0] != b[0]);", c_source)

    def test_i8_less_than_produces_bool(self):
        c_source = compile_source(
            'fn main() i32\n  let a i8[1]\n  let b i8[1]\n  let p bool = a[0] < b[0]\n  ret 0\nend'
        )
        self.assertIn("bool p = (a[0] < b[0]);", c_source)

    def test_i8_mixed_with_i32_comparison_is_rejected(self):
        self.assert_compile_error(
            'fn main() i32\n  let a i8[1]\n  let p bool = a[0] < 1\n  ret 0\nend',
            "operator '<' requires i32 or i8 operands of matching type, got 'i8' and 'i32'",
        )

    def test_i8_struct_field_emits_int8_t(self):
        c_source = compile_source('type B struct\n  flag i8\nend\nfn main() i32\n  let b B\n  ret 0\nend')
        self.assertIn("int8_t flag;", c_source)


class SizeOfTests(unittest.TestCase):
    def assert_compile_error(self, source, text):
        with self.assertRaisesRegex(SemanticError, text):
            compile_source(source)

    def test_parse_sizeof_primitive(self):
        program = parse('fn main() i32\n  ret sizeof(i32)\nend')
        ret_stmt = program.functions[0].body[0]
        self.assertIsInstance(ret_stmt.expr, SizeOf)
        self.assertEqual(ret_stmt.expr.typ, "i32")

    def test_parse_sizeof_struct(self):
        program = parse('type Token struct\n  k i32\nend\nfn main() i32\n  ret sizeof(Token)\nend')
        ret_stmt = program.functions[0].body[0]
        self.assertIsInstance(ret_stmt.expr, SizeOf)
        self.assertEqual(ret_stmt.expr.typ, "Token")

    def test_parse_sizeof_array_type(self):
        program = parse('fn main() i32\n  ret sizeof(i32[10])\nend')
        ret_stmt = program.functions[0].body[0]
        self.assertIsInstance(ret_stmt.expr, SizeOf)
        self.assertIsInstance(ret_stmt.expr.typ, ArrayType)
        self.assertEqual(ret_stmt.expr.typ.element_type, "i32")
        self.assertEqual(ret_stmt.expr.typ.size, 10)

    def test_emit_sizeof_primitive(self):
        c_source = compile_source('fn main() i32\n  ret sizeof(i32)\nend')
        self.assertIn("return ((int32_t)sizeof(int32_t));", c_source)

    def test_emit_sizeof_bool(self):
        c_source = compile_source('fn main() i32\n  ret sizeof(bool)\nend')
        self.assertIn("return ((int32_t)sizeof(bool));", c_source)

    def test_emit_sizeof_i8(self):
        c_source = compile_source('fn main() i32\n  ret sizeof(i8)\nend')
        self.assertIn("return ((int32_t)sizeof(int8_t));", c_source)

    def test_emit_sizeof_struct(self):
        c_source = compile_source(
            'type Pt struct\n  x i32\n  y i32\nend\nfn main() i32\n  ret sizeof(Pt)\nend'
        )
        self.assertIn("return ((int32_t)sizeof(Pt));", c_source)

    def test_emit_sizeof_array(self):
        c_source = compile_source('fn main() i32\n  ret sizeof(i32[10])\nend')
        self.assertIn("return ((int32_t)sizeof(int32_t[10]));", c_source)

    def test_sizeof_is_i32(self):
        c_source = compile_source(
            'fn main() i32\n  let n i32 = sizeof(i32)\n  ret n\nend'
        )
        self.assertIn("int32_t n = ((int32_t)sizeof(int32_t));", c_source)

    def test_sizeof_unknown_type_fails(self):
        self.assert_compile_error(
            'fn main() i32\n  ret sizeof(Nope)\nend',
            "unsupported type 'Nope'",
        )

    def test_sizeof_value_expression_fails(self):
        with self.assertRaisesRegex(ParseError, "sizeof requires a type, not an expression"):
            parse('fn main() i32\n  let x i32 = 1\n  ret sizeof(x + 1)\nend')

    def test_sizeof_value_name_passes_parser_then_fails_sema(self):
        # `sizeof(x)` parses as type 'x' (parser cannot tell name from type),
        # then sema rejects it because 'x' is not a known type.
        self.assert_compile_error(
            'fn main() i32\n  let x i32 = 1\n  ret sizeof(x)\nend',
            "unsupported type 'x'",
        )

    def test_sizeof_int_literal_fails_in_parser(self):
        with self.assertRaisesRegex(ParseError, "sizeof requires a type name"):
            parse('fn main() i32\n  ret sizeof(123)\nend')

    def test_compile_and_run_sizeof_i32(self):
        c_source = compile_source('fn main() i32\n  ret sizeof(i32)\nend')
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 4)

    def test_compile_and_run_sizeof_struct_two_i32(self):
        c_source = compile_source(
            'type Pt struct\n  x i32\n  y i32\nend\nfn main() i32\n  ret sizeof(Pt)\nend'
        )
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 8)


if __name__ == "__main__":
    unittest.main()
