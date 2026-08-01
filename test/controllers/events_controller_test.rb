require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  PER_PAGE = EventsController::PER_PAGE

  test "renders the market-events timeline" do
    get events_url
    assert_response :success
    assert_select "h1", /Market events/
  end

  test "lists curated market events" do
    # Dated today so it lands on the first page regardless of how many events
    # the catalog accumulates ahead of it.
    MarketEvent.create!(title: "The DeepSeek moment", event_date: Date.current,
                        kind: "market", status: "published", note: "Markets jolt.")

    get events_url
    assert_response :success
    assert_select ".ev-title", text: /The DeepSeek moment/
    assert_select ".ev-note", text: /Markets jolt./
  end

  test "a released model is not an event — the timeline is market events only" do
    ai_models(:opus).update!(released_on: Date.current)
    MarketEvent.create!(title: "A curated event", event_date: Date.current,
                        kind: "market", status: "published")

    get events_url
    assert_response :success
    assert_select ".ev-title", text: /A curated event/
    assert_select ".ev-title", text: /released/, count: 0
  end

  test "orders year groups and the events within them newest-first" do
    # Two per year so within-year ordering is exercised, not just the year
    # boundary.
    [ Date.new(2026, 6, 30), Date.new(2026, 1, 15),
      Date.new(2025, 11, 24), Date.new(2025, 2, 3) ].each_with_index do |date, i|
      MarketEvent.create!(title: "Milestone #{i}", event_date: date,
                          kind: "market", status: "published")
    end

    get events_url
    assert_response :success

    years = css_select(".ev-year").map { |el| el.text.strip }
    assert_equal years.sort.reverse, years, "year headers should run newest-first"
    assert_equal "2026", years.first, "the newest fixture launches are in 2026"

    # Every event, across AND within years, must descend by date — this is what
    # proves the intra-year ordering, which the year-header check alone misses.
    dates = css_select(".ev-item time").map { |el| el["datetime"] }
    assert_operator dates.size, :>, 1, "expected several dated events in the timeline"
    assert_equal dates.sort.reverse, dates, "events should render newest-first by date"
  end

  test "an old ?kind= link degrades gracefully to the full timeline" do
    MarketEvent.create!(title: "Still listed", event_date: Date.current,
                        kind: "market", status: "published")

    get events_url(kind: "launch")
    assert_response :success
    # There is no kind filter anymore, so the param is simply ignored.
    assert_select ".ev-title", text: /Still listed/
  end

  test "excludes draft market events" do
    # Dated today: were drafts wrongly included, this would surface on page one.
    MarketEvent.create!(title: "Unpublished draft event", event_date: Date.current,
                        kind: "market", status: "draft")

    get events_url
    assert_response :success
    assert_select ".ev-title", text: /Unpublished draft event/, count: 0
  end

  test "renders no kind filter — there is only one kind of event left" do
    get events_url
    assert_response :success
    assert_select ".events-toolbar", count: 0
    assert_select ".tp-seg", count: 0
  end

  test "caps the first page and offers a load-more sentinel when more remain" do
    seed_market_events(PER_PAGE + 5)

    get events_url
    assert_response :success
    assert_equal PER_PAGE, css_select(".ev-item").size,
      "the first page should hold exactly PER_PAGE events when more remain"
    assert_select "#ev-sentinel[data-next-url=?]", events_path(page: 2)
  end

  test "a direct page hit renders cumulatively so no-JS paging stays coherent" do
    seed_market_events(PER_PAGE + 5)

    page_one = (get(events_url) && css_select(".ev-item").size)
    page_two = (get(events_url(page: 2)) && css_select(".ev-item").size)
    assert_operator page_two, :>, page_one,
      "page two (HTML) should include page one's events plus the next batch"
  end

  test "paging is stable across a block of same-date events" do
    # A date tie with no secondary sort key is DB-dependent, which could show an
    # event on both pages or on neither. Every event here shares one date.
    (PER_PAGE + 5).times do |i|
      MarketEvent.create!(title: "Same-day event #{i}", event_date: Date.current,
                          kind: "market", status: "published")
    end

    get events_url
    page_one = css_select(".ev-title").map { |el| el.text.strip }
    get events_url(page: 2), as: :turbo_stream
    page_two = css_select(".ev-title").map { |el| el.text.strip }

    assert_equal PER_PAGE, page_one.size
    assert_empty page_one & page_two, "no event should appear on both pages"
    assert_equal (page_one + page_two).uniq.size, page_one.size + page_two.size
  end

  test "a turbo-stream request appends only the requested page" do
    seed_market_events(PER_PAGE + 5)

    get events_url(page: 2), as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_select "turbo-stream[action=append][target=ev-timeline]"
    assert_select "turbo-stream[action=replace][target=ev-sentinel]"
    # Only the second page's slice, not a cumulative render — and not empty.
    appended = css_select("turbo-stream[target=ev-timeline] .ev-item").size
    assert_operator appended, :>, 0
    assert_operator appended, :<=, PER_PAGE
  end

  test "exhausting the timeline renders an end cap instead of a sentinel" do
    seed_market_events(3)

    get events_url(page: 999)
    assert_response :success
    assert_select ".ev-sentinel-end"
    assert_select "#ev-sentinel[data-next-url]", count: 0
  end

  test "the subtitle no longer links to the retired news feed" do
    get events_url
    assert_response :success
    assert_select "a.events-newslink", count: 0
    assert_select ".events-subtitle a[href='/news']", count: 0
  end

  test "emits a self-canonical link that ignores query params" do
    get events_url(ref: "twitter")
    assert_response :success
    assert_select "link[rel=canonical][href=?]", events_url
  end

  test "the curated timeline does not carry the raw price-changes strip (it lives at /changes)" do
    get events_url
    assert_response :success
    assert_select "section.changes", count: 0
  end

  test "the retired /trends page redirects to /events" do
    get "/trends"
    assert_redirected_to "/events"
    assert_response :moved_permanently
  end

  private

  # Publish n market events on distinct, descending recent dates — enough to push
  # the timeline past a single page so the pagination paths have data to exercise.
  def seed_market_events(count)
    count.times do |i|
      MarketEvent.create!(title: "Seeded event #{i}", event_date: Date.current - i,
                          kind: "market", status: "published")
    end
  end
end
