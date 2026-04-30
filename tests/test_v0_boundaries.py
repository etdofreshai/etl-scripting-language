import unittest

from compiler0.etl0 import ParseError, parse


class V0BoundaryTests(unittest.TestCase):
    def assert_parse_error(self, source: str, text: str) -> None:
        with self.assertRaisesRegex(ParseError, text):
            parse(source)

    def test_reserved_but_unimplemented_statement_keywords_stay_rejected(self):
        cases = [
            ("if 1\n    ret 1\n  end\n  ret 0", "expected statement at 2:3"),
            ("while 1\n    ret 1\n  end\n  ret 0", "expected statement at 2:3"),
            ("type Thing", "expected statement at 2:3"),
            ("use thing", "expected statement at 2:3"),
        ]
        for body, diagnostic in cases:
            with self.subTest(body=body):
                self.assert_parse_error(f"fn main() i32\n  {body}\nend", diagnostic)


if __name__ == "__main__":
    unittest.main()
