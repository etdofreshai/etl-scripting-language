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
    Binary,
    BoolLit,
    Call,
    IntLit,
    Let,
    LexerError,
    Name,
    ParseError,
    Ret,
    SemanticError,
    SourceLoc,
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
        kinds = [t.kind for t in lex("fn let if else while ret type use end")]
        self.assertEqual(kinds, ["FN", "LET", "IF", "ELSE", "WHILE", "RET", "TYPE", "USE", "END", "EOF"])

    def test_lex_rejects_non_ascii_identifier_start_for_c_backend(self):
        with self.assertRaisesRegex(LexerError, "unexpected character 'é' at 1:4"):
            lex("fn émain() i32\n  ret 0\nend")

    def test_lex_rejects_non_ascii_identifier_continue_for_c_backend(self):
        with self.assertRaisesRegex(LexerError, "unexpected character 'é' at 1:8"):
            lex("fn cafeé() i32\n  ret 0\nend")

    def test_rejects_keyword_function_name(self):
        with self.assertRaisesRegex(ParseError, "expected IDENT, got IF at 1:4"):
            parse("fn if() i32\n  ret 0\nend")

    def test_rejects_unimplemented_if_statement_as_keyword(self):
        with self.assertRaisesRegex(ParseError, "expected statement at 2:3"):
            parse("fn main() i32\n  if 1\n    ret 1\n  end\n  ret 0\nend")

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

    def test_rejects_unary_minus_before_non_integer(self):
        with self.assertRaisesRegex(ParseError, "expected integer literal after unary '-' at 2:7"):
            parse("fn main() i32\n  ret -x\nend")

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

    def test_if_keyword_still_produces_not_yet_implemented_diagnostic(self):
        with self.assertRaisesRegex(ParseError, "expected statement at 2:3"):
            parse("fn main() i32\n  if true\n    ret 1\n  end\n  ret 0\nend")


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
                    validate_expr(expr, {}, {"left": "u32"}, "main")

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
            "operator '<' requires i32 operands.*'bool' and 'i32'",
        )

    def test_rejects_gt_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let x bool = true\n  let p bool = 1 > x\n  ret 0\nend",
            "operator '>' requires i32 operands.*'i32' and 'bool'",
        )

    def test_rejects_lte_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let p bool = true <= false\n  ret 0\nend",
            "operator '<=' requires i32 operands.*'bool' and 'bool'",
        )

    def test_rejects_gte_with_bool_operand(self):
        self.assert_compile_error(
            "fn main() i32\n  let p bool = true >= false\n  ret 0\nend",
            "operator '>=' requires i32 operands.*'bool' and 'bool'",
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


if __name__ == "__main__":
    unittest.main()
