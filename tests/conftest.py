"""Pytest configuration and fixtures for CSL citation tests."""

import pytest
import yaml
from pathlib import Path
from typing import Any

from lib.generator import CitationGenerator
from lib.comparator import CompareMode


# Paths relative to tests directory
TESTS_DIR = Path(__file__).parent
PROJECT_DIR = TESTS_DIR.parent
STYLES_FILE = TESTS_DIR / 'styles.yaml'
TESTS_FILE = TESTS_DIR / 'citation-tests.yaml'


@pytest.fixture(scope='session')
def styles_config() -> dict[str, Any]:
    """Load the styles configuration."""
    with open(STYLES_FILE, encoding='utf-8') as f:
        return yaml.safe_load(f)


@pytest.fixture(scope='session')
def test_cases() -> dict[str, Any]:
    """Load the test cases."""
    with open(TESTS_FILE, encoding='utf-8') as f:
        return yaml.safe_load(f)


@pytest.fixture(scope='session')
def bibliography_path(test_cases: dict) -> Path:
    """Get the path to the bibliography file."""
    bib_path = test_cases['metadata']['bibliography']
    return (TESTS_DIR / bib_path).resolve()


@pytest.fixture(scope='session')
def generators(styles_config: dict, bibliography_path: Path) -> dict[str, CitationGenerator]:
    """Create citation generators for each style."""
    gens = {}
    for style_id, style_info in styles_config['styles'].items():
        csl_path = (TESTS_DIR / style_info['file']).resolve()
        lua_filter = None
        if 'lua_filter' in style_info:
            lua_path = (TESTS_DIR / style_info['lua_filter']).resolve()
            if lua_path.exists():
                lua_filter = lua_path
        if csl_path.exists():
            gens[style_id] = CitationGenerator(bibliography_path, csl_path, lua_filter)
    return gens


def pytest_addoption(parser):
    """Add custom command-line options."""
    parser.addoption(
        '--style',
        action='store',
        default=None,
        help='Only run tests for this style (e.g., sbl-fullnote)'
    )
    parser.addoption(
        '--compare-mode',
        action='store',
        default='normalised',
        choices=['exact', 'normalised', 'semantic'],
        help='Comparison mode for tests'
    )


@pytest.fixture(scope='session')
def compare_mode(request) -> CompareMode:
    """Get the comparison mode from command-line options."""
    mode_str = request.config.getoption('--compare-mode')
    return CompareMode(mode_str)


@pytest.fixture(scope='session')
def style_filter(request) -> str | None:
    """Get the style filter from command-line options."""
    return request.config.getoption('--style')


def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        'markers',
        'style(name): mark test to run only for a specific style'
    )
    config.addinivalue_line(
        'markers',
        'form(name): mark test to run only for a specific citation form'
    )
    config.addinivalue_line(
        'markers',
        'sblhs_section(num): mark test with SBLHS section number'
    )


def pytest_collection_modifyitems(config, items):
    """Filter tests based on command-line options."""
    style_filter = config.getoption('--style')

    if style_filter:
        # Skip tests that don't match the style filter
        skip_style = pytest.mark.skip(reason=f'Only running tests for style: {style_filter}')
        for item in items:
            # Check if test has style marker or is parametrised with style
            if hasattr(item, 'callspec') and 'style_id' in item.callspec.params:
                if item.callspec.params['style_id'] != style_filter:
                    item.add_marker(skip_style)


def pytest_report_teststatus(report, config):
    """Customise test status reporting."""
    if report.when == 'call':
        if report.passed:
            return report.outcome, '.', 'PASSED'
        elif report.failed:
            return report.outcome, 'F', 'FAILED'
        elif report.skipped:
            return report.outcome, 's', 'SKIPPED'


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    """Add custom summary at the end of the test run."""
    passed = len(terminalreporter.getreports('passed'))
    failed = len(terminalreporter.getreports('failed'))
    skipped = len(terminalreporter.getreports('skipped'))

    terminalreporter.write_sep('=', 'CSL Citation Test Summary')
    terminalreporter.write_line(f'  Passed:  {passed}')
    terminalreporter.write_line(f'  Failed:  {failed}')
    terminalreporter.write_line(f'  Skipped: {skipped}')
    terminalreporter.write_line(f'  Total:   {passed + failed + skipped}')
