// repro.typ — note-class CSL style, citation inside an explicit footnote
#set page(width: 14cm, height: auto)

Auto-noted citation.#cite(<talbert>)

Discursive note containing a citation.#footnote[
  See further #cite(<talbert>, supplement: [127]).
]

#bibliography("works.bib",
  style: "society-of-biblical-literature-fullnote-bibliography.csl")
