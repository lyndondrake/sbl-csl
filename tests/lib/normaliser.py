"""Output normalisation for citation comparison."""

import re
import unicodedata
from typing import Optional
from dataclasses import dataclass


@dataclass
class NormaliseOptions:
    """Options for text normalisation."""

    whitespace: bool = True  # Collapse multiple spaces, normalise newlines
    dashes: bool = True  # Normalise various dash characters
    quotes: bool = True  # Normalise quotation marks
    unicode: bool = True  # Normalise Unicode characters (NFC)
    case_sensitive: bool = True  # Whether comparison is case-sensitive
    strip_outer_tags: bool = True  # Remove outermost HTML tags
    html_to_markdown: bool = True  # Convert HTML emphasis to markdown


def normalise(text: str, options: Optional[NormaliseOptions] = None) -> str:
    """
    Normalise text for comparison.

    Args:
        text: The text to normalise
        options: Normalisation options (defaults to all enabled)

    Returns:
        Normalised text
    """
    if options is None:
        options = NormaliseOptions()

    result = text

    # Convert HTML emphasis to markdown first (before other normalisation)
    if options.html_to_markdown:
        result = _html_to_markdown(result)

    # Strip outer tags first if requested
    if options.strip_outer_tags:
        result = _strip_outer_tags(result)

    # Decode HTML entities
    result = _decode_html_entities(result)

    # Unicode normalisation (NFC form)
    if options.unicode:
        result = unicodedata.normalize('NFC', result)

    # Normalise spacing around markdown italic markers
    # This handles PDF extraction artifacts
    result = re.sub(r'(\w)\*([A-Z])', r'\1 *\2', result)  # word*Title -> word *Title
    result = re.sub(r'\*\.(\w)', r'*. \1', result)  # *. word (space after period after closing italic)
    result = re.sub(r'\*,(\w)', r'*, \1', result)  # *, word
    result = re.sub(r'\*(\w)', r'* \1', result)  # *word -> * word (after closing italic)
    result = re.sub(r'\*\[', r'* [', result)  # *[ -> * [ (italic before bracket)
    result = re.sub(r'\*§', r'* §', result)  # *§ -> * § (italic before section symbol)
    result = re.sub(r'\*\(', r'* (', result)  # *( -> * ( (italic before paren)
    # Normalise italic-close delimiter: *, and *. both become *
    # (handles CSL comma vs SBL period after italic title)
    result = re.sub(r'\*[.,]\s', r'* ', result)
    # Ensure space after semicolons
    result = re.sub(r';(\w)', r'; \1', result)
    # Ensure space after comma before asterisk
    result = re.sub(r',\*', r', *', result)
    # Ensure space between closing quote and opening italic (both straight and curly quotes)
    result = re.sub(r'["\u201c\u201d]\*', lambda m: m.group(0)[0] + ' *', result)
    # Ensure space after closing paren before word
    result = re.sub(r'\)([A-Za-z])', r') \1', result)
    # Normalise comma-space before locator digits
    result = re.sub(r'\),(\d)', r'), \1', result)

    # Normalise superscript digits to regular digits
    result = result.replace('¹', '1').replace('²', '2').replace('³', '3')

    # Normalise trailing punctuation
    # Strip trailing period for comparison (PDF extraction may truncate it)
    result = result.rstrip()
    result = result.rstrip('.')

    # Whitespace normalisation
    if options.whitespace:
        # Convert non-breaking spaces and tildes to regular space
        result = result.replace('~', ' ')
        result = result.replace('\u00a0', ' ')
        # Convert all whitespace (including newlines) to regular space
        result = re.sub(r'\s+', ' ', result)
        # Strip overall
        result = result.strip()

    # Dash normalisation
    if options.dashes:
        # Em dash variants to standard em dash
        result = result.replace('\u2015', '\u2014')  # Horizontal bar to em dash
        result = result.replace('---', '\u2014')  # Triple hyphen to em dash

        # Normalise en-dashes and hyphens to a single form (hyphen)
        # This handles the page range discrepancy: xi–xxi vs xi-xxi
        result = result.replace('\u2013', '-')  # En dash to hyphen
        result = result.replace('--', '-')  # Double hyphen to hyphen

        # Normalise minus signs
        result = result.replace('\u2212', '-')  # Minus sign to hyphen
        result = result.replace('\u2010', '-')  # Hyphen to hyphen-minus

    # Quote normalisation
    if options.quotes:
        # Double quotes to straight
        result = result.replace('\u201c', '"')  # Left double
        result = result.replace('\u201d', '"')  # Right double
        result = result.replace('\u201e', '"')  # Low double
        result = result.replace('\u201f', '"')  # Reversed double

        # Single quotes to straight
        result = result.replace('\u2018', "'")  # Left single
        result = result.replace('\u2019', "'")  # Right single (also apostrophe)
        result = result.replace('\u201a', "'")  # Low single
        result = result.replace('\u201b', "'")  # Reversed single

        # Guillemets to straight
        result = result.replace('\u00ab', '"')  # Left guillemet
        result = result.replace('\u00bb', '"')  # Right guillemet
        result = result.replace('\u2039', "'")  # Left single guillemet
        result = result.replace('\u203a', "'")  # Right single guillemet

    # Case normalisation
    if not options.case_sensitive:
        result = result.lower()

    return result


def _decode_html_entities(text: str) -> str:
    """Decode common HTML entities."""
    result = text
    result = result.replace('&amp;', '&')
    result = result.replace('&lt;', '<')
    result = result.replace('&gt;', '>')
    result = result.replace('&quot;', '"')
    result = result.replace('&apos;', "'")
    result = result.replace('&nbsp;', ' ')
    # Numeric entities
    result = re.sub(
        r'&#(\d+);',
        lambda m: chr(int(m.group(1))),
        result
    )
    result = re.sub(
        r'&#x([0-9a-fA-F]+);',
        lambda m: chr(int(m.group(1), 16)),
        result
    )
    return result


def _html_to_markdown(text: str) -> str:
    """
    Convert HTML formatting to markdown equivalents.

    Converts:
    - <em>, <i> -> *text*
    - <strong>, <b> -> **text**
    - <span class="nocase"> -> text (removes span)
    """
    result = text

    # Strip <a> tags (keep link text)
    result = re.sub(r'<a\b[^>]*>(.*?)</a>', r'\1', result, flags=re.DOTALL)

    # Convert <em> and <i> to markdown italics
    result = re.sub(r'<em\b[^>]*>(.*?)</em>', r'*\1*', result, flags=re.DOTALL)
    result = re.sub(r'<i\b[^>]*>(.*?)</i>', r'*\1*', result, flags=re.DOTALL)

    # Convert <strong> and <b> to markdown bold
    result = re.sub(r'<strong\b[^>]*>(.*?)</strong>', r'**\1**', result, flags=re.DOTALL)
    result = re.sub(r'<b\b[^>]*>(.*?)</b>', r'**\1**', result, flags=re.DOTALL)

    # Remove span tags (commonly used for nocase)
    result = re.sub(r'<span\b[^>]*>(.*?)</span>', r'\1', result, flags=re.DOTALL)

    # Handle self-closing breaks
    result = re.sub(r'<br\s*/?\s*>', ' ', result)

    return result


def _strip_outer_tags(text: str) -> str:
    """Strip the outermost HTML tag if present."""
    text = text.strip()

    # Match opening and closing tags
    match = re.match(r'^<(\w+)[^>]*>(.*)</\1>$', text, re.DOTALL)
    if match:
        return match.group(2).strip()

    return text


def strip_html_tags(text: str) -> str:
    """
    Remove all HTML tags from text, preserving content.

    Args:
        text: Text potentially containing HTML tags

    Returns:
        Text with all HTML tags removed
    """
    # Remove HTML comments
    result = re.sub(r'<!--.*?-->', '', text, flags=re.DOTALL)

    # Remove HTML tags but keep content
    result = re.sub(r'<[^>]+>', '', result)

    # Decode common HTML entities
    result = result.replace('&amp;', '&')
    result = result.replace('&lt;', '<')
    result = result.replace('&gt;', '>')
    result = result.replace('&quot;', '"')
    result = result.replace('&apos;', "'")
    result = result.replace('&nbsp;', ' ')

    # Decode numeric entities
    result = re.sub(
        r'&#(\d+);',
        lambda m: chr(int(m.group(1))),
        result
    )
    result = re.sub(
        r'&#x([0-9a-fA-F]+);',
        lambda m: chr(int(m.group(1), 16)),
        result
    )

    return result


def normalise_for_semantic_comparison(text: str) -> str:
    """
    Normalise text for semantic comparison (ignoring formatting).

    This strips HTML tags and applies standard normalisation,
    useful for comparing content regardless of markup differences.

    Args:
        text: The text to normalise

    Returns:
        Normalised plain text
    """
    plain = strip_html_tags(text)
    return normalise(plain)
