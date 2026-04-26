import subprocess
import tempfile
import unittest
from pathlib import Path

from compiler0.etl0 import Binary, Call, Let, LexerError, ParseError, Ret, compile_source, lex, main, parse

SAMPLE = """fn add(a i32, b i32) i32 {
  ret a + b
}

fn main() i32 {
  let x i32 = add(2, 3)
  ret x
}
"""


class Compiler0Tests(unittest.TestCase):
    def test_lex_sample(self):
        kinds = [t.kind for t in lex(SAMPLE)]
        self.assertEqual(kinds[:5], ["FN", "IDENT", "LPAREN", "IDENT", "IDENT"])
        self.assertEqual(kinds[-1], "EOF")
        self.assertIn("RET", kinds)

    def test_lex_skips_line_comments(self):
        kinds = [t.kind for t in lex("// comment before code\nfn main() i32 { ret 0 } // trailing comment\n")]
        self.assertEqual(kinds[:4], ["FN", "IDENT", "LPAREN", "RPAREN"])
        self.assertNotIn("SLASH", kinds)
        self.assertEqual(kinds[-1], "EOF")

    def test_compile_sample_with_comments(self):
        c_source = compile_source("""// file comment
fn main() i32 {
  // body comment
  ret 0 // trailing comment
}
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
        program = parse("fn main() i32 { ret (1 + 2) + 3 }")
        expr = program.functions[0].body[0].expr
        self.assertIsInstance(expr, Binary)
        self.assertIsInstance(expr.left, Binary)

    def test_compile_and_run_parenthesized_expression(self):
        c_source = compile_source("fn main() i32 { ret (1 + 2) + 3 }")
        self.assertIn("return ((1 + 2) + 3);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 6)

    def test_compile_and_run_subtraction_and_negative_literal(self):
        c_source = compile_source("fn main() i32 { ret 10 - 3 + -2 }")
        self.assertIn("return ((10 - 3) + -2);", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

    def test_rejects_unary_minus_before_non_integer(self):
        with self.assertRaisesRegex(ParseError, "expected integer literal after unary '-' at 1:21"):
            parse("fn main() i32 { ret -x }")

    def test_lexer_error_reports_line_and_column(self):
        with self.assertRaisesRegex(LexerError, "unexpected character '@' at 2:3"):
            lex("fn main() i32 {\n  @\n}")

    def test_parse_error_reports_line_and_column(self):
        with self.assertRaisesRegex(ParseError, "expected statement at 2:3"):
            parse("fn main() i32 {\n  123\n}")

    def test_parse_error_reports_expected_token(self):
        with self.assertRaisesRegex(ParseError, "expected RPAREN, got IDENT at 1:15"):
            parse("fn main(a i32 b i32) i32 { ret a }")

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

    def test_forward_function_call_compiles_cleanly(self):
        c_source = compile_source("""fn main() i32 {
  ret add(2, 3)
}

fn add(a i32, b i32) i32 {
  ret a + b
}
""")
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", "-Wall", "-Werror", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)

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



class SemanticValidationTests(unittest.TestCase):
    def assert_compile_error(self, source, text):
        from compiler0.etl0 import SemanticError
        with self.assertRaisesRegex(SemanticError, text):
            compile_source(source)

    def test_rejects_duplicate_functions(self):
        self.assert_compile_error("""
fn main() i32 { ret 0 }
fn main() i32 { ret 1 }
""", "duplicate function")

    def test_rejects_unsupported_type(self):
        self.assert_compile_error("fn main() u32 { ret 0 }", "unsupported type")

    def test_rejects_call_arity(self):
        self.assert_compile_error("""
fn add(a i32, b i32) i32 { ret a + b }
fn main() i32 { ret add(1) }
""", "expects 2 args")

    def test_rejects_unknown_name(self):
        self.assert_compile_error("fn main() i32 { ret nope }", "unknown name")

    def test_rejects_missing_return(self):
        self.assert_compile_error("fn main() i32 { let x i32 = 1 }", "must end with ret")

    def test_rejects_empty_function_body(self):
        self.assert_compile_error("fn main() i32 { }", "must end with ret")

    def test_rejects_let_after_return(self):
        self.assert_compile_error("fn main() i32 {\n  ret 0\n  let x i32 = 1\n}", "3:3: unreachable statement after ret")

    def test_rejects_second_return(self):
        self.assert_compile_error("fn main() i32 {\n  ret 0\n  ret 1\n}", "3:3: unreachable statement after ret")

    def test_cli_returns_error_for_bad_source(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "bad.etl"
            c_path = Path(td) / "out.c"
            input_path.write_text("fn main() u32 { ret 0 }")
            self.assertEqual(main(["compile", str(input_path), "-o", str(c_path)]), 1)
            self.assertFalse(c_path.exists())

    def test_semantic_error_reports_unknown_name_location(self):
        self.assert_compile_error("fn main() i32 {\n  ret nope\n}", "2:7: unknown name")

    def test_semantic_error_reports_call_location(self):
        self.assert_compile_error("""
fn add(a i32, b i32) i32 { ret a + b }
fn main() i32 {
  ret add(1)
}
""", "4:7: function 'add' expects 2 args")

    def test_semantic_error_reports_local_type_location(self):
        self.assert_compile_error("fn main() i32 {\n  let x u32 = 1\n  ret x\n}", "2:3: unsupported type 'u32'")

    def test_rejects_integer_literals_outside_i32_range(self):
        self.assert_compile_error("fn main() i32 {\n  ret 2147483648\n}", "2:7: integer literal 2147483648 is outside supported i32 range")

    def test_rejects_c_reserved_function_name(self):
        self.assert_compile_error("fn int() i32 { ret 0 }", "1:1: function name 'int' is reserved by the C backend")

    def test_rejects_c_reserved_parameter_name(self):
        self.assert_compile_error("fn main(void i32) i32 { ret void }", "1:9: parameter name 'void' is reserved by the C backend")

    def test_rejects_c_reserved_local_name(self):
        self.assert_compile_error("fn main() i32 {\n  let return i32 = 1\n  ret return\n}", "2:3: local name 'return' is reserved by the C backend")

    def test_accepts_max_i32_literal(self):
        c_source = compile_source("fn main() i32 { ret 2147483647 }")
        self.assertIn("return 2147483647;", c_source)

    def test_accepts_min_i32_literal(self):
        c_source = compile_source("fn main() i32 { ret -2147483648 }")
        self.assertIn("return -2147483648;", c_source)


if __name__ == "__main__":
    unittest.main()
