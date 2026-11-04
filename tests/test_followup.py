import importlib.util
from pathlib import Path
import tempfile
import unittest

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("stability", ROOT / "scripts" / "05_model_stability.py")
stability = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stability)


class FollowupTests(unittest.TestCase):
    def test_source_hash_survives_windows_to_linux_checkout(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "script.py"
            path.write_bytes(b"first\r\nsecond\r\n")
            windows = stability.source_sha(path)
            path.write_bytes(b"first\nsecond\n")
            self.assertEqual(stability.source_sha(path), windows)
            path.write_bytes(b"first\nchanged\n")
            self.assertNotEqual(stability.source_sha(path), windows)

    def test_bootstrap_respondents_cannot_cross_calibration_or_test(self):
        data = pd.DataFrame({"year": np.repeat([2023, 2024, 2025], 100),
                             "y": np.tile([0, 1], 150)})
        for resample in (False, True):
            a = stability.partitions(data, "y", 42, resample)
            b = stability.partitions(data, "y", 42, resample)
            for left, right in zip(a[:5], b[:5]):
                np.testing.assert_array_equal(left, right)
            fit, tune, cal, refit, test, overlap = a
            self.assertFalse(any(overlap.values()))
            self.assertFalse(set(fit) & set(tune))
            self.assertEqual(len(refit), len(fit) + len(tune))
            self.assertEqual(set(data.loc[test, "year"]), {2025})
            self.assertEqual(set(data.loc[refit, "year"]), {2023, 2024})
            if resample:
                self.assertLess(len(set(refit)), len(refit))

    def test_test_only_categories_do_not_enter_vocabulary(self):
        data = pd.DataFrame({"role": ["known", "test-only"]})
        aligned = stability.categorise(data, {"role": ["known"]})
        self.assertEqual(aligned.role.iloc[0], "known")
        self.assertTrue(pd.isna(aligned.role.iloc[1]))

    def test_paired_intervals_preserve_identical_predictions(self):
        y = np.tile([0, 1], 50)
        p = np.linspace(.1, .9, len(y))
        intervals = stability.paired_interval(y, p, p, seed=7, reps=30)
        self.assertTrue(all(value == 0 for value in intervals.values()))


if __name__ == "__main__":
    unittest.main()
