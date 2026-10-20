"""GET /api/similarity's compact shape, and /api/exercises' always-present fields.

The full matrix with an explanation per pair was 70 MB of JSON at 463
exercises and took ~200 MB to build, which killed the 256 MB production worker
on every Explore visit (2026-10-20). The browser reported it as a CORS error.

    SUPABASE_URL='' .venv/bin/python test_similarity.py
"""
from __future__ import annotations

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import loader
from src.similarity import (
    TOP_N, _category, compute_all_similarities, exercise_similarity,
)


def pair_index(i: int, j: int, n: int) -> int:
    """frontend/src/api/similarity.ts pairIndex."""
    a, b = min(i, j), max(i, j)
    return a * n - a * (a + 1) // 2 + (b - a - 1)


class CategoryTests(unittest.TestCase):
    def test_upper_triangle_and_nearest(self):
        values = {'a': 0, 'b': 1, 'c': 5, 'd': 2}

        def pair(x, y):
            score = round(1 - abs(x - y) / 10, 4)
            return {'score': score, 'primary': {}, 'secondary': {}}

        out = _category(list(values.items()), pair, top=2)
        ids, n = out['ids'], len(out['ids'])
        self.assertEqual(ids, ['a', 'b', 'c', 'd'])
        self.assertEqual(len(out['scores']), n * (n - 1) // 2)
        for i in range(n):
            for j in range(n):
                if i != j:
                    want = pair(values[ids[i]], values[ids[j]])['score']
                    self.assertEqual(out['scores'][pair_index(i, j, n)], want, (ids[i], ids[j]))
        self.assertEqual([p['id'] for p in out['top']['a']], ['b', 'd'])
        self.assertEqual([p['id'] for p in out['top']['c']], ['d', 'b'])
        self.assertTrue(all(len(peers) == 2 for peers in out['top'].values()))

    def test_ties_go_to_the_item_listed_first(self):
        same = lambda x, y: {'score': 0.5, 'primary': {}, 'secondary': {}}
        out = _category([('a', 0), ('b', 0), ('c', 0), ('d', 0)], same, top=2)
        self.assertEqual([p['id'] for p in out['top']['d']], ['a', 'b'])
        self.assertEqual([p['id'] for p in out['top']['a']], ['b', 'c'])


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.exercises, _ = loader.load_all_exercises()
        cls.out = compute_all_similarities(
            loader.load_philosophies(), loader.load_all_frameworks(),
            loader.load_all_modalities(), loader.load_all_archetypes(), cls.exercises,
        )

    def test_every_category_is_compact(self):
        for name, cat in self.out.items():
            n = len(cat['ids'])
            self.assertEqual(len(cat['scores']), n * (n - 1) // 2, name)
            self.assertTrue(all(len(peers) <= TOP_N for peers in cat['top'].values()), name)
        size = len(json.dumps(self.out))
        self.assertLess(size, 6_000_000, f'{size / 1e6:.1f} MB')

    def test_exercise_scores_match_the_pair_function(self):
        cat = self.out['exercises']
        ids, n = cat['ids'], len(cat['ids'])
        i, j = ids.index('kb_swing_two_hand'), ids.index('wk_kb_swing_two_hand')
        want = exercise_similarity(self.exercises[ids[i]], self.exercises[ids[j]])['score']
        self.assertEqual(cat['scores'][pair_index(i, j, n)], want)
        top = cat['top']['kb_swing_two_hand']
        self.assertEqual(top[0]['id'], 'wk_kb_swing_two_hand')
        self.assertIn('detail', top[0]['primary'])
        self.assertEqual([p['score'] for p in top], sorted((p['score'] for p in top), reverse=True))


class RouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import api
        cls.client = api.app.test_client()

    def test_exercises_carry_every_list_and_progressions(self):
        exercises = self.client.get('/api/exercises').get_json()
        for ex in exercises:
            self.assertIsInstance(ex['progressions'], dict, ex['id'])
            for key in ('modality', 'equipment', 'movement_patterns', 'requires', 'unlocks',
                        'contraindicated_with', 'sources'):
                self.assertIsInstance(ex[key], list, (ex['id'], key))

    def test_similarity_route(self):
        body = self.client.get('/api/similarity').get_json()
        self.assertEqual(set(body), {'philosophies', 'frameworks', 'modalities', 'archetypes',
                                     'exercises', 'movement_patterns'})
        self.assertIn('kb_swing_two_hand', body['exercises']['top'])


if __name__ == '__main__':
    unittest.main(verbosity=1)
