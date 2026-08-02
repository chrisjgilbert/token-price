class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Conditional GET for public reference pages, keyed on the catalog's freshness
  # (the latest price-row write). Callers pass an `etag:` array carrying every
  # param the page varies by, so a filtered/sorted view never 304s off another
  # view's cache. Pass `last_modified:` to override (e.g. a single model's price
  # date on a show page). Returns true when a 304 was rendered, so the action can
  # `return` and skip the rest of its work.
  #
  # last_modified is folded into the etag, not just sent as a header. Under
  # strict_freshness (config.load_defaults 8.1) a request carrying If-None-Match
  # is validated on the etag ALONE — If-Modified-Since is ignored entirely — so
  # an etag built only from request params would let a browser 304 forever off a
  # cached copy, however stale the data underneath. Every caller keys on request
  # shape, so this is the one place the data has to enter the key.
  def catalog_fresh?(etag:, last_modified: PriceCatalog.last_modified)
    fresh_when(etag: [ *etag, last_modified, *chrome_freshness ],
      last_modified: last_modified, public: true)
    performed?
  end

  # The shared layout's own moving parts, which no caller's `last_modified`
  # covers: the footer's AiModel/Provider counts, and the "prices synced" stamp
  # that prints Date.current. Both ride every page, and neither moves
  # PricePoint.maximum(:updated_at) — so without them in the key a browser 304s
  # off a stale footer after a provider is added, and off a stale date stamp
  # every day the catalog happens not to be repriced. Date.current also keys the
  # /changes page's rolling 30-day window, whose contents age out on the clock
  # rather than on a write.
  #
  # It stays out of `last_modified:` deliberately: that value is also rendered
  # ("data updated <date>"), and chrome churn isn't a data update.
  def chrome_freshness
    @chrome_freshness ||= [ Date.current, AiModel.maximum(:updated_at), Provider.maximum(:updated_at) ]
  end
end
