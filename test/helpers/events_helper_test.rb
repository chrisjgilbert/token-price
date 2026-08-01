require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "events_by_year groups newest year first, newest event first within a year" do
    grouped = events_by_year([
      market_event("2025 early",   Date.new(2025, 2, 3)),
      market_event("2026 latest",  Date.new(2026, 6, 30)),
      market_event("2025 late",    Date.new(2025, 11, 24)),
      market_event("2026 earlier", Date.new(2026, 1, 5))
    ])

    assert_equal [ 2026, 2025 ], grouped.map(&:first)
    assert_equal [ "2026 latest", "2026 earlier" ], grouped[0][1].map(&:title)
    assert_equal [ "2025 late", "2025 early" ], grouped[1][1].map(&:title)
  end

  test "events_by_year sorts the same however the input is ordered" do
    events = [
      market_event("Oldest", Date.new(2025, 2, 3)),
      market_event("Newest", Date.new(2026, 6, 30))
    ]

    assert_equal events_by_year(events), events_by_year(events.reverse)
  end

  test "events_by_year orders a same-date pair by title, not by insertion" do
    same_day = Date.new(2026, 6, 30)
    grouped = events_by_year([
      market_event("Alpha cuts prices", same_day),
      market_event("Zeta cuts prices",  same_day)
    ])

    assert_equal [ "Zeta cuts prices", "Alpha cuts prices" ], grouped[0][1].map(&:title)
  end

  test "citation_host strips the scheme and a www prefix" do
    assert_equal "techcrunch.com", citation_host("https://www.techcrunch.com/2026/06/30/story")
    assert_equal "example.org", citation_host("http://example.org/a/b")
  end

  test "citation_host falls back to the raw value for an unparseable URL" do
    assert_equal "not a url", citation_host("not a url")
  end

  private

  def market_event(title, date)
    MarketEvent.new(title: title, event_date: date, kind: "market", status: "published")
  end
end
