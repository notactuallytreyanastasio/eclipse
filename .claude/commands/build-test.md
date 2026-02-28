# Build and Test

Build the project and run the test suite.

## Instructions

1. Compile with warnings-as-errors, then run the full test suite:
   ```bash
   mix compile --warnings-as-errors && mix test
   ```

2. If compilation fails, analyze the errors:
   - Which module failed
   - The specific error (undefined function, type mismatch, syntax error)
   - Suggested fix

3. If tests fail, analyze the failures:
   - Which test failed and in which file
   - What it was testing
   - The assertion that failed (expected vs got)
   - Likely root cause — trace the call chain from test to source
   - Suggested fix (in source code, never in tests)

4. If all tests pass, report success and any warnings from compilation.

5. If the user specifies a specific test file or pattern:
   ```bash
   mix test test/path/to/specific_test.exs
   mix test --only tag_name
   ```

6. For previously failed tests:
   ```bash
   mix test --failed
   ```

$ARGUMENTS
