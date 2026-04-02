"""
Main test runner for CSL citation tests.

Parametrised tests over (test_case, style, form) combinations.
"""

import pytest
import yaml
from pathlib import Path
from typing import Any, Iterator

from lib.generator import CitationGenerator
from lib.comparator import compare, CompareMode, CompareResult


# Load test data at module level for parametrisation
TESTS_DIR = Path(__file__).parent
STYLES_FILE = TESTS_DIR / 'styles.yaml'
TESTS_FILE = TESTS_DIR / 'citation-tests.yaml'


def load_test_params() -> list[tuple[str, str, str, dict, dict]]:
    """
    Load and generate test parameters.

    Returns list of (test_id, style_id, form, test_case, style_config) tuples.
    """
    with open(STYLES_FILE, encoding='utf-8') as f:
        styles_config = yaml.safe_load(f)

    with open(TESTS_FILE, encoding='utf-8') as f:
        tests_data = yaml.safe_load(f)

    params = []

    for test_case in tests_data.get('tests', []):
        test_id = test_case['id']
        expectations = test_case.get('expectations', {})

        for style_id, style_info in styles_config['styles'].items():
            style_expectations = expectations.get(style_id, {})

            for form in style_info['citation_forms']:
                form_expectation = style_expectations.get(form)

                # Include test even if no expectation (will be skipped)
                params.append((
                    f"{test_id}-{style_id}-{form}",
                    style_id,
                    form,
                    test_case,
                    style_info,
                ))

    return params


# Generate test parameters
TEST_PARAMS = load_test_params()


@pytest.mark.parametrize(
    'param_id,style_id,form,test_case,style_info',
    TEST_PARAMS,
    ids=[p[0] for p in TEST_PARAMS]
)
def test_citation(
    param_id: str,
    style_id: str,
    form: str,
    test_case: dict,
    style_info: dict,
    generators: dict[str, CitationGenerator],
    compare_mode: CompareMode,
):
    """
    Test a single citation form for a specific style.

    This test:
    1. Checks if expectations exist for this style/form combination
    2. Generates the citation using pandoc
    3. Compares against expected output
    """
    # Get the expectation for this style and form
    expectations = test_case.get('expectations', {})
    style_expectations = expectations.get(style_id, {})
    form_expectation = style_expectations.get(form)

    # Skip if no expectation defined
    if not form_expectation:
        pytest.skip(f"No expectation for {style_id}/{form}")

    # Skip if generator not available
    if style_id not in generators:
        pytest.skip(f"Generator not available for style: {style_id}")

    generator = generators[style_id]
    # Allow form-level entry_id override (for cross-entry subsequent notes)
    entry_id = form_expectation.get('entry_id', test_case['entry_id'])
    expected = form_expectation['expected']

    # Skip if expected value is None (not yet populated).
    # An empty string expected: '' is valid — it means the entry should
    # produce no output (e.g. skipbib entries in the bibliography).
    if expected is None:
        pytest.skip(f"No expected value for {style_id}/{form}")
    locator = form_expectation.get('locator')
    first_entry_id = form_expectation.get('first_entry_id')

    # Generate the citation
    try:
        actual = generator.generate_citation(entry_id, form, locator, first_entry_id)
    except Exception as e:
        pytest.fail(f"Failed to generate citation: {e}")

    # Compare
    result = compare(expected, actual, compare_mode)

    if not result.matches:
        # Format a helpful error message
        msg = format_failure_message(
            test_case=test_case,
            style_id=style_id,
            form=form,
            result=result,
        )
        pytest.fail(msg)


def format_failure_message(
    test_case: dict,
    style_id: str,
    form: str,
    result: CompareResult,
) -> str:
    """Format a detailed failure message."""
    lines = [
        f"\nCitation mismatch for {test_case['id']} ({style_id}/{form})",
        f"SBLHS section: {test_case['sblhs_section']}",
        f"Entry ID: {test_case['entry_id']}",
        "",
        "Expected:",
        f"  {result.expected_normalised}",
        "",
        "Actual:",
        f"  {result.actual_normalised}",
        "",
    ]

    if result.diff:
        lines.extend([
            "Diff:",
            result.diff,
        ])

    return '\n'.join(lines)


class TestCitationForms:
    """Group tests by citation form for better organisation."""

    @pytest.mark.parametrize(
        'test_case',
        [
            tc for tc in yaml.safe_load(open(TESTS_FILE))['tests']
            if tc.get('expectations', {}).get('sbl-fullnote', {}).get('first_note')
        ],
        ids=lambda tc: tc['id']
    )
    def test_first_note_form(
        self,
        test_case: dict,
        generators: dict[str, CitationGenerator],
        compare_mode: CompareMode,
    ):
        """Test first note citations specifically."""
        self._run_form_test(test_case, 'sbl-fullnote', 'first_note', generators, compare_mode)

    @pytest.mark.parametrize(
        'test_case',
        [
            tc for tc in yaml.safe_load(open(TESTS_FILE))['tests']
            if tc.get('expectations', {}).get('sbl-fullnote', {}).get('subsequent_note')
        ],
        ids=lambda tc: tc['id']
    )
    def test_subsequent_note_form(
        self,
        test_case: dict,
        generators: dict[str, CitationGenerator],
        compare_mode: CompareMode,
    ):
        """Test subsequent note citations specifically."""
        self._run_form_test(test_case, 'sbl-fullnote', 'subsequent_note', generators, compare_mode)

    @pytest.mark.parametrize(
        'test_case',
        [
            tc for tc in yaml.safe_load(open(TESTS_FILE))['tests']
            if tc.get('expectations', {}).get('sbl-fullnote', {}).get('bibliography')
        ],
        ids=lambda tc: tc['id']
    )
    def test_bibliography_form(
        self,
        test_case: dict,
        generators: dict[str, CitationGenerator],
        compare_mode: CompareMode,
    ):
        """Test bibliography entries specifically."""
        self._run_form_test(test_case, 'sbl-fullnote', 'bibliography', generators, compare_mode)

    def _run_form_test(
        self,
        test_case: dict,
        style_id: str,
        form: str,
        generators: dict[str, CitationGenerator],
        compare_mode: CompareMode,
    ):
        """Run a test for a specific form."""
        expectations = test_case.get('expectations', {})
        style_expectations = expectations.get(style_id, {})
        form_expectation = style_expectations.get(form)

        if not form_expectation:
            pytest.skip(f"No expectation for {style_id}/{form}")

        if style_id not in generators:
            pytest.skip(f"Generator not available for style: {style_id}")

        generator = generators[style_id]
        # Allow form-level entry_id override (for cross-entry subsequent notes)
        entry_id = form_expectation.get('entry_id', test_case['entry_id'])
        expected = form_expectation['expected']

        # Skip if expected value is None (not yet populated).
        # An empty string expected: '' is valid — it means the entry should
        # produce no output (e.g. skipbib entries in the bibliography).
        if expected is None:
            pytest.skip(f"No expected value for {style_id}/{form}")

        locator = form_expectation.get('locator')
        first_entry_id = form_expectation.get('first_entry_id')

        try:
            actual = generator.generate_citation(entry_id, form, locator, first_entry_id)
        except Exception as e:
            pytest.fail(f"Failed to generate citation: {e}")

        result = compare(expected, actual, compare_mode)

        if not result.matches:
            msg = format_failure_message(
                test_case=test_case,
                style_id=style_id,
                form=form,
                result=result,
            )
            pytest.fail(msg)


# Utility function for running individual tests from command line
def run_single_test(test_id: str, style_id: str = 'sbl-fullnote', form: str = 'first_note'):
    """
    Run a single test case programmatically.

    Useful for debugging specific test cases.

    Usage:
        from test_citations import run_single_test
        run_single_test('6.2.1-a-book-by-a-single-author')
    """
    with open(STYLES_FILE, encoding='utf-8') as f:
        styles_config = yaml.safe_load(f)

    with open(TESTS_FILE, encoding='utf-8') as f:
        tests_data = yaml.safe_load(f)

    # Find the test case
    test_case = None
    for tc in tests_data.get('tests', []):
        if tc['id'] == test_id:
            test_case = tc
            break

    if not test_case:
        print(f"Test case not found: {test_id}")
        return

    # Get style config
    style_info = styles_config['styles'].get(style_id)
    if not style_info:
        print(f"Style not found: {style_id}")
        return

    # Create generator
    bib_path = (TESTS_DIR / tests_data['metadata']['bibliography']).resolve()
    csl_path = (TESTS_DIR / style_info['file']).resolve()
    generator = CitationGenerator(bib_path, csl_path)

    # Get expectation
    expectations = test_case.get('expectations', {})
    style_expectations = expectations.get(style_id, {})
    form_expectation = style_expectations.get(form)

    if not form_expectation:
        print(f"No expectation for {style_id}/{form}")
        return

    entry_id = test_case['entry_id']
    expected = form_expectation['expected']
    locator = form_expectation.get('locator')

    print(f"Test: {test_id}")
    print(f"Style: {style_id}")
    print(f"Form: {form}")
    print(f"Entry ID: {entry_id}")
    print(f"Locator: {locator}")
    print()

    try:
        actual = generator.generate_citation(entry_id, form, locator)
        print("Generated:")
        print(f"  {actual}")
        print()
        print("Expected:")
        print(f"  {expected}")
        print()

        result = compare(expected, actual, CompareMode.NORMALISED)
        print(f"Match: {result.matches}")

        if not result.matches and result.diff:
            print()
            print("Diff:")
            print(result.diff)
    except Exception as e:
        print(f"Error: {e}")
