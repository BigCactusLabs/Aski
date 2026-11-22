"""Portable regression tests for the maintained-documentation navigation gate."""

import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check-doc-links.py"
SPEC = importlib.util.spec_from_file_location("check_doc_links", SCRIPT)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class DocumentationLinksTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name).resolve()

    def write(self, path, text=""):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        return target

    def check(self, path, text):
        return CHECKER.check_file(self.write(path, text), self.root, {})

    def test_missing_file_image_and_renamed_heading_report_source_lines(self):
        self.write("target.md", "# Current heading\n")
        failures, checked = self.check(
            "README.md",
            "# Start\n\n[file](gone.md)\n![preview](gone.png)\n[section](target.md#old-heading)\n",
        )
        self.assertEqual(checked, 3)
        self.assertEqual(failures, [
            "README.md:3: missing target: gone.md",
            "README.md:4: missing target: gone.png",
            "README.md:5: missing heading #old-heading: target.md#old-heading",
        ])

    def test_formatted_duplicate_setext_and_explicit_heading_anchors(self):
        self.write("target.md", "\n".join([
            "# `ASCIIGrid` & **colors**",
            "## More", "## More", "## More-1", "## More",
            "Setext title", "---",
            '<a id="legacy"></a>',
            "## [API](README.md) ###",
            "## Café",
        ]))
        anchors = ["asciigrid--colors", "more", "more-1", "more-1-1", "more-2",
                   "setext-title", "legacy", "api", "café"]
        failures, checked = self.check(
            "README.md", "\n".join(f"[go](target.md#{anchor})" for anchor in anchors)
        )
        self.assertEqual(failures, [])
        self.assertEqual(checked, len(anchors))

    def test_code_fences_comments_and_inline_code_do_not_create_links(self):
        self.write("target.md", "# Present\n")
        lines = [
            "# Start",
            "`[inline](missing.md)`",
            "``text with ` and [inline](missing.md)``",
            "````markdown",
            "[fenced](missing.md)",
            "```",  # A shorter marker does not close this fence.
            "[still fenced](missing.md)",
            "<!--",  # Comment syntax inside code is literal.
            "````",
            "~~~markdown",
            "![tilde fence](missing.png)",
            "~~~",
            "<!--",
            "```markdown",  # A fence inside a comment must not hide live prose.
            "[comment](missing.md)",
            "-->",
            "`<!--` is a literal code span.",
            "[present](target.md#present)",
            "[broken](target.md#gone)",
        ]
        failures, checked = self.check("README.md", "\n".join(lines))
        self.assertEqual(checked, 2)
        self.assertEqual(failures, [
            "README.md:19: missing heading #gone: target.md#gone"
        ])

    def test_reference_destinations_and_normalized_labels(self):
        self.write("target.md", "# Section\n")
        failures, checked = self.check("README.md", "\n".join([
            "[label   TEXT]: target.md#section",
            "[read][Label text]",
            "[collapsed][]",
            "[collapsed]: target.md",
            "![preview][unknown]",
            "[missing]: absent.md",
        ]))
        self.assertEqual(checked, 3)
        self.assertEqual(set(failures), {
            "README.md:5: undefined reference [unknown]",
            "README.md:6: missing target: absent.md",
        })

    def test_escaped_syntax_paths_percent_encoding_and_titles(self):
        self.write("file(name).md", "# Section\n")
        self.write("with space.md")
        self.write("name&value.md")
        failures, checked = self.check("README.md", "\n".join([
            r"\[literal](missing.md)",
            r"\[literal][missing]",
            r"\<doc:Missing>",
            r"[parentheses](file\(name\).md#section)",
            '[space](<with space.md> "title")',
            "[encoded](with%20space.md)",
            "[entity](name&amp;value.md)",
            r"\![escaped image marker is a link](with%20space.md)",
            r"\\[two backslashes do not escape the link](with%20space.md)",
        ]))
        self.assertEqual(failures, [])
        self.assertEqual(checked, 6)

    def test_same_repo_main_urls_are_local_but_tags_and_other_hosts_are_not(self):
        self.write("docs/guide.md", "# Here\n")
        failures, checked = self.check("README.md", "\n".join([
            "[blob](https://github.com/BigCactusLabs/Aski/blob/main/docs/guide.md#here)",
            "[raw](https://raw.githubusercontent.com/BigCactusLabs/Aski/main/docs/guide.md#gone)",
            "[tree](https://github.com/BigCactusLabs/Aski/tree/main/docs)",
            "[tag](https://github.com/BigCactusLabs/Aski/blob/v0.7.0/gone.md)",
            "[other](https://github.com/Other/Aski/blob/main/gone.md)",
            "[remote](https://example.com/gone.md#absent)",
            "[missing](https://github.com/BigCactusLabs/Aski/blob/main/gone.md)",
        ]))
        self.assertEqual(checked, 4)
        self.assertEqual(failures, [
            "README.md:2: missing heading #gone: https://raw.githubusercontent.com/BigCactusLabs/Aski/main/docs/guide.md#gone",
            "README.md:7: missing target: https://github.com/BigCactusLabs/Aski/blob/main/gone.md",
        ])

    def test_docc_articles_and_catalog_images_resolve_but_symbols_are_native(self):
        catalog = "Sources/Aski/Aski.docc"
        self.write(f"{catalog}/Rendering.md", "# Rendering\n\n## Output\n")
        self.write(f"{catalog}/Resources/example.png")
        failures, checked = self.check(f"{catalog}/Aski.md", "\n".join([
            "# ``Aski``",
            "``ASCIIConverter/convert()``",
            "<doc:Rendering#output>",
            "![example](example.png)",
            "<doc:RemovedArticle>",
            "![missing](missing.png)",
        ]))
        self.assertEqual(checked, 4)
        self.assertEqual(failures, [
            f"{catalog}/Aski.md:6: missing target: missing.png",
            f"{catalog}/Aski.md:5: missing target: doc:RemovedArticle",
        ])
        failures, _ = self.check("docs/guide.md", "![outside a catalog](example.png)")
        self.assertEqual(failures, ["docs/guide.md:1: missing target: example.png"])

    def test_local_root_relative_links_and_fragment_only_links(self):
        self.write("README.md", "# Root\n")
        failures, checked = self.check(
            "docs/guide.md", "# Local\n[root](/README.md#root)\n[here](#local)\n[encoded](../README.md#%72oot)\n"
        )
        self.assertEqual(failures, [])
        self.assertEqual(checked, 3)

    def test_scope_covers_entry_points_and_guides_without_rewriting_history(self):
        for name in CHECKER.ENTRY_FILES:
            self.write(name, "# Entry\n")
        included = [
            "docs/architecture.md", "docs/agents/nested/guide.md",
            "docs/guides/recipe.md", "Sources/Aski/Aski.docc/Article.md",
        ]
        excluded = [
            "docs/Research/2026-01-01-note.md",
            "docs/Research/Results/old/README.md", "docs/release-notes/v0.1.0.md",
            "backlog/tasks/task-1.md", "Scripts/research/old/README.md",
        ]
        for name in included:
            self.write(name, "# Guide\n")
        for name in excluded:
            self.write(name, "[historical](not-in-this-checkout.md)")
        found = set(CHECKER.documentation_files(self.root))
        self.assertTrue({self.root / name for name in included}.issubset(found))
        self.assertTrue({self.root / name for name in excluded}.isdisjoint(found))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(CHECKER.main(["--root", str(self.root)]), 0)
        self.assertIn("Documentation navigation passed", output.getvalue())
        self.write("docs/agents/nested/guide.md", "[broken](missing.md)")
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            self.assertEqual(CHECKER.main(["--root", str(self.root)]), 1)
        self.assertIn("docs/agents/nested/guide.md:1: missing target", errors.getvalue())

    def test_targets_cannot_escape_the_checkout(self):
        failures, checked = self.check("README.md", "[escape](../outside.md)\n")
        self.assertEqual(checked, 1)
        self.assertEqual(failures, ["README.md:1: target escapes repository: ../outside.md"])


if __name__ == "__main__":
    unittest.main()
