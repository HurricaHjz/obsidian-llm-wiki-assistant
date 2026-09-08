#!/usr/bin/env python3
"""Tests for repo_pack.py — controls per the design (repo-pack-design.md §Tests), plus the project-store
snapshot guards of 2026-09-07 (project-store-design.md D4: dirty tree, credential URL, absolute --repo, slice)."""
import os, re, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
RP = os.path.join(HERE, "repo_pack.py")
import importlib.util
spec = importlib.util.spec_from_file_location("repo_pack", RP)
rp = importlib.util.module_from_spec(spec); spec.loader.exec_module(rp)

def sh(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)

class Fixture(unittest.TestCase):
    def setUp(self):
        # 2026-08-30 rule: remove-and-recreate, never rm -rf "$d"/*
        self.root = tempfile.mkdtemp(prefix="rp-fix-")
        self.repo = os.path.join(self.root, "repo")
        os.makedirs(self.repo)
        sh(["git", "init", "-q"], cwd=self.repo)
        sh(["git", "config", "user.email", "t@t"], cwd=self.repo)
        sh(["git", "config", "user.name", "t"], cwd=self.repo)
        open(os.path.join(self.repo, "plain.md"), "w").write("# planted-doc-e7q1\nhello\n")
        open(os.path.join(self.repo, "nested.md"), "w").write("outer\n```\ninner fence body\n```\ntail [[link]] [x](bareword)\n## in-body heading that must not count as a section\n")
        open(os.path.join(self.repo, "big.md"), "w").write("A" * (rp.TRUNCATE_AT + 100))
        open(os.path.join(self.repo, "ptr.bin"), "wb").write(b"version https://git-lfs.github.com/spec/v1\noid sha256:aa\n")
        open(os.path.join(self.repo, "ctrl.md"), "wb").write(b"line\x0cfeed\n")
        sh(["git", "add", "-A"], cwd=self.repo); sh(["git", "commit", "-qm", "fix"], cwd=self.repo)
        self.sha = sh(["git", "rev-parse", "HEAD"], cwd=self.repo).stdout.strip()
        self.url = "https://github.com/fixture/repo"
        sh(["git", "remote", "add", "origin", self.url], cwd=self.repo)

    def tearDown(self):
        shutil.rmtree(self.root)

    def build(self, rels, **kw):
        return rp.build_pack(self.repo, rels, self.url, self.sha, kw.get("slice"), 2, "test")

    def pack(self, *extra):
        """Run the real verb with --no-write against the fixture by ABSOLUTE path (the project-store shape)."""
        return sh([sys.executable, RP, "pack-and-write", "--repo", self.repo, "--ledger-id", "t", "--no-write", *extra])

    def test_planted_file_appears_and_sha_pinned(self):
        body, n = self.build(["plain.md"])
        self.assertIn("planted-doc-e7q1", body)
        self.assertIn(f"- sha: {self.sha}", body)          # pin proof vs git rev-parse
        self.assertEqual(n, 1)
        self.assertIsNone(rp.self_check(body))

    def test_nested_fence_escalates_and_roundtrips_capture_write(self):
        body, _ = self.build(["nested.md"])
        m = re.search(r"^(`{4,})\n", body, re.M)
        self.assertIsNotNone(m, "fence must escalate past interior ```")
        # round-trip through the real sanitiser: fenced bodies byte-exact (no control bytes here)
        sys.path.insert(0, HERE)
        import capture_write as cw
        sanitised = cw.sanitise(body) if hasattr(cw, "sanitise") else None
        if sanitised is not None:
            self.assertIn("inner fence body", sanitised)
            self.assertIn("[[link]]", sanitised)           # inside fence → NOT defanged
            self.assertIn("[x](bareword)", sanitised)

    def test_truncation_marker(self):
        body, _ = self.build(["big.md"])
        self.assertIn(f"[TRUNCATED at {rp.TRUNCATE_AT} bytes]", body)

    def test_lfs_pointer_skipped_and_empty_selection_refused(self):
        body, n = self.build(["ptr.bin", "plain.md"])
        self.assertIn("git-LFS pointer", body); self.assertEqual(n, 1)
        with self.assertRaises(SystemExit):                # only skippables → §11 refusal
            self.build(["ptr.bin"])

    def test_control_bytes_noted(self):
        body, _ = self.build(["ctrl.md", "plain.md"])
        self.assertIn("control bytes present", body)

    def test_killed_emission_fails_self_check(self):
        body, _ = self.build(["plain.md"])
        cut = body[: len(body) // 2]                       # simulate death mid-emission
        err = rp.self_check(cut)
        self.assertIsNotNone(err, "truncated pack must fail the footer/count checker")
        self.assertIn("footer", err)

    def test_count_invariant_fires(self):
        body, _ = self.build(["plain.md", "nested.md"])
        bad = body.replace("- files: 2", "- files: 3")
        self.assertIsNotNone(rp.self_check(bad))

    def test_clean_refuses_outside_store(self):            # negative control
        r = sh([sys.executable, RP, "clean", "--repo", "../../etc"])
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refusing", r.stderr)

    # ---- project-store snapshot guards (2026-09-07) -------------------------------------------------

    def test_clean_refuses_project_store_root(self):       # the decisive negative control (design rollout step 4)
        target = os.path.expanduser("~/.llm-wiki/projects/fixture-never-created")
        r = sh([sys.executable, RP, "clean", "--repo", target])
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refusing", r.stderr)

    def test_pack_accepts_absolute_repo_outside_store(self):   # positive control
        r = self.pack("--paths", "plain.md")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pack ok: 1 files", r.stdout)

    def test_credential_remote_refused_and_bare_user_stripped(self):
        sh(["git", "remote", "set-url", "origin", "https://git:tok-e7q1@host.example/x"], cwd=self.repo)
        r = self.pack("--paths", "plain.md")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("credential part", r.stderr)
        self.assertNotIn("pack ok", r.stdout)               # refused before any emission
        self.assertNotIn("tok-e7q1", r.stdout + r.stderr)   # the secret never echoed
        sh(["git", "remote", "set-url", "origin", "https://git@git.overleaf.example/abc"], cwd=self.repo)
        body, _ = rp.build_pack(self.repo, ["plain.md"], "https://git@git.overleaf.example/abc", self.sha, None, 2, "t")
        self.assertIn("- repo: https://git.overleaf.example/abc\n", body)   # bare user part dropped from the header

    def test_dirty_tracked_file_refused(self):              # the guard fires
        open(os.path.join(self.repo, "plain.md"), "a").write("edit after commit\n")
        r = self.pack("--paths", "nested.md")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("dirty tree", r.stderr)
        self.assertIn("plain.md (modified", r.stderr)

    def test_unselected_untracked_never_blocks_but_selected_does(self):   # the guard does not fire, then does
        open(os.path.join(self.repo, ".DS_Store"), "wb").write(b"\x00\x00")
        open(os.path.join(self.repo, "notes-untracked.md"), "w").write("draft\n")
        r = self.pack("--paths", "plain.md")
        self.assertEqual(r.returncode, 0, r.stderr)
        r2 = self.pack("--paths", "plain.md,notes-untracked.md")
        self.assertNotEqual(r2.returncode, 0)
        self.assertIn("notes-untracked.md (untracked, selected)", r2.stderr)

    def test_allow_large_lifts_per_file_truncation(self):
        r = self.pack("--paths", "big.md")
        self.assertEqual(r.returncode, 0, r.stderr)
        body, _ = rp.build_pack(self.repo, ["big.md"], self.url, self.sha, None, 2, "t")
        self.assertIn("[TRUNCATED at", body)                         # default: truncated
        whole, _ = rp.build_pack(self.repo, ["big.md"], self.url, self.sha, None, 2, "t", truncate_at=None)
        self.assertNotIn("[TRUNCATED at", whole)                    # lifted: packed whole
        self.assertIn("A" * (rp.TRUNCATE_AT + 100), whole)

    def test_provenance_distinct_per_slice_and_defaults_to_sha12(self):
        u = "https://git.overleaf.example/abc"
        p1 = rp.provenance(u, self.sha, "aaaa1111")
        p2 = rp.provenance(u, self.sha, "bbbb2222")
        self.assertNotEqual(p1, p2)
        self.assertEqual(rp.provenance(u, self.sha, "aaaa1111"), p1)     # a repeated slice repeats the provenance
        self.assertEqual(rp.provenance(u, self.sha, None), f"{u}#{self.sha[:12]}")   # non-GitHub default: the short sha
        self.assertEqual(rp.provenance("https://github.com/o/r", self.sha, None), f"https://github.com/o/r/tree/{self.sha}")

if __name__ == "__main__":
    unittest.main(verbosity=1)
