import subprocess
import tempfile
import unittest
from pathlib import Path

from compiler0.etl0 import Binary, Call, Let, Ret, compile_source, lex, parse

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

    def test_parse_sample(self):
        program = parse(SAMPLE)
        self.assertEqual([f.name for f in program.functions], ["add", "main"])
        self.assertIsInstance(program.functions[0].body[0], Ret)
        self.assertIsInstance(program.functions[0].body[0].expr, Binary)
        self.assertIsInstance(program.functions[1].body[0], Let)
        self.assertIsInstance(program.functions[1].body[0].expr, Call)

    def test_compile_and_run_sample(self):
        c_source = compile_source(SAMPLE)
        self.assertIn("int32_t add(int32_t a, int32_t b)", c_source)
        self.assertIn("int32_t main(void)", c_source)
        with tempfile.TemporaryDirectory() as td:
            c_path = Path(td) / "out.c"
            exe_path = Path(td) / "out"
            c_path.write_text(c_source)
            subprocess.run(["cc", str(c_path), "-o", str(exe_path)], check=True)
            proc = subprocess.run([str(exe_path)], check=False)
            self.assertEqual(proc.returncode, 5)


if __name__ == "__main__":
    unittest.main()
