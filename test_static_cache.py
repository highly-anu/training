"""The static reference routes, served from memory (api.static_json), and the
C YAML parser they are built with (loader.safe_load).

Each route used to re-read every package file per request; the Explore tab's
eight at once timed out on the shared-CPU machine.

    SUPABASE_URL='' .venv/bin/python test_static_cache.py
"""
from __future__ import annotations

import glob
import gzip
import os
import sys
import tempfile
import threading
import unittest

os.environ.setdefault('SUPABASE_URL', '')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import yaml  # noqa: E402

import api  # noqa: E402
from src import loader  # noqa: E402


class StaticCacheTests(unittest.TestCase):
    def setUp(self):
        api.clear_static_cache()
        self.client = api.app.test_client()

    def test_every_route_answers_the_same_bytes(self):
        for path in api._static_paths():
            first = self.client.get(path)
            again = self.client.get(path)
            self.assertEqual(first.status_code, 200, path)
            self.assertEqual(first.data, again.data, path)
            self.assertEqual(first.headers['ETag'], again.headers['ETag'], path)
            self.assertEqual(first.headers['Cache-Control'], 'no-cache', path)
        self.assertEqual(len(api._STATIC), len(set(api._static_paths())))

    def test_revalidation_is_a_304(self):
        etag = self.client.get('/api/philosophies').headers['ETag']
        resp = self.client.get('/api/philosophies', headers={'If-None-Match': etag})
        self.assertEqual(resp.status_code, 304)
        self.assertEqual(resp.data, b'')

    def test_gzip_when_asked_never_for_a_watch(self):
        plain = self.client.get('/api/archetypes').data
        zipped = self.client.get('/api/archetypes', headers={'Accept-Encoding': 'gzip'})
        self.assertEqual(zipped.headers['Content-Encoding'], 'gzip')
        self.assertEqual(gzip.decompress(zipped.data), plain)
        watch = self.client.get('/api/archetypes', headers={'Accept-Encoding': 'gzip',
                                                            'Authorization': 'Bearer ciqdev_x'})
        self.assertNotIn('Content-Encoding', watch.headers)
        self.assertEqual(watch.data, plain)

    def test_query_strings_are_their_own_answer(self):
        male = self.client.get('/api/standards?sex=male').get_json()
        female = self.client.get('/api/standards?sex=female').get_json()
        self.assertNotEqual(male, female)

    def test_an_error_is_not_kept(self):
        self.assertEqual(self.client.get('/api/philosophies/nope/describe').status_code, 404)
        self.assertNotIn('/api/philosophies/nope/describe?', api._STATIC)

    def test_an_authoring_write_clears_it(self):
        self.client.get('/api/archetypes')
        self.assertTrue(api._STATIC)
        with api.app.test_request_context('/api/archetypes/x', method='PUT'):
            api._package_data_changed(api.app.response_class(status=200))
        self.assertEqual(api._STATIC, {})
        # A refused write, or a read, keeps it.
        self.client.get('/api/archetypes')
        with api.app.test_request_context('/api/archetypes/x', method='PUT'):
            api._package_data_changed(api.app.response_class(status=422))
        with api.app.test_request_context('/api/user/program', method='PUT'):
            api._package_data_changed(api.app.response_class(status=200))
        self.assertTrue(api._STATIC)

    def test_a_cold_burst_builds_once(self):
        from src import explore_philosophy
        calls = []
        real = explore_philosophy.glance_all

        def counted():
            calls.append(1)
            return real()
        explore_philosophy.glance_all = counted
        try:
            def hit():
                self.assertEqual(api.app.test_client().get('/api/philosophies/glance').status_code, 200)
            threads = [threading.Thread(target=hit) for _ in range(8)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
        finally:
            explore_philosophy.glance_all = real
        self.assertEqual(len(calls), 1)


class BuildTests(unittest.TestCase):
    """The Docker build answers every route into files; the worker serves them
    without reading a package."""

    @classmethod
    def setUpClass(cls):
        api.clear_static_cache()
        cls.dir = tempfile.mkdtemp()
        cls.manifest = api.build_static(cls.dir)
        cls.answers = dict(api._STATIC)

    def setUp(self):
        api.clear_static_cache()
        api._STATIC_BUILD_DIR, api._BUILT = self.dir, None

    def tearDown(self):
        api._STATIC_BUILD_DIR, api._BUILT = None, None
        api.clear_static_cache()

    def test_every_route_is_built(self):
        keys = {p if '?' in p else p + '?' for p in api._static_paths()}
        self.assertEqual(set(self.manifest), keys)

    def test_served_from_the_build_without_reading_a_package(self):
        def refuse(*_a, **_k):
            raise AssertionError('a package was read')
        saved = loader._load_yaml
        loader._load_yaml = refuse
        try:
            client = api.app.test_client()
            for key, entry in self.manifest.items():
                resp = client.get(key.rstrip('?'))
                self.assertEqual(resp.status_code, 200, key)
                self.assertEqual(resp.headers['ETag'], f'"{entry["etag"]}"', key)
                self.assertEqual(resp.data, self.answers[key][0], key)
        finally:
            loader._load_yaml = saved

    def test_an_authoring_write_stops_serving_the_build(self):
        api.app.test_client().get('/api/archetypes')
        with api.app.test_request_context('/api/archetypes/x', method='PUT'):
            api._package_data_changed(api.app.response_class(status=200))
        self.assertIsNone(api._built('/api/archetypes?'))


class ParserTests(unittest.TestCase):
    def test_the_c_parser_reads_every_data_file_alike(self):
        self.assertTrue(yaml.__with_libyaml__, 'PyYAML without libyaml: the reference routes are 10x slower')
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
        for path in glob.glob(os.path.join(root, '**', '*.yaml'), recursive=True):
            with open(path, encoding='utf-8') as f:
                text = f.read()
            self.assertEqual(loader.safe_load(text), yaml.load(text, Loader=yaml.SafeLoader), path)


if __name__ == '__main__':
    unittest.main(verbosity=1)
