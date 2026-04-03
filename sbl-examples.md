---
title: "SBL Citation Examples for Pandoc/Citeproc"
author: "Adapted from biblatex-sbl-examples.tex"
date: 2026-03-27
bibliography: sbl-examples.yaml
csl: society-of-biblical-literature-fullnote-bibliography.csl
reference-section-title: "Bibliography"
nocite: |
  @TDNT, @NIDNTT, @TLNT, @IDB, @DOTP, @josephus, @tacitus,
  @hunt+edgar:1932, @betz:1996, @malherbe:1977, @ANF, @NPNF1,
  @PG, @PL, @Str-B, @ANRW, @dahood:1965-1970, @NIB,
  @COS, @ANET, @AEL, @ABC, @RIMA,
  @ARM1, @ARMT1, @gerhardsson:1961, @hoffner:1990,
  @plutarch:moralia5, @philo:cherubim,
  @series-ABC
---

# Introduction

This document mirrors all the examples from the `biblatex-sbl` package (SBLHS 2nd edition, sections 6.2–6.4 and 7.1–7.3), adapted for pandoc Markdown with citeproc. It serves as both a demonstration and a test document for the SBL citation system.

Each section corresponds to a subsection in the biblatex-sbl-examples.tex file. Examples show first-note citations (full form), subsequent-note citations (short form), and parenthetical citations where applicable. The bibliography is generated automatically by citeproc.

To render this document:

```bash
pandoc sbl-examples.md \
  --citeproc \
  --lua-filter=sbl-filter.lua \
  -o output.html
```

Without the Lua filter, the CSL produces sensible output for all standard entry types. The filter adds shorthand handling, bibliography control, abbreviation list generation, and subsequent note refinements.

# Abbreviations {#sbl-abbreviations}

# Notes and Bibliographies

## General Examples: Books

### A Book by a Single Author

The simplest case: author, title (italic), place, publisher, date, and page locator.

First note: [@talbert:1992, 127]

Subsequent: [@talbert:1992, 22]

### A Book by Two or Three Authors

All authors are listed in notes; bibliography inverts the first author's name.

First note: [@robinson+koester:1971, 237]

Subsequent: [@robinson+koester:1971, 23]

### A Book by More than Three Authors

More than three authors triggers "et al." in notes; bibliography lists all authors.

First note: [@scott+etal:1993, 53]

Subsequent: [@scott+etal:1993, 42]

### A Translated Volume

Translator appears after the title in notes ("trans.") and as a separate sentence in bibliography ("Translated by").

First note: [@egger:1996, 28]

Subsequent: [@egger:1996, 291]

### The Full History of a Translated Volume

Complex chain: reprint of a translation of a German original. CSL handles the current edition with reprint info appended.

First note: [@wellhausen:1957, 296]

### A Book with One Editor

Editor appears with "ed." label; bibliography inverts and uses comma before "ed."

First note: [@tigay:1985, 35]

Subsequent: [@tigay:1985, 38]

### A Book with Two or Three Editors

Multiple editors listed with "eds." label. Series abbreviation (RBS) shown in notes.

First note: [@kaltner+mckenzie:2002, xii]

Subsequent: [@kaltner+mckenzie:2002, viii]

### A Book with Four or More Editors

Uses "et al." for editors in notes. Series abbreviation (BASPSup) included.

First note: [@oates+etal:2001, 10]

### A Book with Both Author and Editor

Author is primary; editor shown after title with "ed." in notes, "Edited by" in bibliography.

First note: [@schillebeeckx:1986, 20]

### A Book with Author, Editor, and Translator

Author, editor, and translator all shown. Note uses abbreviated labels; bibliography uses full verbs.

First note: [@blass+debrunner:1982, 40]

### A Title in a Modern Work Citing a Nonroman Alphabet

Nonroman text within a title is preserved in brackets with appropriate font.

First note: [@irvine:2014]

### An Article in an Edited Volume

Article title in quotation marks, container title (book) in italic, editor after container.

First note: [@attridge:1986]

Subsequent: [@attridge:1986, 311-343]

### An Article in a Festschrift

Same format as edited volume. Festschrift titles may include German or other languages.

First note: [@vanseters:1995]

Subsequent: [@vanseters:1995, 222]

### An Introduction, Preface, or Foreword Written by Someone Other Than the Author

The introduction author is primary; the book author appears after the title with "by".

First note: [@boers:1996, xi-xxi]

Subsequent: [@boers:1996, xi-xx]

### Multiple Publishers for a Single Book

When a book has multiple publishers in different cities, both are listed.

(Bibliography only — see gerhardsson:1961 in the bibliography.)

### A Revised Edition

Edition information appears after the title. Numeric editions use ordinal form; textual editions are preserved as-is.

First note: [@pritchard:1969, xxi]

First note: [@blenkinsopp:1996, 81]

### A Recent Reprint Title

Current publisher appears first, followed by "repr. of" with original publication details.

First note: [@vanseters:1997, 35]

### A Reprint Title in the Public Domain

Uses "orig." with just the original year when no original publisher is specified.

First note: [@deissmann:1995, 55]

### A Forthcoming Book

Uses "forthcoming" instead of a date when the publication status is set.

First note: [@harrison+welborn:forthcoming]

Subsequent: [@harrison+welborn:forthcoming, 201]

### A Multivolume Work

Volume count shown in notes; bibliography includes translator and full date range.

First note: [@harnack:1896-1905]

Subsequent: [@harnack:1896-1905, 2:126]

### A Titled Volume in a Multivolume, Edited Work

Individual volume title shown first, then "vol. X of" the multivolume work title (italic). Collection editor follows the maintitle.

First note: [@winter+clarke:1993, 25]

Subsequent: [@winter+clarke:1993, 25]

### A Chapter within a Multivolume Work

Chapter title in quotes, "in" before the container, volume:page locator format.

First note: [@mason:1996]

Subsequent: [@mason:1996, 224]

### A Chapter within a Titled Volume in a Multivolume Work

Chapter in a titled volume of a larger work. Shows volume number, individual volume title, and multivolume title.

First note: [@peterson:1993]

Subsequent: [@peterson:1993, 92]

### A Work in a Series

Series abbreviation and number appear after the title. Two examples: WUNT and SBT (with series-in-series notation).

First note: [@hofius:1989, 122]

Subsequent: [@hofius:1989, 124]

First note: [@jeremias:1967, 123-127]

Subsequent: [@jeremias:1967, 126]

### Electronic Book

Ebook citations include medium (Nook, Kindle) and may use chapter rather than page locators. DOI or URL provided where available.

First note: [@reventlow:2009, ch. 1.3]

Subsequent: [@reventlow:2009, ch. 1.3]

First note: [@wright:2014, ch. 3, "Introducing David"]

Subsequent: [@wright:2014, ch. 5, "Evidence from Qumran"]

First note: [@killebrew+steiner:2014]

Subsequent: [@killebrew+steiner:2014]

First note: [@kaufman:1974]

Subsequent: [@kaufman:1974, 123]

## General Examples: Journal Articles, Reviews, and Dissertations

### A Journal Article

Journal title abbreviated in notes (using container-title-short), full in bibliography. Volume (year): pages format.

First note: [@leyerle:1993]

Subsequent: [@leyerle:1993, 161]

### A Journal Article with Multiple Page Locations and Volumes

Article spanning multiple volumes uses combined volume/page notation.

First note: [@wildberger:1965]

First note: [@wellhausen:1876-1877]

### A Journal Article Republished in a Collected Volume

Can be cited either by the original journal publication or the collected volume reprint.

First note (original): [@freedman:1977, 20]

First note (reprint): [@freedman:1980, 14]

### A Book Review

Review format depends on whether the review has its own title. Untitled reviews use "review of *Title*" as the title element.

First note: [@teeple:1966]

Subsequent: [@teeple:1966, 369]

First note: [@pelikan:1992]

First note: [@petersen:1988]

Subsequent: [@petersen:1988, 8]

### An Unpublished Dissertation or Thesis

Uses "PhD diss." genre label and institution name instead of publisher.

First note: [@klosinski:1988, 22-44]

Subsequent: [@klosinski:1988, 23]

### An Article in an Encyclopaedia or a Dictionary

Multivolume reference works use shorthand in notes; bibliography expands with "Pages X–Y in vol. Z of *Full Title*. Edited by Editor."

First note: [@stendahl:1962]

Subsequent: [@stendahl:1962, 419]

First note: [@olson:2003]

Subsequent: [@olson:2003, 612]

### An Article in a Lexicon or Theological Dictionary

Lexicon articles use the headword as title and the lexicon shorthand. Subsequent notes may cite a different headword from the same lexicon.

First note: [@dahn+liefeld:see+vision+eye]

First note: [@beyer:diakoneo+diakonia+ktl]

Subsequent: [@beyer:diakoneo+diakonia+ktl, 83]

First note: [@spicq:atakteo+ataktos+ataktos]

First note: [@spicq:amoibe]

Subsequent: [@spicq:amoibe, 95]

First note: [@beyer:diakoneo]

First note: [@dahn:horao]

Subsequent: [@dahn:horao, 511]

### A Paper Presented at a Professional Society

Conference papers use "paper presented at" followed by the event name, location, and date.

First note: [@niditch:1994, 13-17]

Subsequent: [@niditch:1994, 14]

### An Article in a Magazine

Magazine articles use ", no." for issue numbers (distinct from journal ".issue" format) and include page ranges.

First note: [@saldarini:1998]

Subsequent: [@saldarini:1998, 28]

### An Electronic Journal Article

Electronic journal articles include DOI or URL after the page reference.

First note: [@springer:2014]

Subsequent: [@springer:2014, 158]

First note: [@truehart:1996]

Subsequent: [@truehart:1996, 37]

First note: [@kirk:2007]

Subsequent: [@kirk:2007, 186]

## Special Examples

### Texts from the Ancient Near East

Ancient Near Eastern texts are cited by their standard designation with translator and collection reference (COS, ANET, or other anthology). These use the `annote` field for custom citation formats.

First note: [@greathymnaten]

Subsequent: [@greathymnaten, 44-46]

First note: [@suppiluliumas, 319]

First note: [@erraandishum]

First note: [@doomedprince]

Subsequent: [@doomedprince, 200-203]

First note: [@disappearanceofsungod]

First note: [@ashurinscription]

Subsequent: [@ashurinscription]

First note: [@esarhaddonchronicle]

Subsequent: [@esarhaddonchronicle]

### Loeb Classical Library (Greek and Latin)

Classical texts use author + abbreviated work title + section numbers. Subsequent notes add translator and series (e.g., "Thackeray, LCL"). Bibliography lists the collected edition.

First note: [@josephus:ant, 2.233-235]

First note: [@tacitus:ann, 15.18-19]

First note: [@josephus:ant:thackery, 2.233-235]

First note: [@tacitus:ann:jackson, 15.18-19]

Plutarch's *Moralia* cited by abbreviated work title with section numbers. The bibliography entry lists the LCL volume; subsequent notes add the translator and series.

First note: [@plutarch:isos, 351C-352A]

Subsequent: [@plutarch:isos, 354D]

Philo's treatises follow the same pattern. The abbreviated work title (*Cher.*) appears in the note; the bibliography lists the collected LCL volume.

First note: [@philo:cher, 27-30]

Subsequent: [@philo:cher, 42]

### Papyri, Ostraca, and Epigraphica

Papyrological citations use standard sigla from the Checklist of Editions. The designation number is part of the name, not a page locator. Subsequent notes may include modern edition references.

First note: [@pcairzen, 59003]

First note: [@PGM, III. 1-164]

First note: [@PGM:betz, III. 1-164]

### Ancient Epistles and Homilies

Ancient letters and homilies use author + work title + section numbers. Subsequent notes add the modern editor/translator.

First note: [@heraclitus:epistle1, 10]

First note: [@heraclitus:epistle1:worley, 10]

### *ANF* and *NPNF*, First and Second Series

Church father texts reference the ANF or NPNF series with work title, section number, and series volume:page in parentheses.

First note: [@clementinehomilies]

First note: [@augustine:letters]

### J.-P. Migne's Patrologia Latina and Patrologia Graeca

Patristic texts from Migne's Patrologia use the work title with PG or PL volume and column reference.

First note: [@gregory:orationestheologicae]

### Strack-Billerbeck

Strack-Billerbeck is cited by shorthand (Str-B) with volume:page.

First note: [@Str-B]

### *Aufstieg und Niedergang der römischen Welt* (ANRW)

ANRW articles use author, title, and the ANRW volume.part:pages reference.

First note: [@anderson:pepaideumenos]

Subsequent: [@anderson:pepaideumenos, 86]

### Bible Commentaries

Single-volume commentaries cite like books with series abbreviation. Multi-author study Bibles cite the specific contributor's section.

First note: [@hooker:1991, 223]

First note: [@petersen:2006, 1096]

Subsequent: [@petersen:2006, 1096]

First note: [@partain:1995]

Subsequent: [@partain:1995, 175]

### Multivolume Commentaries

Multivolume commentaries can be cited as the complete set (with volume:page locator) or by individual volume.

First note: [@dahood:1965-1970, 3:127]

Subsequent: [@dahood:1965-1970, 2:121]

First note: [@dahood:1965, 44]

Subsequent: [@dahood:1965, 78]

First note: [@dahood:1968, 374]

First note: [@miller:2001, 577]

### SBL Seminar Papers

SBL Seminar Papers are cited as chapters in a collection with the SBLSP series abbreviation.

First note: [@crenshaw:2001]

### Text Editions Published Online with No Print Counterpart

Online-only text editions include the database name and release date.

First note: [@wilhelm:2013]

Subsequent: [@wilhelm:2013]

### Online Database

Online databases cite the author/institution, entry title, database name, and URL with access date.

First note: [@cobb:figurines]

First note: [@caraher:2013]

Subsequent: [@caraher:2013]

### Websites and Blogs

Blog posts cite the author, post title, blog name, date, and URL.

First note: [@goodacre:2014]

### Video and Film

Video citations include the director or presenter, title, medium (DVD where applicable), publisher, and date. Films omit the medium designation.

First note: [@wright:kingdom]

Subsequent: [@wright:kingdom]

First note: [@gibson:passion]

Subsequent: [@gibson:passion]

## Privileged Reference Works

### BDAG, BDB, BDF

Standard lexicons and grammars are cited by shorthand with page or section locator. The bibliography lists the full entry with shorthand label prepended.

BDAG: [@BDAG, 35]

BDB: [@BDB, 432]

BDF: [@BDF, §441]

### HALOT, TLOT

Hebrew and Old Testament lexicons follow the same shorthand pattern.

HALOT: [@HALOT, 2:223]

TLOT: [@TLOT, 1:24]

### SBLHS

The Handbook itself is cited by shorthand with section reference.

SBLHS: [@SBLHS, §6.2.1]

### GKC, IBHS

Hebrew grammars cited by shorthand. GKC (*Gesenius' Hebrew Grammar*) uses section references; IBHS (*An Introduction to Biblical Hebrew Syntax*) uses page or section locators.

GKC: [@GKC, §154a]

GKC: [@GKC, §111b]

IBHS: [@IBHS, 71]

IBHS: [@IBHS, §16.3.2]

# References
