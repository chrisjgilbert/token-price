require "application_system_test_case"

# Browsing the read pages the way a visitor does: a model's detail page with its
# price-history chart, a provider page and its model list, and the market-events
# timeline. These confirm the pages render and link up in a
# real browser, including the SVG chart the price-chart controller enhances.
class ContentBrowsingTest < ApplicationSystemTestCase
  test "a model detail page shows its price history chart and snapshots" do
    visit model_path("deepseek-v4-pro")

    assert_selector "h1", text: "DeepSeek V4 Pro"
    # The chart renders server-side as SVG (the Stimulus controller only adds the
    # crosshair on top), so it's present without any interaction.
    assert_selector "svg[data-price-chart-target='svg']"
    assert_selector "h2", text: "Snapshots"
    # Two price points (launch + the 75% cut) means a price-change summary.
    assert_text "75.0%"
  end

  test "a provider page lists its models and links through to one" do
    visit provider_path("deepseek")

    assert_selector "h1", text: "DeepSeek"
    assert_text "DeepSeek V4 Pro"

    click_on "DeepSeek V4 Pro", match: :first

    assert_current_path model_path("deepseek-v4-pro")
    assert_selector "h1", text: "DeepSeek V4 Pro"
  end

  test "the events timeline renders published market events" do
    # There is no market_events fixture file, so the timeline needs a row of its
    # own — without one the page renders its empty state and no #ev-timeline.
    MarketEvent.create!(title: "Opus gets 67% cheaper", event_date: Date.current,
                        kind: "market", status: "published",
                        note: "Anthropic drops Opus pricing to $5/$25.")

    visit events_path

    assert_selector "h1", text: "Market events"
    assert_selector "#ev-timeline"
    assert_selector ".ev-title", text: "Opus gets 67% cheaper"
    # The kind filter is gone — market events are the only kind left.
    assert_no_selector ".events-toolbar"
  end
end
