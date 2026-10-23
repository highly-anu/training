using Toybox.Test;
using Toybox.Lang;

// The lead-in rule both watches share (data/commons/watch_vocabulary.json `cues`;
// the Apple Watch's is WatchCues.leadIn, in WatchStepsTests). Run with
// build.sh --test.

(:test)
function leadInTicksTheLastThreeSecondsThenGoes(logger as Test.Logger) as Lang.Boolean {
    Test.assertMessage(Cues.leadIn(4) == null, "nothing before the last three seconds");
    Test.assertEqualMessage(Cues.leadIn(3), :tick, "3");
    Test.assertEqualMessage(Cues.leadIn(2), :tick, "2");
    Test.assertEqualMessage(Cues.leadIn(1), :tick, "1");
    Test.assertEqualMessage(Cues.leadIn(0), :go, "go at 0");
    Test.assertMessage(Cues.leadIn(-1) == null, "nothing after");
    Test.assertMessage(Cues.leadIn(null) == null, "no clock, no lead-in");
    return true;
}

(:test)
function leadInWordsFollowTheCount(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(Vocab.leadInWords().size(), Vocab.LEAD_IN_SEC + 1, "a word per count and the go");
    Test.assertEqualMessage(Cues.leadText(3), "Work in 3", "3");
    Test.assertEqualMessage(Cues.leadText(1), "1", "1");
    Test.assertEqualMessage(Cues.leadText(0), "Go", "go");
    Test.assertMessage(Cues.leadText(5) == null, "outside the count");
    return true;
}
