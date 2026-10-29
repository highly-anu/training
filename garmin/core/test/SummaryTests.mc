using Toybox.Test;
using Toybox.Lang;

// The post-save pages' words and scales. Run with build.sh --test.

(:test)
function trainingEffectWordsFollowGarminsBands(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(SummaryView.benefit(0.4), "No benefit", "under 1.0");
    Test.assertEqualMessage(SummaryView.benefit(1.0), "Minor benefit", "1.0 starts minor");
    Test.assertEqualMessage(SummaryView.benefit(2.9), "Maintaining", "2.0-2.9");
    Test.assertEqualMessage(SummaryView.benefit(3.0), "Improving", "3.0 starts improving");
    Test.assertEqualMessage(SummaryView.benefit(4.6), "Highly improving", "4.0-4.9");
    Test.assertEqualMessage(SummaryView.benefit(5.0), "Overreaching", "5.0");
    return true;
}

// The athlete's 45 at 30-something reads Good (green), as his watch shows it.
(:test)
function vo2BandsFollowGarminsRatings(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(SummaryView.vo2Band(45, false, 35), 2, "45, a man of 35: Good");
    Test.assertEqualMessage(SummaryView.vo2Band(55, false, 35), 4, "55 at 35: Superior");
    Test.assertEqualMessage(SummaryView.vo2Band(40, false, 35), 0, "40 at 35: Poor");
    Test.assertEqualMessage(SummaryView.vo2Band(45, true, 35), 3, "45, a woman of 35: Excellent");
    Test.assertEqualMessage(SummaryView.vo2Band(45, false, 17), 1, "under 20 reads as the twenties: Fair");
    Test.assertEqualMessage(SummaryView.vo2Band(40, false, 85), 3, "80 and over as the seventies");
    Test.assertMessage(SummaryView.vo2Band(45, null, 35) == null, "no sex, no band");
    Test.assertEqualMessage(SummaryView.vo2Color(null), Toybox.Graphics.COLOR_WHITE, "no band is white");
    return true;
}

(:test)
function hrChartMarksEveryTenMinutes(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(SummaryView.timeStep(25 * 60), 600, "a 25-minute session: 10:00, 20:00");
    Test.assertEqualMessage(SummaryView.timeStep(15 * 60), 300, "a short one every 5");
    Test.assertEqualMessage(SummaryView.timeStep(2 * 3600), 1800, "two hours every 30");
    return true;
}
