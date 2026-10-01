"""The OAuth landing URL names a route every frontend deployment knows."""
import os
os.environ.setdefault('SUPABASE_URL', '')

import api  # loads .env / .env.local, which may set FRONTEND_URL — so override after


def test_landing_is_the_profile_tab_with_the_outcome():
    os.environ['FRONTEND_URL'] = 'https://example.pages.dev'
    assert api._integrations_redirect('garmin', 'connected') == \
        'https://example.pages.dev/profile?tab=connections&garmin=connected'
    assert api._integrations_redirect('strava', 'error', 'denied') == \
        'https://example.pages.dev/profile?tab=connections&strava=error&reason=denied'


if __name__ == '__main__':
    test_landing_is_the_profile_tab_with_the_outcome()
    print('OAuth landing test passed.')
