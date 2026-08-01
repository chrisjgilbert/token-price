require "test_helper"

class MarketEvent::AnnouncementTest < ActiveSupport::TestCase
  # minitest/mock's #stub is not loaded in this suite (see slack_notifier_test.rb).
  # Intercept the social client's real `.post` by capturing the original method,
  # swapping in a singleton that records its text (or raises), then restoring the
  # original in an ensure. Restoring (not removing) matters: `.post` is a real
  # `def self.post`, so remove_method would delete it and leak across tests.
  def stub_post(client, capture: nil, raise_with: nil)
    original = client.singleton_class.instance_method(:post)
    client.define_singleton_method(:post) do |text:|
      capture << text if capture
      raise raise_with if raise_with

      nil
    end
    yield
  ensure
    client.singleton_class.define_method(:post, original)
  end

  def published_event
    MarketEvent.create!(
      title: "Anthropic cuts Claude Sonnet output pricing",
      note: "Output drops from $15 to $10 per 1M tokens, effective today.",
      event_date: Date.new(2026, 6, 30), kind: "market", status: "published"
    )
  end

  test "draft event posts nothing and leaves announced_at nil" do
    event = MarketEvent.create!(
      title: "Draft", note: "Pending.", event_date: Date.new(2026, 6, 30),
      kind: "market", status: "draft"
    )
    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    assert_empty posts
    assert_nil event.reload.announced_at
  end

  test "already-announced event is a no-op and does not call the clients" do
    event = published_event
    event.update_column(:announced_at, Time.current)
    stamp = event.reload.announced_at

    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    assert_empty posts
    assert_equal stamp.to_i, event.reload.announced_at.to_i
  end

  test "published, unannounced event posts to both platforms and stamps announced_at" do
    event = published_event
    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    assert_equal 2, posts.size
    assert_equal posts[0], posts[1]
    assert_not_nil event.reload.announced_at
  end

  test "a per-platform failure is non-fatal" do
    event = published_event
    mastodon_posts = []

    assert_nothing_raised do
      stub_post(BlueskyClient, raise_with: RuntimeError.new("bsky down")) do
        stub_post(MastodonClient, capture: mastodon_posts) do
          MarketEvent::Announcement.new(event).run
        end
      end
    end

    assert_equal 1, mastodon_posts.size, "Mastodon should still be posted when BlueSky fails"
    assert_not_nil event.reload.announced_at, "announced_at is still stamped after a partial failure"
  end

  test "post text contains the title and events link and is within the character limit" do
    event = published_event
    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    text = posts.first
    assert_includes text, event.title
    assert_includes text, "https://tokenprice.fyi/events"
    assert_operator text.length, :<=, 300
  end

  test "post text uses the so_what in place of the note when present" do
    event = published_event
    event.update!(so_what: "Output-token costs for chained agent calls drop a third overnight.")
    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    text = posts.first
    assert_includes text, "Output-token costs for chained agent calls"
    assert_not_includes text, event.note
  end

  test "a so_what too long for a post is cut on a word boundary, never mid-word" do
    # A so_what may run to SO_WHAT_LIMIT, well past what's left of BlueSky's 300
    # after the title and link — so this path truncates on nearly every post.
    event = published_event
    event.update!(so_what: "Terra's blended rate now works out to $14 per million tokens " \
                           "($2 in / $12 out), which puts it below Anthropic's mid-tier Claude " \
                           "Sonnet 4.6, priced at $3 per million input tokens and $15 per million " \
                           "output tokens, so any routing logic picking models on cost-per-token " \
                           "alone now favors Terra over Sonnet by a real margin.")
    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    text = posts.first
    assert_operator text.length, :<=, 300
    assert text.end_with?("https://tokenprice.fyi/events")
    assert_includes text, event.title
    # The cut lands after a whole word: the character before the ellipsis is not
    # mid-word, i.e. the truncated body ends "… by a real" not "… by a real marg".
    body = text.delete_suffix("\n\nhttps://tokenprice.fyi/events")
    assert body.end_with?("…"), "expected an ellipsis on a truncated blurb"
    assert_includes event.so_what, body.delete_suffix("…").split("\n\n").last.strip,
      "the kept prefix should be a verbatim word-boundary prefix of the so_what"
  end

  test "an overlong note is truncated but the link is preserved" do
    event = MarketEvent.create!(
      title: "Big pricing shift", note: "x" * 500,
      event_date: Date.new(2026, 6, 30), kind: "market", status: "published"
    )
    posts = []
    stub_post(BlueskyClient, capture: posts) do
      stub_post(MastodonClient, capture: posts) do
        MarketEvent::Announcement.new(event).run
      end
    end

    text = posts.first
    assert_operator text.length, :<=, 300
    assert text.end_with?("https://tokenprice.fyi/events")
    assert_includes text, "…"
  end
end
