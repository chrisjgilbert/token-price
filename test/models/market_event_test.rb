require "test_helper"

class MarketEventTest < ActiveSupport::TestCase
  def valid_attrs
    { title: "GPT-4 Turbo: 3× cheaper", event_date: Date.new(2023, 11, 6),
      kind: "market", status: "published" }
  end

  # --- validations -----------------------------------------------------------

  test "valid with required attributes" do
    assert MarketEvent.new(valid_attrs).valid?
  end

  test "invalid without title" do
    assert_not MarketEvent.new(valid_attrs.merge(title: nil)).valid?
  end

  test "invalid without event_date" do
    assert_not MarketEvent.new(valid_attrs.merge(event_date: nil)).valid?
  end

  test "invalid with unknown status" do
    assert_not MarketEvent.new(valid_attrs.merge(status: "pending")).valid?
  end

  test "invalid with unknown kind" do
    assert_not MarketEvent.new(valid_attrs.merge(kind: "launch")).valid?
  end

  test "valid as draft" do
    assert MarketEvent.new(valid_attrs.merge(status: "draft")).valid?
  end

  test "valid with a blank source_url" do
    assert MarketEvent.new(valid_attrs.merge(source_url: nil)).valid?
    assert MarketEvent.new(valid_attrs.merge(source_url: "")).valid?
  end

  test "valid with an https source_url" do
    assert MarketEvent.new(valid_attrs.merge(source_url: "https://techcrunch.com/story")).valid?
  end

  test "invalid with a javascript: source_url" do
    assert_not MarketEvent.new(valid_attrs.merge(source_url: "javascript:alert(1)")).valid?
  end

  test "invalid when a newline smuggles a second scheme past the http(s) prefix" do
    # \A-only anchoring would accept this; \z + \S close the bypass.
    assert_not MarketEvent.new(valid_attrs.merge(source_url: "https://ok.test\njavascript:alert(1)")).valid?
  end

  # --- scopes ----------------------------------------------------------------

  test "published scope returns only published events" do
    pub   = MarketEvent.create!(valid_attrs)
    draft = MarketEvent.create!(valid_attrs.merge(title: "Draft event", status: "draft",
                                                   event_date: Date.new(2024, 1, 1)))

    ids = MarketEvent.published.pluck(:id)
    assert_includes ids, pub.id
    assert_not_includes ids, draft.id
  end

  test "drafts scope returns only draft events" do
    pub   = MarketEvent.create!(valid_attrs)
    draft = MarketEvent.create!(valid_attrs.merge(title: "Draft event", status: "draft",
                                                   event_date: Date.new(2024, 1, 1)))

    ids = MarketEvent.drafts.pluck(:id)
    assert_includes ids, draft.id
    assert_not_includes ids, pub.id
  end

  # --- associations ----------------------------------------------------------

  test "news_items association nullifies market_event_id on destroy" do
    event = MarketEvent.create!(valid_attrs)
    item  = NewsItem.create!(url: "https://example.com/test", title: "Test item",
                              source: "hn", market_event_id: event.id)

    event.destroy
    assert_nil item.reload.market_event_id
  end

  # --- citations default ------------------------------------------------------

  test "citations default to an empty array" do
    assert_equal [], MarketEvent.create!(valid_attrs).citations
  end

  # --- generate_insight facade ------------------------------------------------

  test "generate_insight persists the so_what, citations, and a timestamp" do
    event = MarketEvent.create!(valid_attrs)
    client = fake_anthropic_search_client(text: "Frontier prices fell again.",
                                          citations: [ { url: "https://example.com/a", title: "A" } ])

    event.generate_insight(client: client)
    event.reload

    assert_equal "Frontier prices fell again.", event.so_what
    assert_equal [ { "url" => "https://example.com/a", "title" => "A" } ], event.citations
    assert_not_nil event.so_what_generated_at
  end
end
