require "test_helper"

# Ensure Anthropic::Errors::Error exists for error stubs even if the gem
# is not fully loaded in the test environment.
unless defined?(Anthropic::Errors::Error)
  module Anthropic
    module Errors
      class Error < StandardError; end
    end
  end
end

class MarketEvent::InsightTest < ActiveSupport::TestCase
  # A plain stand-in for a MarketEvent responding to the attributes the prompt
  # reads, mirroring the NewsItem::Classification test's stub style.
  def stub_event(title:, event_date:, note: nil, source_url: nil, news_items: [])
    event = Object.new
    event.define_singleton_method(:title)      { title }
    event.define_singleton_method(:event_date) { event_date }
    event.define_singleton_method(:note)       { note }
    event.define_singleton_method(:source_url) { source_url }
    event.define_singleton_method(:news_items) { news_items }
    event
  end

  def stub_news_item(title:, source:, url:)
    item = Object.new
    item.define_singleton_method(:title)  { title }
    item.define_singleton_method(:source) { source }
    item.define_singleton_method(:url)    { url }
    item
  end

  test "returns the so_what prose and its citations" do
    event = stub_event(title: "Opus gets 67% cheaper", event_date: Date.new(2025, 11, 24),
                       note: "Anthropic drops Opus pricing to $5/$25.")
    client = fake_anthropic_search_client(
      text: "Frontier Opus-tier inference is now a third of its former price, narrowing the gap to mid-tier models.",
      citations: [ { url: "https://anthropic.com/news", title: "Opus 4.5" } ]
    )

    result = MarketEvent::Insight.new(event, client: client).run

    assert_match "third of its former price", result[:so_what]
    assert_equal [ { "url" => "https://anthropic.com/news", "title" => "Opus 4.5" } ], result[:citations]
  end

  test "includes event detail and linked news items in the prompt" do
    sent = {}
    item = stub_news_item(title: "DeepSeek R1 ships", source: "deepseek.com", url: "https://deepseek.com/r1")
    event = stub_event(title: "The DeepSeek moment", event_date: Date.new(2025, 1, 20),
                       note: "Near-frontier reasoning at 1/20th the price.",
                       source_url: "https://example.com/x", news_items: [ item ])
    client = fake_anthropic_search_client(text: "x", into: sent)

    MarketEvent::Insight.new(event, client: client).run

    prompt = sent[:messages].first[:content]
    assert_match "The DeepSeek moment", prompt
    assert_match "Near-frontier reasoning", prompt
    assert_match "https://example.com/x", prompt
    assert_match "DeepSeek R1 ships — deepseek.com — https://deepseek.com/r1", prompt
  end

  test "keeps a so_what within the limit exactly as written" do
    text = "Frontier prices fell by a third. Mid-tier models no longer undercut them on cost alone."
    event = stub_event(title: "t", event_date: Date.new(2025, 1, 1))
    client = fake_anthropic_search_client(text: text)

    result = MarketEvent::Insight.new(event, client: client).run

    assert_equal text, result[:so_what]
  end

  test "an over-long so_what drops whole sentences rather than stopping mid-word" do
    # Four sentences, over the limit together; the last must be dropped whole.
    text = "Anthropic cut Sonnet 5 input pricing to $1.50 per million tokens. " \
           "That undercuts GPT-5 mini by about 40 percent at the same context length. " \
           "Teams already batching through Sonnet 4.5 see the change without a migration. " \
           "This fourth sentence is long enough on its own to push the whole answer well past " \
           "the character budget, so the fit has to drop it whole rather than cut into it, " \
           "which is the behaviour under test here."
    event = stub_event(title: "t", event_date: Date.new(2025, 1, 1))
    client = fake_anthropic_search_client(text: text)

    so_what = MarketEvent::Insight.new(event, client: client).run[:so_what]

    assert_operator so_what.length, :<=, MarketEvent::Insight::SO_WHAT_LIMIT
    refute_includes so_what, "…", "a sentence-boundary cut needs no ellipsis"
    assert so_what.end_with?("without a migration."), "expected the last whole sentence to be kept"
    refute_includes so_what, "fourth sentence"
  end

  test "a single over-long sentence falls back to a word boundary" do
    event = stub_event(title: "t", event_date: Date.new(2025, 1, 1))
    client = fake_anthropic_search_client(text: "#{'word ' * 200}end.")

    so_what = MarketEvent::Insight.new(event, client: client).run[:so_what]

    assert_operator so_what.length, :<=, MarketEvent::Insight::SO_WHAT_LIMIT
    assert so_what.end_with?("word…"), "expected a whole-word cut, not a split word"
  end

  test "states the character budget in the prompt so the model can land under it" do
    assert_includes MarketEvent::Insight::SYSTEM_PROMPT,
      "under #{MarketEvent::Insight::SO_WHAT_LIMIT} characters"
  end

  test "caps the number of citations" do
    event = stub_event(title: "t", event_date: Date.new(2025, 1, 1))
    many  = Array.new(10) { |i| { url: "https://example.com/#{i}", title: "S#{i}" } }
    client = fake_anthropic_search_client(text: "x", citations: many)

    result = MarketEvent::Insight.new(event, client: client).run

    assert_equal MarketEvent::Insight::MAX_CITATIONS, result[:citations].size
  end

  test "wraps an AnthropicClient error in MarketEvent::Insight::Error" do
    event = stub_event(title: "t", event_date: Date.new(2025, 1, 1))
    client = fake_anthropic_search_client(raises: Anthropic::Errors::Error.new("overloaded"))

    error = assert_raises(MarketEvent::Insight::Error) do
      MarketEvent::Insight.new(event, client: client).run
    end
    assert_match "overloaded", error.message
  end
end
