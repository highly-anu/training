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


class OwnPackagesTests(unittest.TestCase):
    """An athlete with packages of their own gets the reference routes with
    theirs added; everyone else, and the build, are untouched (roadmap 20.4)."""

    @classmethod
    def setUpClass(cls):
        # test_private_packages keeps its rows and overlays in a scratch
        # folder of its own (TRAINING_USER_PACKAGES_DIR), set when imported.
        import test_private_packages as tpp
        from src import package_store
        cls.store = package_store
        cls.store._SETS.clear()
        cls.me = 'local-dev-user'               # who a local request is
        cls.pkg, cls.files = tpp.package_for(cls.me)

    @classmethod
    def tearDownClass(cls):
        cls.store.remove(cls.me, cls.pkg)
        cls.store._SETS.clear()
        api.clear_static_cache()

    def setUp(self):
        api.clear_static_cache()
        self.store.remove(self.me, self.pkg)
        self.client = api.app.test_client()

    def ids(self, client=None, **kw):
        return {p['id'] for p in (client or self.client).get('/api/philosophies', **kw).get_json()}

    def test_without_a_package_the_answer_is_the_shared_one(self):
        resp = self.client.get('/api/philosophies')
        self.assertEqual(resp.headers['Cache-Control'], 'no-cache')
        self.assertNotIn('Authorization', resp.headers.get('Vary', ''))
        self.assertEqual(api._USER_STATIC, {})

    def test_their_package_is_added_for_them_and_marked_private(self):
        shared = self.client.get('/api/philosophies')
        self.assertTrue(self.store.install(self.me, self.files)['installed'])
        mine = self.client.get('/api/philosophies')
        self.assertEqual(self.ids() - {p['id'] for p in shared.get_json()}, {self.pkg})
        self.assertEqual(mine.headers['Cache-Control'], 'private, no-cache')
        self.assertIn('Authorization', mine.headers['Vary'])
        self.assertNotEqual(mine.headers['ETag'], shared.headers['ETag'])
        # Their own page, which the shared view answers 404.
        self.assertEqual(self.client.get(f'/api/philosophies/{self.pkg}/describe').status_code, 200)
        self.assertIn(self.pkg, {g['id'] for g in self.client.get('/api/philosophies/glance').get_json()})
        # Revalidation is still a 304.
        again = self.client.get('/api/philosophies', headers={'If-None-Match': mine.headers['ETag']})
        self.assertEqual(again.status_code, 304)

    def test_the_shared_answers_are_never_theirs(self):
        self.assertTrue(self.store.install(self.me, self.files)['installed'])
        self.ids()
        for key, (body, _gz, _etag) in api._STATIC.items():
            self.assertNotIn(self.pkg.encode(), body, key)
        # Someone not signed in (a production request without a token): the shared bytes.
        from src import auth
        real = auth.optional_user_id
        auth.optional_user_id = lambda: None
        try:
            anonymous = self.client.get('/api/philosophies')
            self.assertNotIn(self.pkg, {p['id'] for p in anonymous.get_json()})
            self.assertEqual(anonymous.headers['Cache-Control'], 'no-cache')
            self.assertEqual(self.client.get(f'/api/philosophies/{self.pkg}/describe').status_code, 404)
            # Another athlete, signed in, with no package: the shared bytes too.
            auth.optional_user_id = lambda: 'someone-else'
            other = self.client.get('/api/philosophies')
            self.assertEqual(other.data, anonymous.data)
        finally:
            auth.optional_user_id = real

    def test_a_route_their_package_does_not_change_keeps_the_shared_bytes(self):
        self.client.get('/api/analytics/vocabulary')
        self.assertTrue(self.store.install(self.me, self.files)['installed'])
        self.client.get('/api/analytics/vocabulary')
        (key, hit), = [(k, v) for k, v in api._USER_STATIC.items() if k[1].startswith('/api/analytics/vocabulary')]
        self.assertIs(hit, api._STATIC[key[1]])

    def test_a_change_is_a_new_answer_with_nothing_cleared(self):
        self.ids()                               # the shared answer, built before they have a package
        self.assertTrue(self.store.install(self.me, self.files)['installed'])
        self.assertIn(self.pkg, self.ids())
        shared_before = dict(api._STATIC)
        self.store.remove(self.me, self.pkg)
        self.assertNotIn(self.pkg, self.ids())
        self.assertEqual(dict(api._STATIC), shared_before)

    def test_the_store_is_bounded(self):
        self.assertTrue(self.store.install(self.me, self.files)['installed'])
        saved = api._USER_STATIC_MAX
        api._USER_STATIC_MAX = 3
        try:
            for path in api._static_paths()[:8]:
                self.client.get(path)
            self.assertLessEqual(len(api._USER_STATIC), 3)
        finally:
            api._USER_STATIC_MAX = saved


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

    def test_an_athletes_own_answers_leave_the_build_in_place(self):
        import test_private_packages as tpp
        from src import package_store
        package_store._SETS.clear()
        pkg, files = tpp.package_for('local-dev-user')
        try:
            self.assertTrue(package_store.install('local-dev-user', files)['installed'])
            client = api.app.test_client()
            self.assertIn(pkg, {p['id'] for p in client.get('/api/philosophies').get_json()})
            self.assertTrue(api._BUILT, 'the build was abandoned')
            package_store.remove('local-dev-user', pkg)
            resp = client.get('/api/philosophies')
            self.assertEqual(resp.headers['ETag'].strip('"'), self.manifest['/api/philosophies?']['etag'])
        finally:
            package_store.remove('local-dev-user', pkg)
            package_store._SETS.clear()

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
