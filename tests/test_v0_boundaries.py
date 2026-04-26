import unittest

from compiler0.etl0 import ParseError, parse


class V0BoundaryTests(unittest.TestCase):
    def assert_parse_error(self, source: str, text: str) -> None:
        with self.assertRaisesRegex(ParseError, text):
            parse(source)

    def test_unsupported_tokenized_arithmetic_operators_have_explicit_diagnostics(self):
        cases = [
            ("*", r"operator '\*' is not supported in ETL v0 at 1:23"),
            ("/", r"operator '/' is not supported in ETL v0 at 1:23"),
        ]
        for operator, diagnostic in cases:
            with self.subTest(operator=operator):
                self.assert_parse_error(f"fn main() i32 {{ ret 2 {operator} 3 }}", diagnostic)

    def test_reserved_but_unimplemented_statement_keywords_stay_rejected(self):
        cases = [
            ("if 1 { ret 1 } ret 0", "expected statement at 1:17"),
            ("while 1 { ret 1 } ret 0", "expected statement at 1:17"),
            ("type Thing", "expected statement at 1:17"),
            ("use thing", "expected statement at 1:17"),
        ]
        for body, diagnostic in cases:
            with self.subTest(body=body):
                self.assert_parse_error(f"fn main() i32 {{ {body} }}", diagnostic)


if __name__ == "__main__":
    unittest.main()
