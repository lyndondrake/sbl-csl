"""Citation generation via pandoc subprocess."""

import subprocess
import tempfile
import re
from pathlib import Path
from typing import Optional
from bs4 import BeautifulSoup


class CitationGenerator:
    """Generates citations using pandoc with various CSL styles."""

    def __init__(self, bibliography: Path, csl_file: Path, lua_filter: Path = None):
        """
        Initialise the generator.

        Args:
            bibliography: Path to the CSL YAML bibliography file
            csl_file: Path to the CSL style file
            lua_filter: Optional path to a Lua filter to run after citeproc
        """
        self.bibliography = bibliography
        self.csl_file = csl_file
        self.lua_filter = lua_filter
        self._xref_cache = None

    def _get_xref_parent(self, entry_id: str) -> Optional[str]:
        """Look up the xref parent for an entry, if any."""
        if self._xref_cache is None:
            self._xref_cache = {}
            import yaml
            with open(self.bibliography) as f:
                data = yaml.safe_load(f)
            for ref in data.get('references', data if isinstance(data, list) else []):
                note = str(ref.get('note', ''))
                if 'xref:' in note:
                    import re as _re
                    m = _re.search(r'xref:\s*(\S+)', note)
                    if m:
                        self._xref_cache[ref['id']] = m.group(1)
        return self._xref_cache.get(entry_id)

    def generate_citation(
        self,
        entry_id: str,
        form: str,
        locator: Optional[str] = None,
        first_entry_id: Optional[str] = None,
    ) -> str:
        """
        Generate a citation in the specified form.

        Args:
            entry_id: The citation key from the bibliography
            form: The citation form (first_note, subsequent_note, bibliography, inline)
            locator: Optional page/volume locator
            first_entry_id: For subsequent_note, optionally cite a different entry first

        Returns:
            The generated citation HTML
        """
        if form == 'first_note':
            return self._generate_first_note(entry_id, locator)
        elif form == 'subsequent_note':
            return self._generate_subsequent_note(entry_id, locator, first_entry_id)
        elif form == 'bibliography':
            return self._generate_bibliography(entry_id)
        elif form == 'inline':
            return self._generate_inline(entry_id, locator)
        else:
            raise ValueError(f'Unknown citation form: {form}')

    def _generate_first_note(self, entry_id: str, locator: Optional[str] = None) -> str:
        """Generate a first-occurrence footnote citation."""
        cite = f'[@{entry_id}'
        if locator:
            cite += f', {locator}'
        cite += ']'

        markdown = f'Text with citation.{cite}\n'
        html = self._run_pandoc(markdown)
        return self._extract_footnote(html, 1)

    def _generate_subsequent_note(
        self, entry_id: str, locator: Optional[str] = None,
        first_entry_id: Optional[str] = None,
    ) -> str:
        """Generate a subsequent-occurrence footnote citation.

        Args:
            entry_id: The citation key for the subsequent (second) citation
            locator: Optional page/volume locator for the subsequent citation
            first_entry_id: Optional different entry for the first citation
                (for cross-entry subsequent notes, e.g. citing a different
                article from the same lexicon)
        """
        # First citation to establish context
        first_id = first_entry_id or entry_id
        first_cite = f'[@{first_id}]'
        second_cite = f'[@{entry_id}'
        if locator:
            second_cite += f', {locator}'
        second_cite += ']'

        markdown = f'First citation.{first_cite}\n\nSecond citation.{second_cite}\n'
        html = self._run_pandoc(markdown)
        return self._extract_footnote(html, 2)

    def _generate_bibliography(self, entry_id: str) -> str:
        """Generate a bibliography entry."""
        cite = f'[@{entry_id}]'
        markdown = f'Text with citation.{cite}\n'
        html = self._run_pandoc(markdown)
        return self._extract_bibliography_entry(html, entry_id)

    def _generate_inline(self, entry_id: str, locator: Optional[str] = None) -> str:
        """Generate an inline (author-date) citation."""
        cite = f'[@{entry_id}'
        if locator:
            cite += f', {locator}'
        cite += ']'

        markdown = f'Text with citation {cite}.\n'
        html = self._run_pandoc(markdown)
        return self._extract_inline_citation(html)

    def _run_pandoc(self, markdown: str) -> str:
        """Run pandoc on the given markdown and return HTML output."""
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='.md', delete=False
        ) as f:
            f.write(markdown)
            input_file = f.name

        try:
            cmd = [
                    'pandoc',
                    '--from=markdown',
                    '--to=html',
                    '--citeproc',
                    f'--bibliography={self.bibliography}',
                    f'--csl={self.csl_file}',
                ]
            if self.lua_filter:
                cmd.append(f'--lua-filter={self.lua_filter}')
            cmd.append(input_file)
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f'Pandoc failed: {e.stderr}') from e
        finally:
            Path(input_file).unlink()

    def _extract_footnote(self, html: str, index: int) -> str:
        """
        Extract the nth footnote content from HTML.

        Args:
            html: The HTML output from pandoc
            index: 1-based index of the footnote to extract

        Returns:
            The footnote content (inner HTML)
        """
        soup = BeautifulSoup(html, 'html.parser')

        # pandoc generates footnotes in a section with class 'footnotes'
        # or as inline footnotes depending on the output format
        footnotes = soup.select('section.footnotes li')

        if not footnotes:
            # Try alternative footnote format
            footnotes = soup.select('.footnote-ref')
            if footnotes:
                # Get the corresponding footnote content
                fn_id = footnotes[index - 1].get('href', '').lstrip('#')
                fn_content = soup.find(id=fn_id)
                if fn_content:
                    return self._clean_footnote_content(fn_content)

        if len(footnotes) >= index:
            return self._clean_footnote_content(footnotes[index - 1])

        # Fallback: look for any footnote-like content
        fn_back = soup.select('a.footnote-back')
        if fn_back:
            parent = fn_back[index - 1].find_parent('li')
            if parent:
                return self._clean_footnote_content(parent)

        raise ValueError(f'Could not find footnote {index} in HTML')

    def _clean_footnote_content(self, element) -> str:
        """Clean up footnote content by removing back-references."""
        # Clone the element to avoid modifying the original
        content = BeautifulSoup(str(element), 'html.parser')

        # Remove footnote back-references
        for back_ref in content.select('a.footnote-back'):
            back_ref.decompose()

        # Get the inner content, removing the outer <li> or <p> if present
        inner = content.find(['p', 'span'])
        if inner:
            return str(inner.decode_contents()).strip()

        return str(content).strip()

    def _extract_bibliography_entry(self, html: str, entry_id: str) -> str:
        """
        Extract a bibliography entry from HTML.

        Args:
            html: The HTML output from pandoc
            entry_id: The citation key to find

        Returns:
            The bibliography entry content
        """
        soup = BeautifulSoup(html, 'html.parser')

        # pandoc generates bibliography in a div with id='refs'
        refs_div = soup.find('div', id='refs')
        if refs_div:
            # Find the entry by its id (usually 'ref-{entry_id}')
            entry = refs_div.find(id=f'ref-{entry_id}')
            if entry:
                return self._clean_bibliography_entry(entry)

            # Fallback: get all entries (for single-citation case)
            entries = refs_div.find_all('div', class_='csl-entry')
            if entries:
                return self._clean_bibliography_entry(entries[0])

        # Entry not found — this is expected for skipbib entries that
        # are suppressed from the bibliography.
        return ''

    def _clean_bibliography_entry(self, element) -> str:
        """Clean up bibliography entry content."""
        # Get the inner content
        content = element.decode_contents() if hasattr(element, 'decode_contents') else str(element)
        return content.strip()

    def _extract_inline_citation(self, html: str) -> str:
        """
        Extract an inline citation from HTML.

        Args:
            html: The HTML output from pandoc

        Returns:
            The inline citation content
        """
        soup = BeautifulSoup(html, 'html.parser')

        # For author-date styles, citations appear in parentheses or as spans
        cite = soup.find('span', class_='citation')
        if cite:
            return str(cite.decode_contents()).strip()

        # Fallback: look for parenthetical citation pattern
        p = soup.find('p')
        if p:
            text = str(p)
            # Match parenthetical citations like (Author 2020, 123)
            match = re.search(r'\([^)]+\d{4}[^)]*\)', text)
            if match:
                return match.group(0)

        raise ValueError('Could not find inline citation in HTML')
