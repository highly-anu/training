import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;

// The one network call the spike makes. GET <apiBaseUrl>/devices/status is public: with no
// device token it answers 400 {"detail":"Missing device token"} and touches no data, so any
// answer (see `answered`) proves the phone-bridged request worked from where it was made.
(:background)
module Net {
    const DEFAULT_BASE = "https://training-api.fly.dev/api";

    function base() as String {
        var url = null;
        try {
            url = Application.Properties.getValue("apiBaseUrl");
        } catch (ex) {
            url = null;
        }
        if (url == null || !(url instanceof Lang.String) || (url as String).length() == 0) {
            return DEFAULT_BASE;
        }
        return url as String;
    }

    // A negative response code is a transport error, except these two: the round trip completed but
    // the body was not JSON (a proxy's HTML error page, say), which the SDK reports in place of the status.
    const BODY_NOT_JSON = -400;      // Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE
    const BAD_CONTENT_TYPE = -1002;  // Communications.UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE

    function answered(code as Number) as Boolean {
        return code > 0 || code == BODY_NOT_JSON || code == BAD_CONTENT_TYPE;
    }

    function probe(cb as Method(code as Number, data as Dictionary or String or Null) as Void) as Void {
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(base() + "/devices/status", null, opts, cb);
    }
}
