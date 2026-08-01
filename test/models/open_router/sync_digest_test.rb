require "test_helper"

module OpenRouter
  class SyncDigestTest < ActiveSupport::TestCase
    def make_repriced(overrides = {})
      ModelSync::RepricedRecord.new(
        model_name:         overrides.fetch(:model_name,  "Claude Opus 4.8"),
        provider_name:      overrides.fetch(:provider_name, "Anthropic"),
        model_slug:         overrides.fetch(:model_slug,  "anthropic-claude-opus-4-8"),
        old_input:          overrides.fetch(:old_input,   15.0),
        old_output:         overrides.fetch(:old_output,  75.0),
        old_cached:         overrides.fetch(:old_cached,  nil),
        new_input:          overrides.fetch(:new_input,   12.0),
        new_output:         overrides.fetch(:new_output,  60.0),
        new_cached:         overrides.fetch(:new_cached,  nil),
        pct_input_change: overrides.fetch(:pct_input_change, -20.0)
      )
    end

    def make_created(overrides = {})
      ModelSync::CreatedRecord.new(
        model_name:     overrides.fetch(:model_name,     "Wonder 1"),
        provider_name:  overrides.fetch(:provider_name,  "NewLab"),
        model_slug:     overrides.fetch(:model_slug,     "newlab-wonder-1"),
        new_provider:   overrides.fetch(:new_provider,   false),
        input_per_mtok: overrides.fetch(:input_per_mtok, 0.1),
        output_per_mtok: overrides.fetch(:output_per_mtok, 0.4)
      )
    end

    def make_result(created_records: [], repriced_records: [])
      ModelSync::Result.new(
        created:          created_records.size,
        enriched:         0,
        repriced:         repriced_records.size,
        skipped:          0,
        created_records:  created_records,
        repriced_records: repriced_records
      )
    end

    def digest(result, date: Date.new(2026, 6, 12))
      SyncDigest.new(result, date: date)
    end

    # --- nil when nothing changed -------------------------------------------

    test "returns nil when both records arrays are empty" do
      result = make_result
      assert_nil digest(result).to_slack_payload
    end

    # --- price moves section -------------------------------------------------

    test "includes price moves section when repriced_records are present" do
      result = make_result(repriced_records: [ make_repriced ])
      payload = digest(result).to_slack_payload
      refute_nil payload
      blocks = payload[:blocks]
      assert blocks.any? { |b| b.dig(:text, :text)&.include?("Price moves") }
    end

    test "price moves line contains model name, provider and edit link" do
      r = make_repriced(model_name: "Claude Opus 4.8", provider_name: "Anthropic",
                        model_slug: "anthropic-claude-opus-4-8",
                        old_input: 15.0, old_output: 75.0,
                        new_input: 12.0, new_output: 60.0,
                        pct_input_change: -20.0)
      payload = digest(make_result(repriced_records: [ r ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      assert_includes section_text, "Claude Opus 4.8"
      assert_includes section_text, "Anthropic"
      assert_includes section_text, "-20.0%"
      assert_includes section_text, "edit"
      assert_includes section_text, "/admin/models/anthropic-claude-opus-4-8/edit"
      # Deep-links to the public recent-price-changes page.
      assert_includes section_text, "https://tokenprice.fyi/changes"
    end

    test "shows positive sign for price increase" do
      r = make_repriced(pct_input_change: 10.0)
      payload = digest(make_result(repriced_records: [ r ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      assert_includes section_text, "+10.0%"
    end

    test "shows cached prices in line when old_cached or new_cached present" do
      r = make_repriced(old_cached: 1.5, new_cached: 1.2)
      payload = digest(make_result(repriced_records: [ r ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      assert_includes section_text, "cached"
      assert_includes section_text, "1.5"
      assert_includes section_text, "1.2"
    end

    test "omits cached string when old_cached and new_cached are both nil" do
      r = make_repriced(old_cached: nil, new_cached: nil)
      payload = digest(make_result(repriced_records: [ r ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      refute_includes section_text, "cached"
    end

    # --- new models section --------------------------------------------------

    test "includes new models section when created_records are present" do
      result = make_result(created_records: [ make_created ])
      payload = digest(result).to_slack_payload
      refute_nil payload
      blocks = payload[:blocks]
      assert blocks.any? { |b| b.dig(:text, :text)&.include?("New models") }
    end

    test "new model line contains model name, provider, prices and edit link" do
      c = make_created(model_name: "Wonder 1", provider_name: "NewLab",
                       model_slug: "newlab-wonder-1", new_provider: false,
                       input_per_mtok: 0.1, output_per_mtok: 0.4)
      payload = digest(make_result(created_records: [ c ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      assert_includes section_text, "Wonder 1"
      assert_includes section_text, "NewLab"
      assert_includes section_text, "edit"
      assert_includes section_text, "/admin/models/newlab-wonder-1/edit"
    end

    test "shows 'new provider' marker when new_provider is true" do
      c = make_created(provider_name: "BrandNewCo", new_provider: true)
      payload = digest(make_result(created_records: [ c ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      assert_includes section_text, "new provider ★"
      assert_includes section_text, "BrandNewCo"
    end

    test "does not show 'new provider' marker when new_provider is false" do
      c = make_created(provider_name: "Anthropic", new_provider: false)
      payload = digest(make_result(created_records: [ c ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      refute_includes section_text, "new provider"
    end

    # --- both sections together ---------------------------------------------

    test "includes both sections when both records arrays are populated" do
      result = make_result(
        created_records:  [ make_created ],
        repriced_records: [ make_repriced ]
      )
      payload = digest(result).to_slack_payload
      refute_nil payload
      section_texts = payload[:blocks].filter_map { |b| b.dig(:text, :text) }
      assert section_texts.any? { |t| t.include?("Price moves") }
      assert section_texts.any? { |t| t.include?("New models") }
    end

    # --- Slack block size limits ---------------------------------------------

    # Slack rejects a message ("invalid_blocks", HTTP 400) when a single section
    # block's text exceeds 3000 chars. A large repricing run can blow past that,
    # so the lines must be split across multiple section blocks.
    test "splits a large price-moves batch across multiple section blocks under Slack's limit" do
      records = 40.times.map do |i|
        make_repriced(model_name: "Model #{i} #{"x" * 60}",
                      model_slug: "provider-model-#{i}")
      end
      payload = digest(make_result(repriced_records: records)).to_slack_payload

      sections = payload[:blocks].select { |b| b[:type] == "section" }
      assert_operator sections.size, :>, 1, "expected the batch to span multiple section blocks"
      sections.each do |block|
        assert_operator block.dig(:text, :text).length, :<=, 3000,
                        "each section block must stay within Slack's 3000-char limit"
      end

      section_texts = sections.map { |b| b.dig(:text, :text) }
      assert_includes section_texts.first, "Price moves (40)"
      assert_includes section_texts.last, "See all recent price changes"
    end

    test "splits a large new-models batch across multiple section blocks under Slack's limit" do
      records = 40.times.map do |i|
        make_created(model_name: "Model #{i} #{"x" * 60}", model_slug: "newlab-model-#{i}")
      end
      payload = digest(make_result(created_records: records)).to_slack_payload

      sections = payload[:blocks].select { |b| b[:type] == "section" }
      assert_operator sections.size, :>, 1, "expected the batch to span multiple section blocks"
      sections.each do |block|
        assert_operator block.dig(:text, :text).length, :<=, 3000,
                        "each section block must stay within Slack's 3000-char limit"
      end
      assert_includes sections.first.dig(:text, :text), "New models (40)"
    end

    test "truncates a single line that exceeds the section limit" do
      r = make_repriced(model_name: "z" * 4000)
      payload = digest(make_result(repriced_records: [ r ])).to_slack_payload

      sections = payload[:blocks].select { |b| b[:type] == "section" }
      sections.each do |block|
        assert_operator block.dig(:text, :text).length, :<=, 3000
      end
      text = sections.map { |b| b.dig(:text, :text) }.join("\n")
      assert_includes text, "…", "an over-long line should be truncated with an ellipsis"
    end

    test "caps the payload at Slack's 50-block limit" do
      # Each line exceeds the per-block budget, so it gets its own section block
      # — 60 records would need 60 sections plus the header, well past 50.
      records = 60.times.map do |i|
        make_repriced(model_name: "Model #{i} #{"x" * 3000}", model_slug: "provider-model-#{i}")
      end
      payload = digest(make_result(repriced_records: records)).to_slack_payload

      assert_operator payload[:blocks].size, :<=, OpenRouter::SyncDigest::MAX_BLOCKS
    end

    # --- header and date formatting -----------------------------------------

    test "header block contains the formatted date" do
      result = make_result(repriced_records: [ make_repriced ])
      payload = digest(result, date: Date.new(2026, 6, 12)).to_slack_payload
      header = payload[:blocks].find { |b| b[:type] == "header" }
      assert_includes header.dig(:text, :text), "12 Jun 2026"
    end

    test "text field contains the formatted date" do
      result = make_result(repriced_records: [ make_repriced ])
      payload = digest(result, date: Date.new(2026, 6, 12)).to_slack_payload
      assert_includes payload[:text], "12 Jun 2026"
    end

    # --- fmt helper (exercised indirectly) ----------------------------------

    test "formats zero cached as '0' when cached values are 0" do
      # Zero values reach fmt via old_cached/new_cached. In Ruby, 0 is truthy,
      # so (old_cached || new_cached) is truthy and cached_str is rendered.
      r = make_repriced(old_cached: 0, new_cached: 0)
      payload = digest(make_result(repriced_records: [ r ])).to_slack_payload
      section_text = payload[:blocks].find { |b| b[:type] == "section" }&.dig(:text, :text)
      assert_includes section_text, "cached"
      # fmt(0) returns "0", not "0.00"
      assert_includes section_text, "$0→$0 cached"
    end
  end
end
