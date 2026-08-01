require "test_helper"

class ModelsControllerTest < ActionDispatch::IntegrationTest
  test "index lists models" do
    get root_url
    assert_response :success
    assert_select "h1", /LLM API pricing, tracked from launch/
    assert_select "tbody td", /Claude Opus 4.8/
  end

  test "the homepage no longer carries the recent price changes strip" do
    get root_url
    assert_response :success
    assert_select "section.changes", count: 0
  end

  test "hero is the price-index hero with a pricing-explainer CTA and a trends CTA" do
    get root_url
    assert_response :success
    # Primary CTA into the pricing explainer.
    assert_select ".hero-cta a[href=?]", how_pricing_works_path, text: /How pricing works/
  end

  test "hero subtitle renders the dynamic category and provider counts, never a static 40+" do
    get root_url
    assert_response :success
    language_count = AiModel.listed.to_a.count { |m| ModelCategory.for("language").member?(m.modality_class) }
    assert_select ".hero-sub", /language models across/
    assert_select ".hero-sub .num", text: language_count.to_s
    assert_select ".hero-sub", text: /40\+/, count: 0
  end

  test "each category tab renders its own hero heading, not the language one" do
    get image_generation_url
    assert_response :success
    assert_select "h1.hero-h1", text: ModelCategory.for("image").hero_heading
    assert_select "h1", text: /LLM API pricing, tracked from launch/, count: 0
    assert_select ".hero-eyebrow", /director|dated/i
  end

  test "directory hero subhead counts that category's models, not the whole catalog" do
    get image_generation_url
    assert_response :success
    image_count = AiModel.listed.to_a.count { |m| ModelCategory.for("image").member?(m.modality_class) }
    assert_operator image_count, :>, 0
    assert_select ".hero-sub .num", text: image_count.to_s
    assert_select ".hero-sub", /image models/
  end

  test "directory tabs route the hero CTA to sources, language to the pricing explainer" do
    get image_generation_url
    assert_select ".hero-cta a[href=?]", sources_path
    get root_url
    assert_select ".hero-cta a[href=?]", how_pricing_works_path
  end

  test "directory tables surface each price's as-of date" do
    get image_generation_url
    assert_response :success
    assert_select ".tp-price-asof", text: /2026/
  end

  # --- Model show: journey fixes (PR2) ---

  test "an image model's breadcrumb returns to the image tab, not the language table" do
    get model_url("test-priced-image-model")
    assert_response :success
    assert_select "nav[aria-label=Breadcrumb] a[href=?]", image_generation_path, text: /Image generation/
    assert_select "nav[aria-label=Breadcrumb] a", text: /All models/, count: 0
  end

  test "a language model's breadcrumb returns to the root models table" do
    get model_url("claude-opus-4-8")
    assert_response :success
    assert_select "nav[aria-label=Breadcrumb] a[href=?]", root_path
  end

  test "an untracked video model's pricing fallback names its native unit, not per image" do
    get model_url("test-unpriced-video-model")
    assert_response :success
    assert_match(/per second/i, @response.body)
    assert_no_match(/priced per image/i, @response.body)
  end

  test "model-show JSON-LD category uses the modality label, not a hardcoded LLM label" do
    get model_url("test-priced-image-model")
    assert_response :success
    assert_no_match(/"category":"LLM API model"/, @response.body)
    assert_match(/"category":"Image generation model"/, @response.body)
  end

  test "index emits an owned meta description targeting the head term and providers" do
    get root_url
    assert_response :success
    # An owned description, not the layout default fallback.
    assert_select "meta[name=description][content*=?]", "LLM API token prices"
    assert_select "meta[name=description][content*=?]", "Claude"
    assert_select "meta[name=description][content*=?]", "updated daily"
  end

  test "latest-events widget is present and the market-event timeline strip is gone" do
    get root_url
    assert_response :success
    assert_select ".hero-card-tag", /Latest events/
    # Dropped per audit #6: the thin, redundant market-event strip.
    assert_select ".hero-timeline", count: 0
    assert_select ".hero-card", text: /Recent activity/, count: 0
  end

  test "hero card has exactly one primary call to action" do
    get root_url
    assert_response :success
    # The CTA always links to the events timeline; there is exactly one.
    assert_select ".hero-card a.tp-btn", count: 1
  end

  test "hero renders a mini-timeline of several recent events, not just one" do
    3.times do |i|
      MarketEvent.create!(title: "Event #{i}", event_date: Date.current - i,
                          kind: "market", status: "published")
    end

    get root_url
    assert_response :success
    # The headline event plus a row per runner-up, so the hero doesn't have to
    # pick a single "winner" among recent events.
    assert_select ".hero-card .hero-card-timeline-row" do |rows|
      assert_operator rows.size, :>, 1
    end
  end

  test "hero CTA always routes to the events timeline" do
    # A market event newer than every fixture release becomes the primary
    # (model-less) event; the CTA should still route to /events regardless.
    MarketEvent.create!(title: "Newest market event", event_date: Date.new(2026, 6, 10),
                        kind: "market", status: "published", note: "A note.")

    get root_url
    assert_response :success
    assert_select ".hero-card a.tp-btn[href=?]", events_path, text: /View timeline/
  end

  test "hero shows market events only — no model releases, and there is no ticker" do
    # No fixture file exists for the market_events table, so create one directly.
    MarketEvent.create!(title: "Test market event", event_date: Date.current,
                        kind: "market", status: "published", note: "A note.")
    ai_models(:opus).update!(released_on: Date.current)

    get root_url
    assert_response :success
    assert_select ".hero-card .hero-card-title", text: /Test market event/
    # A model release is not an event: neither its title nor a link to it.
    assert_select ".hero-card", text: /released/, count: 0
    assert_select ".hero-card a[href=?]", model_path(ai_models(:opus)), count: 0
    # Price changes aren't surfaced as events anywhere, so no ticker banner.
    assert_select ".tp-ticker", count: 0
  end

  test "hero renders nothing but the empty card when there are no market events" do
    MarketEvent.delete_all

    get root_url
    assert_response :success
    assert_select ".hero-card"
    assert_select ".hero-card .hero-card-headline", count: 0
    assert_select ".hero-card a.tp-btn[href=?]", events_path
  end

  test "the hero (and its price-change feed) is skipped on Turbo Frame refreshes" do
    get root_url, headers: { "Turbo-Frame" => "models" }
    assert_response :success
    assert_select ".hero-card", count: 0
  end

  test "footer carries the deck sourcing disclaimer" do
    get root_url
    assert_response :success
    assert_select ".tp-foot",
      text: /Sourced from provider price pages · costs are per-call estimates, never a monthly bill/
  end

  test "the beta flag is gone from the chrome" do
    get root_url
    assert_response :success
    assert_select ".tp-beta", count: 0
    assert_select ".tp-foot-beta", count: 0
    assert_no_match(/data is still being sense-checked/, response.body)
  end

  test "index can be sorted" do
    get root_url(sort: "output", dir: "desc")
    assert_response :success
  end

  test "the homepage table has no price-change column" do
    get root_url
    assert_response :success
    assert_select "th", text: /Δ input/i, count: 0
  end

  test "index can be filtered to a single provider" do
    get root_url(providers: [ "anthropic" ])
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /DeepSeek/, count: 0
  end

  test "index can be filtered to multiple providers" do
    get root_url(providers: [ "anthropic", "deepseek" ])
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /DeepSeek V4 Pro/
  end

  test "index accepts a scalar providers param" do
    get root_url(providers: "anthropic")
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /DeepSeek/, count: 0
  end

  test "index ignores a hash-shaped providers param" do
    get root_url(providers: { evil: "payload" })
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /DeepSeek V4 Pro/
  end

  test "index ignores unknown provider slugs" do
    get root_url(providers: [ "not-a-provider" ])
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
  end

  test "index treats punctuation-only queries as no filter" do
    get root_url(q: "!!!")
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /DeepSeek V4 Pro/
  end

  test "index never lists retired models, even when searched for" do
    get root_url
    assert_select "tbody td", text: /Claude Instant/, count: 0

    get root_url(q: "instant")
    assert_select "td", /No models match your filters/
  end

  test "sort links carry the active filters and sort state rides in the form" do
    get root_url(q: "claude", providers: [ "anthropic" ], sort: "input", dir: "asc")
    assert_response :success
    assert_select "thead a[href*='q=claude']"
    assert_select "thead a[href*='providers%5B%5D=anthropic']"
    assert_select "input[type=hidden][name=sort][value=input][form=filters]", count: 1
    assert_select "input[type=hidden][name=dir][value=asc][form=filters]", count: 1
  end

  test "default sort state is omitted from the filter form" do
    get root_url
    assert_select "input[type=hidden][name=sort]", count: 0
    assert_select "input[type=hidden][name=dir]", count: 0
  end

  test "frame navigation is scoped so row links break out of the frame" do
    get root_url
    assert_select "turbo-frame#models[target=_top]", count: 1
    assert_select "thead a[data-turbo-frame=models]", count: 6
    assert_select "form#filters[data-turbo-frame=models]", count: 1
  end

  test "index can be searched" do
    get root_url(q: "deepseek")
    assert_select "tbody td", text: /DeepSeek V4 Pro/
    assert_select "tbody td", text: /Claude/, count: 0
  end

  test "index search tolerates typos" do
    get root_url(q: "antropic")
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /DeepSeek/, count: 0
  end

  test "index shows an empty state when nothing matches" do
    get root_url(q: "zzzzzz")
    assert_response :success
    assert_select "td", /No models match your filters/
  end

  test "index caps pathological search queries" do
    get root_url(q: "abc " * 2_000)
    assert_response :success
  end

  test "search and provider filters combine" do
    get root_url(q: "opus", providers: [ "deepseek" ])
    assert_select "td", /No models match your filters/
  end

  test "index can be filtered to multimodal models" do
    get root_url(modality: "multimodal")
    assert_response :success
    # The Sonnet fixture is multimodal (text, image in → text out).
    assert_select "tbody td", text: /Guide Sonnet Fixture/
    # Text-only models drop out of a multimodal-only view.
    assert_select "tbody td", text: /DeepSeek V4 Pro/, count: 0
    assert_select "tbody td", text: /Claude Opus 4.8/, count: 0
  end

  test "index ignores an unknown modality filter" do
    get root_url(modality: "not-a-class")
    assert_response :success
    assert_select "tbody td", text: /Guide Sonnet Fixture/
    assert_select "tbody td", text: /DeepSeek V4 Pro/
  end

  test "index only offers modality facets present among the current category" do
    get root_url
    assert_response :success
    # The language tab offers the classes its listed rows have — text and the
    # multimodal sonnet — but not image_generation (now its own tab) nor a class
    # no listed row has (video_generation).
    assert_select "input[value=multimodal][name=?]", "modality[]"
    assert_select "input[value=image_generation][name=?]", "modality[]", count: 0
    assert_select "input[value=video_generation][name=?]", "modality[]", count: 0
  end

  test "the index renders a category tab strip with all families and their counts, language active" do
    get root_url
    assert_response :success
    assert_select ".tp-tabs .tp-tab", count: 7
    assert_select ".tp-tabs .tp-tab", text: /Language models/
    assert_select ".tp-tabs .tp-tab", text: /Embeddings/
    assert_select ".tp-tabs .tp-tab", text: /Rerank/
    assert_select ".tp-tabs .tp-tab", text: /Speech to text/
    assert_select ".tp-tabs .tp-tab", text: /Text to speech/
    assert_select ".tp-tabs .tp-tab", text: /Image generation/
    assert_select ".tp-tabs .tp-tab", text: /Video generation/
    # The current tab is the language one and carries aria-current.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Language models/
    language = ModelCategory.for("language")
    language_count = AiModel.listed.count { |m| language.member?(m.modality_class) }
    assert_select ".tp-tabs .tp-tab[aria-current=page] .tp-tab-count", text: language_count.to_s
  end

  test "the image tab swaps in a Pricing column and drops the per-token headers" do
    get image_generation_url
    assert_response :success
    assert_select "thead th", text: /Pricing/
    assert_select "thead th", text: %r{Input /1M}, count: 0
    assert_select "thead th", text: /Context/, count: 0
    # The image tab is the current page.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Image generation/
    # A natively-priced image row shows its curated per-image summary.
    assert_select "tbody td", text: %r{\$0\.04 / image}
  end

  test "the language tab keeps the per-token headers and has no Pricing column" do
    get root_url
    assert_response :success
    assert_select "thead th", text: %r{Input /1M}
    assert_select "thead th", text: /Pricing/, count: 0
  end

  test "the language tab renders a sortable Released column with each model's release date" do
    get root_url
    assert_response :success
    assert_select "thead a[href*='sort=released']", text: /Released/
    # Opus fixture is released_on 2026-05-28, formatted "%b %Y".
    assert_select "tbody td[data-label=Released]", text: /May 2026/
  end

  test "the language tab sorts by released" do
    # Ascending: DeepSeek V4 Pro (2026-02-01) is the earliest listed release.
    get root_url(sort: "released", dir: "asc")
    assert_response :success
    assert_select "tbody tr:first-child .tp-model-name", text: /DeepSeek V4 Pro/

    # Descending: Claude Fable 5 (2026-06-09) is the latest.
    get root_url(sort: "released", dir: "desc")
    assert_response :success
    assert_select "tbody tr:first-child .tp-model-name", text: /Claude Fable 5/
  end

  test "image-tab sort links stay on the image path and sorting by name returns 200" do
    get image_generation_url
    assert_response :success
    # Every sortable header links back to the image path, not the root tab.
    assert_select "thead a[href*=?]", "/image-generation"
    assert_select "thead a[href*='sort=provider'][href*='/image-generation']"

    get image_generation_url(sort: "name", dir: "asc")
    assert_response :success
    assert_select "tbody td", text: /Test Image Model/
  end

  test "the image tab keeps search and provider facets" do
    get image_generation_url
    assert_response :success
    assert_select ".tp-search input#q", count: 1
    assert_select ".tp-facet-chip-label", text: "Provider"
  end

  test "the image tab lists image-generation models" do
    get image_generation_url
    assert_response :success
    assert_select "tbody td", text: /Test Image Model/
    # Text and multimodal rows live on the language tab, not here.
    assert_select "tbody td", text: /DeepSeek V4 Pro/, count: 0
    assert_select "tbody td", text: /Guide Sonnet Fixture/, count: 0
  end

  test "the image tab shows a directory listing's price as not yet tracked, never a dash or $0" do
    get image_generation_url
    assert_response :success
    assert_select "td.tp-price-untracked", text: /not yet tracked/i
  end

  test "the image tab renders a natively-priced image row's price summary, not the untracked note" do
    get image_generation_url
    assert_response :success
    # The curated per-image price shows as a real value in the row.
    assert_select "td", text: /\$0\.04 \/ image/
    assert_select "td:match('class', ?)", /tp-price-untracked/, text: /\$0\.04 \/ image/, count: 0
  end

  test "the image tab still shows a price-less image row as not yet tracked" do
    get image_generation_url
    assert_response :success
    assert_select "td.tp-price-untracked", text: /not yet tracked/i
  end

  test "the language tab (root) excludes image-generation and embedding models" do
    get root_url
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "tbody td", text: /Guide Sonnet Fixture/
    # Image, embedding, speech-to-text, text-to-speech and video rows moved to
    # their own tabs.
    assert_select "tbody td", text: /Test Image Model/, count: 0
    assert_select "tbody td", text: /Test Priced Image Model/, count: 0
    assert_select "tbody td", text: /Test Embedding Model/, count: 0
    assert_select "tbody td", text: /Test Transcribe/, count: 0
    assert_select "tbody td", text: /Test Speak/, count: 0
    assert_select "tbody td", text: /Test Video Model/, count: 0
    assert_select "tbody td", text: /Test Unpriced Video Model/, count: 0
  end

  test "the embeddings tab lists embedding models with an input and dimensions column, no output or pricing" do
    get embeddings_url
    assert_response :success
    # The input-only embedding row lists here, priced per input token.
    assert_select "tbody td", text: /Test Embedding Model/
    assert_select "thead th", text: %r{Input /1M}
    assert_select "thead th", text: /Dimensions/
    # Embeddings have no output/cached rate and no native pricing column.
    assert_select "thead th", text: %r{Output /1M}, count: 0
    assert_select "thead th", text: /Pricing/, count: 0
    # Its vector dimensions render in the row.
    assert_select "tbody td", text: /1536/
    # Text and image rows live on their own tabs, not here.
    assert_select "tbody td", text: /Claude Opus 4.8/, count: 0
    assert_select "tbody td", text: /Test Image Model/, count: 0
    # The embeddings tab is the current page.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Embeddings/
  end

  test "the embeddings tab canonicalizes to its own path and carries embedding SEO" do
    get embeddings_url
    assert_response :success
    assert_select "link[rel=canonical][href=?]", embeddings_url
    assert_select "title", /embedding/i
    assert_select "meta[name=description][content*=?]", "input token"
  end

  test "the embeddings tab keeps search and provider facets" do
    get embeddings_url
    assert_response :success
    assert_select ".tp-search input#q", count: 1
    assert_select ".tp-facet-chip-label", text: "Provider"
  end

  test "the rerank tab lists rerankers with a Pricing column in native units, no per-token headers" do
    get rerank_url
    assert_response :success
    assert_select "tbody td", text: /Test Rerank/
    assert_select "thead th", text: /Pricing/
    assert_select "thead th", text: %r{Input /1M}, count: 0
    assert_select "thead th", text: /Context/, count: 0
    # The curated per-search price shows as a real value (image-style summary).
    assert_select "tbody td", text: %r{\$2\.00 / 1K searches}
    # Embedding, text and image rows live on their own tabs, not here.
    assert_select "tbody td", text: /Test Embedding Model/, count: 0
    assert_select "tbody td", text: /Claude Opus 4.8/, count: 0
    # The rerank tab is the current page.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Rerank/
  end

  test "the rerank tab canonicalizes to its own path and carries reranker SEO" do
    get rerank_url
    assert_response :success
    assert_select "link[rel=canonical][href=?]", rerank_url
    assert_select "title", /rerank/i
    assert_select "meta[name=description][content*=?]", "per search"
  end

  test "the rerank tab keeps search and provider facets" do
    get rerank_url
    assert_response :success
    assert_select ".tp-search input#q", count: 1
    assert_select ".tp-facet-chip-label", text: "Provider"
  end

  test "embeddings-tab sort links stay on the embeddings path and default to cheapest input" do
    get embeddings_url
    assert_response :success
    assert_select "thead a[href*=?]", "/embeddings"
    # Default is cheapest input first, so no sort/dir ride in the filter form.
    assert_select "input[type=hidden][name=sort]", count: 0

    get embeddings_url(sort: "input", dir: "asc")
    assert_response :success
    assert_select "tbody td", text: /Test Embedding Model/
  end

  test "the speech-to-text tab lists transcription models with a per-minute Price column, no per-token headers" do
    get speech_to_text_url
    assert_response :success
    assert_select "tbody td", text: /Test Transcribe/
    assert_select "thead th", text: /Price/
    assert_select "thead th", text: %r{Input /1M}, count: 0
    assert_select "thead th", text: %r{Output /1M}, count: 0
    assert_select "thead th", text: /Context/, count: 0
    # The native per-minute rate renders through price_headline.
    assert_select "tbody td", text: %r{\$0\.006 /min}
    # Text, embedding and image rows live on their own tabs, not here.
    assert_select "tbody td", text: /Claude Opus 4.8/, count: 0
    assert_select "tbody td", text: /Test Embedding Model/, count: 0
    assert_select "tbody td", text: /Test Image Model/, count: 0
    # The speech-to-text tab is the current page.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Speech to text/
  end

  test "the speech-to-text tab canonicalizes to its own path and carries transcription SEO" do
    get speech_to_text_url
    assert_response :success
    assert_select "link[rel=canonical][href=?]", speech_to_text_url
    assert_select "title", /speech-to-text/i
    assert_select "meta[name=description][content*=?]", "per minute"
  end

  test "speech-to-text sort links stay on its path and default to cheapest per minute" do
    get speech_to_text_url
    assert_response :success
    assert_select "thead a[href*=?]", "/speech-to-text"
    # Cheapest per minute is the default, so no sort/dir ride in the filter form.
    assert_select "input[type=hidden][name=sort]", count: 0

    get speech_to_text_url(sort: "native_price", dir: "asc")
    assert_response :success
    assert_select "tbody td", text: /Test Transcribe/
  end

  test "the speech-to-text tab keeps search and provider facets" do
    get speech_to_text_url
    assert_response :success
    assert_select ".tp-search input#q", count: 1
    assert_select ".tp-facet-chip-label", text: "Provider"
  end

  test "the video tab lists video models with a Pricing column, no per-token headers" do
    get video_generation_url
    assert_response :success
    assert_select "tbody td", text: /Test Video Model/
    assert_select "thead th", text: /Pricing/
    assert_select "thead th", text: %r{Input /1M}, count: 0
    assert_select "thead th", text: /Context/, count: 0
    # The curated per-second price shows as a real value (image-style summary).
    assert_select "tbody td", text: %r{\$0\.05 / sec}
    # A price-less video row reads "not yet tracked", never a dash or $0.
    assert_select "td.tp-price-untracked", text: /not yet tracked/i
    # Text, embedding and image rows live on their own tabs, not here.
    assert_select "tbody td", text: /Claude Opus 4.8/, count: 0
    assert_select "tbody td", text: /Test Image Model/, count: 0
    # The video tab is the current page.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Video generation/
  end

  test "the video tab canonicalizes to its own path and carries video SEO" do
    get video_generation_url
    assert_response :success
    assert_select "link[rel=canonical][href=?]", video_generation_url
    assert_select "title", /video/i
    assert_select "meta[name=description][content*=?]", "per second"
  end

  test "video-tab sort links stay on the video path and sorting by name returns 200" do
    get video_generation_url
    assert_response :success
    assert_select "thead a[href*=?]", "/video-generation"

    get video_generation_url(sort: "name", dir: "asc")
    assert_response :success
    assert_select "tbody td", text: /Test Video Model/
  end

  test "the video tab keeps search and provider facets" do
    get video_generation_url
    assert_response :success
    assert_select ".tp-search input#q", count: 1
    assert_select ".tp-facet-chip-label", text: "Provider"
  end

  test "the text-to-speech tab lists synthesis models with a per-1M-char Price column, no per-token headers" do
    get text_to_speech_url
    assert_response :success
    assert_select "tbody td", text: /Test Speak/
    assert_select "thead th", text: /Price/
    assert_select "thead th", text: %r{Input /1M}, count: 0
    assert_select "thead th", text: /Context/, count: 0
    # The native per-1M-char rate renders through price_headline.
    assert_select "tbody td", text: %r{\$15\.00 /1M chars}
    # Transcription, embedding and image rows live on their own tabs, not here.
    assert_select "tbody td", text: /Test Transcribe/, count: 0
    assert_select "tbody td", text: /Claude Opus 4.8/, count: 0
    # The text-to-speech tab is the current page.
    assert_select ".tp-tabs .tp-tab[aria-current=page]", text: /Text to speech/
  end

  test "the text-to-speech tab canonicalizes to its own path and carries synthesis SEO" do
    get text_to_speech_url
    assert_response :success
    assert_select "link[rel=canonical][href=?]", text_to_speech_url
    assert_select "title", /text-to-speech/i
    assert_select "meta[name=description][content*=?]", "per 1M characters"
  end

  test "text-to-speech sort links stay on its path and default to cheapest per 1M chars" do
    get text_to_speech_url
    assert_response :success
    assert_select "thead a[href*=?]", "/text-to-speech"
    assert_select "input[type=hidden][name=sort]", count: 0

    get text_to_speech_url(sort: "native_price", dir: "asc")
    assert_response :success
    assert_select "tbody td", text: /Test Speak/
  end

  test "the text-to-speech tab keeps search and provider facets" do
    get text_to_speech_url
    assert_response :success
    assert_select ".tp-search input#q", count: 1
    assert_select ".tp-facet-chip-label", text: "Provider"
  end

  test "a stale modality param outside the current tab is ignored, not a dead empty table" do
    # /?modality=image_generation used to list image rows; they now have their own
    # tab. On the language tab that modality doesn't apply, so it's dropped rather
    # than filtering every language row out into a 'no models match' state.
    get root_url(modality: "image_generation")
    assert_response :success
    assert_select "tbody td", text: /Claude Opus 4.8/
    assert_select "td", text: /No models match your filters/, count: 0
  end

  test "the result count denominator is the current tab's total, not the whole catalog" do
    get root_url
    assert_response :success
    language_total = AiModel.listed.count { |m| ModelCategory.for("language").member?(m.modality_class) }
    assert_operator language_total, :<, AiModel.listed.count, "fixtures must include image rows for this to be meaningful"
    assert_select ".result-count", text: /of #{language_total}\b/
  end

  test "the image tab canonicalizes to the image path and carries image-specific SEO" do
    get image_generation_url
    assert_response :success
    assert_select "link[rel=canonical][href=?]", image_generation_url
    assert_select "title", /Image generation/
    assert_select "meta[name=description][content*=?]", "per image"
  end

  test "the image tab sorts by name and falls back to its default for a token-price sort" do
    get image_generation_url(sort: "name", dir: "asc")
    assert_response :success
    assert_select "tbody td", text: /Test Image Model/

    # "input" is a language-only sort; on the image tab it is not offered, so it
    # falls back to the category default rather than erroring.
    get image_generation_url(sort: "input")
    assert_response :success
    assert_select "tbody td", text: /Test Image Model/
  end

  test "the language and image tabs do not share a conditional-GET cache key" do
    get root_url
    assert_response :success
    language_etag = @response.headers["ETag"]

    get image_generation_url
    assert_response :success
    image_etag = @response.headers["ETag"]

    assert_not_equal language_etag, image_etag,
      "category tabs must not collide on one conditional-GET cache key"
  end

  test "index renders a modality badge on multimodal rows only" do
    get root_url
    assert_response :success
    assert_select ".tp-modality-badge", minimum: 1
  end

  test "the modality filter rides in the etag so filtered views do not share a 304" do
    get root_url(modality: "multimodal")
    assert_response :success
    multimodal_etag = @response.headers["ETag"]

    get root_url(modality: "text")
    assert_response :success
    text_etag = @response.headers["ETag"]

    assert_not_equal multimodal_etag, text_etag,
      "different modality filters must not collide on one conditional-GET cache key"
  end

  test "show renders the modality badge for a multimodal model" do
    get model_url(ai_models(:sonnet))
    assert_response :success
    assert_select ".tp-modality-badge", text: "Multimodal"
  end

  test "show omits the modality badge for a plain text model" do
    get model_url(ai_models(:opus))
    assert_response :success
    assert_select ".tp-modality-badge", count: 0
  end

  test "show renders a directory listing with a not-yet-tracked note and no price history" do
    get model_url(ai_models(:image_gen))
    assert_response :success
    assert_select ".tp-modality-badge", text: "Image generation"
    assert_select "p", text: /Priced per image — not yet tracked/
    # No per-token price cards and no price-history section for a price-less row.
    assert_select "h2", text: "Price history", count: 0
  end

  test "show meta description reflects a native-priced image model, not empty token prices" do
    get model_url(ai_models(:image_priced))
    assert_response :success
    # The directory_listing? re-key must not drop these rows to the per-token
    # description branch, which would emit "— input / — output per 1M tokens".
    assert_select "meta[name=description]" do |tags|
      content = tags.first["content"]
      assert_includes content, "$0.04 / image"
      assert_not_includes content, "per 1M tokens"
      assert_not_includes content, "—"
    end
  end

  test "show renders a natively-priced image model with its price summary, label and source, but no price history" do
    model = ai_models(:image_priced)
    get model_url(model)
    assert_response :success
    assert_select "*", text: /\$0\.04 \/ image/
    assert_select "*", text: /Per image/
    assert_select "*", text: /example\.com\/pricing/
    # A curated native price still isn't a per-token history.
    assert_select "h2", text: "Price history", count: 0
    assert_select "p", text: /Priced per image — not yet tracked/, count: 0
  end

  test "show renders a model and its price history chart" do
    get model_url(ai_models(:deepseek_v4))
    assert_response :success
    assert_select "h1", "DeepSeek V4 Pro"
    assert_select "svg"
  end

  test "show mounts the interactive price-chart controller with its data" do
    # The chart is progressively enhanced: the controller plus the serialized
    # price points (for the hover crosshair/tooltip) ride on the container.
    get model_url(ai_models(:deepseek_v4))
    assert_response :success
    assert_select "[data-controller~='price-chart']" do
      assert_select "[data-price-chart-target='overlay']"
      assert_select "[data-price-chart-target='tooltip']"
    end
    # The points value carries the dated price labels the tooltip renders.
    assert_select "[data-price-chart-points-value*='date']"
  end

  test "show always renders the chart, even with a single price on record" do
    # Opus has one price point. The chart must still render as an SVG rather
    # than falling back to a 'appears once a price changes' message.
    model = ai_models(:opus)
    assert_equal 1, model.price_points.size, "fixture should have a lone price point"
    get model_url(model)
    assert_response :success
    assert_select "svg"
    assert_no_match(/appears once a price changes/, @response.body)
    # With a single point no lines are drawn, so the solid/dashed legend is
    # withheld — it would describe line styles that aren't on the chart.
    assert_select "span", text: /Input \(solid\)/, count: 0
  end

  test "show lists the extra billed dimensions with their units when present" do
    get model_url(ai_models(:sonnet))
    assert_response :success
    assert_select ".tp-also-billed" do
      assert_select "*", text: /Cache write/
      assert_select "*", text: /Image input/
      assert_select "*", text: %r{/ image}
      assert_select "*", text: %r{/ 1M}
    end
  end

  test "show omits the also-billed block for a model with no extra dimensions" do
    get model_url(ai_models(:opus))
    assert_response :success
    assert_select ".tp-also-billed", count: 0
  end

  test "show stamps when the model data was last updated" do
    model = ai_models(:opus)
    get model_url(model)
    assert_response :success
    freshness = [ model.current_price&.updated_at, model.updated_at ].compact.max
    assert_select "time[datetime=?]", freshness.iso8601, text: /Data updated/
  end

  test "show offers a report link prefilled with the model context" do
    model = ai_models(:opus)
    get model_url(model)
    assert_response :success
    assert_select "a[href^=?]", "mailto:#{ApplicationHelper::REPORT_EMAIL}", text: "Report a problem" do
      assert_select ":match('href', ?)", "data%20issue%3A%20#{ERB::Util.url_encode(model.name)}"
    end
  end

  test "show emits a self-canonical link that ignores query params" do
    get model_url(ai_models(:opus), ref: "twitter")
    assert_response :success
    assert_select "link[rel=canonical][href=?]", model_url(ai_models(:opus))
  end

  test "show returns 404 for an unknown slug" do
    get model_url(id: "does-not-exist")
    assert_response :not_found
  end

  test "index emits a canonical link and JSON-LD" do
    get root_url(sort: "input", dir: "desc")
    assert_response :success
    assert_select "link[rel=canonical]", count: 1
    assert_select "script[type='application/ld+json']", minimum: 1
  end

  test "index canonicalizes every filtered/sorted state to the bare root URL" do
    get root_url(sort: "input", dir: "desc")
    assert_response :success
    assert_select "link[rel=canonical][href=?]", root_url
  end

  test "show emits Product JSON-LD" do
    get model_url(ai_models(:opus))
    assert_select "script[type='application/ld+json']", minimum: 1
    assert_includes @response.body, "\"@type\":\"Product\""
  end

  test "show emits an AggregateOffer spanning input and output prices" do
    model = ai_models(:opus) # input 5, output 25, cached 0.5 per 1M tokens
    get model_url(model)
    assert_response :success

    body = @response.body
    assert_includes body, "\"@type\":\"AggregateOffer\""
    assert_includes body, "\"priceCurrency\":\"USD\""
    # offerCount is derived from the non-nil price set: input + output + cached = 3.
    assert_includes body, "\"offerCount\":3"
    # lowPrice = min over the priced set, highPrice = max over the same set.
    assert_includes body, "\"lowPrice\":\"#{model.current_cached_input}\""
    assert_includes body, "\"highPrice\":\"#{model.current_output}\""
    # Availability carried over from the old single Offer.
    assert_includes body, "\"availability\":\"https://schema.org/InStock\""
    # The unit (per 1M tokens) must be expressed so the price isn't ambiguous.
    assert_match(/per 1M tokens/i, body)
    # No stale single-Offer price field that hid the output cost.
    assert_not_includes body, "\"@type\":\"Offer\""
  end

  test "show AggregateOffer drops the nil cached component from count and breakdown" do
    # A model with input + output but NO cached input (the only nilable price
    # column): the cached component must be absent from offerCount and from the
    # price breakdown, and no non-numeric em-dash placeholder (from usd_plain(nil))
    # may land in the structured-data price text.
    model = ai_models(:opus)
    model.current_price.update!(cached_input_per_mtok: nil)
    get model_url(model)
    assert_response :success

    all_ld = @response.body.scan(/<script type="application\/ld\+json">(.+?)<\/script>/m).map(&:first)
    json_ld = all_ld.find { |s| s.include?('"Product"') }
    assert json_ld, "expected Product JSON-LD on the show page"
    # input + output only (cached dropped) → offerCount 2.
    assert_includes json_ld, "\"offerCount\":2"
    # The dropped cached component must not appear at all in the breakdown.
    assert_not_includes json_ld, "cached input"
    # No em-dash placeholder for a nil price value in the breakdown text.
    assert_not_includes json_ld, "input —"
    assert_not_includes json_ld, "—\""
  end

  test "show renders the three per-token cards for a text model unchanged" do
    get model_url(ai_models(:opus))
    assert_response :success
    assert_select "p", text: /Input \/ 1M/
    assert_select "p", text: /Output \/ 1M/
    assert_select "p", text: /Cached input \/ 1M/
  end

  test "show renders the release date visibly, not just in JSON-LD" do
    model = ai_models(:opus) # released_on 2026-05-28
    get model_url(model)
    assert_response :success
    assert_select "header", text: /Released May 2026/
    # The JSON-LD releaseDate is still emitted alongside the visible text.
    assert_includes @response.body, "\"releaseDate\":\"2026-05-28\""
  end

  test "show omits the release-date line for a model with no released_on" do
    model = ai_models(:no_price)
    assert_nil model.released_on
    get model_url(model)
    assert_response :success
    assert_select "header", text: /Released/, count: 0
  end

  test "show renders editorial facets when present" do
    ai_models(:opus).update!(
      strengths: "Highly autonomous agentic work",
      best_for: "Long-horizon coding",
      limitations: "Premium pricing"
    )
    get model_url(ai_models(:opus))
    assert_response :success
    assert_select "dt", text: "Strengths"
    assert_select "dd", text: "Highly autonomous agentic work"
    assert_select "dt", text: "Best for"
    assert_select "dt", text: "Limitations"
  end
end
