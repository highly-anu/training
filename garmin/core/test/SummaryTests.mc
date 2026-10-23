using Toybox.Test;
using Toybox.Lang;

// The post-save pages' words. Run with build.sh --test.

(:test)
function trainingEffectWordsFollowGarminsBands(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(SummaryView.benefit(0.4)[0], "No benefit", "under 1.0");
    Test.assertEqualMessage(SummaryView.benefit(1.0)[0], "Minor benefit", "1.0 starts minor");
    Test.assertEqualMessage(SummaryView.benefit(2.9)[0], "Maintaining", "2.0-2.9");
    Test.assertEqualMessage(SummaryView.benefit(3.0)[0], "Improving", "3.0 starts improving");
    Test.assertEqualMessage(SummaryView.benefit(4.6)[0], "Highly improving", "4.0-4.9");
    Test.assertEqualMessage(SummaryView.benefit(5.0)[0], "Overreaching", "5.0");
    return true;
}
