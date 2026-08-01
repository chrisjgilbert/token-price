require "test_helper"

class MarketEvent::ProseTest < ActiveSupport::TestCase
  test "text within the budget passes through unchanged" do
    text = "Frontier prices fell by a third."
    assert_equal text, MarketEvent::Prose.fit(text, limit: 100)
  end

  test "keeps whole sentences and adds no ellipsis" do
    text = "Frontier prices fell by a third. Mid-tier models no longer undercut them. " \
           "This third sentence is what has to go to get under the budget."

    fitted = MarketEvent::Prose.fit(text, limit: 80)

    assert_equal "Frontier prices fell by a third. Mid-tier models no longer undercut them.", fitted
    refute_includes fitted, "…"
  end

  test "keeps the opening clause of a multi-line blurb" do
    # Regression: the sentence scan can't cross a newline, so an opening line
    # with no terminator matched nothing and the head was silently dropped.
    text = "OpenAI cut Terra pricing by 20 percent today\n\n" \
           "That puts its blended rate below Anthropic's mid-tier Sonnet on cost per token."

    fitted = MarketEvent::Prose.fit(text, limit: 90)

    assert fitted.start_with?("OpenAI cut Terra pricing"), "expected the opening clause to survive"
    refute_includes fitted, "\n"
  end

  test "falls back to a word boundary when no whole sentence fits" do
    fitted = MarketEvent::Prose.fit("#{'word ' * 50}end.", limit: 60)

    assert_operator fitted.length, :<=, 60
    assert fitted.end_with?("word…"), "expected a whole-word cut, not a split word"
  end

  test "handles text with no sentence terminator at all" do
    fitted = MarketEvent::Prose.fit("a long stretch of prose that never terminates properly", limit: 20)

    assert_operator fitted.length, :<=, 20
    assert fitted.start_with?("a long"), "expected the head, not an empty string"
  end

  test "returns an empty string for blank input" do
    assert_equal "", MarketEvent::Prose.fit(nil, limit: 100)
    assert_equal "", MarketEvent::Prose.fit("   ", limit: 100)
  end
end
