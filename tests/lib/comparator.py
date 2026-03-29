"""Comparison and diff logic for citation testing."""

import difflib
from enum import Enum
from dataclasses import dataclass
from typing import Optional, Tuple

from .normaliser import normalise, normalise_for_semantic_comparison, NormaliseOptions


class CompareMode(Enum):
    """Comparison modes for citation testing."""

    EXACT = 'exact'  # Exact string match (after basic normalisation)
    NORMALISED = 'normalised'  # Normalised comparison (whitespace, dashes, quotes)
    SEMANTIC = 'semantic'  # Content-only comparison (ignores HTML formatting)


@dataclass
class CompareResult:
    """Result of a citation comparison."""

    matches: bool
    expected_normalised: str
    actual_normalised: str
    diff: Optional[str] = None
    mode: CompareMode = CompareMode.NORMALISED


def compare(
    expected: str,
    actual: str,
    mode: CompareMode = CompareMode.NORMALISED,
) -> CompareResult:
    """
    Compare expected and actual citation output.

    Args:
        expected: The expected citation output
        actual: The actual citation output from pandoc
        mode: The comparison mode to use

    Returns:
        CompareResult with match status and normalised texts
    """
    if mode == CompareMode.EXACT:
        # Basic whitespace normalisation only
        options = NormaliseOptions(
            whitespace=True,
            dashes=False,
            quotes=False,
            unicode=True,
        )
        expected_norm = normalise(expected, options)
        actual_norm = normalise(actual, options)
    elif mode == CompareMode.NORMALISED:
        # Full normalisation
        expected_norm = normalise(expected)
        actual_norm = normalise(actual)
    elif mode == CompareMode.SEMANTIC:
        # Semantic comparison (plain text)
        expected_norm = normalise_for_semantic_comparison(expected)
        actual_norm = normalise_for_semantic_comparison(actual)
    else:
        raise ValueError(f'Unknown comparison mode: {mode}')

    matches = expected_norm == actual_norm

    result = CompareResult(
        matches=matches,
        expected_normalised=expected_norm,
        actual_normalised=actual_norm,
        mode=mode,
    )

    if not matches:
        result.diff = format_diff(expected_norm, actual_norm)

    return result


def format_diff(expected: str, actual: str) -> str:
    """
    Generate a human-readable diff between expected and actual.

    Args:
        expected: The expected text
        actual: The actual text

    Returns:
        A formatted diff string
    """
    # For short strings, use inline diff
    if len(expected) < 200 and len(actual) < 200 and '\n' not in expected and '\n' not in actual:
        return _inline_diff(expected, actual)

    # For longer strings, use unified diff
    expected_lines = expected.splitlines(keepends=True)
    actual_lines = actual.splitlines(keepends=True)

    diff = difflib.unified_diff(
        expected_lines,
        actual_lines,
        fromfile='expected',
        tofile='actual',
        lineterm='',
    )

    return ''.join(diff)


def _inline_diff(expected: str, actual: str) -> str:
    """
    Generate an inline diff for short strings.

    Uses character-level diff to highlight differences.
    """
    matcher = difflib.SequenceMatcher(None, expected, actual)
    output = []

    output.append('Expected: ')
    output.append(expected)
    output.append('\n')
    output.append('Actual:   ')
    output.append(actual)
    output.append('\n')
    output.append('Diff:     ')

    # Build a visual diff line
    diff_chars = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'equal':
            diff_chars.append(' ' * (i2 - i1))
        elif tag == 'replace':
            diff_chars.append('^' * max(i2 - i1, j2 - j1))
        elif tag == 'delete':
            diff_chars.append('-' * (i2 - i1))
        elif tag == 'insert':
            diff_chars.append('+' * (j2 - j1))

    output.append(''.join(diff_chars))

    return ''.join(output)


def highlight_differences(expected: str, actual: str) -> Tuple[str, str]:
    """
    Return expected and actual with differences highlighted using ANSI codes.

    Args:
        expected: The expected text
        actual: The actual text

    Returns:
        Tuple of (highlighted_expected, highlighted_actual)
    """
    # ANSI codes
    RED = '\033[91m'
    GREEN = '\033[92m'
    RESET = '\033[0m'

    matcher = difflib.SequenceMatcher(None, expected, actual)

    expected_highlighted = []
    actual_highlighted = []

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'equal':
            expected_highlighted.append(expected[i1:i2])
            actual_highlighted.append(actual[j1:j2])
        elif tag == 'replace':
            expected_highlighted.append(f'{RED}{expected[i1:i2]}{RESET}')
            actual_highlighted.append(f'{GREEN}{actual[j1:j2]}{RESET}')
        elif tag == 'delete':
            expected_highlighted.append(f'{RED}{expected[i1:i2]}{RESET}')
        elif tag == 'insert':
            actual_highlighted.append(f'{GREEN}{actual[j1:j2]}{RESET}')

    return ''.join(expected_highlighted), ''.join(actual_highlighted)


def similarity_ratio(expected: str, actual: str) -> float:
    """
    Calculate the similarity ratio between two strings.

    Args:
        expected: The expected text
        actual: The actual text

    Returns:
        A float between 0 and 1 indicating similarity (1 = identical)
    """
    matcher = difflib.SequenceMatcher(None, expected, actual)
    return matcher.ratio()
