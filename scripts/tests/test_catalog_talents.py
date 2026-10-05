import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from catalog_talents import normalize_talents

class TalentProjectionTests(unittest.TestCase):
    def test_old_layout_is_unchanged(self):
        raw = [0] * 113
        raw[1:3] = [32, 10]
        form = {'talentData': raw.copy(), 'talent': 1}
        normalize_talents(form)
        self.assertEqual(form['talentData'], raw)
        self.assertNotIn('additionalTalentData', form)

    def test_eleven_slots_preserve_every_value_and_unknown_effect(self):
        raw = [0] * 155
        raw[1:3] = [32, 10]
        raw[113:127] = [999, 5, 10, 50, 0, 0, 0, 0, 0, 0, 103, 14, -1, 1]
        raw[141] = 14
        form = {'talentData': raw.copy(), 'talent': 1}
        normalize_talents(form)
        self.assertEqual(len(form['talentData']), 113)
        self.assertEqual(form['talentData'][1], 32)
        self.assertEqual(form['talentData'] + form['additionalTalentData'], raw)

    def test_expanded_empty_tail_still_works_in_old_app(self):
        raw = [0] * 155
        raw[1] = 16
        form = {'talentData': raw.copy(), 'talent': 1}
        normalize_talents(form)
        self.assertEqual(len(form['talentData']), 113)
        self.assertEqual(form['talentData'] + form['additionalTalentData'], raw)

    def test_incomplete_or_missing_flagged_slots_are_rejected(self):
        for raw in [[0] * 154, [], [0] * 155, [0, '32']]:
            with self.subTest(raw_length=len(raw)), self.assertRaises(ValueError):
                normalize_talents({'talentData': raw, 'talent': 1})

if __name__ == '__main__':
    unittest.main()
