package app.banktrack.community.domain;

/** The markets a bet can be on, each settled from the final score, as the app's TipMarket. */
public enum Market {
    homeWin, draw, awayWin, homeOrDraw, awayOrDraw,
    over15, over25, under25, under35,
    bttsYes, bttsNo, homeScores, awayScores,
    overLine, underLine;

    /** Whether a bet on this market won with this final score; line is for overLine and underLine. */
    public boolean wins(int h, int a, Double line) {
        return switch (this) {
            case homeWin -> h > a;
            case draw -> h == a;
            case awayWin -> a > h;
            case homeOrDraw -> h >= a;
            case awayOrDraw -> a >= h;
            case over15 -> h + a > 1.5;
            case over25 -> h + a > 2.5;
            case under25 -> h + a < 2.5;
            case under35 -> h + a < 3.5;
            case bttsYes -> h > 0 && a > 0;
            case bttsNo -> h == 0 || a == 0;
            case homeScores -> h > 0;
            case awayScores -> a > 0;
            case overLine -> line != null && h + a > line;
            case underLine -> line != null && h + a < line;
        };
    }
}
