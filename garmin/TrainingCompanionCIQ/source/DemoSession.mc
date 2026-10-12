using Toybox.Lang;
using Toybox.Application;
using Toybox.Application.Storage;

// A built-in session covering every slot type and every archetype specialization.
//
// The workout screens are otherwise only reachable through pair -> sync -> today,
// which needs an account, a backend and a generated program. This lets the nine
// screens be driven in the simulator and on-wrist before any of that exists, and
// it is the practical way to exercise the hardware-verification gate.
//
// Shapes exactly mirror api.py::_encode_watch_exercise, so what renders here is
// what renders from the real payload.
module DemoSession {

    function enabled() {
        try {
            return Application.Properties.getValue("demoProgrammes") == true;
        } catch (e) {
            return false;
        }
    }

    // The readiness the session list draws on its bezel.
    function readiness() { return { "status" => "green", "score" => 78 }; }
}
