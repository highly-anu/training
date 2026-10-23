using Toybox.Test;
using Toybox.Lang;

// The pre-start list's focus: -1 is the header, then the rows, round again
// both ways. Run with build.sh --test.

(:test)
function preStartFocusWrapsThroughTheHeader(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(NativeList.step(-1, 1, 3), 0, "DOWN from the header: the first row");
    Test.assertEqualMessage(NativeList.step(1, 1, 3), 2, "along the list");
    Test.assertEqualMessage(NativeList.step(2, 1, 3), -1, "past the last row: the header");
    Test.assertEqualMessage(NativeList.step(-1, -1, 3), 2, "UP from the header: the last row");
    Test.assertEqualMessage(NativeList.step(0, -1, 3), -1, "UP from the first row: the header");
    Test.assertEqualMessage(NativeList.step(-1, 1, 0), -1, "no rows: the header stays");
    return true;
}
