require "test_helper"

# Public reference pages support conditional GET (ETag + Last-Modified) so a
# daily-updated crawl budget isn't spent re-downloading unchanged HTML. The
# correctness risk is param-varying pages: the ETag MUST vary by the filter/sort
# params, or a conditional GET would serve a stale filtered view from cache.
class ConditionalGetTest < ActionDispatch::IntegrationTest
  # Replays the conditioning headers a client would send back, and asserts 304.
  def assert_not_modified_on_replay(url)
    get url
    assert_response :success
    etag = response.headers["ETag"]
    last_mod = response.headers["Last-Modified"]
    assert etag.present?, "expected an ETag on #{url}"
    assert last_mod.present?, "expected a Last-Modified on #{url}"

    get url, headers: { "If-None-Match" => etag, "If-Modified-Since" => last_mod }
    assert_response :not_modified
    [ etag, last_mod ]
  end

  test "models#index supports conditional GET" do
    assert_not_modified_on_replay(root_url)
  end

  test "models#index ETag varies by filter and sort params" do
    get root_url(sort: "input", dir: "desc")
    assert_response :success
    filtered_etag = response.headers["ETag"]

    # The first view's etag must NOT satisfy a request for a different view.
    get root_url(sort: "output", dir: "asc"),
        headers: { "If-None-Match" => filtered_etag }
    assert_response :success, "a different filter/sort must not 304 off another view's etag"

    # ...but replaying its own etag does 304.
    get root_url(sort: "input", dir: "desc"),
        headers: { "If-None-Match" => filtered_etag }
    assert_response :not_modified
  end

  test "models#index ETag varies between a Turbo-Frame and a full-page render" do
    # The full-page render includes the hero; the Turbo-Frame render skips it,
    # so the two responses to the SAME url differ. Their ETags must differ too,
    # or replaying one's If-None-Match on the other 304s off the wrong body.
    get root_url(tier: "frontier")
    assert_response :success
    full_etag = response.headers["ETag"]

    get root_url(tier: "frontier"), headers: { "Turbo-Frame" => "models" }
    assert_response :success
    frame_etag = response.headers["ETag"]

    assert_not_equal full_etag, frame_etag,
      "frame and full-page renders of the same url must not share an etag"

    # Replaying the full-page etag on a frame request must NOT 304.
    get root_url(tier: "frontier"),
        headers: { "Turbo-Frame" => "models", "If-None-Match" => full_etag }
    assert_response :success,
      "a frame request must not 304 off the full-page etag"
  end

  test "models#index ETag varies by query and provider params" do
    get root_url(q: "claude", providers: [ "anthropic" ])
    assert_response :success
    etag = response.headers["ETag"]

    get root_url(q: "deepseek", providers: [ "deepseek" ]),
        headers: { "If-None-Match" => etag }
    assert_response :success
  end

  test "models#show supports conditional GET keyed on the model's current price" do
    assert_not_modified_on_replay(model_url(ai_models(:opus)))
  end

  test "models#show etag invalidates on a same-day in-place price correction" do
    model = ai_models(:opus)
    get model_url(model)
    assert_response :success
    before_etag = response.headers["ETag"]

    # Correct the price in place: the value (and updated_at) change, but the
    # effective_on date stays the same. Keying on effective_on would serve a
    # stale 304; keying on the price point's updated_at must not.
    pp = model.current_price
    travel_to 1.hour.from_now do
      pp.update!(input_per_mtok: pp.input_per_mtok + 1) # same effective_on, new updated_at
    end

    get model_url(model), headers: { "If-None-Match" => before_etag }
    assert_response :success,
      "a same-day price correction must invalidate the show etag, not 304"
  end

  test "how_pricing_works supports conditional GET" do
    assert_not_modified_on_replay(how_pricing_works_url)
  end

  test "providers#show supports conditional GET" do
    assert_not_modified_on_replay(provider_url(providers(:anthropic)))
  end

  test "providers#show ETag varies by sort param" do
    get provider_url(providers(:anthropic), sort: "input")
    assert_response :success
    etag = response.headers["ETag"]

    get provider_url(providers(:anthropic), sort: "output"),
        headers: { "If-None-Match" => etag }
    assert_response :success
  end

  test "events supports conditional GET" do
    MarketEvent.create!(title: "A market event", event_date: Date.current,
                        kind: "market", status: "published")

    assert_not_modified_on_replay(events_url)
  end

  test "events still carries a Last-Modified with no market events yet" do
    # Without one the etag is fully static, so a client that cached the empty
    # timeline would 304 forever once events are published.
    MarketEvent.delete_all

    get events_url
    assert_response :success
    assert response.headers["Last-Modified"].present?,
      "expected a Last-Modified even when the timeline is empty"
  end

  test "events revalidates when a model changes — the shared footer counts them" do
    MarketEvent.create!(title: "A market event", event_date: Date.current,
                        kind: "market", status: "published")
    etag, last_mod = assert_not_modified_on_replay(events_url)

    # A plain touch can land in the same second as the request above, and
    # Last-Modified only has second granularity — so stamp it unambiguously.
    ai_models(:opus).update_column(:updated_at, 1.minute.from_now)

    get events_url, headers: { "If-None-Match" => etag, "If-Modified-Since" => last_mod }
    assert_response :success, "a model edit must bust /events — the footer renders AiModel.listed.count"
  end

  test "events revalidates on an If-None-Match alone once an event is published" do
    # strict_freshness (config.load_defaults 8.1) makes the etag the sole
    # validator when If-None-Match is sent, so the freshness stamp has to be in
    # the etag key. Without it a client that cached the empty timeline — a real
    # browser walking the site, as the system tests do — never sees a new event.
    MarketEvent.delete_all

    get events_url
    etag = response.headers["ETag"]

    event = MarketEvent.create!(title: "First published event", event_date: Date.current,
                                kind: "market", status: "published")
    # The stamp reaches the etag through Array#to_s, which renders a Time to the
    # second — so an event created in the same second as the fixtures' newest
    # row leaves the key unchanged. Stamp it forward rather than race the clock.
    event.update_column(:updated_at, 1.minute.from_now)

    get events_url, headers: { "If-None-Match" => etag }
    assert_response :success
    assert_select ".ev-title", text: /First published event/
  end

  # Every page here keys its etag on request params — category, sort, slug — and
  # none of them carry data. With strict_freshness (config.load_defaults 8.1) a
  # request carrying If-None-Match is validated on the etag ALONE, so before
  # catalog_fresh? folded the freshness stamp in, a browser would 304 off its
  # cached copy indefinitely no matter how far the catalog had moved on.
  CACHED_PAGES = {
    "models#index"    => -> { root_url },
    "models#show"     => -> { model_url(ai_models(:opus)) },
    "providers#show"  => -> { provider_url(providers(:anthropic)) },
    "price_changes"   => -> { price_changes_url },
    "how_pricing_works" => -> { how_pricing_works_url },
    "learn#reasoning" => -> { learn_reasoning_url },
    "events"          => -> { events_url }
  }.freeze

  test "a catalog write revalidates every conditional-GET page on an If-None-Match alone" do
    etags = CACHED_PAGES.transform_values do |url|
      get instance_exec(&url)
      assert_response :success
      response.headers["ETag"]
    end

    # A price-row write is what PriceCatalog.last_modified tracks, and it feeds
    # every page's stamp. Stamped forward because the etag renders the Time to
    # the second — a same-second touch would leave the key unchanged.
    price_points(:opus_launch).update_column(:updated_at, 1.minute.from_now)

    CACHED_PAGES.each do |name, url|
      get instance_exec(&url), headers: { "If-None-Match" => etags[name] }
      assert_response :success, "#{name} must revalidate after a catalog write, not 304 off a stale etag"
    end
  end

  test "each cached page still 304s when nothing has changed" do
    # The other half of the contract: folding data into the etag must not make
    # every request a miss, or conditional GET stops buying anything.
    CACHED_PAGES.each do |name, url|
      resolved = instance_exec(&url)
      get resolved
      assert_response :success

      get resolved, headers: { "If-None-Match" => response.headers["ETag"] }
      assert_response :not_modified, "#{name} should still 304 when the catalog is unchanged"
    end
  end

  test "a provider write revalidates every page — the shared footer counts them" do
    # Most pages key last_modified on PriceCatalog.last_modified, which is
    # PricePoint.maximum(:updated_at) — a provider or model row write doesn't
    # move it. The footer counts both on every page, so the etag has to.
    etags = CACHED_PAGES.transform_values do |url|
      get instance_exec(&url)
      assert_response :success
      response.headers["ETag"]
    end

    # Stamped forward because the etag renders a Time to the second: a provider
    # created in the same second as the fixtures leaves the key unchanged.
    Provider.create!(name: "Probe", slug: "probe").update_column(:updated_at, 1.minute.from_now)

    CACHED_PAGES.each do |name, url|
      get instance_exec(&url), headers: { "If-None-Match" => etags[name] }
      assert_response :success, "#{name} must revalidate after a provider write — its footer counts providers"
    end
  end

  test "every page revalidates across a day rollover" do
    # The layout stamps "prices synced <Date.current>" on every page, and
    # /changes renders a rolling 30-day window. Both move on the clock, not on a
    # write, so a quiet catalog would otherwise 304 a stale date indefinitely.
    etags = CACHED_PAGES.transform_values do |url|
      get instance_exec(&url)
      assert_response :success
      response.headers["ETag"]
    end

    travel 1.day do
      CACHED_PAGES.each do |name, url|
        get instance_exec(&url), headers: { "If-None-Match" => etags[name] }
        assert_response :success, "#{name} must revalidate once the date it prints has changed"
      end
    end
  end
end
